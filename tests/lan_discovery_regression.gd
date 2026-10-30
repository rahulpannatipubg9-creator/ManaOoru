extends SceneTree

## Squad rooms are found without typing an IP: a searching device discovers a
## hosting one, sees its name and player count, forgets it when it closes, and
## ignores packets that are not from this game.

const Discovery := preload("res://scripts/network/lan_discovery.gd")

var _failures := 0
var _events := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var host := Discovery.new()
	host.extra_targets = ["127.0.0.1"]
	root.add_child(host)
	var finder := Discovery.new()
	finder.extra_targets = ["127.0.0.1"]
	root.add_child(finder)
	finder.rooms_changed.connect(func(_rooms: Array) -> void: _events += 1)

	_check(finder.start_searching() == OK, "Searching opens its port")
	_check(host.start_hosting({"name": "Xiaomi Pad 7", "port": 7777, "players": 1, "max_players": 17}) == OK, "Hosting opens its port")
	await _wait(2.5, func() -> bool: return not finder.rooms().is_empty())
	var rooms: Array = finder.rooms()
	_check(rooms.size() == 1, "The hosted room is found (%d rooms)" % rooms.size())
	if not rooms.is_empty():
		_check(rooms[0].name == "Xiaomi Pad 7" and rooms[0].port == 7777 and rooms[0].players == 1, "The room shows its name, port and players (%s)" % rooms[0])
		_check(not String(rooms[0].ip).is_empty(), "The room carries the host's address to join")

	host.update_room({"players": 3})
	await _wait(2.5, func() -> bool: return not finder.rooms().is_empty() and finder.rooms()[0].players == 3)
	_check(not finder.rooms().is_empty() and finder.rooms()[0].players == 3, "A growing squad updates the player count")

	# Foreign and broken packets on the same port change nothing.
	var stranger := PacketPeerUDP.new()
	stranger.set_dest_address("127.0.0.1", Discovery.LISTEN_PORT)
	for junk in ["hello", "{\"tag\":\"OTHERGAME\",\"type\":\"room\",\"port\":1}", "{\"tag\":\"MANAOORU-SQUAD\",\"v\":1,\"type\":\"room\",\"port\":99999}", "x".repeat(2000)]:
		stranger.put_packet(String(junk).to_utf8_buffer())
	for _frame in 10:
		await process_frame
	_check(finder.rooms().size() == 1, "Packets from other apps or out-of-range ports are ignored")

	# Two finders on one device cannot share the port: the second reports it cleanly.
	var second := Discovery.new()
	root.add_child(second)
	_check(second.start_searching() != OK and not second.is_searching(), "A busy port is reported, not crashed on")

	host.stop_hosting()
	await _wait(Discovery.ROOM_TIMEOUT + 2.0, func() -> bool: return finder.rooms().is_empty())
	_check(finder.rooms().is_empty(), "A closed room disappears from the list")
	_check(_events >= 3, "The list announces each change (%d)" % _events)

	finder.stop()
	_check(not finder.is_searching() and not finder.is_hosting(), "Stopping closes everything")
	for address in Discovery.local_ipv4s():
		_check(not address.begins_with("127."), "Own addresses list only local-network IPs (%s)" % address)
	_check(Discovery.broadcast_targets().has("255.255.255.255"), "Broadcast targets include the global broadcast")

	if _failures > 0:
		print("FAIL LAN discovery regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS LAN discovery regression: room found without an IP, name/port/players shown, count updates, junk ignored, busy port handled, closed room expires")
	quit()

func _wait(seconds: float, done: Callable) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and not done.call():
		await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
