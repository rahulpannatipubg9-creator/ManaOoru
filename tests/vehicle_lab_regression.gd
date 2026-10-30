extends SceneTree

## Vehicle physics lab: measures the rigid-body raycast car against a VehicleBody3D
## baseline on the same track, then checks car-to-car collisions with five parked
## cars and one driven car. Prints a comparison table and fails on regressions.

const KMH := 1.0 / 3.6
const FRAMES_PER_SECOND := 60

var _failures := 0
var _lab: VehicleLab

func _init() -> void:
	_lab = VehicleLab.new()
	_lab.interactive = false
	root.add_child(_lab)
	_lab.build_arena()
	await physics_frame
	var rigid := await _measure("RigidBody3D + raycast", func() -> Node: return _lab.spawn_car(Vector3.ZERO, 0.0, true))
	var baseline := await _measure("VehicleBody3D", _make_vehicle_body)
	print("\n%-24s %10s %12s %12s %12s %12s" % ["metric", "rest drift", "0-50 km/h", "60-0 brake", "ramp hold", "corner up.y"])
	for result in [rigid, baseline]:
		print("%-24s %8.3f m %10.2f s %10.1f m %10.3f m %12.3f" % [result.name, result.rest_drift, result.accel_time,
			result.brake_distance, result.ramp_drift, result.corner_up])
	_check(rigid.rest_drift < 0.02, "Rigid car must sit still at rest (drift %.3f m)" % rigid.rest_drift)
	_check(rigid.accel_time > 3.0 and rigid.accel_time < 12.0, "0-50 km/h must be realistic (%.2f s)" % rigid.accel_time)
	_check(rigid.brake_distance > 10.0 and rigid.brake_distance < 35.0, "60-0 km/h braking distance must be realistic (%.1f m)" % rigid.brake_distance)
	_check(rigid.ramp_drift < 0.15, "Parked car must hold on a 15%% slope (drift %.3f m)" % rigid.ramp_drift)
	_check(rigid.corner_up > 0.85, "Car must stay upright in a full-lock turn at 40 km/h")
	_check(rigid.climbed, "Car must drive up a 15% ramp")
	await _test_collisions()
	if _failures > 0:
		print("FAIL vehicle lab regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS vehicle lab regression: rest, acceleration, braking, slope hold, ramp climb, cornering, car-to-car momentum, settling, input isolation")
	quit()

## Runs the same five manoeuvres on a freshly spawned car of either kind.
func _measure(label: String, factory: Callable) -> Dictionary:
	var result := {"name": label}
	var car: Node3D = factory.call()
	# Long open run along +Z, clear of the ramp, bumps and wall.
	car.global_position = Vector3(150, 0.6, -250)
	await _frames(120)
	var start := car.global_position
	await _frames(120)
	result.rest_drift = car.global_position.distance_to(start)

	var elapsed := 0.0
	while _speed(car) < 50.0 * KMH and elapsed < 20.0:
		_drive(car, 1.0, 0.0)
		await physics_frame
		elapsed += 1.0 / FRAMES_PER_SECOND
	result.accel_time = elapsed
	while _speed(car) < 60.0 * KMH and elapsed < 30.0:
		_drive(car, 1.0, 0.0)
		await physics_frame
		elapsed += 1.0 / FRAMES_PER_SECOND
	var brake_start := car.global_position
	var guard := 0
	while _speed(car) > 0.5 and guard < 600:
		_drive(car, -1.0, 0.0)
		await physics_frame
		guard += 1
	result.brake_distance = car.global_position.distance_to(brake_start)
	_drive(car, 0.0, 0.0)

	# Full lock at 40 km/h for three seconds.
	_place(car, Vector3(60, 0.6, -100), 0.0)
	await _frames(30)
	guard = 0
	while _speed(car) < 40.0 * KMH and guard < 900:
		_drive(car, 1.0, 0.0)
		await physics_frame
		guard += 1
	var lowest_up := 1.0
	for _frame in 180:
		_drive(car, 0.4, 1.0)
		await physics_frame
		lowest_up = minf(lowest_up, car.global_transform.basis.y.y)
	result.corner_up = lowest_up
	if car is RigidVehicle:
		# The front wheels must visibly point into the turn the body is making.
		var yaw_before: float = car.global_rotation.y
		for _frame in 20:
			_drive(car, 0.4, 1.0)
			await physics_frame
		var turned := angle_difference(yaw_before, car.global_rotation.y)
		var wheel_angle: float = car.wheels[0].rotation.y
		_check(signf(turned) == signf(wheel_angle) and absf(wheel_angle) > 0.05,
			"Front wheels must steer into the turn (yaw %.3f, wheel %.3f)" % [turned, wheel_angle])
	_drive(car, 0.0, 0.0)

	# Park on the 15% ramp, then climb it.
	var ramp_point := Vector3(-20, 0.0, -40)
	ramp_point.y = 20.0 * VehicleLab.RAMP_GRADE + 0.6
	_place(car, ramp_point, PI)
	_set_parked(car, true)
	await _frames(90)
	var ramp_start := car.global_position
	await _frames(180)
	result.ramp_drift = car.global_position.distance_to(ramp_start)
	_set_parked(car, false)
	_place(car, Vector3(-20, 0.6, -14), PI)
	await _frames(30)
	var climb_start := car.global_position.y
	for _frame in 360:
		_drive(car, 1.0, 0.0)
		await physics_frame
	result.climbed = car.global_position.y - climb_start > 3.0
	_drive(car, 0.0, 0.0)
	car.queue_free()
	await physics_frame
	return result

func _test_collisions() -> void:
	var parked: Array[RigidVehicle] = []
	for spot in VehicleLab.PARKED_POSITIONS:
		parked.append(_lab.spawn_car(spot + Vector3(0, 0.6, 200), 0.0, false))
	var driven := _lab.spawn_car(Vector3(0, 0.6, 140), 0.0, true)
	await _frames(120)
	var origins: Array[Vector3] = []
	for car in parked:
		origins.append(car.global_position)

	# Global WASD must only reach the driven car.
	Input.action_press("forward")
	await _frames(240)
	var speed_at_impact := driven.linear_velocity.length()
	var guard := 0
	while driven.global_position.z < 222.0 and guard < 600:
		speed_at_impact = maxf(speed_at_impact, driven.linear_velocity.length())
		await physics_frame
		guard += 1
	Input.action_release("forward")
	for index in [3, 4]:
		_check(parked[index].global_position.distance_to(origins[index]) < 0.05,
			"Parked car %d must ignore keyboard input and stay put" % index)
	var hit_car := parked[0]
	await _frames(30)
	var displaced := hit_car.global_position.distance_to(origins[0])
	_check(displaced > 0.3, "A %.0f km/h impact must shove the parked car (moved %.2f m)" % [speed_at_impact * 3.6, displaced])
	for car in parked + [driven]:
		for other in parked + [driven]:
			if car != other:
				_check(_separated(car, other), "Cars must never overlap after an impact")
	await _frames(360)
	_check(hit_car.linear_velocity.length() < 0.15, "The shoved car must settle (still moving at %.2f m/s)" % hit_car.linear_velocity.length())
	_check(hit_car.global_position.distance_to(origins[0]) > 0.3, "The shoved car must stay where it was pushed, not teleport back")
	_check(hit_car.global_transform.basis.y.y > 0.9, "The shoved car must stay upright")

	# Harder impacts push further: compare a slow nudge with the fast hit.
	var target := _lab.spawn_car(Vector3(40, 0.6, 200), 0.0, false)
	var slow := _lab.spawn_car(Vector3(40, 0.6, 186), 0.0, true)
	await _frames(60)
	var target_origin := target.global_position
	guard = 0
	while slow.global_position.z < 194.5 and guard < 900:
		slow.set_touch_move_input(Vector2(0, -0.35 if _speed(slow) < 12.0 * KMH else 0.0))
		await physics_frame
		guard += 1
	slow.set_touch_move_input(Vector2.ZERO)
	await _frames(360)
	var nudge := target.global_position.distance_to(target_origin)
	_check(nudge < displaced, "A slow nudge (%.2f m) must move a parked car less than a fast hit (%.2f m)" % [nudge, displaced])
	print("collision: fast hit at %.0f km/h moved parked car %.2f m; slow nudge moved one %.2f m" % [speed_at_impact * 3.6, displaced, nudge])

func _separated(a: RigidVehicle, b: RigidVehicle) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var shape_node := a.get_node("CollisionShape3D") as CollisionShape3D
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform.scaled_local(Vector3(0.97, 0.97, 0.97))
	params.collide_with_bodies = true
	for hit in a.get_world_3d().direct_space_state.intersect_shape(params, 16):
		if hit.collider == b:
			return false
	return true

func _make_vehicle_body() -> Node:
	var car := VehicleBody3D.new()
	car.mass = 1800.0
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	car.center_of_mass = Vector3(0, 0.55, 0.15)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.45, 4.28)
	shape.shape = box
	shape.position = Vector3(0, 1.17, -0.134)
	car.add_child(shape)
	for z in [1.3, -1.3]:
		for x in [-0.858, 0.858]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(x, 0.9, z)
			wheel.wheel_radius = 0.394
			wheel.wheel_rest_length = 0.506
			wheel.suspension_travel = 0.18
			wheel.suspension_stiffness = 40.0
			wheel.damping_compression = 2.3
			wheel.damping_relaxation = 2.8
			wheel.wheel_friction_slip = 2.0
			wheel.use_as_traction = true
			wheel.use_as_steering = z > 0.0
			car.add_child(wheel)
	_lab.add_child(car)
	return car

func _drive(car: Node, throttle: float, steer: float) -> void:
	if car is RigidVehicle:
		car.set_touch_move_input(Vector2(steer, -throttle))
	elif car is VehicleBody3D:
		var forward_speed: float = car.linear_velocity.dot(car.global_transform.basis.z)
		var braking := throttle < 0.0 and forward_speed > 0.5
		car.engine_force = 0.0 if braking else throttle * 7000.0
		car.brake = 60.0 if braking else 0.0
		car.steering = -steer * 0.5

func _set_parked(car: Node, value: bool) -> void:
	if car is RigidVehicle:
		car.set_driving_enabled(not value)
		car.set_input_authority(not value)
	elif car is VehicleBody3D:
		car.engine_force = 0.0
		car.brake = 60.0 if value else 0.0

func _place(car: Node3D, at: Vector3, yaw: float) -> void:
	var body := car as RigidBody3D
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(Vector3.UP, yaw), at))
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

func _speed(car: Node3D) -> float:
	return (car as RigidBody3D).linear_velocity.length()

func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
