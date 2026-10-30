extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var game: Node = main_scene.instantiate()
	root.add_child(game)
	for i in range(15):
		await process_frame

	if game.get("hud") and game.hud.has_method("toggle_multiplayer_panel"):
		game.hud.toggle_multiplayer_panel()

	for i in range(10):
		await process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var img := root.get_viewport().get_texture().get_image()
	if img:
		img.save_png(ProjectSettings.globalize_path("res://outputs/bgmi_milestone2_multiplayer.png"))
		print("Saved screenshot to outputs/bgmi_milestone2_multiplayer.png")

	quit(0)
