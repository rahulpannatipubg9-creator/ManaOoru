extends SceneTree

func _init() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var data := MapData.load_shared()
	var buildings := BuildingBuilder.new()
	root.add_child(buildings)
	buildings.setup(data, func(_points: PackedVector2Array) -> bool: return false)
	var found := false
	var center := Vector2.ZERO
	var base := 0.0
	for index in buildings.building_metadata.size():
		if str(buildings.building_metadata[index].id).trim_suffix(".0") == preload("res://scripts/world/cinema_poster_wall.gd").BUILDING_ID:
			found = true
			center = buildings._centroid(buildings.footprints[index])
			base = buildings.building_metadata[index].base
	assert(found, "Photo-reference neighbouring footprint must exist")
	buildings.build_around(center, 90.0)
	var wall := buildings.find_child("AshokRoadMoviePosterWall", true, false)
	assert(wall != null, "Poster wall must be integrated into its building chunk")
	var posters: MeshInstance3D = wall.get_node("WeatheredMoviePosters")
	assert(posters.mesh.get_surface_count() == 1, "Posters must share a single mesh surface")
	assert(posters.material_override.albedo_texture != null, "Offline poster texture must load")
	var arrays := posters.mesh.surface_get_arrays(0)
	assert(arrays[Mesh.ARRAY_VERTEX].size() >= 36, "Frontage needs multiple poster panels")
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		assert(vertex.y >= base + 0.19 and vertex.y < base + 1.7, "Paper must stay in wall band")
	print("PASS cinema posters: mapped neighbour, chunk integration, offline atlas, single poster surface, wall-height clearance")
	if "--capture" in OS.get_cmdline_user_args():
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color("a6c4ce")
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color.WHITE
		settings.ambient_light_energy = 0.7
		environment.environment = settings
		root.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		root.add_child(sun)
		var viewpoint := GeoProjection.lon_lat_to_map(79.515554, 18.7541618)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(viewpoint.x, base + 3.0, viewpoint.y)
		camera.look_at(Vector3(center.x, base + 1.5, center.y))
		camera.current = true
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_movie_posters.png")
	buildings.queue_free()
	await process_frame
	quit()
