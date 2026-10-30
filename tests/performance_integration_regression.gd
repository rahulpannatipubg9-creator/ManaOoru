extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(10): await process_frame
	var controller = game.performance_controller
	assert(controller != null)
	controller.settings.select("Low")
	controller.apply_settings()
	assert(Engine.max_fps == 30 and is_equal_approx(root.scaling_3d_scale, 0.65))
	assert(not game.get_node("Sun").shadow_enabled)
	assert(game.get_node("World").buildings.stream_radius == 320.0)
	assert(controller.active_ambient_count <= 12)
	assert(game.city_life.environment.effects_budget == 0.25)
	controller.settings.select("High")
	controller.apply_settings()
	assert(Engine.max_fps == 60 and root.scaling_3d_scale == 1.0)
	assert(controller.active_ambient_count <= 55)
	game.hud.settings_menu.open_menu()
	assert(paused and game.hud.settings_menu.graphics_controls.size() == 7)
	print("PASS performance integration: resolution, cap, shadow, streaming, population, weather and settings tab")
	game.hud.settings_menu.panel.hide()
	paused = false
	quit(0)
