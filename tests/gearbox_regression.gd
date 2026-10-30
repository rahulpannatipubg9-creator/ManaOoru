extends SceneTree

const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
const Gearbox := preload("res://scripts/player/gearbox.gd")
const KMH := 3.6

var _failures := 0

func _init() -> void:
	_test_driveline_rules()
	await _test_drive()
	if _failures > 0:
		print("FAIL gearbox regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS gearbox regression: first-gear start, sequential upshifts, 0-100 time, top speed, coasting, manual mode, over-rev guard, anti-stall, reverse, limiter, manual-only profile")
	quit()

func _test_driveline_rules() -> void:
	var gearbox := Gearbox.new()
	_check(gearbox.gear == 1 and gearbox.label() == "D1", "A fresh gearbox must start in first, Drive")
	_check(gearbox.engine_torque(2000.0) == 300.0, "Thar mHawk must make 300 Nm in its plateau")
	var road_rpm_90 := 25.0 / (TAU * 0.394) * 60.0 * gearbox.overall_ratio(6)
	_check(absf(road_rpm_90 - 1500.0) < 60.0, "6th gear must turn ~1500 rpm at 90 km/h (%.0f)" % road_rpm_90)

	gearbox.toggle_mode()
	_check(gearbox.label() == "M1", "T must switch to Manual")
	gearbox.request_shift_up()
	_check(gearbox.gear == 2, "Manual up-shift must select the next gear")
	gearbox.gear = 4
	gearbox.request_shift_down(130.0 / KMH, 0.394)
	_check(gearbox.gear == 4, "Down-shift that would over-rev the engine must be refused")
	gearbox.update(5.0, 0.0, 0.394, 1.0 / 60.0)
	_check(gearbox.gear == 3, "Manual mode must still drop a gear before the engine lugs")

	gearbox.reset()
	gearbox.update(0.0, -1.0, 0.394, 1.0 / 60.0)
	_check(gearbox.label() == "R", "S from a standstill must select reverse")
	_check(gearbox.update(0.0, -1.0, 0.394, 1.0) < 0.0, "Reverse must push the car backwards")

	gearbox.reset()
	_check(gearbox.update(60.0 / KMH, 1.0, 0.394, 1.0) == 0.0 and gearbox.rpm <= 4200.0,
		"The limiter must cut drive at redline")

	var manual_only := DrivetrainProfile.new()
	manual_only.automatic_available = false
	var manual_box := Gearbox.new(manual_only)
	manual_box.toggle_mode()
	_check(manual_box.label() == "M1", "A manual-only car must stay in Manual")

func _test_drive() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(12000.0, 1.0, 12000.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	root.add_child(ground)
	var car := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	car.position = Vector3(0.0, 1.2, -5500.0)
	root.add_child(car)
	for _frame in 90:
		await physics_frame
	_check(car.gearbox.label() == "D1", "Every drive must start in first")

	car.set_touch_move_input(Vector2(0.0, -1.0))
	var shifts: Array[int] = [1]
	var seconds := 0.0
	var time_to_100 := -1.0
	var top_speed := 0.0
	# 90 s flat out: long enough to settle at top speed in fifth.
	for _frame in 5400:
		await physics_frame
		seconds += 1.0 / Engine.physics_ticks_per_second
		var gear: int = car.gearbox.gear
		if gear != shifts[-1]:
			shifts.append(gear)
		top_speed = maxf(top_speed, car.current_speed * KMH)
		if time_to_100 < 0.0 and car.current_speed * KMH >= 100.0:
			time_to_100 = seconds
	print("  Thar flat out: 0-100 km/h in %.1f s, top speed %.0f km/h, gears %s" % [time_to_100, top_speed, str(shifts)])
	var sequential := true
	for index in range(1, shifts.size()):
		sequential = sequential and shifts[index] == shifts[index - 1] + 1
	_check(sequential, "Full throttle must climb one gear at a time without hunting (%s)" % str(shifts))
	_check(shifts[-1] >= 5, "Full throttle must reach fifth (%s)" % str(shifts))
	_check(time_to_100 > 10.0 and time_to_100 < 16.0, "0-100 km/h must take a Thar-like ~13 s (%.1f s)" % time_to_100)
	_check(top_speed > 135.0 and top_speed < 160.0, "Top speed must be Thar-like ~145 km/h (%.0f km/h)" % top_speed)

	var lift_speed: float = car.current_speed
	car.set_touch_move_input(Vector2.ZERO)
	for _frame in 120:
		await physics_frame
	_check(car.current_speed < lift_speed and car.current_speed > lift_speed * 0.8,
		"Lifting off must coast down gently (%.0f -> %.0f km/h)" % [lift_speed * KMH, car.current_speed * KMH])

	car.set_driving_enabled(false)
	car.set_driving_enabled(true)
	_check(car.gearbox.label() == "D1", "Getting back in must start in first again")
	car.queue_free()
	ground.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
