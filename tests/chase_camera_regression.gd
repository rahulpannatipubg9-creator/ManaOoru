extends SceneTree

var _failures := 0

func _init() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 1.0, 4000.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var car := (load("res://scenes/vehicles/porsche_911.tscn") as PackedScene).instantiate()
	root.add_child(car)
	var pivot := car.get_node("CameraPivot") as Node3D
	var camera := car.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	for _frame in 60:
		await physics_frame
	var base_fov := camera.fov

	# Parked: the camera stays wherever the player left it.
	pivot._yaw = car.global_rotation.y + PI + 1.4
	var parked_yaw: float = pivot._yaw
	for _frame in 120:
		await process_frame
	_check(absf(angle_difference(pivot._yaw, parked_yaw)) < 0.01, "Chase camera must not move while the car is parked")

	# Driving straight: it swings round behind the car once the mouse is left alone.
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 180:
		await physics_frame
	_check(_behind_error(car, pivot) < 0.15, "Chase camera must settle behind a moving car (off by %.2f rad)" % _behind_error(car, pivot))
	_check(camera.fov > base_fov + 2.0, "Field of view must widen with speed (%.1f -> %.1f)" % [base_fov, camera.fov])

	# Cornering: it trails the turn rather than snapping to it.
	car.set_touch_move_input(Vector2(-1.0, -1.0).normalized())
	var max_lag := 0.0
	for _frame in 90:
		await physics_frame
		max_lag = maxf(max_lag, _behind_error(car, pivot))
	_check(max_lag > 0.02 and max_lag < 1.2, "Chase camera must lag a little behind the turn (max %.2f rad)" % max_lag)

	# Looking around with the mouse holds the camera until the player lets go.
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 60:
		await physics_frame
	pivot._look(Vector2(1.2, 0.0))
	var looked_yaw: float = pivot._yaw
	for _frame in 30:
		await process_frame
	_check(absf(angle_difference(pivot._yaw, looked_yaw)) < 0.05, "Mouse look must hold the camera for a moment")
	for _frame in 240:
		await physics_frame
	_check(_behind_error(car, pivot) < 0.2, "Camera must swing back behind the car after the mouse goes quiet")

	if _failures > 0:
		print("FAIL chase camera regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS chase camera regression: parked hold, settles behind, trails turns, speed FOV, mouse look hold and return")
	quit()

## Angle between the camera's view and the car's direction of travel.
func _behind_error(car: Node3D, pivot: Node3D) -> float:
	var camera := pivot.get_node("SpringArm3D/Camera3D") as Camera3D
	var view := -camera.global_basis.z
	var travel: Vector3 = car.velocity if car.velocity.length() > 1.0 else car.global_basis.z
	return absf(Vector2(view.x, view.z).angle_to(Vector2(travel.x, travel.z)))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
