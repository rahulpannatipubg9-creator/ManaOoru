extends SceneTree

func _init():
	var scene_path = "res://Godavarikhani_Bridge_3D/Godavarikhani_Bridge.glb"
	var packed: PackedScene = load(scene_path)
	var bridge = packed.instantiate()
	
	var abutment_x = 757.87
	var abutment_z = -3286.52
	var heading_deg = -4.57
	var ground_h = -25.07
	var deck_local_h = 12.43
	
	var heading_rad = deg_to_rad(heading_deg)
	var forward = Vector3(sin(heading_rad), 0.0, -cos(heading_rad))
	var center = Vector3(abutment_x, ground_h - deck_local_h, abutment_z) + forward * 550.0
	
	bridge.position = center
	bridge.rotation.y = deg_to_rad(90.0) + heading_rad
	
	_setup_collisions(bridge)
	root.add_child(bridge)
	
	# Load a vehicle
	var car_scene: PackedScene = load("res://scenes/vehicles/rigid_thar.tscn")
	var car = car_scene.instantiate() as RigidVehicle
	car.position = Vector3(751.5, -24.5, -3350.0)
	car.rotation.y = heading_rad
	root.add_child(car)
	
	print("Vehicle placed above bridge at: ", car.position)
	
	# Run 60 physics frames
	for frame in range(60):
		await physics_frame
	
	print("Vehicle settled at position: ", car.position)
	print("Wheel contacts: ", car.wheel_contacts)
	print("Linear velocity: ", car.linear_velocity)
	
	# Check that vehicle is resting on bridge (Y around -25.0 to -24.8) and has not fallen through
	assert(car.position.y > -26.0 and car.position.y < -24.0, "Car must rest on bridge deck")
	assert(car.wheel_contacts.any(func(c): return c), "At least some wheels must contact bridge deck")
	
	print("PASS: Vehicle successfully drove/settled on the Godavarikhani Bridge!")
	car.queue_free()
	bridge.queue_free()
	quit()

func _setup_collisions(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D and child.name.begins_with("COL_"):
			var static_body = StaticBody3D.new()
			static_body.name = child.name + "_Static"
			static_body.transform = child.transform
			var is_road = child.name.begins_with("COL_Road")
			static_body.collision_layer = 3 if is_road else 1
			static_body.collision_mask = 0
			var col_shape = CollisionShape3D.new()
			col_shape.shape = child.mesh.create_trimesh_shape()
			static_body.add_child(col_shape)
			child.get_parent().add_child(static_body)
			child.visible = false
		else:
			_setup_collisions(child)
