extends SceneTree

## The no-typing SQUAD flow: one device taps HOST GAME, another taps FIND GAMES,
## the room shows up as a button, and tapping it joins. JOIN BY NUMBER works with
## the on-screen keys and rejects bad numbers. Uses a stand-in network manager so
## both "devices" can run in one test; the room finder is the real one.

const Lobby := preload("res://scripts/network/squad_lobby.gd")
const Discovery := preload("res://scripts/network/lan_discovery.gd")
const MANAGER := """extends Node
signal connection_state_changed(active: bool, is_host: bool)
signal peer_list_updated(peers: Dictionary)
const DEFAULT_PORT := 7777
const MAX_CLIENTS := 16
var hosting := false
var joined := ""
var peers := {}
var fail_host := false
func is_active() -> bool: return hosting or not joined.is_empty()
func host_game(_port: int, nickname: String) -> Error:
	if fail_host: return ERR_ALREADY_IN_USE
	hosting = true
	peers = {1: {"nickname": nickname}}
	connection_state_changed.emit(true, true)
	peer_list_updated.emit(peers)
	return OK
func join_game(address: String, port: int, _nickname: String) -> Error:
	joined = "%s:%d" % [address, port]
	return OK
func disconnect_game() -> void:
	hosting = false
	joined = ""
	peers = {}
	connection_state_changed.emit(false, false)
	peer_list_updated.emit(peers)
"""

var _failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var pad := _device("Xiaomi Pad 7")
	var phone := _device("moto g86 power")
	await process_frame
	var pad_lobby: Lobby = pad.lobby
	var phone_lobby: Lobby = phone.lobby
	_check(phone_lobby.nickname == "moto g86 power", "A phone uses its model as the player name")
	_check(Lobby.default_nickname("2410CRP4CI").begins_with("Player "), "A model code becomes a friendly 'Player NN'")
	_check(Lobby.default_nickname("").begins_with("Player "), "An unknown model still gets a name")

	_tap(pad_lobby, "HOST GAME")
	_check(pad.manager.hosting and pad.finder.is_hosting(), "HOST GAME starts the room and announces it")
	_check(pad_lobby.status_label.text.contains("hosting"), "The host is told it is hosting (%s)" % pad_lobby.status_label.text)

	_tap(phone_lobby, "FIND GAMES")
	_check(phone.finder.is_searching(), "FIND GAMES starts looking")
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and _room_button(phone_lobby) == null:
		await process_frame
	var room := _room_button(phone_lobby)
	_check(room != null, "The host's game appears as a button")
	if room:
		_check(room.text.contains("Xiaomi Pad 7") or room.text.contains("Player"), "The button names the host's game (%s)" % room.text)
		_check(room.text.contains("1/17"), "The button shows players and room size (%s)" % room.text)
		room.pressed.emit()
		_check(phone.manager.joined.ends_with(":7777") and not phone.finder.is_searching(), "Tapping the room joins it (%s)" % phone.manager.joined)
		phone.manager.connection_state_changed.emit(true, false)
		_check(phone_lobby.status_label.text.contains("Connected"), "The player is told they're in")

	# Squad grows: the advertised count follows.
	pad.manager.peers = {1: {"nickname": "Pad"}, 2: {"nickname": "Phone"}, 3: {"nickname": "Friend"}}
	pad.manager.peer_list_updated.emit(pad.manager.peers)
	_check(pad.finder._room.players == 3, "More players update the room's count")
	_check(pad_lobby.players_label.text.contains("(3)"), "The host sees who joined (%s)" % pad_lobby.players_label.text)

	# JOIN BY NUMBER with the on-screen keys.
	_tap(phone_lobby, "LEAVE")
	_check(phone.manager.joined.is_empty() and phone_lobby.status_label.text.contains("Not connected"), "LEAVE disconnects")
	_tap(phone_lobby, "JOIN BY NUMBER")
	for key in "999.1.1":
		phone_lobby.press_key(key)
	_tap(phone_lobby, "JOIN THIS NUMBER")
	_check(phone.manager.joined.is_empty() and phone_lobby.status_label.text.contains("valid"), "A wrong number is refused with a hint")
	for _i in 10:
		phone_lobby.press_key("⌫")
	for key in "255.255.255.2551":
		phone_lobby.press_key(key)
	_check(phone_lobby._ip == "255.255.255.255", "The number box stops at the longest possible address (%s)" % phone_lobby._ip)
	for _i in 20:
		phone_lobby.press_key("⌫")
	_check(phone_lobby._ip.is_empty(), "Backspace clears the number, and never goes below empty")
	for key in "10.242.242.164":
		phone_lobby.press_key(key)
	_tap(phone_lobby, "JOIN THIS NUMBER")
	_check(phone.manager.joined == "10.242.242.164:7777", "JOIN BY NUMBER joins with the typed address (%s)" % phone.manager.joined)

	# Hosting failure is explained, not silent.
	_tap(pad_lobby, "LEAVE")
	pad.manager.fail_host = true
	_tap(pad_lobby, "HOST GAME")
	_check(not pad.finder.is_hosting() and pad_lobby.status_label.text.contains("Couldn't"), "A busy port is explained")

	_check(Lobby.is_valid_ipv4("192.168.1.5") and not Lobby.is_valid_ipv4("192.168.1") and not Lobby.is_valid_ipv4("1.2.3.256") and not Lobby.is_valid_ipv4("a.b.c.d"),
		"Address checking accepts only real addresses")

	if _failures > 0:
		print("FAIL squad lobby regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS squad lobby regression: HOST GAME announces, FIND GAMES lists it, tap joins, player count grows, LEAVE, JOIN BY NUMBER with on-screen keys, bad numbers and busy port explained")
	quit()

func _device(model: String) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)
	var manager := Node.new()
	var script := GDScript.new()
	script.source_code = MANAGER
	script.reload()
	manager.set_script(script)
	holder.add_child(manager)
	var finder := Discovery.new()
	finder.extra_targets = ["127.0.0.1"]
	holder.add_child(finder)
	var lobby := Lobby.new()
	holder.add_child(lobby)
	lobby.setup(manager, finder)
	lobby.nickname = model if " " in model else lobby.nickname
	return {"manager": manager, "finder": finder, "lobby": lobby}

func _tap(lobby: Node, text: String) -> void:
	for button in lobby.find_children("*", "Button", true, false):
		if button.text == text:
			button.pressed.emit()
			return
	_check(false, "Button %s exists" % text)

func _room_button(lobby: Node) -> Button:
	for button in lobby.find_children("*", "Button", true, false):
		if button.text.begins_with("JOIN  ") and not button.is_queued_for_deletion():
			return button
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
