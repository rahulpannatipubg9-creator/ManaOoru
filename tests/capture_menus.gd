extends SceneTree

## Opens every menu screen in a real window and saves a PNG of each.
## Run windowed: godot --path . --script tests/capture_menus.gd -- <output-dir> [--dev]

var _out := "user://menu_captures"
var _game: Node

func _init() -> void:
	run.call_deferred()

func shot(title: String) -> void:
	for frame in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, title]
	var result := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s %s" % [path, error_string(result)])

func back() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.action_press("pause")
	root.push_input(event)
	for frame in 3:
		await process_frame
	Input.action_release("pause")
	for frame in 3:
		await process_frame

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			_out = argument
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	_game = load("res://scenes/main.tscn").instantiate()
	root.add_child(_game)
	for frame in 30:
		await process_frame
	var settings: CanvasLayer = _game.hud.settings_menu
	var pause: CanvasLayer = settings.pause_menu
	var life: Node = _game.city_life
	life.save_enabled = false
	pause.open_menu()
	await shot("01_pause")
	pause.buttons["Settings"].pressed.emit()
	for index: int in settings.tabs.get_tab_count():
		if settings.tabs.is_tab_hidden(index):
			continue
		settings.tabs.current_tab = index
		await shot("02_settings_%d_%s" % [index, settings.tabs.get_tab_title(index).replace(" & ", " ").to_snake_case()])
	await back()
	pause.buttons["Activities"].pressed.emit()
	await shot("03_activities")
	_game.gameplay._board_to_journal()
	await shot("04_journal")
	await back()
	await back()
	await back()
	life.open_shop({"name": "Local shop", "kind": "fuel", "position": _game.person.global_position})
	await shot("05_shop")
	life.close_modal()
	if not _game.gameplay.market.shops.is_empty():
		_game.gameplay.market.open_shop(_game.gameplay.market.shops[0])
		await shot("06_market_shop")
		life.close_modal()
	_game.set_map_open(true)
	await shot("07_map")
	_game.hud.full_map._search.grab_focus()
	await shot("08_map_search")
	_game.hud.full_map._search.release_focus()
	_game.set_map_open(false)
	print("CAPTURE DONE")
	_game.queue_free()
	await process_frame
	quit()
