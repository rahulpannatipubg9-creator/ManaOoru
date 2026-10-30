extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(960,600)
	DisplayServer.window_set_size(Vector2i(960,600))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.visible = false
	var world = game.get_node("World")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var point: Vector2 = GeoProjection.world_to_map(world.player_spawn.position)
	var target := Vector3(point.x,world.ground_height(point)+1,point.y)
	camera.position = target + Vector3(12,4,17)
	camera.look_at(target)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/visual_polish/final_street.png")
	print("Saved final street")
	quit()
