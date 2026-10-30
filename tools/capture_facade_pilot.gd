extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1100,700)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.hide()
	var world = game.get_node("World")
	var builder = world.buildings
	var found := false
	for i in builder.building_metadata.size():
		var meta: Dictionary = builder.building_metadata[i]
		if not meta.appearance_evidence.has("photo_reference"):
			continue
		found = true
		assert(meta.floors == 2)
		var center := BuildingBuilder._centroid(builder.footprints[i])
		builder.build_around(center,100.0)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.current = true
		var target := Vector3(center.x,meta.base + 3.0,center.y)
		camera.position = target + Vector3(-22,8,-10)
		camera.look_at(target)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/facade_review/photo_pilot.png")
	assert(found,"Photo reference must bind to an actual generated building")
	print("PASS photo pilot: source building bound, two storeys, rendered screenshot")
	quit()
