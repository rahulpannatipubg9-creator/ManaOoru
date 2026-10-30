extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 1, 1000)
	collision.shape = box
	collision.position.y = -0.5
	ground.add_child(collision)
	root.add_child(ground)
	var water = load("res://scripts/gameplay/water_system.gd").new()
	root.add_child(water)
	water.regions.append({"points": PackedVector2Array([Vector2(-100,-100),Vector2(100,-100),Vector2(100,100),Vector2(-100,100)]), "height": 10.0, "center": Vector2.ZERO})
	for kind: String in ["motorcycle", "boat", "plane"]:
		var vehicle = load("res://scripts/gameplay/arcade_vehicle.gd").new()
		vehicle.kind = kind
		vehicle.water = water
		vehicle.position = Vector3(0, 100, 0)
		root.add_child(vehicle)
		vehicle.fall_limit = -200.0
		GameplayControls.owner_id = vehicle.get_instance_id()
		GameplayControls.blocked = false
		vehicle.set_input_authority(true)
		vehicle.set_driving_enabled(true)
		vehicle.set_keyboard_input_enabled(false)
		if kind == "motorcycle":
			vehicle.global_position = Vector3(0, 0.4, 0)
			vehicle.settle_on_ground()
			for i in 120: await physics_frame
			check(absf(vehicle.global_position.y) < 1.0 and vehicle.global_basis.y.dot(Vector3.UP) > 0.8, "Motorcycle balances on suspension")
			vehicle.set_touch_move_input(Vector2(0,-1))
			for i in 150: await physics_frame
			check(vehicle.current_speed > 3.0 and vehicle.global_position.z > 3.0, "Motorcycle accelerates forward")
		elif kind == "boat":
			vehicle.global_position = Vector3(0, 10.2, 0)
			for i in 120: await physics_frame
			check(absf(vehicle.global_position.y - 10.15) < 0.7, "Boat floats at mapped surface")
			vehicle.set_touch_move_input(Vector2(0,-1))
			for i in 120: await physics_frame
			check(vehicle.global_position.z > 3.0, "Boat propulsion moves across water")
		else:
			vehicle.global_position = Vector3(0, 100, 0)
			vehicle.linear_velocity = Vector3(0,0,30)
			for i in 45: await physics_frame
			check(vehicle.global_position.y > 99.0 and vehicle.linear_velocity.y > 0.0, "Fixed-wing lift supports flight at speed")
		check(is_finite(vehicle.global_position.x) and is_finite(vehicle.global_position.y), kind + " remains numerically stable")
		vehicle.queue_free()
		await process_frame
	print("PASS expansion vehicle physics" if failures == 0 else "FAIL expansion vehicle physics: %d" % failures)
	quit(0 if failures == 0 else 1)
