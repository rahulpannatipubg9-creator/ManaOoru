extends SceneTree

var _failures := 0

func _init() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100.0, 1.0, 100.0)
	collision.shape = floor_shape
	collision.position.y = -0.5
	ground.add_child(collision)
	root.add_child(ground)
	var car := (load("res://scenes/vehicles/tuk_tuk.tscn") as PackedScene).instantiate() as RigidVehicle
	root.add_child(car)
	for _frame in 120:
		await physics_frame
	_check(car.wheel_contacts.all(func(contact: bool) -> bool: return contact), "Auto must rest on all four simulated contact points")
	var total_load := 0.0
	for load_value in car.wheel_loads:
		total_load += load_value
	_check(absf(total_load - car.vehicle_mass * car._gravity) < car.vehicle_mass * car._gravity * 0.08,
		"Three-wheel contact layout must support the auto's weight")
	var expected_rest_y := -(car.SUSPENSION_MOUNT_HEIGHT - car.suspension_rest_length - car.wheel_radius)
	_check(absf(car.global_position.y - expected_rest_y) < 0.04, "Auto body must settle at the Thar suspension's calculated ride height")
	_check(car.drivetrain.redline_rpm == 4000.0 and car.drivetrain.gear_ratios.size() == 4,
		"Auto must use its own lightweight four-speed drivetrain profile")
	var visual := car.get_node("TukTukVisual")
	var front_wheel := visual.get("_front_wheel") as Node3D
	var rear_wheels := visual.get("_rear_wheels") as Node3D
	_check(front_wheel != null and rear_wheels != null, "Imported front and rear wheel meshes must be found")
	if front_wheel != null and rear_wheels != null:
		var front_local := car.to_local(front_wheel.global_position)
		var rear_local := car.to_local(rear_wheels.global_position)
		_check(absf(front_local.z - 1.204) < 0.02 and absf(rear_local.z + 0.98) < 0.02,
			"Animated model wheels must align with the front/rear suspension geometry")
		_check(absf(front_local.y - (car.SUSPENSION_MOUNT_HEIGHT - (car._lengths[0] + car._lengths[1]) * 0.5)) < 0.02,
			"Front model wheel must follow suspension compression")
	var start := car.global_position
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 120:
		await physics_frame
	var speed_before_braking := absf(car.current_speed)
	_check(car.global_position.distance_to(start) > 2.0 and speed_before_braking > 3.0,
		"Rear-wheel-drive auto must accelerate using its drivetrain and tyre forces")
	car.set_touch_move_input(Vector2(0.0, 1.0))
	for _frame in 90:
		await physics_frame
	_check(absf(car.current_speed) < speed_before_braking, "Service braking must reduce forward speed")
	var start_yaw := car.rotation.y
	var front_axle_before: Vector3 = (car.global_basis.inverse() * front_wheel.global_basis).x.normalized()
	car.set_touch_move_input(Vector2(0.65, -1.0))
	for _frame in 90:
		await physics_frame
	_check(absf(angle_difference(start_yaw, car.rotation.y)) > 0.1,
		"Front steering and rear tyre forces must turn the auto")
	var front_axle_after: Vector3 = (car.global_basis.inverse() * front_wheel.global_basis).x.normalized()
	_check(front_axle_before.angle_to(front_axle_after) > 0.2,
		"Visible front wheel must steer with the physical front contact points")
	car.set_touch_move_input(Vector2.ZERO)
	car.set_driving_enabled(false)
	for _frame in 60:
		await process_frame
	car.queue_free()
	ground.queue_free()
	await process_frame
	for _frame in 4:
		await process_frame
	if _failures > 0:
		push_error("FAIL tuk-tuk physics regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS tuk-tuk physics regression: three-wheel layout, static ride height, suspension load, visuals, drivetrain acceleration and braking")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
