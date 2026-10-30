extends SceneTree

const EPSILON := 0.02
var _failures := 0

func _init() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 5:
		await physics_frame
	var person := game.get_node("Player") as CharacterBody3D
	var car := game.get_node("Vehicle") as PhysicsBody3D
	var person_pivot := person.get_node("CameraPivot") as Node3D
	var car_pivot := car.get_node("CameraPivot") as Node3D
	var person_arm := person_pivot.get_node("SpringArm3D") as SpringArm3D
	var car_arm := car_pivot.get_node("SpringArm3D") as SpringArm3D
	var third_person_position: Vector3 = person_pivot._third_person_position
	var third_person_length := person_arm.spring_length

	# V: third person -> first person on foot.
	game.toggle_camera_view()
	await process_frame
	_check(person_pivot.is_first_person() and car_pivot.is_first_person(), "V must switch every camera to first person")
	_check(person_arm.spring_length == 0.0, "First-person camera must sit at the eye, not on a boom")
	_check(person_pivot.position.distance_to(person_pivot.first_person_offset) < EPSILON, "First-person camera must move to the head")
	var walk_yaw: float = person_pivot.movement_yaw()
	person.rotation.y += 1.0
	await process_frame
	_check(absf(angle_difference(person_pivot.movement_yaw(), walk_yaw)) < EPSILON,
		"On-foot first-person look must not spin when the body turns towards its walk direction")

	# C: look behind on foot keeps walking controls pointing the same way.
	Input.action_press("camera_look_behind")
	await process_frame
	_check(_camera_faces(person_pivot, -person.global_basis.z), "C must look behind the person")
	_check(absf(angle_difference(person_pivot.movement_yaw(), walk_yaw)) < EPSILON, "Looking behind must not flip WASD")
	Input.action_release("camera_look_behind")
	await process_frame
	_check(absf(angle_difference(_camera_yaw(person_pivot), walk_yaw)) < EPSILON, "Releasing C must restore the previous view")

	# Driving in first person: the view is locked to the dashboard and turns with the car.
	person.set_movement_enabled(false)
	person.global_position = car.global_position + car.global_basis.x * -2.0
	game.enter_vehicle(car)
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	_check(car_pivot.is_first_person(), "First-person choice must carry into the vehicle")
	_check(car_arm.spring_length == 0.0, "Vehicle first-person camera must sit in the driver's seat")
	_check(_camera_faces(car_pivot, car.global_basis.z), "Vehicle first-person camera must look out of the windscreen")
	car.rotation.y += 0.8
	await process_frame
	_check(_camera_faces(car_pivot, car.global_basis.z), "Vehicle first-person camera must turn with the car")
	var eye := car.to_local((car_pivot.get_node("SpringArm3D/Camera3D") as Camera3D).global_position)
	_check(eye.x < 0.0 and eye.y > 1.0, "Driver's eye must be on the driver's side above the bonnet")
	_check(eye.y >= 1.65 and eye.z >= 0.10, "Thar driver eye must clear the tall dashboard and rear seat obstruction")

	# C while driving: rear view out of the back window, then straight back to the road ahead.
	Input.action_press("camera_look_behind")
	await process_frame
	_check(_camera_faces(car_pivot, -car.global_basis.z), "C must show the rear view while driving")
	Input.action_release("camera_look_behind")
	await process_frame
	_check(_camera_faces(car_pivot, car.global_basis.z), "Releasing C must return to the road ahead")

	# Back to third person: chase camera behind the car, GTA-style rear view in front of it.
	game.toggle_camera_view()
	await process_frame
	_check(not car_pivot.is_first_person() and not person_pivot.is_first_person(), "V must switch back to third person")
	_check(absf(car_arm.spring_length - car_pivot.camera_distance) < EPSILON, "Third-person camera must restore its boom length")
	await process_frame
	_check(person.to_local(person_pivot.global_position).distance_to(third_person_position) < 0.05
		and absf(person_arm.spring_length - third_person_length) < EPSILON, "Person third-person camera must be restored")
	Input.action_press("camera_look_behind")
	for _frame in 3:
		await process_frame
	var rear_camera := car_pivot.get_node("SpringArm3D/Camera3D") as Camera3D
	_check(car.to_local(rear_camera.global_position).z > 1.0, "Third-person rear view must swing the camera in front of the car")
	_check(_camera_faces(car_pivot, -car.global_basis.z), "Third-person rear view must look back past the car")
	Input.action_release("camera_look_behind")

	if _failures > 0:
		print("FAIL camera regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS camera regression: V first/third person on foot and driving, B look behind, WASD stability, view restore")
	quit()

func _camera_yaw(pivot: Node3D) -> float:
	return pivot.global_rotation.y

func _camera_faces(pivot: Node3D, direction: Vector3) -> bool:
	var camera := pivot.get_node("SpringArm3D/Camera3D") as Camera3D
	var forward := -camera.global_basis.z
	var flat_forward := Vector2(forward.x, forward.z).normalized()
	var flat_direction := Vector2(direction.x, direction.z).normalized()
	return flat_forward.dot(flat_direction) > 0.95

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
