extends SceneTree

func _init() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 60:
		await physics_frame
	var person := game.get_node("Player") as CharacterBody3D
	var car := game.get_node("Vehicle") as PhysicsBody3D
	var parked: Dictionary = {}
	for vehicle in game.vehicles:
		parked[vehicle] = vehicle.global_position
		print("before ", vehicle.name, " pos=", vehicle.global_position, " vel=", vehicle.linear_velocity if vehicle is RigidBody3D else Vector3.ZERO)
	person.global_position = car.global_position + car.global_transform.basis.x * -1.6
	game.enter_vehicle(car)
	for _frame in 300:
		await physics_frame
		if game.control_state == game.ControlState.DRIVING:
			break
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 60:
		await physics_frame
	car.set_touch_move_input(Vector2.ZERO)
	for vehicle in game.vehicles:
		print("after ", vehicle.name, " delta=", vehicle.global_position.distance_to(parked[vehicle]), " pos=", vehicle.global_position, " vel=", vehicle.linear_velocity if vehicle is RigidBody3D else Vector3.ZERO)
	game.queue_free()
	await process_frame
	quit()
