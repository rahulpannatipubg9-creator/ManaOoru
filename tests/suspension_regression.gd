extends SceneTree

var _failures := 0

func _init() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(2000.0, 1.0, 2000.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	root.add_child(ground)
	var car := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	car.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(car)
	await physics_frame
	var ride_height: float = car.SUSPENSION_MOUNT_HEIGHT - car.suspension_rest_length - car.wheel_radius
	_check(absf(car.global_position.y - ride_height) < 0.01, "A spawned car must settle onto its springs, not float")

	# Rest: the four springs carry the car's weight and the body sits level.
	for _frame in 90:
		await physics_frame
	var weight: float = car.vehicle_mass * car._gravity
	var total_load := 0.0
	for load_value: float in car.wheel_loads:
		total_load += load_value
	_check(car.wheel_contacts.all(func(contact: bool) -> bool: return contact), "All four tyres must touch the road at rest")
	_check(absf(total_load - weight) < weight * 0.05, "Springs must carry the car's weight at rest (%.0f vs %.0f N)" % [total_load, weight])
	_check(absf(car.body_pitch) < 0.01 and absf(car.body_roll) < 0.01, "Body must sit level at rest")
	_check(absf(car.global_position.y - ride_height) < 0.03, "Car must rest at its ride height")
	_check(car.velocity.length() < 0.05, "A parked-on-the-spot car must not creep")

	# Accelerating squats the rear, braking dives the nose.
	var min_pitch := 0.0
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 40:
		await physics_frame
		min_pitch = minf(min_pitch, car.body_pitch)
	_check(min_pitch < -0.01, "Hard acceleration must squat the body (pitch %.3f)" % min_pitch)
	# A Thar diesel needs about 13 s to reach 100 km/h, so 2/3 s of full throttle is a gentle start.
	_check(car.current_speed > 2.0, "Car must accelerate through its tyres")
	var max_pitch := 0.0
	car.set_touch_move_input(Vector2(0.0, 1.0))
	for _frame in 20:
		await physics_frame
		max_pitch = maxf(max_pitch, car.body_pitch)
	_check(max_pitch > 0.01, "Hard braking must dive the nose (pitch %.3f)" % max_pitch)

	# Cornering rolls the body towards the outside of the turn.
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 150:
		await physics_frame
	var max_roll := 0.0
	var roll_matches_turn := true
	var grip_slide := 0.0
	var turn_start_yaw: float = car.rotation.y
	car.set_touch_move_input(Vector2(-1.0, -1.0).normalized())
	for _frame in 60:
		await physics_frame
		if absf(car._body_acceleration.x) > 4.0 and absf(car.body_roll) > 0.01:
			roll_matches_turn = roll_matches_turn and signf(car.body_roll) == signf(car._body_acceleration.x)
		max_roll = maxf(max_roll, absf(car.body_roll))
		grip_slide = maxf(grip_slide, absf(car.velocity.dot(car.global_transform.basis.x)))
	_check(max_roll > 0.02, "Hard cornering must roll the body (roll %.3f)" % max_roll)
	_check(roll_matches_turn, "Body must lean away from the centre of the turn")
	var turn_yaw := angle_difference(turn_start_yaw, car.rotation.y)
	_check(signf(car.wheels[0].rotation.y) == signf(turn_yaw) and signf(car.wheels[1].rotation.y) == signf(turn_yaw),
		"Front wheels must point into the turn the car is making")
	var grip_slip: float = car.tyre_slip
	_check(grip_slip < 0.5, "Tyres must grip in a normal full-lock turn (slip %.2f)" % grip_slip)

	# The same turn entered on the handbrake lets the rear step out.
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 90:
		await physics_frame
	var max_slide := 0.0
	car.set_touch_move_input(Vector2(-1.0, -1.0).normalized())
	Input.action_press("vehicle_handbrake")
	for _frame in 45:
		await physics_frame
		max_slide = maxf(max_slide, absf(car.velocity.dot(car.global_transform.basis.x)))
	Input.action_release("vehicle_handbrake")
	_check(max_slide > car.SKID_LATERAL_SPEED and max_slide > grip_slide * 2.0,
		"Handbrake turn must let the rear slide sideways (%.2f vs %.2f m/s gripping)" % [max_slide, grip_slide])

	# Wheels never leave their travel range and stay planted on the road.
	var mount_height: float = car.SUSPENSION_MOUNT_HEIGHT
	var lowest: float = mount_height - car.suspension_rest_length - car.suspension_droop_travel - 0.35
	var highest: float = mount_height - car.suspension_rest_length + car.suspension_bump_travel + 0.35
	for wheel: Node3D in car.wheels:
		_check(wheel.position.y > lowest and wheel.position.y < highest, "Wheel %s must stay within suspension travel" % wheel.name)

	# Airborne: no tyre contact means no throttle, braking or steering authority.
	car.set_touch_move_input(Vector2.ZERO)
	for _frame in 120:
		await physics_frame
	car.global_position.y += 3.0
	car.velocity = Vector3(0.0, 0.0, 0.0)
	await physics_frame
	var air_yaw: float = car.rotation.y
	car.set_touch_move_input(Vector2(1.0, -1.0).normalized())
	for _frame in 8:
		await physics_frame
	_check(not car.wheel_contacts.any(func(contact: bool) -> bool: return contact), "Lifted car must be airborne")
	_check(Vector2(car.velocity.x, car.velocity.z).length() < 0.05, "Airborne tyres must not accelerate the car")
	_check(absf(car.rotation.y - air_yaw) < 0.001, "Airborne car must not steer")
	car.set_touch_move_input(Vector2.ZERO)

	# Landing: the springs absorb the drop and the car settles again.
	for _frame in 180:
		await physics_frame
	_check(car.wheel_contacts.all(func(contact: bool) -> bool: return contact), "Car must land on all four tyres")
	_check(absf(car.global_position.y - ride_height) < 0.03, "Springs must settle the car after a drop")
	_check(absf(car.velocity.y) < 0.05, "Suspension must stop bouncing after landing")
	_check(absf(car.body_pitch) < 0.01 and absf(car.body_roll) < 0.01, "Body must level out after landing")

	# Recovery resets the body pose along with the transform.
	car.recover_vehicle()
	_check(car.body_pitch == 0.0 and car.body_roll == 0.0, "Recovery must reset body pitch and roll")
	if _failures > 0:
		print("FAIL suspension regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS suspension regression: ride height, load, squat, dive, roll, tyre grip, handbrake slide, airborne, landing")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
