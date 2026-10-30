extends SceneTree

const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
const EngineSound := preload("res://scripts/player/engine_sound.gd")

var _failures := 0

func _init() -> void:
	_test_layer_weights()
	await _test_synthesis()
	await _test_drive_cycle()
	await _test_possession()
	if _failures > 0:
		print("FAIL engine sound regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS engine sound regression: crank/idle, gears, redline, horn, loudness, parked cars silent, engine off on exit")
	quit()

func _test_synthesis() -> void:
	var sound: AudioStreamPlayer3D = load("res://scripts/player/engine_sound.gd").new()
	root.add_child(sound)
	sound.set_running(true)
	await process_frame
	sound.set_process(false)
	for _step in 150:
		sound.update_drive_state(0.0, 0.0, 0.0, false, 1.0 / 60.0)
		sound._update_engine_state(1.0 / 60.0)
	_check(absf(sound.rpm - sound.idle_rpm) < 1.0, "Engine must crank, catch and settle at idle (%.0f rpm)" % sound.rpm)
	var idle := _measure(sound.render(22050))
	_check(idle.x > 0.05, "Idle must be clearly audible (rms %.3f)" % idle.x)
	_check(idle.y <= 1.0, "Idle must not clip")
	for _step in 120:
		sound.set_engine_rpm(3000.0, 3)
		sound.update_drive_state(18.0, 1.0, 0.0, false, 1.0 / 60.0)
		sound._update_engine_state(1.0 / 60.0)
	var loaded := _measure(sound.render(22050))
	_check(loaded.x > idle.x * 1.3, "Full throttle must be louder than idle (%.3f vs %.3f)" % [loaded.x, idle.x])
	_check(loaded.y <= 1.0 and not is_nan(loaded.x), "Full throttle must not clip or produce NaN")
	var petrol := DrivetrainProfile.new()
	petrol.cylinders = 6
	petrol.diesel_clatter = 0.0
	petrol.redline_rpm = 7500.0
	sound.configure(petrol)
	for _step in 120:
		sound.set_engine_rpm(6500.0, 3)
		sound.update_drive_state(40.0, 1.0, 0.0, false, 1.0 / 60.0)
		sound._update_engine_state(1.0 / 60.0)
	var petrol_loaded := _measure(sound.render(22050))
	_check(petrol_loaded.x > 0.05 and not is_nan(petrol_loaded.x), "A petrol six at 6500 rpm must be audible and stable")
	sound.queue_free()

func _test_drive_cycle() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(4000.0, 1.0, 4000.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	root.add_child(ground)
	var car := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(car)
	var sound := car.get_node("EngineAudio")
	for _frame in 90:
		await physics_frame
	_check(sound.engine_running and sound.playing, "Driven car must have its engine running")
	car.set_touch_move_input(Vector2(0.0, -1.0))
	var peak_rpm := 0.0
	var previous_rpm: float = sound.rpm
	var shift_drop := 0.0
	var highest_gear := 1
	# 15 s of full throttle: a Thar reaches about 110 km/h and fourth gear.
	for _frame in 900:
		await physics_frame
		peak_rpm = maxf(peak_rpm, sound.rpm)
		shift_drop = maxf(shift_drop, previous_rpm - sound.rpm)
		previous_rpm = sound.rpm
		highest_gear = maxi(highest_gear, sound.gear)
	_check(peak_rpm > 3000.0, "Accelerating must rev the engine (peak %.0f rpm)" % peak_rpm)
	_check(peak_rpm <= sound.redline_rpm, "Engine must never pass the redline")
	_check(highest_gear >= 4, "Gearbox must change up while accelerating (reached gear %d)" % highest_gear)
	# The Thar plays real recorded diesel loops, crossfaded and pitched to the gearbox rpm.
	_check(sound.has_recording(), "The Thar must use its recorded engine loops")
	var playing_layers := 0
	for layer: AudioStreamPlayer3D in sound._layers:
		if layer.playing:
			playing_layers += 1
			_check(absf(layer.pitch_scale * sound._recording.loop_rpms[sound._layers.find(layer)] - sound.rpm) < 1.0,
				"Each recorded loop must be pitched to the engine rpm")
	_check(playing_layers == sound._layers.size(), "All recorded loops must run while the engine runs")
	_check(shift_drop > 15.0, "Revs must drop at an upshift")
	Input.action_press("vehicle_horn")
	await physics_frame
	_check(sound.horn_pressed, "H must sound the horn while driving")
	Input.action_release("vehicle_horn")
	await physics_frame
	_check(not sound.horn_pressed, "Releasing H must stop the horn")
	car.queue_free()
	ground.queue_free()
	await process_frame

func _test_possession() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 10:
		await physics_frame
	for vehicle: Node in game.vehicles:
		if vehicle is GdkHelicopter:
			_check(not vehicle.get_node("RotorEngineAudio").playing, "Parked helicopter rotor audio must be stopped")
			continue
		var parked_sound := vehicle.get_node("EngineAudio")
		_check(not parked_sound.engine_running and not parked_sound.playing, "Parked cars must be silent")
	var person := game.get_node("Player") as CharacterBody3D
	var car := game.get_node("Vehicle") as PhysicsBody3D
	var sound := car.get_node("EngineAudio")
	person.set_movement_enabled(false)
	person.global_position = car.global_position + car.global_basis.x * -2.0
	game.enter_vehicle(car)
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	for _frame in 10:
		await physics_frame
	_check(sound.engine_running and sound.playing, "Entering a car must start its engine")
	for vehicle: Node in game.vehicles:
		if vehicle != car:
			if vehicle is GdkHelicopter:
				_check(not vehicle.get_node("RotorEngineAudio").playing, "Unoccupied helicopter audio must remain stopped")
			else:
				_check(not vehicle.get_node("EngineAudio").playing, "Only the driven car's engine may run")
	game.exit_vehicle()
	for _frame in 300:
		if game.control_state == game.ControlState.ON_FOOT:
			break
		await physics_frame
	for _frame in 60:
		await physics_frame
	_check(not sound.engine_running and not sound.playing, "Exiting must switch the engine off")
	for layer: AudioStreamPlayer3D in sound._layers:
		_check(not layer.playing, "Exiting must silence the recorded engine loops")
	game.queue_free()

func _test_layer_weights() -> void:
	var rpms: Array[float] = [900.0, 1800.0, 3600.0]
	var at_idle: Array[float] = EngineSound.layer_weights(700.0, rpms)
	_check(at_idle[0] == 1.0 and at_idle[1] == 0.0, "Below the lowest loop only that loop plays")
	var between: Array[float] = EngineSound.layer_weights(2545.6, rpms)
	_check(absf(between[1] - between[2]) < 0.01 and absf(between[1] * between[1] + between[2] * between[2] - 1.0) < 0.01,
		"Halfway in pitch between two loops they share equal power")
	var top: Array[float] = EngineSound.layer_weights(5000.0, rpms)
	_check(top[2] == 1.0, "Above the highest loop only that loop plays")

func _measure(buffer: PackedVector2Array) -> Vector2:
	var sum := 0.0
	var peak := 0.0
	for frame in buffer:
		sum += frame.x * frame.x
		peak = maxf(peak, absf(frame.x))
	return Vector2(sqrt(sum / buffer.size()), peak)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
