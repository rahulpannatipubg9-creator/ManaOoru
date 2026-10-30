extends SceneTree

func _init():
	var map_data = MapData.load_shared()
	var scene_path = "res://Godavarikhani_Bridge_3D/Godavarikhani_Bridge.glb"
	assert(ResourceLoader.exists(scene_path), "Bridge GLB must exist")
	
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
	
	var col_bodies = []
	_setup_collisions(bridge, col_bodies)
	
	print("Bridge loaded successfully!")
	print("  Position: ", bridge.position)
	print("  Rotation Y: ", rad_to_deg(bridge.rotation.y))
	print("  Collision bodies created: ", col_bodies.size())
	for b in col_bodies:
		print("    Body: ", b.name, " layer: ", b.collision_layer)
	
	assert(col_bodies.size() == 6, "Expected 6 collision bodies (2 road lanes + 4 barriers)")
	
	bridge.free()
	print("Bridge builder test passed!")
	quit()

func _setup_collisions(node: Node, col_bodies: Array):
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
			col_bodies.append(static_body)
		else:
			_setup_collisions(child, col_bodies)

