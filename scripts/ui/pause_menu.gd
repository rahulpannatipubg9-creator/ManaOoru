extends CanvasLayer
## The one pause menu: Resume, Map, Activities, Squad, Settings, Quit.
## It also routes Esc, so Esc steps back one screen wherever the player is.
## A live Team Deathmatch never pauses: game.pause_tree refuses, and the menu sits over the match.

enum Page { NONE, MAP, SETTINGS, SQUAD }

const WIDTH := 320.0

var panel: PanelContainer
var buttons: Dictionary = {}
var _card: PanelContainer
var _hud: Node
var _settings: CanvasLayer
var _game: Node
var _page := Page.NONE
var _wired := false
var _owned_last_frame := false

func setup(owner_hud: Node, settings: CanvasLayer) -> void:
	_hud = owner_hud
	_settings = settings
	layer = 34
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "PauseMenu"
	panel.theme = UiTheme.theme()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DIM, 0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card.custom_minimum_size.x = WIDTH
	panel.add_child(_card)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_S)
	_card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_S)
	margin.add_child(column)
	for item: Array in [["Resume", close_menu], ["Map", _open_map], ["Activities", _open_activities],
			["Squad", _open_squad], ["Settings", _open_settings], ["Quit", _quit]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size.y = UiTheme.TOUCH_TARGET + UiTheme.SPACE_XS
		button.pressed.connect(item[1])
		column.add_child(button)
		buttons[item[0]] = button
	UiTheme.make_primary(buttons["Resume"])
	panel.hide()
	settings.closed.connect(_on_settings_closed)

func is_open() -> bool:
	return panel.visible

func open_menu() -> void:
	if not _available() or panel.visible or _page != Page.NONE or _screen_up():
		return
	_wire()
	_game._clear_control_inputs()
	_game.pause_tree(true)
	_show_panel()

func close_menu() -> void:
	if not panel.visible:
		return
	panel.hide()
	_page = Page.NONE
	_resume_game()

## True while Esc and M belong to these menus, so main's polling leaves them alone. It stays
## true for one frame after a screen closes: that press was the close, not a new pause.
func owns_keys() -> bool:
	return _owned_last_frame or _keys_are_ours()

## Steps back one screen.
func back() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		focused.release_focus()
	elif _game.city_life.has_modal():
		_game.city_life.back_modal()
	elif _settings.panel.visible:
		_settings.close_menu()
	elif _lobby_open():
		_hud.toggle_multiplayer_panel()
	else:
		close_menu()

func _process(_delta: float) -> void:
	if not _available():
		return
	_owned_last_frame = _keys_are_ours()
	# The layout editor draws over Settings, and this menu must not show through it.
	panel.modulate.a = 0.0 if _layout_editor_open() else 1.0

func _input(event: InputEvent) -> void:
	if not _available() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("pause") and _keys_are_ours():
		if not _layout_editor_open():
			back()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("map_toggle"):
		_open_map()
		get_viewport().set_input_as_handled()

## Only the free-roam game has a pause menu; the sketch map shares this HUD but not the game.
func _available() -> bool:
	_game = _hud._game
	return _game != null and _game.has_method("pause_tree")

func _keys_are_ours() -> bool:
	return _screen_up() or panel.visible or _layout_editor_open() or _lobby_open() \
		or GameplayControls.text_focused(get_viewport())

## A full-screen menu is up, whatever the tree's pause state.
func _screen_up() -> bool:
	return _settings.panel.visible or (is_instance_valid(_game.city_life) and _game.city_life.has_modal())

func _menu_up() -> bool:
	return panel.visible or _screen_up()

func _lobby_open() -> bool:
	return is_instance_valid(_hud.multiplayer_panel) and _hud.multiplayer_panel.visible

func _layout_editor_open() -> bool:
	return is_instance_valid(_hud._layout_editor) and _hud._layout_editor.is_open()

func _in_match() -> bool:
	return _game.tdm_local != null and _game.tdm_local.in_match

## The map is made after this menu, so these are connected on first use.
func _wire() -> void:
	if _wired:
		return
	_wired = true
	_hud.full_map.visibility_changed.connect(_on_map_visibility)
	_hud.multiplayer_panel.visibility_changed.connect(_on_lobby_visibility)
	var bridge: Node = _hud.get_node_or_null("MenuTouchBridge")
	if bridge != null:
		bridge.live_menu = _menu_up

func _show_panel() -> void:
	_page = Page.NONE
	buttons["Activities"].visible = not _in_match()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	buttons["Resume"].grab_focus()
	_card.create_tween().tween_property(_card, "modulate:a", 1.0, UiTheme.MOTION_FAST).from(0.01)

func _resume_game() -> void:
	_game.pause_tree(false)
	_game._update_mouse_mode()
	_game._sync_input_context()

func _return_here() -> void:
	if _in_match():
		_page = Page.NONE
		_resume_game()
		return
	_game.pause_tree(true)
	_show_panel()

func _open_map() -> void:
	_page = Page.MAP
	panel.hide()
	_game.set_map_open(true)

func _on_map_visibility() -> void:
	if _page == Page.MAP and not _hud.full_map.visible:
		_return_here.call_deferred()

func _open_activities() -> void:
	close_menu()
	_game.gameplay.open_board()
	if _game.city_life.has_modal():
		_game.city_life.modal_back = open_menu

## The lobby stays over the paused game. A match starting closes it, and the game resumes.
func _open_squad() -> void:
	_page = Page.SQUAD
	panel.hide()
	_hud.toggle_multiplayer_panel()

func _on_lobby_visibility() -> void:
	if _page == Page.SQUAD and not _hud.multiplayer_panel.visible:
		_return_here.call_deferred()

func _open_settings() -> void:
	_page = Page.SETTINGS
	panel.hide()
	_settings.open_menu()

func _on_settings_closed() -> void:
	if _page == Page.SETTINGS:
		_show_panel()

## Goes through the window-close path so the game saves exactly as it does on closing.
func _quit() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()
