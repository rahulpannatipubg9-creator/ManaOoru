extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(25):
		await process_frame

	if game.has_node("HUD"):
		game.get_node("HUD").visible = false

	var world = game.get_node("World")
	var stadium = world.find_child("stadium_with_swimming_pool", true, false)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.current = true

	var target_pos := Vector3(542.9, 7.1, 979.2)
	if stadium != null:
		target_pos = stadium.global_position

	# Ground-level player perspective: standing on the pitch edge looking at the pavilion and Telugu signboard
	camera.global_position = target_pos + Vector3(0.0, 4.0, -10.0)
	camera.look_at(target_pos + Vector3(0.0, 5.0, 15.0), Vector3.UP)

	for i in range(15):
		await process_frame
	RenderingServer.force_draw()

	var art_path := "/Users/rahulpannati/.gemini/antigravity/brain/9fb53f81-6420-4ef4-bdaa-ac2ddffc036c/stadium_player_view.png"
	root.get_texture().get_image().save_png(art_path)
	print("Saved player view to: ", art_path)
	quit()
