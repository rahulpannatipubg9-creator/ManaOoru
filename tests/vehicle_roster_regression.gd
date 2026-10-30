extends SceneTree

const NODE_LAYOUT := ["Chassis", "Chassis/FrontIndicator", "FrontLeftWheel", "FrontRightWheel", "RearLeftWheel",
	"RearRightWheel", "FrontLeftHub", "FrontRightHub", "RearLeftHub", "RearRightHub", "CollisionShape3D",
	"CameraPivot", "CameraPivot/SpringArm3D/Camera3D", "EngineAudio"]
var _failures := 0

func _init() -> void:
	await _test_porsche_scene()
	await _test_porsche_outruns_thar()
	await _test_porsche_in_world()
	await _test_compass_scene()
	await _test_compass_in_world()
	if _failures > 0:
		print("FAIL vehicle roster regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS vehicle roster regression: Porsche 911 and Jeep Compass layouts, drivetrain profiles, ride height, performance, enterable in world")
	quit()

func _test_porsche_scene() -> void:
	var ground := _add_ground()
	var car := (load("res://scenes/vehicles/porsche_911.tscn") as PackedScene).instantiate()
	root.add_child(car)
	for path: String in NODE_LAYOUT:
		_check(car.get_node_or_null(path) != null, "Porsche must keep the shared car node layout: %s" % path)
	var profile: Resource = car.drivetrain
	_check(profile != null and profile.gear_ratios.size() == 8, "Porsche must use its 8-speed PDK profile")
	_check(profile != null and profile.redline_rpm == 7500.0 and profile.cylinders == 6 and profile.diesel_clatter == 0.0,
		"Porsche must sound like a petrol flat-six revving to 7500 rpm")
	var recording: Resource = profile.engine_recording if profile else null
	_check(recording != null and recording.loops.size() == 2 and recording.loop_rpms == [1150.0, 2600.0],
		"Porsche must use its own recorded idle and rev loops")
	if recording != null:
		for loop: AudioStreamWAV in recording.loops:
			_check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.get_length() > 1.0,
				"Porsche engine loop %s must import as a seamless forward loop" % loop.resource_path)
		_check(recording.start_sound is AudioStreamWAV and recording.start_sound.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"Porsche start-up recording must play once")
	for _frame in 90:
		await physics_frame
	_check(car.wheel_contacts.all(func(contact: bool) -> bool: return contact), "Porsche must rest on all four tyres")
	_check(absf(car.global_position.y) < 0.03, "Porsche must settle at its ride height (y %.3f)" % car.global_position.y)
	var total_load := 0.0
	for load_value: float in car.wheel_loads:
		total_load += load_value
	var weight: float = car.vehicle_mass * car._gravity
	_check(absf(total_load - weight) < weight * 0.05, "Porsche springs must carry its weight")
	var tyre := car.get_node("RearLeftWheel/Tyre") as Node3D
	_check(tyre.get_child_count() > 0, "Porsche tyre model must load")
	car.queue_free()
	ground.queue_free()
	await process_frame

## A 443 hp Porsche must clearly out-accelerate a 130 hp diesel Thar.
func _test_porsche_outruns_thar() -> void:
	var porsche_speed := await _speed_after("res://scenes/vehicles/porsche_911.tscn", 150)
	var thar_speed := await _speed_after("res://scenes/player/player.tscn", 150)
	_check(porsche_speed > 15.0, "Porsche must reach 54 km/h within 2.5 s (got %.0f km/h)" % (porsche_speed * 3.6))
	_check(porsche_speed > thar_speed * 1.3,
		"Porsche must out-accelerate the Thar (%.0f vs %.0f km/h)" % [porsche_speed * 3.6, thar_speed * 3.6])

func _speed_after(scene_path: String, frames: int) -> float:
	var ground := _add_ground()
	var car := (load(scene_path) as PackedScene).instantiate()
	root.add_child(car)
	for _frame in 90:
		await physics_frame
	car.set_touch_move_input(Vector2(0.0, -1.0))
	var peak_rpm := 0.0
	for _frame in frames:
		await physics_frame
		peak_rpm = maxf(peak_rpm, car.gearbox.rpm)
	var speed: float = car.current_speed
	_check(peak_rpm <= car.drivetrain.redline_rpm + 1.0, "%s must respect its redline" % scene_path)
	car.queue_free()
	ground.queue_free()
	await process_frame
	return speed

func _test_porsche_in_world() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 10:
		await physics_frame
	var car := game.get_node_or_null("Porsche 911") as PhysicsBody3D
	_check(car != null and car in game.vehicles, "Porsche must be an enterable vehicle in the world")
	if car == null:
		game.queue_free()
		return
	var person := game.get_node("Player") as CharacterBody3D
	person.set_movement_enabled(false)
	person.global_position = car.global_position + car.global_basis.x * -2.2
	game.enter_vehicle(car)
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	for _frame in 10:
		await physics_frame
	_check(game.control_state == game.ControlState.DRIVING and game.active_vehicle == car, "Player must be able to drive the Porsche")
	_check(car.get_node("EngineAudio").engine_running, "Porsche engine must start when entered")
	game.queue_free()

func _test_compass_scene() -> void:
	var ground := _add_ground()
	var car := (load("res://scenes/vehicles/jeep_compass.tscn") as PackedScene).instantiate()
	root.add_child(car)
	for path: String in NODE_LAYOUT:
		_check(car.get_node_or_null(path) != null, "Compass must keep the shared car node layout: %s" % path)
	var profile: Resource = car.drivetrain
	_check(profile != null and profile.gear_ratios.size() == 9, "Compass must use its 9-speed automatic profile")
	_check(profile != null and profile.cylinders == 4 and profile.diesel_clatter > 0.0 and profile.redline_rpm <= 4600.0,
		"Compass must sound like a 2.0 four-cylinder diesel")
	for _frame in 90:
		await physics_frame
	_check(car.wheel_contacts.all(func(contact: bool) -> bool: return contact), "Compass must rest on all four tyres")
	_check(absf(car.global_position.y) < 0.03, "Compass must settle at its ride height (y %.3f)" % car.global_position.y)
	var total_load := 0.0
	for load_value: float in car.wheel_loads:
		total_load += load_value
	var weight: float = car.vehicle_mass * car._gravity
	_check(absf(total_load - weight) < weight * 0.05, "Compass springs must carry its weight")
	_check((car.get_node("RearLeftWheel/Tyre") as Node3D).get_child_count() > 0, "Compass tyre model must load")
	_check((car.get_node("Chassis/Compass") as Node3D).get_child_count() > 0, "Compass body model must load")
	car.queue_free()
	ground.queue_free()
	await process_frame
	# 125 kW / 350 Nm diesel: quicker than the 97 kW Thar, far behind the Porsche.
	var compass_speed := await _speed_after("res://scenes/vehicles/jeep_compass.tscn", 150)
	var porsche_speed := await _speed_after("res://scenes/vehicles/porsche_911.tscn", 150)
	_check(compass_speed > 8.0, "Compass must pull away briskly (got %.0f km/h after 2.5 s)" % (compass_speed * 3.6))
	_check(compass_speed < porsche_speed, "Compass must be slower than the Porsche (%.0f vs %.0f km/h)" % [compass_speed * 3.6, porsche_speed * 3.6])

func _test_compass_in_world() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 10:
		await physics_frame
	var car := game.get_node_or_null("ParkedVehicle_3") as PhysicsBody3D
	_check(car != null and car.get_node_or_null("Chassis/Compass") != null and car in game.vehicles,
		"Jeep Compass must be an enterable vehicle in the world")
	if car == null:
		game.queue_free()
		return
	var person := game.get_node("Player") as CharacterBody3D
	person.set_movement_enabled(false)
	person.global_position = car.global_position + car.global_basis.x * -2.2
	game.enter_vehicle(car)
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	for _frame in 10:
		await physics_frame
	_check(game.control_state == game.ControlState.DRIVING and game.active_vehicle == car, "Player must be able to drive the Compass")
	_check(car.get_node("EngineAudio").engine_running, "Compass engine must start when entered")
	game.queue_free()

func _add_ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 1.0, 4000.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	return ground

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
