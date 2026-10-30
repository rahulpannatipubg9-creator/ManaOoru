extends SceneTree

## Walks every menu with real key events: Esc steps back one screen at a time, the paused
## pause menu reaches Settings with a free mouse, Team Deathmatch never pauses the tree,
## and the Settings pages hide what this device or build should not show.

var _failures := 0
var _game: Node

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)

func press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	# Polling and event handlers both see the key, as they do with a real press.
	if keycode == KEY_ESCAPE:
		Input.action_press("pause")
	root.push_input(event)
	await settle()
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	if keycode == KEY_ESCAPE:
		Input.action_release("pause")
	root.push_input(release)
	await settle()

func settle() -> void:
	for frame in 3:
		await process_frame

func focused() -> Control:
	return root.gui_get_focus_owner()

func run() -> void:
	_game = load("res://scenes/main.tscn").instantiate()
	root.add_child(_game)
	for frame in 10:
		await process_frame
	var settings: CanvasLayer = _game.hud.settings_menu
	var pause: CanvasLayer = settings.pause_menu
	var life: Node = _game.city_life
	life.save_enabled = false

	await press(KEY_ESCAPE)
	check(pause.is_open() and paused, "Esc opens the pause menu and pauses")
	check(focused() == pause.buttons["Resume"], "Resume takes keyboard focus")
	await press(KEY_ESCAPE)
	check(not pause.is_open() and not paused, "Esc on the pause menu resumes")

	# Coordinator bug: Settings must open from the paused pause menu, with a free mouse.
	pause.open_menu()
	await settle()
	pause.buttons["Settings"].pressed.emit()
	await settle()
	check(settings.panel.visible and not pause.is_open(), "Settings opens from the paused pause menu")
	check(paused, "The game stays paused under Settings")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Settings has a free mouse")
	check(focused() == settings.tabs.get_tab_bar(), "Settings starts on the tabs")
	await press(KEY_ESCAPE)
	check(pause.is_open() and not settings.panel.visible and paused, "Esc in Settings returns to the pause menu")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The pause menu keeps a free mouse")

	# Map from the pause menu, then back.
	pause.buttons["Map"].pressed.emit()
	await settle()
	check(_game.is_map_open() and not pause.is_open() and paused, "Map opens from the pause menu")
	await press(KEY_ESCAPE)
	check(not _game.is_map_open() and pause.is_open() and paused, "Esc on the map returns to the pause menu")

	# Activities from the pause menu: Esc returns, a choice leaves.
	pause.buttons["Activities"].pressed.emit()
	await settle()
	check(life.has_modal() and paused and not pause.is_open(), "Activities opens from the pause menu")
	check(focused() is BaseButton, "Activities has keyboard focus")
	await press(KEY_ESCAPE)
	check(not life.has_modal() and pause.is_open(), "Esc on Activities returns to the pause menu")
	await press(KEY_ESCAPE)
	check(not pause.is_open() and not paused, "The pause menu closes after Activities")

	# Journal through the board keeps the way back.
	_game.gameplay.open_board()
	await settle()
	check(paused and life.has_modal(), "F7 path opens Activities straight over the game")
	await press(KEY_ESCAPE)
	check(not paused and not life.has_modal() and not pause.is_open(), "Esc from a direct board goes to the game")
	pause.open_menu()
	await settle()
	pause.buttons["Activities"].pressed.emit()
	await settle()
	_game.gameplay._board_to_journal()
	await settle()
	await press(KEY_ESCAPE)
	check(life.has_modal(), "Esc on the journal returns to Activities")
	await press(KEY_ESCAPE)
	check(pause.is_open(), "Esc again returns to the pause menu")
	await press(KEY_ESCAPE)

	# Squad from the pause menu.
	pause.open_menu()
	await settle()
	pause.buttons["Squad"].pressed.emit()
	await settle()
	check(_game.hud.multiplayer_panel.visible and not pause.is_open(), "Squad opens from the pause menu")
	await press(KEY_ESCAPE)
	check(not _game.hud.multiplayer_panel.visible and pause.is_open(), "Esc in Squad returns to the pause menu")
	await press(KEY_ESCAPE)

	# Settings opened directly goes back to the game, and F6 lands on its tab.
	_game.environment_controls.open_menu()
	await settle()
	check(settings.tabs.get_tab_title(settings.tabs.current_tab) == "Time & Weather", "F6 path opens Time & Weather")
	await press(KEY_ESCAPE)
	check(not settings.panel.visible and not paused and not pause.is_open(), "Esc from direct Settings returns to the game")

	# Pages for this device and build.
	var titles: Array[String] = []
	for index: int in settings.tabs.get_tab_count():
		if not settings.tabs.is_tab_hidden(index):
			titles.append(settings.tabs.get_tab_title(index))
	check(titles.slice(0, 4) == ["Controls", "Graphics", "Audio", "Time & Weather"], "Four settings tabs in order: %s" % [titles])
	var developer_tab: bool = settings.tabs.is_tab_hidden(settings.tabs.get_tab_count() - 1)
	check(developer_tab == not settings.developer_visible(), "Developer tab follows its gate")
	var dev_arg: bool = "--dev" in OS.get_cmdline_user_args()
	if not dev_arg:
		check(not settings.developer_visible(), "Developer tools are off by default")
	check(settings.controls.gyro_mode.get_parent().visible == _game.hud._touch_overlay_enabled, "Gyro rows follow the touch overlay")
	var credit_button: Button = settings._credits
	check(not credit_button.visible, "Credits stays hidden without a hook")
	settings.credits_action = func() -> void: pass
	check(credit_button.visible, "The credits hook shows its button")
	settings.credits_action = Callable()

	# Team Deathmatch never pauses, and the menu still gives a free mouse.
	_game.tdm_local.in_match = true
	pause.open_menu()
	await settle()
	check(pause.is_open() and not paused, "The pause menu leaves a live match running")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "A live match menu has a free mouse")
	check(not pause.buttons["Activities"].visible, "Activities hides during a match")
	pause.buttons["Settings"].pressed.emit()
	await settle()
	check(settings.panel.visible and not paused, "Settings leaves a live match running")
	await press(KEY_ESCAPE)
	check(pause.is_open() and not paused, "Esc in match Settings returns to the pause menu")
	await press(KEY_ESCAPE)
	check(not pause.is_open() and not paused, "Esc closes the match menu")
	_game.tdm_local.in_match = false

	if _failures == 0:
		print("PASS pause menu: Esc steps back everywhere, Settings opens while paused, match stays live")
	_game.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)
