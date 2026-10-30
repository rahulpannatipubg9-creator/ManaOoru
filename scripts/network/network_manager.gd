extends Node
class_name NetworkManager

signal connection_state_changed(active: bool, is_host: bool)
signal peer_list_updated(peers: Dictionary)
signal player_downed(peer_id: int, nickname: String)
signal player_revived(peer_id: int, nickname: String)
signal player_eliminated(peer_id: int, nickname: String)
signal hit_confirmed(target_name: String, damage: float, is_headshot: bool)
signal notification_posted(message: String, is_alert: bool)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 16
const SYNC_INTERVAL := 0.05 # 20 Hz sync
const TDM_SYNC_INTERVAL := 1.0 / 30.0
const REVIVE_DURATION := 8.0 # 8.0 seconds held revive (BGMI / PUBG Mobile standard)

var peer: ENetMultiplayerPeer
var local_nickname := "Player"
var peers: Dictionary = {} # peer_id -> {"nickname": String, "health": float, "is_downed": bool}
var puppets: Dictionary = {} # peer_id -> CharacterBody3D

var main_node: Node = null
## Set by main.gd. While a Team Deathmatch is running the host owns health, so the
## trusting damage and downed/revive paths below stand down (docs/TDM_DESIGN.md, section 4).
var tdm: Node = null
var puppet_container: Node3D = null

var _sync_timer := 0.0
var _local_is_firing := false
var _revive_target_id := -1
var _revive_progress := 0.0
var _bleedout_timer := 60.0

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

## Host a zero-cost P2P server on given port
func host_game(port: int = DEFAULT_PORT, nickname: String = "Host") -> Error:
	disconnect_game()
	local_nickname = nickname.strip_edges()
	if local_nickname.is_empty():
		local_nickname = "Host"

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		notification_posted.emit("Failed to create server on port %d: %d" % [port, err], true)
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
	notification_posted.emit("Room hosted on port %d as '%s'" % [port, local_nickname], false)
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
		notification_posted.emit("Failed to connect to %s:%d" % [clean_addr, port], true)
		return err

	var mp := _get_mp()
	if mp:
		mp.multiplayer_peer = peer
	notification_posted.emit("Connecting to %s:%d..." % [clean_addr, port], false)
	return OK

func disconnect_game() -> void:
	var mp := _get_mp()
	if mp and mp.has_multiplayer_peer():
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null
	peer = null
	_clear_all_puppets()
	peers.clear()
	connection_state_changed.emit(false, false)
	peer_list_updated.emit(peers)

func _clear_all_puppets() -> void:
	for id in puppets:
		var p: Node = puppets[id]
		if is_instance_valid(p):
			p.queue_free()
	puppets.clear()

# --- Connection Event Callbacks ---

func _on_peer_connected(id: int) -> void:
	notification_posted.emit("Peer connected: %d" % id, false)
	if not peers.has(id):
		peers[id] = {
			"nickname": "Player %d" % id,
			"health": 100.0,
			"is_downed": false
		}
		_spawn_puppet(id, peers[id]["nickname"])
		peer_list_updated.emit(peers)
	var mp := _get_mp()
	if mp and mp.is_server():
		# Inform new client about existing players
		rpc_id(id, "rpc_receive_room_state", peers)

func _on_peer_disconnected(id: int) -> void:
	var name_tag: String = peers.get(id, {}).get("nickname", "Player %d" % id)
	notification_posted.emit("%s left the match" % name_tag, false)
	_remove_puppet(id)
	peers.erase(id)
	peer_list_updated.emit(peers)

func _on_connected_to_server() -> void:
	var my_id := _get_id()
	peers[my_id] = {
		"nickname": local_nickname,
		"health": 100.0,
		"is_downed": false
	}
	connection_state_changed.emit(true, false)
	notification_posted.emit("Connected to host as '%s'" % local_nickname, false)
	rpc("rpc_register_player", local_nickname)

func _on_connection_failed() -> void:
	notification_posted.emit("Connection failed. Check host IP and port.", true)
	disconnect_game()

func _on_server_disconnected() -> void:
	notification_posted.emit("Host closed the room or lost connection.", true)
	disconnect_game()

# --- Puppet Management ---

func _spawn_puppet(id: int, player_name: String) -> CharacterBody3D:
	if id == _get_id() or puppets.has(id):
		return puppets.get(id, null)
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

	var in_tdm: bool = tdm != null and tdm.active
	if not in_tdm:
		# Teammate Revive Check
		_process_revive_interaction(delta)

		# Local Downed Bleedout Loop
		_process_local_downed(delta)

	# Network State Broadcast
	_sync_timer += delta
	if _sync_timer >= (TDM_SYNC_INTERVAL if in_tdm else SYNC_INTERVAL):
		_sync_timer = 0.0
		_broadcast_local_state()

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

# --- RPC Handlers ---

@rpc("any_peer", "reliable")
func rpc_register_player(nickname: String) -> void:
	var mp := _get_mp()
	var sender_id := mp.get_remote_sender_id() if mp else 1
	peers[sender_id] = {
		"nickname": nickname,
		"health": 100.0,
		"is_downed": false
	}
	_spawn_puppet(sender_id, nickname)
	peer_list_updated.emit(peers)
	notification_posted.emit("%s joined the squad!" % nickname, false)
	if mp and mp.is_server():
		# Forward registration to all peers
		for id in peers:
			if id != sender_id and id != 1:
				rpc_id(id, "rpc_peer_joined", sender_id, nickname)

@rpc("any_peer", "reliable")
func rpc_peer_joined(peer_id: int, nickname: String) -> void:
	peers[peer_id] = {
		"nickname": nickname,
		"health": 100.0,
		"is_downed": false
	}
	_spawn_puppet(peer_id, nickname)
	peer_list_updated.emit(peers)
	notification_posted.emit("%s joined the squad!" % nickname, false)

@rpc("any_peer", "reliable")
func rpc_receive_room_state(room_peers: Dictionary) -> void:
	peers = room_peers.duplicate(true)
	peer_list_updated.emit(peers)
	for id in peers:
		if id != _get_id():
			_spawn_puppet(id, peers[id].get("nickname", "Player %d" % id))

@rpc("any_peer", "unreliable_ordered")
func rpc_sync_transform(pos: Vector3, yaw: float, pitch: float, stance_code: int, peek: float, armed: bool, firing: bool) -> void:
	var mp := _get_mp()
	var sender_id := mp.get_remote_sender_id() if mp else 1
	if tdm != null and tdm.active:
		tdm.on_peer_position(sender_id, pos)
	if puppets.has(sender_id):
		var puppet: CharacterBody3D = puppets[sender_id]
		if is_instance_valid(puppet) and puppet.has_method("update_network_state"):
			puppet.update_network_state(pos, yaw, pitch, stance_code, peek, armed, firing)

# --- Combat & Hit Reporting ---

func report_hit(target_peer_id: int, damage: float, hit_zone: String, hit_pos: Vector3) -> void:
	if not is_active() or (tdm != null and tdm.active):
		return
	hit_confirmed.emit(peers.get(target_peer_id, {}).get("nickname", "Target"), damage, hit_zone == "head")
	rpc("rpc_apply_damage", target_peer_id, damage, hit_zone, hit_pos)

@rpc("any_peer", "reliable")
func rpc_apply_damage(target_peer_id: int, damage: float, hit_zone: String, _hit_pos: Vector3) -> void:
	if tdm != null and tdm.active:
		return # In TDM only the host's validated damage counts.
	var my_id := _get_id()
	if target_peer_id == my_id:
		# Local player damaged!
		var person := _get_local_person()
		if person:
			if person.get("downed") == true:
				# Extra damage while downed accelerates bleedout
				_bleedout_timer = maxf(0.0, _bleedout_timer - damage * 0.4)
			else:
				person.health = maxf(0.0, person.health - damage)
				if "health_changed" in person:
					person.health_changed.emit(person.health, person.max_health)
				if person.health <= 0.0:
					_trigger_local_downed()
	elif puppets.has(target_peer_id):
		# Update puppet visual health
		var puppet: CharacterBody3D = puppets[target_peer_id]
		if is_instance_valid(puppet) and puppet.has_method("apply_local_damage"):
			puppet.apply_local_damage(damage, hit_zone)

# --- DBNO (Down-But-Not-Out) & Revive ---

func _trigger_local_downed() -> void:
	var person := _get_local_person()
	if not person:
		return
	person.downed = true
	person.health = 0.0
	_bleedout_timer = 60.0
	if person.has_method("_update_stance"):
		person._update_stance(false, true) # Force crawl prone
	rpc("rpc_notify_downed", _get_id())

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_downed(downed_id: int) -> void:
	var name_tag: String = peers.get(downed_id, {}).get("nickname", "Teammate")
	if peers.has(downed_id):
		peers[downed_id]["is_downed"] = true
	if puppets.has(downed_id):
		var p: CharacterBody3D = puppets[downed_id]
		if is_instance_valid(p) and p.has_method("set_downed"):
			p.set_downed(true)
	player_downed.emit(downed_id, name_tag)
	notification_posted.emit("⚠️ %s is KNOCKED DOWN!" % name_tag, true)

func _process_local_downed(delta: float) -> void:
	var person := _get_local_person()
	if not person:
		return
	if person.get("downed") == true:
		_bleedout_timer -= delta
		if _bleedout_timer <= 0.0:
			# Bleedout complete -> Elimination
			notify_player_eliminated(_get_id())

func _process_revive_interaction(delta: float) -> void:
	var local_person := _get_local_person()
	if not local_person or local_person.get("downed") == true:
		return

	# Find closest downed puppet within 2.5m
	var closest_downed := -1
	var min_dist := 2.5
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
		_revive_progress += delta / REVIVE_DURATION # 8 seconds held revive
		var target_name: String = peers.get(_revive_target_id, {}).get("nickname", "Teammate")
		notification_posted.emit("Reviving %s: %d%%" % [target_name, int(_revive_progress * 100.0)], false)
		if _revive_progress >= 1.0:
			rpc("rpc_notify_revived", _revive_target_id)
			_revive_target_id = -1
			_revive_progress = 0.0
	else:
		if _revive_target_id != -1:
			_revive_target_id = -1
			_revive_progress = 0.0

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_revived(revived_id: int) -> void:
	var name_tag: String = peers.get(revived_id, {}).get("nickname", "Teammate")
	if peers.has(revived_id):
		peers[revived_id]["is_downed"] = false
		peers[revived_id]["health"] = 25.0
	if puppets.has(revived_id):
		var p: CharacterBody3D = puppets[revived_id]
		if is_instance_valid(p) and p.has_method("set_downed"):
			p.set_downed(false)
	if revived_id == _get_id():
		var person := _get_local_person()
		if person:
			person.downed = false
			person.health = 25.0
			if "health_changed" in person:
				person.health_changed.emit(25.0, person.max_health)
			if person.has_method("_update_stance"):
				person._update_stance(false, false)
	player_revived.emit(revived_id, name_tag)
	notification_posted.emit("💚 %s was REVIVED!" % name_tag, false)

func notify_player_eliminated(elim_id: int) -> void:
	var crate_pos := Vector3.ZERO
	var person := _get_local_person()
	if elim_id == _get_id() and person:
		crate_pos = person.global_position
	elif puppets.has(elim_id) and is_instance_valid(puppets[elim_id]):
		crate_pos = puppets[elim_id].global_position
	rpc("rpc_notify_eliminated", elim_id, crate_pos)

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_eliminated(elim_id: int, crate_pos: Vector3) -> void:
	var name_tag: String = peers.get(elim_id, {}).get("nickname", "Player %d" % elim_id)
	player_eliminated.emit(elim_id, name_tag)
	notification_posted.emit("☠️ %s was ELIMINATED!" % name_tag, true)

	# Spawn death loot crate
	if crate_pos != Vector3.ZERO and main_node:
		var crate := LootCrateScript.new()
		crate.name = "LootCrate_%d" % elim_id
		crate.position = crate_pos
		crate.crate_id = elim_id
		crate.network_manager = self
		main_node.add_child(crate)

	if elim_id == _get_id():
		# Local respawn after delay
		var person := _get_local_person()
		if person:
			person.downed = false
			person.health = person.max_health
			person.global_position = person.respawn_position
			if "health_changed" in person:
				person.health_changed.emit(person.health, person.max_health)
			if person.has_method("_update_stance"):
				person._update_stance(false, false)
	else:
		_remove_puppet(elim_id)

func notify_crate_looted(crate_id: int, looter_id: int) -> void:
	if not is_active():
		return
	rpc("rpc_notify_crate_looted", crate_id, looter_id)

@rpc("any_peer", "call_local", "reliable")
func rpc_notify_crate_looted(crate_id: int, looter_id: int) -> void:
	var looter_name: String = peers.get(looter_id, {}).get("nickname", "Player")
	if main_node:
		var crate_node := main_node.get_node_or_null("LootCrate_%d" % crate_id)
		if crate_node and is_instance_valid(crate_node):
			crate_node.queue_free()
	notification_posted.emit("📦 %s looted death crate!" % looter_name, false)
