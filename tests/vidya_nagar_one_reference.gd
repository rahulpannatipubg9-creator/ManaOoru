extends SceneTree
func _init() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var world: Node = game.get_node("World")
	var entrance: Node3D = world.get_node("VidyaNagar1PhotoEntrance")
	assert(entrance != null and entrance.basis.determinant() > 0.99, "Entrance must exist with unmirrored lettering")
	assert(entrance.get_meta("clearance") >= 5, "Arch needs vehicle headroom")
	assert(entrance.has_node("DenseOverheadServiceWires"), "Photo-reference wiring must exist")
	var half: float = entrance.get_meta("road_half_width")
	for child in entrance.get_children():
		if str(child.name).begins_with("RustyArchUpright"):
			assert(absf(child.position.x) > half + 0.5, "Arch uprights must stand outside the carriageway")
			var p: Vector3 = child.global_position
			assert(world.buildings.is_clear(Vector2(p.x, p.z), 0.25), "Arch support must not intersect a building")
	assert(entrance.find_children("*", "MeshInstance3D", true, false).size() < 100, "Keep local furniture bounded")
	print("PASS Vidya Nagar 1: local entrance integration, road clearance, readable orientation, overhead wiring, bounded geometry")
	if "--capture" in OS.get_cmdline_user_args():
		game.environment_controls.environment.set_time_mode("Afternoon")
		var point := GeoProjection.lon_lat_to_map(79.5158116, 18.7544193)
		world.buildings.build_around(point, 100)
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.position = Vector3(point.x, world.ground_height(point) + 2.0, point.y)
		camera.look_at(entrance.global_position + Vector3.UP * 3.4)
		camera.current = true
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_vidya_nagar_one.png")
	game.queue_free()
	await process_frame
	quit()
