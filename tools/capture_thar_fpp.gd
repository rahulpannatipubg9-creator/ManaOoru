extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.hide()
	var car = game.get_node("Vehicle")
	var pivot = car.get_node("CameraPivot")
	pivot.set_view_mode(pivot.ViewMode.FIRST_PERSON)
	pivot.get_node("SpringArm3D/Camera3D").current = true
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/mana_thar_fpp.png")
	quit()
