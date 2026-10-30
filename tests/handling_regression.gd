extends SceneTree

## GTA-style handling: stable straight line, grippy cornering without spinning at
## speed, handbrake drifts that the countersteer assist catches, self-centring wheel.

var _failures := 0

func _car(path: String) -> RigidBody3D:
	var car := (load(path) as PackedScene).instantiate() as RigidBody3D
	root.add_child(car)
	car.set_driving_enabled(true)
	car.set_input_authority(true)
	for _f in 30:
		await physics_frame
	return car
func _launch(car: RigidBody3D, speed: float) -> void:
	car.sleeping = false
	car.linear_velocity = car.global_basis.z * speed
func _slip(car: RigidBody3D) -> float:
	var v := car.global_basis.inverse() * car.linear_velocity
	return rad_to_deg(atan2(v.x, maxf(absf(v.z), 0.5)))
func _init() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(6000, 1, 6000)
	cs.shape = b
	cs.position.y = -0.5
	ground.add_child(cs)
	root.add_child(ground)
	for path in ["res://scenes/vehicles/porsche_911.tscn", "res://scenes/vehicles/rigid_thar.tscn"]:
		var label: String = path.get_file().get_basename()
		var car: RigidBody3D = await _car(path)
		_launch(car, 27.8)
		car.set_touch_move_input(Vector2(0, -0.6))
		var yaw0: float = car.rotation.y
		for _f in 180:
			await physics_frame
		_check(absf(rad_to_deg(angle_difference(yaw0, car.rotation.y))) < 1.0, "%s: must run straight with no steering" % label)
		car.queue_free()
		await physics_frame
		car = await _car(path)
		_launch(car, 11.1)
		car.set_touch_move_input(Vector2(-0.5, -0.4))
		var maxb := 0.0
		for _f in 180:
			await physics_frame
			maxb = maxf(maxb, absf(_slip(car)))
		_check(maxb < 10.0 and absf(rad_to_deg(car.angular_velocity.y)) > 25.0, "%s: must corner on its tyres at 40 km/h (slip %.1f deg)" % [label, maxb])
		car.queue_free()
		await physics_frame
		car = await _car(path)
		_launch(car, 22.2)
		car.set_touch_move_input(Vector2(-1, -0.5).normalized())
		maxb = 0.0
		var up_min := 1.0
		for _f in 120:
			await physics_frame
			maxb = maxf(maxb, absf(_slip(car)))
			up_min = minf(up_min, car.global_basis.y.y)
		_check(maxb < 20.0 and up_min > 0.9, "%s: full lock at 80 km/h must not spin or roll it (slip %.1f deg)" % [label, maxb])
		car.queue_free()
		await physics_frame
		car = await _car(path)
		_launch(car, 13.9)
		car.set_touch_move_input(Vector2(-1, 0))
		Input.action_press("vehicle_handbrake")
		yaw0 = car.rotation.y
		maxb = 0.0
		for _f in 45:
			await physics_frame
			maxb = maxf(maxb, absf(_slip(car)))
		Input.action_release("vehicle_handbrake")
		car.set_touch_move_input(Vector2(0, -0.3))
		var turned := rad_to_deg(angle_difference(yaw0, car.rotation.y))
		var rec := -1.0
		var assisted := false
		for f in 240:
			await physics_frame
			maxb = maxf(maxb, absf(_slip(car)))
			assisted = assisted or (absf(_slip(car)) > 10.0 and signf(car._steer) == signf(_slip(car)))
			if rec < 0.0 and absf(_slip(car)) < 8.0 and f > 10:
				rec = f / 60.0
		_check(absf(turned) > 60.0 and maxb > 20.0, "%s: a handbrake turn must swing the rear out (turned %.0f, slip %.0f)" % [label, turned, maxb])
		_check(assisted, "%s: the front wheels must steer into the slide when the player lets go" % label)
		_check(rec > 0.0 and rec < 2.0, "%s: the slide must be caught after the handbrake is released (%.2f s)" % [label, rec])
		car.queue_free()
		await physics_frame
		car = await _car(path)
		_launch(car, 11.1)
		car.set_touch_move_input(Vector2(-1, -0.3))
		for _f in 30:
			await physics_frame
		car.set_touch_move_input(Vector2(0, -0.3))
		var t := -1.0
		for f in 60:
			await physics_frame
			if t < 0.0 and absf(car._steer) < 0.02:
				t = f / 60.0
		_check(t > 0.0 and t < 0.4, "%s: the wheel must return to centre when released (%.2f s)" % [label, t])
		car.queue_free()
		await physics_frame
	if _failures > 0:
		print("FAIL handling regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS handling regression: straight-line stability, cornering grip, no spin at speed, handbrake drift, countersteer assist, self-centring (Porsche, Thar)")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
