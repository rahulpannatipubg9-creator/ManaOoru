extends Node

## Finds squad rooms on the same Wi-Fi or hotspot, so nobody has to type an IP.
##
## The host listens on QUERY_PORT and, once a second, announces its room to
## LISTEN_PORT. A device looking for games listens on LISTEN_PORT and, once a
## second, asks "any rooms?" on QUERY_PORT; the host answers it directly. Both
## directions run because some phones drop broadcast packets in one of them (a
## phone running the hotspot, Wi-Fi power saving). Messages are small JSON
## packets tagged with GAME_TAG; anything else on these ports is ignored.

signal rooms_changed(rooms: Array)

const GAME_TAG := "MANAOORU-SQUAD"
const VERSION := 1
const QUERY_PORT := 7778
const LISTEN_PORT := 7779
const INTERVAL := 1.0
## A room that has not been heard from for this long has closed or moved away.
const ROOM_TIMEOUT := 4.0
const MAX_PACKET := 512

## Extra addresses to announce to / ask, besides the network broadcast addresses
## (tests use 127.0.0.1, which broadcast never reaches).
var extra_targets: Array[String] = []

var _host_socket: PacketPeerUDP
var _listen_socket: PacketPeerUDP
var _room := {}
## Identifies this room however many network paths it is heard on (hotspot + Wi-Fi, loopback).
var _room_id := ""
var _rooms := {}
var _timer := 0.0

func is_hosting() -> bool:
	return _host_socket != null

func is_searching() -> bool:
	return _listen_socket != null

## Start announcing a room. `room` holds name, port, players and max_players.
func start_hosting(room: Dictionary) -> Error:
	stop_hosting()
	_host_socket = PacketPeerUDP.new()
	var err := _host_socket.bind(QUERY_PORT)
	if err != OK:
		_host_socket = null
		return err
	_host_socket.set_broadcast_enabled(true)
	_room = room.duplicate()
	_room_id = "%08x%08x" % [randi(), randi()]
	_timer = INTERVAL
	return OK

func update_room(room: Dictionary) -> void:
	_room.merge(room, true)

func stop_hosting() -> void:
	if _host_socket:
		_host_socket.close()
	_host_socket = null

func start_searching() -> Error:
	stop_searching()
	_listen_socket = PacketPeerUDP.new()
	var err := _listen_socket.bind(LISTEN_PORT)
	if err != OK:
		_listen_socket = null
		return err
	_listen_socket.set_broadcast_enabled(true)
	_rooms.clear()
	_timer = INTERVAL
	rooms_changed.emit([])
	return OK

func stop_searching() -> void:
	if _listen_socket:
		_listen_socket.close()
	_listen_socket = null
	_rooms.clear()

func stop() -> void:
	stop_hosting()
	stop_searching()

func rooms() -> Array:
	var list := _rooms.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	return list

func _exit_tree() -> void:
	stop()

func _process(delta: float) -> void:
	if not is_hosting() and not is_searching():
		return
	_timer += delta
	if _timer >= INTERVAL:
		_timer = 0.0
		if is_hosting():
			_send_to_all(_host_socket, LISTEN_PORT, _room_message("room"))
		if is_searching():
			_send_to_all(_listen_socket, QUERY_PORT, {"tag": GAME_TAG, "v": VERSION, "type": "query"})
			_expire_rooms()
	if is_hosting():
		_receive_queries()
	if is_searching():
		_receive_rooms()

func _receive_queries() -> void:
	while _host_socket.get_available_packet_count() > 0:
		var message := _decode(_host_socket.get_packet())
		var from := _host_socket.get_packet_ip()
		var port := _host_socket.get_packet_port()
		if message.get("type") == "query" and not from.is_empty() and port > 0:
			_host_socket.set_dest_address(from, port)
			_host_socket.put_packet(JSON.stringify(_room_message("room")).to_utf8_buffer())

func _receive_rooms() -> void:
	var changed := false
	while _listen_socket.get_available_packet_count() > 0:
		var message := _decode(_listen_socket.get_packet())
		var from := _listen_socket.get_packet_ip()
		if message.get("type") != "room" or from.is_empty():
			continue
		var port := int(message.get("port", 0))
		if port <= 0 or port > 65535:
			continue
		var key := String(message.get("id", "%s:%d" % [from, port])).left(32)
		# One entry per room: keep a real network address over this device's own loopback.
		if _rooms.has(key) and from.begins_with("127.") and not String(_rooms[key].ip).begins_with("127."):
			from = _rooms[key].ip
		var room := {
			"ip": from,
			"port": port,
			"name": String(message.get("name", "Squad")).left(32),
			"players": clampi(int(message.get("players", 1)), 0, 99),
			"max_players": clampi(int(message.get("max_players", 1)), 1, 99),
			"mode": String(message.get("mode", "free")).left(8),
			"detail": String(message.get("detail", "")).left(40),
			"seen": Time.get_ticks_msec(),
		}
		changed = changed or not _rooms.has(key) or _rooms[key].players != room.players or _rooms[key].name != room.name \
			or _rooms[key].mode != room.mode or _rooms[key].detail != room.detail
		_rooms[key] = room
	if changed:
		rooms_changed.emit(rooms())

func _expire_rooms() -> void:
	var now := Time.get_ticks_msec()
	var gone := _rooms.keys().filter(func(key: String) -> bool: return now - int(_rooms[key].seen) > ROOM_TIMEOUT * 1000.0)
	for key in gone:
		_rooms.erase(key)
	if not gone.is_empty():
		rooms_changed.emit(rooms())

func _room_message(type: String) -> Dictionary:
	return {"tag": GAME_TAG, "v": VERSION, "type": type, "id": _room_id, "name": _room.get("name", "Squad"),
		"port": _room.get("port", 7777), "players": _room.get("players", 1), "max_players": _room.get("max_players", 17),
		"mode": _room.get("mode", "free"), "detail": _room.get("detail", "")}

static func _decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET:
		return {}
	var text := bytes.get_string_from_utf8()
	if not text.begins_with("{"):
		return {}
	# An instance parse stays quiet on junk; JSON.parse_string would log every stray packet.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and parsed.get("tag") == GAME_TAG and int(parsed.get("v", 0)) == VERSION:
		return parsed
	return {}

func _send_to_all(socket: PacketPeerUDP, port: int, message: Dictionary) -> void:
	var bytes := JSON.stringify(message).to_utf8_buffer()
	for address in broadcast_targets() + extra_targets:
		socket.set_dest_address(address, port)
		socket.put_packet(bytes)

## The everyone-on-this-network address for each local Wi-Fi/hotspot address (the
## common /24 case), plus the global broadcast address.
static func broadcast_targets() -> Array[String]:
	var targets: Array[String] = ["255.255.255.255"]
	for address in local_ipv4s():
		var parts := address.split(".")
		var subnet := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if subnet not in targets:
			targets.append(subnet)
	return targets

## This device's addresses on local networks (what other players type or see).
static func local_ipv4s() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		var first := int(parts[0])
		var second := int(parts[1])
		if first == 10 or (first == 192 and second == 168) or (first == 172 and second >= 16 and second <= 31):
			found.append(address)
	return found
