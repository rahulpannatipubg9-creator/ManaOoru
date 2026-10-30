extends PanelContainer

## The SQUAD screen, made for fingers and for people who have never seen an IP
## address: HOST GAME on one device, FIND GAMES on the others, tap the room.
## Rooms are found automatically on the same Wi-Fi or hotspot (lan_discovery.gd);
## JOIN BY NUMBER is the fallback with big number keys, so no keyboard is needed.

const Discovery := preload("res://scripts/network/lan_discovery.gd")
const TdmConfig := preload("res://scripts/tactical/tdm_config.gd")
const TdmSession := preload("res://scripts/tactical/tdm_session.gd")
const BUTTON_HEIGHT := 64.0
const MAX_ROOMS_SHOWN := 4
## After this long without finding anything, explain the usual causes.
const SEARCH_HINT_SECONDS := 6.0

var network_manager: Node
## Set by main.gd. Hosting in Team Deathmatch mode and leaving a match go through it.
var tdm_local: Node
var discovery: Discovery
var nickname := "Player"
var status_label: Label
var players_label: Label

var _info: Label
var _rooms_box: VBoxContainer
var _keypad_box: VBoxContainer
var _typed_ip: Label
var _ip := ""
var _search_time := 0.0
var _joining := false
var _tdm_mode := false
var _tdm_config := TdmConfig.new()
var _tdm_box: VBoxContainer
var _mode_buttons: Array[Button] = []

func setup(manager: Node, finder: Discovery) -> void:
	network_manager = manager
	discovery = finder
	nickname = default_nickname(OS.get_model_name())
	discovery.rooms_changed.connect(_show_rooms)
	if network_manager:
		network_manager.connection_state_changed.connect(_on_connection_changed)
		network_manager.peer_list_updated.connect(_on_peers_changed)
	_build()
	_show_offline()

## A readable name from the phone model; model codes like "2410CRP4CI" become "Player 42".
static func default_nickname(model: String) -> String:
	var clean := model.strip_edges()
	if clean.is_empty() or clean == "GenericDevice" or not " " in clean:
		return "Player %d" % randi_range(10, 99)
	return clean.left(18)

func _process(delta: float) -> void:
	if discovery and discovery.is_searching() and discovery.rooms().is_empty():
		_search_time += delta
		if _search_time > SEARCH_HINT_SECONDS:
			_info.text = "No games yet. Check that both devices are on the same Wi-Fi or hotspot and the other one tapped HOST GAME. Or use JOIN BY NUMBER."

func host() -> void:
	if network_manager == null:
		return
	discovery.stop_searching()
	_clear_rooms()
	if network_manager.host_game(network_manager.DEFAULT_PORT, nickname) != OK:
		_set_status("Couldn't start a game here (the game port is busy). Close other copies and try again.", Color(1.0, 0.45, 0.4))
		return
	var tdm := _tdm_mode and tdm_local != null
	var room := {"name": "%s's game" % nickname, "port": network_manager.DEFAULT_PORT,
		"players": 1, "max_players": network_manager.MAX_CLIENTS + 1,
		"mode": "tdm" if tdm else "free", "detail": TdmSession.describe(_tdm_config) if tdm else ""}
	if tdm:
		room.max_players = _tdm_config.team_size * 2
	var announced := discovery.start_hosting(room) == OK
	_set_status("You are hosting. Others tap FIND GAMES.", Color(0.3, 1.0, 0.5))
	if tdm:
		tdm_local.host_match(_tdm_config, nickname)
	_info.text = _own_address_text() + ("" if announced else "\nAutomatic finding is unavailable here: others use JOIN BY NUMBER.")

func find() -> void:
	if network_manager == null:
		return
	if network_manager.is_active():
		network_manager.disconnect_game()
	discovery.stop_hosting()
	_keypad_box.visible = false
	_search_time = 0.0
	if discovery.start_searching() != OK:
		_set_status("Can't search on this device right now. Use JOIN BY NUMBER.", Color(1.0, 0.45, 0.4))
		return
	_set_status("Looking for games on this Wi-Fi…", Color("82d4cc"))
	_info.text = "Rooms appear below in a few seconds."

func join(address: String, port: int) -> void:
	if network_manager == null or not is_valid_ipv4(address):
		_set_status("That number isn't a valid address (it looks like 192.168.1.5).", Color(1.0, 0.45, 0.4))
		return
	discovery.stop()
	_clear_rooms()
	_joining = true
	if tdm_local != null:
		tdm_local.session.local_nickname = nickname
		tdm_local.session.last_address = address
		tdm_local.session.last_port = port
	network_manager.join_game(address, port, nickname)
	_set_status("Joining %s…" % address, Color("ffd45a"))
	_info.text = "If this takes more than 10 seconds, check both devices are on the same Wi-Fi."
	get_tree().create_timer(10.0, false).timeout.connect(func() -> void:
		if _joining and not network_manager.is_active():
			_joining = false
			network_manager.disconnect_game()
			_set_status("Couldn't reach that game. Is it still hosting, on the same Wi-Fi?", Color(1.0, 0.45, 0.4)))

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
		"⌫":
			_ip = _ip.left(-1)
		_:
			if _ip.length() < 15:
				_ip += key
	_typed_ip.text = _ip if not _ip.is_empty() else "type the host's number"

func _show_rooms(rooms: Array) -> void:
	_clear_rooms()
	if rooms.is_empty():
		return
	_info.text = "Tap a game to join it."
	for room: Dictionary in rooms.slice(0, MAX_ROOMS_SHOWN):
		var kind := String(room.get("detail", "")) if room.get("mode", "free") == "tdm" else "Free roam"
		var button := _big_button(_rooms_box, "JOIN  %s   •   %s   •   %d/%d players" % [room.name, kind, room.players, room.max_players],
			join.bind(String(room.ip), int(room.port)))
		button.add_theme_color_override("font_color", Color("ffd45a"))

func _clear_rooms() -> void:
	for child in _rooms_box.get_children():
		child.queue_free()

func _on_connection_changed(active: bool, is_host: bool) -> void:
	if active and not is_host:
		_joining = false
		_set_status("Connected! You're in the squad. Tap RESUME GAME to play.", Color(0.3, 1.0, 0.5))
		_info.text = ""
	elif not active and not _joining:
		if discovery.is_hosting():
			discovery.stop_hosting()
		_show_offline()

func _on_peers_changed(peers: Dictionary) -> void:
	if discovery.is_hosting():
		discovery.update_room({"players": maxi(1, peers.size())})
	if peers.is_empty():
		players_label.text = "Squad: just you"
		return
	var names: Array[String] = []
	for id in peers:
		var name: String = peers[id].get("nickname", "Player %d" % id)
		names.append(name + (" (DOWN)" if peers[id].get("is_downed") == true else ""))
	players_label.text = "Squad (%d): %s" % [peers.size(), ", ".join(names)]

func _show_offline() -> void:
	_set_status("Not connected. Playing alone.", Color(0.75, 0.78, 0.8))
	_info.text = "Put both devices on the same Wi-Fi (or one phone's hotspot).\nOne taps HOST GAME, the others tap FIND GAMES."
	players_label.text = "Squad: just you"

func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)

func _own_address_text() -> String:
	var addresses := Discovery.local_ipv4s()
	if addresses.is_empty():
		return "Your number: not on Wi-Fi"
	return "Your number (for JOIN BY NUMBER): %s" % "  or  ".join(addresses)

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.13, 0.97)
	style.border_color = Color(0.2, 0.65, 0.85, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var title := Label.new()
	title.text = "SQUAD  •  play together"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("ffd45a"))
	column.add_child(title)
	var you := Label.new()
	you.text = "You are: %s" % nickname
	you.add_theme_font_size_override("font_size", 16)
	column.add_child(you)
	_build_mode_picker(column)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_big_button(actions, "HOST GAME", host)
	_big_button(actions, "FIND GAMES", find)
	_big_button(actions, "LEAVE", leave)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	column.add_child(status_label)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.78, 0.84, 0.88))
	column.add_child(_info)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 8)
	column.add_child(_rooms_box)
	_keypad_box = VBoxContainer.new()
	_keypad_box.visible = false
	column.add_child(_keypad_box)
	_typed_ip = Label.new()
	_typed_ip.text = "type the host's number"
	_typed_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_typed_ip.add_theme_font_size_override("font_size", 24)
	_keypad_box.add_child(_typed_ip)
	var keys := GridContainer.new()
	keys.columns = 6
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	_keypad_box.add_child(keys)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", "⌫"]:
		var key_button := _big_button(keys, key, press_key.bind(key))
		key_button.custom_minimum_size = Vector2(88.0, 56.0)
	_big_button(_keypad_box, "JOIN THIS NUMBER", func() -> void: join(_ip, network_manager.DEFAULT_PORT if network_manager else 7777))
	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 10)
	column.add_child(lower)
	_big_button(lower, "JOIN BY NUMBER", func() -> void:
		_keypad_box.visible = not _keypad_box.visible
		_rooms_box.visible = not _keypad_box.visible)
	_big_button(lower, "RESUME GAME", func() -> void: visible = false)
	players_label = Label.new()
	players_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	players_label.add_theme_font_size_override("font_size", 15)
	column.add_child(players_label)

## GAME MODE: FREE ROAM keeps today's co-op; TEAM DEATHMATCH shows the match options (host only matters).
func _build_mode_picker(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var title := Label.new()
	title.text = "GAME MODE"
	title.add_theme_font_size_override("font_size", 16)
	row.add_child(title)
	for index in 2:
		var button := _big_button(row, ["FREE ROAM", "TEAM DEATHMATCH"][index], func() -> void: _select_mode(index == 1))
		button.toggle_mode = true
		button.custom_minimum_size.y = 48.0
		_mode_buttons.append(button)
	_mode_buttons[0].button_pressed = true
	_tdm_box = VBoxContainer.new()
	_tdm_box.visible = false
	column.add_child(_tdm_box)
	var options := GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 8)
	options.add_theme_constant_override("v_separation", 6)
	_tdm_box.add_child(options)
	_cycle_button(options, "Team size", ["2v2", "3v3", "4v4", "5v5", "6v6", "7v7", "8v8"], _tdm_config.team_size - 2,
		func(value: int) -> void: _tdm_config.team_size = value + 2)
	_cycle_button(options, "Kills to win", ["20", "40", "60"], _tdm_config.kill_limit_choice,
		func(value: int) -> void: _tdm_config.kill_limit_choice = value)
	_cycle_button(options, "Time limit", ["5 min", "10 min", "15 min"], _tdm_config.time_limit_choice,
		func(value: int) -> void: _tdm_config.time_limit_choice = value)
	_cycle_button(options, "Time of day", ["Morning", "Afternoon", "Night"], _tdm_config.time_of_day,
		func(value: int) -> void: _tdm_config.time_of_day = value)

## A touch-sized button that steps through a short list each tap.
func _cycle_button(parent: Node, label: String, values: Array, start: int, apply: Callable) -> void:
	var index := start
	var button := _big_button(parent, "%s: %s" % [label, values[index]], func() -> void: pass)
	button.custom_minimum_size.y = 48.0
	button.pressed.connect(func() -> void:
		index = (index + 1) % values.size()
		button.text = "%s: %s" % [label, values[index]]
		apply.call(index))

func _select_mode(tdm: bool) -> void:
	_tdm_mode = tdm
	_mode_buttons[0].button_pressed = not tdm
	_mode_buttons[1].button_pressed = tdm
	_tdm_box.visible = tdm

func _big_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
