extends Node
class_name NetworkManager

## Free-roam squad play. The host owns who is in the room, who is down and who is out: clients ask with
## rpc_request_* (any_peer, checked here against the real sender) and everything the host announces is
## authority-only, so no client can speak for another. Team Deathmatch has its own rules in tdm_session.gd.

signal connection_state_changed(active: bool, is_host: bool)
signal peer_list_updated(peers: Dictionary)
signal player_downed(peer_id: int, nickname: String)
signal player_revived(peer_id: int, nickname: String)
signal player_eliminated(peer_id: int, nickname: String)
signal hit_confirmed(target_name: String, damage: float, is_headshot: bool)
signal notification_posted(message: String, is_alert: bool)
## A join that will not complete, with a short reason for the player.
signal join_failed(reason: String)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 16
const SYNC_INTERVAL := 0.05 # 20 Hz sync
const TDM_SYNC_INTERVAL := 1.0 / 30.0
const REVIVE_DURATION := 8.0 # 8.0 seconds held revive (BGMI / PUBG Mobile standard)
## Bump whenever the free-roam messages below change; a joiner on another version is turned away.
## 1: hello handshake; damage, downed, revive and loot go through the host.
const PROTOCOL_VERSION := 1
const HOST_ID := 1
const DIFFERENT_VERSION := "Different game version"
## A peer that says nothing valid for this long is on another build (RPC ids shift between builds).
const HELLO_TIMEOUT := 6.0
const REFUSE_GRACE := 0.4
const MAX_NICKNAME_LENGTH := 18
const BLEEDOUT_SECONDS := 60.0
const REVIVE_RANGE := 2.5
const REVIVED_HEALTH := 25.0
const LOOT_RANGE := 2.5
## How far a position report may trail the player when the host checks a range.
const POSITION_SLACK := 3.5
## A rifle headshot is at most 85; a grenade at point-blank, counted as a headshot, 250.
const MAX_HIT_DAMAGE := 250.0
const MAX_HIT_RANGE := 400.0
const MAX_HITS_PER_SECOND := 24
const DOWNED_DAMAGE_TO_BLEEDOUT := 0.4

var peer: ENetMultiplayerPeer
var local_nickname := "Player"
var peers: Dictionary = {} # peer_id -> {"nickname": String, "health": float, "is_downed": bool}
var puppets: Dictionary = {} # peer_id -> CharacterBody3D
## What this peer announces when it joins. Tests change it to check that a mismatch is refused.
var protocol_version := PROTOCOL_VERSION

var main_node: Node = null
## Set by main.gd. While a Team Deathmatch is running the host owns health, so the
## squad damage and downed/revive paths below stand down (docs/TDM_DESIGN.md, section 4).
var tdm: Node = null
var puppet_container: Node3D = null

var _sync_timer := 0.0
var _local_is_firing := false
var _revive_target_id := -1
var _revive_progress := 0.0
var _revive_step := 0
## Client: seconds left for the host to welcome us; 0 once it has.
var _welcome_left := 0.0
# Host only.
var _awaiting_hello: Dictionary = {} # peer_id -> seconds left
var _positions: Dictionary = {} # peer_id -> last reported Vector3
var _down: Dictionary = {} # peer_id -> {"left": bleedout seconds, "since": msec}
var _hits: Dictionary = {} # peer_id -> {"second": int, "count": int}
var _next_crate_id := 1
# Every peer: crate_id -> LootCrate, with ids handed out by the host.
var _crates: Dictionary = {}

const LootCrateScript := preload("res://scripts/network/loot_crate.gd")
const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")

func _get_mp() -> MultiplayerAPI:
	if is_inside_tree():
		return get_multiplayer()
	return null

func _get_id() -> int:
	var mp := _get_mp()
	return mp.get_unique_id() if mp else 1

func _get_local_person() -> CharacterBody3D:
	if main_node:
		if "person" in main_node and is_instance_valid(main_node.person):
			return main_node.person as CharacterBody3D
		if main_node.get("person") != null:
			return main_node.get("person") as CharacterBody3D
		if main_node.has_node("Player") and is_instance_valid(main_node.get_node("Player")):
			return main_node.get_node("Player") as CharacterBody3D
		if main_node.has_node("Person") and is_instance_valid(main_node.get_node("Person")):
			return main_node.get_node("Person") as CharacterBody3D
	return null

func _ready() -> void:
	name = "NetworkManager"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_signals()

## A scene change frees this node, so the connection must not outlive it (the peer would stay on the tree
## with nothing left to receive its RPCs).
func _exit_tree() -> void:
	_close_peer()

func _connect_signals() -> void:
	var mp := _get_mp()
	if mp and not mp.peer_connected.is_connected(_on_peer_connected):
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected_to_server)
		mp.connection_failed.connect(_on_connection_failed)
		mp.server_disconnected.connect(_on_server_disconnected)

func setup(main: Node) -> void:
	main_node = main
	puppet_container = Node3D.new()
	puppet_container.name = "NetworkPuppets"
	main_node.add_child(puppet_container)
	_connect_signals()

func is_active() -> bool:
	var mp := _get_mp()
	return mp != null and mp.has_multiplayer_peer() and mp.multiplayer_peer is ENetMultiplayerPeer and mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	var mp := _get_mp()
	return is_active() and mp != null and mp.is_server()

func get_local_peer_id() -> int:
	return _get_id() if is_active() else 1

## The way for menus to leave this scene: everyone hears the player go before the nodes disappear.
func leave_and_change_scene(path: String) -> Error:
	if is_active():
		disconnect_game()
	return get_tree().change_scene_to_file(path)

## Host a zero-cost P2P server on given port
func host_game(port: int = DEFAULT_PORT, nickname: String = "Host") -> Error:
	disconnect_game()
	local_nickname = nickname.strip_edges()
	if local_nickname.is_empty():
		local_nickname = "Host"

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		peer = null
		return err

	var mp := _get_mp()
	if mp:
		mp.multiplayer_peer = peer
	peers[1] = {
		"nickname": local_nickname,
		"health": 100.0,
		"is_downed": false
	}
	connection_state_changed.emit(true, true)
	peer_list_updated.emit(peers)
	return OK

## Join an existing room via IP and port
func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT, nickname: String = "Player") -> Error:
	disconnect_game()
	local_nickname = nickname.strip_edges()
	if local_nickname.is_empty():
		local_nickname = "Player"

	var clean_addr := address.strip_edges()
	if clean_addr.is_empty():
		clean_addr = "127.0.0.1"

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(clean_addr, port)
	if err != OK:
		peer = null
		join_failed.emit("Couldn't connect")
		return err

	var mp := _get_mp()
	if mp:
		mp.multiplayer_peer = peer
	return OK

func disconnect_game() -> void:
	_close_peer()
	_clear_all_puppets()
	_clear_all_crates()
	# Nobody is left to revive a downed player, so the session ending stands them up.
	var person := _get_local_person()
	if person and person.get("downed") == true:
		_stand_up_local(REVIVED_HEALTH)
	peers.clear()
	connection_state_changed.emit(false, false)
	peer_list_updated.emit(peers)

func _close_peer() -> void:
	var mp := _get_mp()
	if mp and mp.has_multiplayer_peer():
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null
	peer = null
	_welcome_left = 0.0
	_awaiting_hello.clear()
	_positions.clear()
	_down.clear()
	_hits.clear()
	_next_crate_id = 1

func _clear_all_puppets() -> void:
	for id in puppets:
		var p: Node = puppets[id]
		if is_instance_valid(p):
			p.queue_free()
	puppets.clear()

func _clear_all_crates() -> void:
	for crate_id in _crates:
		var crate: Node = _crates[crate_id]
		if is_instance_valid(crate):
			crate.queue_free()
	_crates.clear()

# --- Connection Event Callbacks ---

func _on_peer_connected(id: int) -> void:
	# Only the host's roster names anyone: clients hear about each other from it, with their real names.
	if is_host():
		_awaiting_hello[id] = HELLO_TIMEOUT

func _on_peer_disconnected(id: int) -> void:
	_awaiting_hello.erase(id)
	_positions.erase(id)
	_down.erase(id)
	_hits.erase(id)
	if not peers.has(id):
		return
	notification_posted.emit("%s left" % peers[id].get("nickname", "Player"), false)
	_remove_puppet(id)
	peers.erase(id)
	peer_list_updated.emit(peers)

func _on_connected_to_server() -> void:
	_welcome_left = HELLO_TIMEOUT
	rpc_id(HOST_ID, "rpc_hello", protocol_version, local_nickname)

func _on_connection_failed() -> void:
	disconnect_game()
	join_failed.emit("Couldn't reach it")

func _on_server_disconnected() -> void:
	notification_posted.emit("Host left", true)
	disconnect_game()

## The client's end of a refused join.
func _fail_join(reason: String) -> void:
	notification_posted.emit(reason, true)
	disconnect_game()
	join_failed.emit(reason)

## The host's end: tell them why, then let the message land before closing.
func _refuse(id: int, reason: String) -> void:
	rpc_id(id, "rpc_refused", reason)
	get_tree().create_timer(REFUSE_GRACE, true).timeout.connect(_drop_peer.bind(id))

func _drop_peer(id: int) -> void:
	var mp := _get_mp()
	# The refused peer may already have left on its own.
	if peer != null and mp != null and mp.get_peers().has(id):
		peer.disconnect_peer(id)

# --- Puppet Management ---

func _spawn_puppet(id: int, player_name: String) -> CharacterBody3D:
	if id == _get_id():
		return null
	if puppets.has(id):
		var existing: CharacterBody3D = puppets[id]
		if is_instance_valid(existing):
			existing.set_nickname(player_name)
		return existing
	var puppet := NetworkPlayerScript.new()
	puppet.name = "Puppet_%d" % id
	puppet.peer_id = id
	puppet.nickname = player_name
	puppet.network_manager = self
	if puppet_container:
		puppet_container.add_child(puppet)
	elif main_node:
		main_node.add_child(puppet)
	puppets[id] = puppet
	return puppet

func _remove_puppet(id: int) -> void:
	if puppets.has(id):
		var p: Node = puppets[id]
		if is_instance_valid(p):
			p.queue_free()
		puppets.erase(id)

# --- State Sync Loop ---

func _physics_process(delta: float) -> void:
	if not is_active():
		return

	_process_join_timeouts(delta)
	if not is_active():
		return
	var in_tdm: bool = tdm != null and tdm.active
	if not in_tdm:
		# Teammate Revive Check
		_process_revive_interaction(delta)

		# Bleedout runs on the host's clock, so nobody can stop their own.
		if is_host():
			_process_bleedout(delta)

	# Network State Broadcast
	_sync_timer += delta
	if _sync_timer >= (TDM_SYNC_INTERVAL if in_tdm else SYNC_INTERVAL):
		_sync_timer = 0.0
		_broadcast_local_state()

## A peer that never finishes the handshake is on another build, and would misread every message.
func _process_join_timeouts(delta: float) -> void:
	if _welcome_left > 0.0:
		_welcome_left -= delta
		if _welcome_left <= 0.0:
			_fail_join(DIFFERENT_VERSION)
			return
	for id: int in _awaiting_hello.keys():
		_awaiting_hello[id] -= delta
		if _awaiting_hello[id] <= 0.0:
			_awaiting_hello.erase(id)
			_drop_peer(id)

func _broadcast_local_state() -> void:
	var person := _get_local_person()
	if not person:
		return
	var pos := person.global_position
	var yaw := person.rotation.y
	var pitch := 0.0
	if "camera_pivot" in person and person.camera_pivot and "_pitch" in person.camera_pivot:
		pitch = person.camera_pivot._pitch

	var stance_code := 0
	if person.get("downed") == true:
		stance_code = 3
	elif person.get("prone") == true:
		stance_code = 2
	elif person.get("crouching") == true:
		stance_code = 1

	# Bit 4 of the stance code says the player is aiming down the sight, so others see the rifle shouldered.
	if "camera_pivot" in person and person.camera_pivot and person.camera_pivot.get("is_aiming") == true:
		stance_code |= 4
	# Bits 8 and up carry which rifle is held (weapon_catalog.gd), so others see an AK as an AK.
	stance_code |= int(person.get("weapon_id") if "weapon_id" in person else 0) << 3
	var peek: float = person.get("peek_input") if "peek_input" in person else 0.0
	var armed: bool = person.is_weapon_equipped() if person.has_method("is_weapon_equipped") else false
	var firing: bool = _local_is_firing
	_local_is_firing = false

	rpc("rpc_sync_transform", pos, yaw, pitch, stance_code, peek, armed, firing)

func notify_local_fired() -> void:
	_local_is_firing = true

# --- Joining ---

func _sender() -> int:
	var mp := _get_mp()
	return mp.get_remote_sender_id() if mp else 0

## A short single-line name. The host cleans it because a client could send anything.
static func clean_nickname(nickname: String, id: int) -> String:
	var clean := ""
	for index in nickname.length():
		if nickname.unicode_at(index) >= 32:
			clean += nickname[index]
	clean = clean.strip_edges().left(MAX_NICKNAME_LENGTH)
	return clean if not clean.is_empty() else "Player %d" % id

@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(version: int, nickname: String) -> void:
	var sender := _sender()
	if not is_host() or peers.has(sender):
		return
	_awaiting_hello.erase(sender)
	if version != PROTOCOL_VERSION:
		_refuse(sender, DIFFERENT_VERSION)
		return
	var clean := clean_nickname(nickname, sender)
	peers[sender] = {"nickname": clean, "health": 100.0, "is_downed": false}
	_spawn_puppet(sender, clean)
	rpc_id(sender, "rpc_receive_room_state", peers)
	for id: int in peers:
		if id != sender and id != HOST_ID:
			rpc_id(id, "rpc_peer_joined", sender, clean)
	peer_list_updated.emit(peers)
	notification_posted.emit("%s joined" % clean, false)

@rpc("authority", "call_remote", "reliable")
func rpc_refused(reason: String) -> void:
	_fail_join(reason)

@rpc("authority", "call_remote", "reliable")
func rpc_peer_joined(peer_id: int, nickname: String) -> void:
	peers[peer_id] = {"nickname": nickname, "health": 100.0, "is_downed": false}
	_spawn_puppet(peer_id, nickname)
	peer_list_updated.emit(peers)
	notification_posted.emit("%s joined" % nickname, false)

## The host's welcome: the room as it stands, including anyone already down.
@rpc("authority", "call_remote", "reliable")
func rpc_receive_room_state(room_peers: Dictionary) -> void:
	var welcomed := _welcome_left > 0.0
	_welcome_left = 0.0
	peers = room_peers.duplicate(true)
	for id: int in peers:
		if id != _get_id():
			var puppet := _spawn_puppet(id, peers[id].get("nickname", "Player %d" % id))
			if peers[id].get("is_downed") == true and is_instance_valid(puppet):
				puppet.set_downed(true)
	peer_list_updated.emit(peers)
	if welcomed:
		connection_state_changed.emit(true, false)

@rpc("any_peer", "unreliable_ordered")
func rpc_sync_transform(pos: Vector3, yaw: float, pitch: float, stance_code: int, peek: float, armed: bool, firing: bool) -> void:
	var sender_id := _sender()
	if tdm != null and tdm.active:
		tdm.on_peer_position(sender_id, pos)
	if peers.has(sender_id):
		_positions[sender_id] = pos
	if puppets.has(sender_id):
		var puppet: CharacterBody3D = puppets[sender_id]
		if is_instance_valid(puppet) and puppet.has_method("update_network_state"):
			# An eliminated player's body stays put, then they reappear where they respawned.
			if puppet.is_eliminated() and not puppet.try_return(pos):
				return
			puppet.update_network_state(pos, yaw, pitch, stance_code, peek, armed, firing)

# --- Host-side checks ---

func _position_of(id: int) -> Variant:
	if id == _get_id():
		var person := _get_local_person()
		return person.global_position if person else null
	return _positions.get(id)

func _within(a: int, b: int, reach: float) -> bool:
	var from: Variant = _position_of(a)
	var to: Variant = _position_of(b)
	return from != null and to != null and (from as Vector3).distance_to(to) <= reach + POSITION_SLACK

func _hit_allowed(sender: int, target: int, damage: float) -> bool:
	if not peers.has(sender) or not peers.has(target) or sender == target or _down.has(sender):
		return false
	if is_nan(damage) or damage <= 0.0 or damage > MAX_HIT_DAMAGE or not _within(sender, target, MAX_HIT_RANGE):
		return false
	var second := Time.get_ticks_msec() / 1000
	var count: Dictionary = _hits.get(sender, {"second": second, "count": 0})
	if count.second != second:
		count = {"second": second, "count": 0}
	count.count += 1
	_hits[sender] = count
	return count.count <= MAX_HITS_PER_SECOND

# --- Combat & Hit Reporting ---

func report_hit(target_peer_id: int, damage: float, hit_zone: String, _hit_pos: Vector3) -> void:
	if not is_active() or (tdm != null and tdm.active):
		return
	hit_confirmed.emit(peers.get(target_peer_id, {}).get("nickname", "Target"), damage, hit_zone == "head")
	if is_host():
		_handle_damage(_get_id(), target_peer_id, damage, hit_zone)
	else:
		rpc_id(HOST_ID, "rpc_request_damage", target_peer_id, damage, hit_zone)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_damage(target_peer_id: int, damage: float, hit_zone: String) -> void:
	if is_host():
		_handle_damage(_sender(), target_peer_id, damage, hit_zone)

func _handle_damage(sender: int, target: int, damage: float, hit_zone: String) -> void:
	if (tdm != null and tdm.active) or not _hit_allowed(sender, target, damage):
		return
	if _down.has(target):
		# Extra damage while downed accelerates bleedout.
		_down[target].left -= damage * DOWNED_DAMAGE_TO_BLEEDOUT
		return
	rpc("rpc_apply_damage", target, damage, "head" if hit_zone == "head" else "body")

@rpc("authority", "call_local", "reliable")
func rpc_apply_damage(target_peer_id: int, damage: float, hit_zone: String) -> void:
	if tdm != null and tdm.active:
		return # In TDM only the host's validated damage counts.
	if target_peer_id == _get_id():
		var person := _get_local_person()
		if person and person.get("downed") != true:
			person.health = maxf(0.0, person.health - damage)
			person.health_changed.emit(person.health, person.max_health)
			# Armour can bring health back above zero during that signal (city_gameplay.gd).
			if person.health <= 0.0:
				knock_down_local()
	elif puppets.has(target_peer_id):
		# Update puppet visual health
		var puppet: CharacterBody3D = puppets[target_peer_id]
		if is_instance_valid(puppet) and puppet.has_method("apply_local_damage"):
			puppet.apply_local_damage(damage, hit_zone)

# --- DBNO (Down-But-Not-Out) & Revive ---

## Health ran out while in a squad, by any cause: go down and wait for a teammate.
func knock_down_local() -> void:
	var person := _get_local_person()
	if not person or person.get("downed") == true:
		return
	person.downed = true
	person.health = 0.0
	if person.has_method("_update_stance"):
		person._update_stance(false, true) # Force crawl prone
	if is_host():
		_handle_downed(_get_id())
	else:
		rpc_id(HOST_ID, "rpc_request_downed")

## A player can only ever report themselves.
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_downed() -> void:
	if is_host():
		_handle_downed(_sender())

func _handle_downed(sender: int) -> void:
	if not peers.has(sender) or _down.has(sender):
		return
	_down[sender] = {"left": BLEEDOUT_SECONDS, "since": Time.get_ticks_msec()}
	rpc("rpc_notify_downed", sender)

@rpc("authority", "call_local", "reliable")
func rpc_notify_downed(downed_id: int) -> void:
	var name_tag: String = peers.get(downed_id, {}).get("nickname", "Teammate")
	if peers.has(downed_id):
		peers[downed_id]["is_downed"] = true
	if puppets.has(downed_id):
		var p: CharacterBody3D = puppets[downed_id]
		if is_instance_valid(p) and p.has_method("set_downed"):
			p.set_downed(true)
	peer_list_updated.emit(peers)
	player_downed.emit(downed_id, name_tag)
	notification_posted.emit("%s is down" % name_tag, true)

func _process_bleedout(delta: float) -> void:
	for id: int in _down.keys():
		_down[id].left -= delta
		if _down[id].left <= 0.0:
			_down.erase(id)
			var crate_position: Variant = _position_of(id)
			if crate_position == null:
				rpc("rpc_notify_eliminated", id, -1, Vector3.ZERO)
			else:
				rpc("rpc_notify_eliminated", id, _next_crate_id, crate_position)
				_next_crate_id += 1

func _process_revive_interaction(delta: float) -> void:
	var local_person := _get_local_person()
	if not local_person or local_person.get("downed") == true:
		return

	# Find closest downed puppet within 2.5m
	var closest_downed := -1
	var min_dist := REVIVE_RANGE
	for id in puppets:
		var p: CharacterBody3D = puppets[id]
		if is_instance_valid(p) and p.get("is_downed") == true:
			var d := local_person.global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest_downed = id

	var touch_rev := false
	if main_node:
		var hud_obj = main_node.get("hud")
		if hud_obj == null and main_node.has_meta("hud"):
			hud_obj = main_node.get_meta("hud")
		if hud_obj != null and hud_obj.get("touch_revive_pressed") == true:
			touch_rev = true
	var wants_revive: bool = Input.is_action_pressed("revive") or touch_rev
	if closest_downed != -1 and wants_revive:
		if _revive_target_id != closest_downed:
			_revive_target_id = closest_downed
			_revive_progress = 0.0
			_revive_step = -1
		_revive_progress += delta / REVIVE_DURATION # 8 seconds held revive
		# Four updates over the hold; one per physics frame would flood the toasts.
		var step := int(_revive_progress * 4.0)
		if step != _revive_step and step < 4:
			_revive_step = step
			var target_name: String = peers.get(_revive_target_id, {}).get("nickname", "Teammate")
			notification_posted.emit("Reviving %s %d%%" % [target_name, step * 25], false)
		if _revive_progress >= 1.0:
			if is_host():
				_handle_revive(_get_id(), _revive_target_id)
			else:
				rpc_id(HOST_ID, "rpc_request_revive", _revive_target_id)
			_revive_target_id = -1
			_revive_progress = 0.0
	else:
		if _revive_target_id != -1:
			_revive_target_id = -1
			_revive_progress = 0.0

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_revive(revived_id: int) -> void:
	if is_host():
		_handle_revive(_sender(), revived_id)

## The reviver must be up and beside them, and the hold takes REVIVE_DURATION, so nobody revives sooner.
func _handle_revive(sender: int, revived_id: int) -> void:
	if (tdm != null and tdm.active) or not peers.has(sender) or _down.has(sender) or not _down.has(revived_id) or sender == revived_id:
		return
	var held_msec := Time.get_ticks_msec() - int(_down[revived_id].since)
	if held_msec < (REVIVE_DURATION - 0.5) * 1000.0 or not _within(sender, revived_id, REVIVE_RANGE):
		return
	_down.erase(revived_id)
	rpc("rpc_notify_revived", revived_id)

@rpc("authority", "call_local", "reliable")
func rpc_notify_revived(revived_id: int) -> void:
	var name_tag: String = peers.get(revived_id, {}).get("nickname", "Teammate")
	if peers.has(revived_id):
		peers[revived_id]["is_downed"] = false
		peers[revived_id]["health"] = REVIVED_HEALTH
	if puppets.has(revived_id):
		var p: CharacterBody3D = puppets[revived_id]
		if is_instance_valid(p) and p.has_method("set_downed"):
			p.set_downed(false)
	if revived_id == _get_id():
		_stand_up_local(REVIVED_HEALTH)
	peer_list_updated.emit(peers)
	player_revived.emit(revived_id, name_tag)
	notification_posted.emit("%s is back" % name_tag, false)

## Ends the local knocked-down state, however it ended.
func _stand_up_local(new_health: float) -> void:
	var person := _get_local_person()
	if not person:
		return
	person.downed = false
	person.health = new_health
	person.health_changed.emit(new_health, person.max_health)
	if person.has_method("_update_stance"):
		person._update_stance(false, false)

@rpc("authority", "call_local", "reliable")
func rpc_notify_eliminated(elim_id: int, crate_id: int, crate_pos: Vector3) -> void:
	var name_tag: String = peers.get(elim_id, {}).get("nickname", "Player %d" % elim_id)
	if peers.has(elim_id):
		peers[elim_id]["is_downed"] = false
		peers[elim_id]["health"] = 100.0
	peer_list_updated.emit(peers)
	player_eliminated.emit(elim_id, name_tag)
	notification_posted.emit("%s is out" % name_tag, true)
	if crate_id >= 0:
		_spawn_crate(crate_id, crate_pos)
	if elim_id == _get_id():
		var person := _get_local_person()
		if person:
			person.global_position = person.respawn_position
			person.velocity = Vector3.ZERO
			_stand_up_local(person.max_health)
	elif puppets.has(elim_id) and is_instance_valid(puppets[elim_id]):
		puppets[elim_id].set_eliminated()

# --- Death Loot Crates ---

func _spawn_crate(crate_id: int, crate_pos: Vector3) -> void:
	if not main_node:
		return
	for old_id: int in _crates.keys():
		if not is_instance_valid(_crates[old_id]):
			_crates.erase(old_id) # Expired on its own (loot_crate.gd).
	var crate := LootCrateScript.new()
	crate.name = "LootCrate_%d" % crate_id
	crate.position = crate_pos
	crate.crate_id = crate_id
	crate.network_manager = self
	main_node.add_child(crate)
	_crates[crate_id] = crate

## The crate has already given its loot here; the host removes it for everyone.
func request_loot(crate_id: int) -> void:
	if is_host():
		_handle_loot(_get_id(), crate_id)
	else:
		rpc_id(HOST_ID, "rpc_request_loot", crate_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_loot(crate_id: int) -> void:
	if is_host():
		_handle_loot(_sender(), crate_id)

func _handle_loot(sender: int, crate_id: int) -> void:
	if not peers.has(sender) or _down.has(sender) or not _crates.has(crate_id) or not is_instance_valid(_crates[crate_id]):
		return
	var from: Variant = _position_of(sender)
	if from == null or (from as Vector3).distance_to(_crates[crate_id].global_position) > LOOT_RANGE + POSITION_SLACK:
		return
	rpc("rpc_notify_crate_looted", crate_id, sender)

@rpc("authority", "call_local", "reliable")
func rpc_notify_crate_looted(crate_id: int, looter_id: int) -> void:
	var looter_name: String = peers.get(looter_id, {}).get("nickname", "Player")
	if _crates.has(crate_id) and is_instance_valid(_crates[crate_id]):
		_crates[crate_id].queue_free()
	_crates.erase(crate_id)
	notification_posted.emit("%s looted a crate" % looter_name, false)
