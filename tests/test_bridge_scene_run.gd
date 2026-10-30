extends SceneTree

func _init():
	var scene_path = "res://scenes/world/godavari_bridge_driving.tscn"
	var packed: PackedScene = load(scene_path)
	assert(packed != null, "Scene must load")
	var instance = packed.instantiate() as Node3D
	root.add_child(instance)
	
	for frame in range(60):
		await physics_frame
	
	var car = instance.driven_vehicle
	assert(car != null, "Vehicle must be spawned")
	assert(car.wheel_contacts.all(func(c): return c), "All 4 wheels must contact bridge road deck")
	
	var start_z = car.global_position.z
	print("Car start Z on bridge: ", start_z)
	
	# Press forward (accelerate across bridge along -Z)
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for frame in range(45):
		await physics_frame
	car.set_touch_move_input(Vector2.ZERO)
	
	var end_z = car.global_position.z
	print("Car end Z on bridge: ", end_z)
	print("Car speed: ", car.current_speed)
	print("Car displacement along bridge: ", start_z - end_z)
	
	assert(end_z < start_z - 2.0, "Car must drive forward along the bridge")
	print("PASS: Driving physics and traction verified across the Godavari River Bridge!")
	
	instance.queue_free()
	quit()
