extends SceneTree
var failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/imported_vehicle_profiles.json"))
	var tested := 0
	for id: String in catalog:
		var path := "res://scenes/vehicles/imported/%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		_check(scene != null, id + ": scene loads")
		if scene == null:
			continue
		var car := scene.instantiate() as RigidVehicle
		root.add_child(car)
		_check(car.is_in_group("enterable_vehicle"), id + ": entry group")
		_check(car.get_node("Chassis").get_child_count() > 1, id + ": actual body assembly")
		for wheel: Node3D in car.wheels:
			_check(wheel != null and not wheel.find_children("*", "MeshInstance3D", true, false).is_empty(), id + ": actual wheel mesh")
		car.set_keyboard_input_enabled(false)
		car.set_input_authority(false)
		for frame in 75:
			await physics_frame
		_check(car.wheel_contacts.all(func(c: bool) -> bool: return c), id + ": four ground contacts")
		_check(absf(car.global_position.y) < 0.2, id + ": stable ride height %.3f" % car.global_position.y)
		var initial := car.global_position
		car.set_input_authority(true)
		car.set_touch_move_input(Vector2(0, -1))
		for frame in 120:
			await physics_frame
		_check(car.current_speed > 1.0, id + ": accelerates %.2f m/s" % car.current_speed)
		_check(car.global_position.z > initial.z + 1.0, id + ": moves forward")
		_check(car.gearbox.rpm <= car.drivetrain.redline_rpm + 1, id + ": redline")
		var before := car.wheels[0].rotation.x
		car.set_touch_move_input(Vector2(.6, -1))
		for frame in 30:
			await physics_frame
		_check(absf(car.wheels[0].rotation.y) > .02, id + ": front wheels steer")
		_check(absf(car.wheels[2].rotation.y) < .001, id + ": rear wheels stay straight")
		_check(absf(car.wheels[0].rotation.x - before) > .01, id + ": wheels rotate")
		car.set_touch_move_input(Vector2.ZERO)
		car.set_driving_enabled(false)
		await physics_frame
		await physics_frame
		_check(car.touch_move_input == Vector2.ZERO, id + ": parking clears input")
		_check(not car.get_node("EngineAudio").engine_running, id + ": parked audio muted")
		print("CHECKED ", id, " speed=", snappedf(car.current_speed, .01), " contacts=", car.wheel_contacts)
		car.queue_free()
		await process_frame
		tested += 1
	ground.queue_free()
	await process_frame
	print("%s imported vehicle regression: %d vehicles, %d failures" % ["PASS" if failures == 0 else "FAIL", tested, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
