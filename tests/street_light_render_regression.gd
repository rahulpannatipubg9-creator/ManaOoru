extends SceneTree

func _init() -> void:
	var world_scene := load("res://scenes/world/world.tscn") as PackedScene
	assert(world_scene != null, "World scene must load")
	var world := world_scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var builder := world.get_node_or_null("StreetLife") as StreetLifeBuilder
	assert(builder != null, "StreetLifeBuilder must be present in generated world")
	assert(builder.pole_count > 0, "Streetlight poles must be generated")
	assert(not builder.lamp_positions.is_empty(), "Streetlight lamp positions must be generated")
	for obstacle: Vector2 in builder.road_obstacle_positions:
		assert(not world._is_on_any_road(obstacle, 0.15),
			"Roadside pole base must remain outside every mapped carriageway")
	var lamp_mesh_count := 0
	var furniture_mesh_count := 0
	for child in builder.get_children():
		if child is MeshInstance3D and child.name.begins_with("StreetLights_"):
			lamp_mesh_count += 1
			assert(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"Streetlight geometry must not shimmer through moving sun shadows")
		elif child is MeshInstance3D and child.name.begins_with("StreetLife_"):
			furniture_mesh_count += 1
	assert(lamp_mesh_count > 0, "Separate streetlight render meshes must exist")
	assert(furniture_mesh_count > 0, "Other street furniture must remain rendered")
	print("PASS streetlight render regression: %d poles, %d lamp meshes, %d street-life meshes; lamp shadows disabled" %
		[builder.pole_count, lamp_mesh_count, furniture_mesh_count])
	quit()
