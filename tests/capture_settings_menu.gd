extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(10): await process_frame
	assert(game.hud.settings_menu != null)
	game.hud.settings_menu.open_menu()
	assert(paused and game.hud.settings_menu.panel.visible)
	game.hud.settings_menu.graphics_preset.get_parent().get_parent().get_parent().current_tab = 3
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/Users/rahulpannati/Documents/Codex/2026-10-27/wha/outputs/graphics-settings.png")
	game.hud.settings_menu.panel.hide()
	paused = false
	print("PASS centralized settings opens and pauses gameplay")
	quit(0)
