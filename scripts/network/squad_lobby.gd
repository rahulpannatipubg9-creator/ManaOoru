extends PanelContainer

## The Squad screen: Host on one device, Find on the others, tap the room. Rooms are found automatically on
## the same Wi-Fi or hotspot (lan_discovery.gd). "Join by number" is the fallback, with on-screen keys.

const Discovery := preload("res://scripts/network/lan_discovery.gd")
const TdmConfig := preload("res://scripts/tactical/tdm_config.gd")
const TdmSession := preload("res://scripts/tactical/tdm_session.gd")
const MAX_ROOMS_SHOWN := 4
## After this long without finding anything, say so.
const SEARCH_HINT_SECONDS := 6.0
const JOIN_TIMEOUT_SECONDS := 10.0
const DELETE_KEY := "Del"
const NICKNAME_SECTION := "player"
const NICKNAME_KEY := "nickname"
## Where the chosen name is kept. Tests point it elsewhere.
static var profile_path := "user://squad_profile.cfg"

var network_manager: Node
## Set by main.gd. Hosting in Team Deathmatch mode and leaving a match go through it.
var tdm_local: Node
var discovery: Discovery
var nickname := "Player"
var status_label: Label
var players_label: Label

var _start_box: VBoxContainer
var _session_box: VBoxContainer
var _name_edit: LineEdit
var _address_label: Label
var _rooms_box: VBoxContainer
var _keypad_box: VBoxContainer
var _typed_ip: Label
var _ip := ""
var _search_time := 0.0
var _joining := false
var _join_attempt := 0
var _tdm_mode := false
var _tdm_config := TdmConfig.new()
var _tdm_box: HBoxContainer
var _mode_buttons: Array[Button] = []

func setup(manager: Node, finder: Discovery) -> void:
	network_manager = manager
	discovery = finder
	nickname = load_nickname()
	discovery.rooms_changed.connect(_show_rooms)
	if network_manager:
		network_manager.connection_state_changed.connect(_on_connection_changed)
		network_manager.peer_list_updated.connect(_on_peers_changed)
		network_manager.join_failed.connect(_on_join_failed)
	_build()
	_show_offline()

## A readable name from the phone model; model codes like "2410CRP4CI" become "Player 42".
static func default_nickname(model: String) -> String:
	var clean := model.strip_edges()
	if clean.is_empty() or clean == "GenericDevice" or not " " in clean:
		return "Player %d" % randi_range(10, 99)
	return clean.left(NetworkManager.MAX_NICKNAME_LENGTH)

## The name the player chose, or one from the device until they do.
static func load_nickname() -> String:
	var profile := ConfigFile.new()
	if profile.load(profile_path) == OK:
		var saved := String(profile.get_value(NICKNAME_SECTION, NICKNAME_KEY, "")).strip_edges()
		if not saved.is_empty():
			return saved.left(NetworkManager.MAX_NICKNAME_LENGTH)
	return default_nickname(OS.get_model_name())

static func save_nickname(value: String) -> Error:
	var profile := ConfigFile.new()
	profile.set_value(NICKNAME_SECTION, NICKNAME_KEY, value)
	return profile.save(profile_path)

## Shows a name without saving it.
func set_nickname(value: String) -> void:
	nickname = value
	_name_edit.text = value

func _commit_nickname() -> void:
	var typed := _name_edit.text.strip_edges()
	if typed.is_empty():
		_name_edit.text = nickname
	elif typed != nickname:
		nickname = typed
		save_nickname(typed)

func _process(delta: float) -> void:
	if discovery and discovery.is_searching() and discovery.rooms().is_empty():
		_search_time += delta
		if _search_time > SEARCH_HINT_SECONDS:
			_set_status("No rooms. Same Wi-Fi?")

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _back() -> void:
	if _keypad_box.visible:
		_toggle_keypad()
		return
	if _name_edit.has_focus():
		_name_edit.release_focus()
	discovery.stop_searching()
	_clear_rooms()
	visible = false

func host() -> void:
	if network_manager == null:
		return
	_commit_nickname()
	discovery.stop_searching()
	_clear_rooms()
	if network_manager.host_game(network_manager.DEFAULT_PORT, nickname) != OK:
		_set_status("Port busy", UiTheme.DANGER)
		return
	var tdm := _tdm_mode and tdm_local != null
	var room := {"name": nickname, "port": network_manager.DEFAULT_PORT,
		"players": 1, "max_players": network_manager.MAX_CLIENTS + 1,
		"mode": "tdm" if tdm else "free", "detail": TdmSession.describe(_tdm_config) if tdm else ""}
	if tdm:
		room.max_players = _tdm_config.team_size * 2
	var announced := discovery.start_hosting(room) == OK
	if tdm:
		tdm_local.host_match(_tdm_config, nickname)
	_show_session("Hosting" if announced else "Hosting by number only")
	_address_label.text = "  ".join(Discovery.local_ipv4s())

func find() -> void:
	if network_manager == null:
		return
	_commit_nickname()
	if network_manager.is_active():
		network_manager.disconnect_game()
	discovery.stop_hosting()
	_show_keypad(false)
	_search_time = 0.0
	if discovery.start_searching() != OK:
		_set_status("Can't search here", UiTheme.DANGER)
		return
	_set_status("Searching")

func join(address: String, port: int) -> void:
	if network_manager == null or not is_valid_ipv4(address):
		_set_status("Not a valid number", UiTheme.DANGER)
		return
	_commit_nickname()
	discovery.stop()
	_clear_rooms()
	_joining = true
	_join_attempt += 1
	var attempt := _join_attempt
	if tdm_local != null:
		tdm_local.session.local_nickname = nickname
		tdm_local.session.last_address = address
		tdm_local.session.last_port = port
	network_manager.join_game(address, port, nickname)
	if not _joining:
		return # Refused on the spot (join_failed).
	_set_status("Joining")
	get_tree().create_timer(JOIN_TIMEOUT_SECONDS, false).timeout.connect(func() -> void:
		if _joining and attempt == _join_attempt:
			network_manager.disconnect_game()
			_on_join_failed("Couldn't reach it"))

func leave() -> void:
	if tdm_local != null and tdm_local.in_match:
		tdm_local.leave_match()
	_joining = false
	discovery.stop()
	if network_manager and network_manager.is_active():
		network_manager.disconnect_game()
	_clear_rooms()
	_show_offline()

static func is_valid_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or int(part) > 255 or part.length() > 3:
			return false
	return true

func press_key(key: String) -> void:
	match key:
		DELETE_KEY:
			_ip = _ip.left(-1)
		_:
			if _ip.length() < 15:
				_ip += key
	_typed_ip.text = _ip

func _show_rooms(rooms: Array) -> void:
	_clear_rooms()
	if rooms.is_empty():
		return
	_set_status("")
	for room: Dictionary in rooms.slice(0, MAX_ROOMS_SHOWN):
		_add_room_row(room)

## One line per room: its name on the left, what it is and how full on the right.
func _add_room_row(room: Dictionary) -> void:
	var row := Button.new()
	row.text = String(room.name)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	row.add_theme_font_size_override("font_size", UiTheme.FONT_LABEL)
	row.pressed.connect(join.bind(String(room.ip), int(room.port)))
	_rooms_box.add_child(row)
	var kind := String(room.get("detail", "")) if room.get("mode", "free") == "tdm" else "Free roam"
	var detail := _label("%s   %d/%d" % [kind, room.players, room.max_players], UiTheme.FONT_SMALL, UiTheme.TEXT_MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(detail)
	detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail.offset_right = -UiTheme.SPACE_M

func _clear_rooms() -> void:
	for child in _rooms_box.get_children():
		_rooms_box.remove_child(child)
		child.queue_free()

func _on_connection_changed(active: bool, is_host: bool) -> void:
	if active and not is_host:
		_joining = false
		_show_session("In squad")
		_address_label.text = ""
	elif not active and not _joining:
		if discovery.is_hosting():
			discovery.stop_hosting()
		_show_offline()

func _on_join_failed(reason: String) -> void:
	if not _joining:
		return
	_joining = false
	_show_offline()
	_set_status(reason, UiTheme.DANGER)

func _on_peers_changed(peers: Dictionary) -> void:
	if discovery.is_hosting():
		discovery.update_room({"players": maxi(1, peers.size())})
	var names: Array[String] = []
	for id in peers:
		var peer_name: String = peers[id].get("nickname", "Player %d" % id)
		names.append(peer_name + ("  down" if peers[id].get("is_downed") == true else ""))
	players_label.text = "\n".join(names) if names.size() > 1 else ""
	players_label.visible = names.size() > 1

func _show_offline() -> void:
	_start_box.visible = true
	_session_box.visible = false
	_show_keypad(false)
	_set_status("")

func _show_session(status: String) -> void:
	_start_box.visible = false
	_session_box.visible = true
	_show_keypad(false)
	_set_status(status)

## One short line, or nothing at all.
func _set_status(text: String, color: Color = UiTheme.TEXT_MUTED) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()
	status_label.add_theme_color_override("font_color", color)

func _toggle_keypad() -> void:
	_show_keypad(not _keypad_box.visible)

func _show_keypad(open: bool) -> void:
	_keypad_box.visible = open
	_rooms_box.visible = not open

func _build() -> void:
	theme = UiTheme.theme()
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_SOLID))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_S)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Squad", UiTheme.FONT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := _button(header, "Back", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_build_start(column)
	_build_session(column)
	status_label = _label("", UiTheme.FONT_LABEL)
	column.add_child(status_label)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", UiTheme.SPACE_S)
	column.add_child(_rooms_box)
	_build_keypad(column)

func _build_start(column: VBoxContainer) -> void:
	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", UiTheme.SPACE_S)
	column.add_child(_start_box)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", UiTheme.SPACE_S)
	_start_box.add_child(identity)
	_name_edit = LineEdit.new()
	_name_edit.text = nickname
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = NetworkManager.MAX_NICKNAME_LENGTH
	_name_edit.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", UiTheme.FONT_LABEL)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _name_edit.release_focus())
	_name_edit.focus_exited.connect(_commit_nickname)
	identity.add_child(_name_edit)
	_build_mode_picker(identity)
	_tdm_box = HBoxContainer.new()
	_tdm_box.add_theme_constant_override("separation", UiTheme.SPACE_S)
	_tdm_box.visible = false
	_start_box.add_child(_tdm_box)
	_cycle_button(_tdm_box, ["2v2", "3v3", "4v4", "5v5", "6v6", "7v7", "8v8"], _tdm_config.team_size - 2,
		func(value: int) -> void: _tdm_config.team_size = value + 2)
	_cycle_button(_tdm_box, ["20 kills", "40 kills", "60 kills"], _tdm_config.kill_limit_choice,
		func(value: int) -> void: _tdm_config.kill_limit_choice = value)
	_cycle_button(_tdm_box, ["5 min", "10 min", "15 min"], _tdm_config.time_limit_choice,
		func(value: int) -> void: _tdm_config.time_limit_choice = value)
	_cycle_button(_tdm_box, ["Morning", "Afternoon", "Night"], _tdm_config.time_of_day,
		func(value: int) -> void: _tdm_config.time_of_day = value)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.SPACE_S)
	_start_box.add_child(actions)
	UiTheme.make_primary(_big_button(actions, "Host", host))
	_big_button(actions, "Find", find)
	var by_number := _button(_start_box, "Join by number", _toggle_keypad)
	by_number.flat = true
	by_number.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)

## Free roam or Team match, side by side. Team match opens its options.
func _build_mode_picker(row: HBoxContainer) -> void:
	var group := ButtonGroup.new()
	for index in 2:
		var button := _button(row, ["Free roam", "Team match"][index], func() -> void: _select_mode(index == 1))
		button.toggle_mode = true
		button.button_group = group
		_mode_buttons.append(button)
	_mode_buttons[0].button_pressed = true

func _build_session(column: VBoxContainer) -> void:
	_session_box = VBoxContainer.new()
	_session_box.add_theme_constant_override("separation", UiTheme.SPACE_S)
	column.add_child(_session_box)
	_address_label = _label("", UiTheme.FONT_TITLE, UiTheme.ACCENT)
	_session_box.add_child(_address_label)
	players_label = _label("", UiTheme.FONT_LABEL)
	_session_box.add_child(players_label)
	_button(_session_box, "Leave", leave)

func _build_keypad(column: VBoxContainer) -> void:
	_keypad_box = VBoxContainer.new()
	_keypad_box.add_theme_constant_override("separation", UiTheme.SPACE_S)
	_keypad_box.visible = false
	column.add_child(_keypad_box)
	_typed_ip = _label("", UiTheme.FONT_TITLE)
	_typed_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_typed_ip.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	_keypad_box.add_child(_typed_ip)
	var keys := GridContainer.new()
	keys.columns = 6
	keys.add_theme_constant_override("h_separation", UiTheme.SPACE_S)
	keys.add_theme_constant_override("v_separation", UiTheme.SPACE_S)
	_keypad_box.add_child(keys)
	for key: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", DELETE_KEY]:
		_button(keys, key, press_key.bind(key))
	_button(_keypad_box, "Join", func() -> void: join(_ip, network_manager.DEFAULT_PORT if network_manager else 7777))

## A button that steps through a short list each tap; the value is its own label.
func _cycle_button(parent: Node, values: Array, start: int, apply: Callable) -> void:
	var index := start
	var button := _button(parent, String(values[index]), func() -> void: pass)
	button.pressed.connect(func() -> void:
		index = (index + 1) % values.size()
		button.text = String(values[index])
		apply.call(index))

func _select_mode(tdm: bool) -> void:
	_tdm_mode = tdm
	_tdm_box.visible = tdm

func _label(text: String, font_size: int, color: Color = UiTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET, UiTheme.TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## One of the two main actions.
func _big_button(parent: Node, text: String, action: Callable) -> Button:
	var button := _button(parent, text, action)
	button.custom_minimum_size.y = UiTheme.TOUCH_TARGET * 2.0
	button.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
	return button
