extends Node

## Team Deathmatch networking: the host owns the match (tdm_match.gd), every peer mirrors it.
## Clients move themselves and report what their crosshair hit; the host checks each claim
## (docs/TDM_DESIGN.md, section 4). Needs a node named "TdmSession" at the same path on every
## peer. Contains no scene or HUD code: tdm_local.gd turns its signals into gameplay and UI.

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Roster := preload("res://scripts/tactical/tdm_roster.gd")
const Spawns := preload("res://scripts/tactical/tdm_spawns.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

## Bump whenever the rules or the messages below change; a mismatched joiner is turned away.
## 2: hit claims name the rifle (M416 or AK-47), which sets the damage and the fastest allowed fire rate.
## 3: the CZ Bren 2 is a valid rifle id, so an older build cannot read its claims or stance bits.
const PROTOCOL_VERSION := 3
const HOST_ID := 1
## The shooter's camera may sit behind the body in third person.
const MAX_ORIGIN_ERROR := 9.0
const MAX_HIT_DISTANCE := 160.0
const HIT_POSITION_TOLERANCE := 2.5
## Faster than this between two position reports is a teleport, not running (run is 7 m/s).
const MAX_SPEED := 12.0
const BROADCAST_INTERVAL := 0.25
const CHAT_INTERVAL_MSEC := 1500
const PING_INTERVAL_MSEC := 2000
const FALL_KILL_DEPTH := 40.0
const CHAT_LINES: Array[String] = ["Enemy here", "Need backup", "On my way", "Good shot", "Thanks", "Hold position"]
## Entries that also drop a map ping.
const PING_CHATS: Array[int] = [0, 1, 5]
const RECONNECT_SECONDS := 60.0
const RECONNECT_RETRY_SECONDS := 3.0

signal lobby_changed
signal state_changed(state: int)
signal spawned(peer_id: int, position: Vector3)
signal damaged(victim_id: int, attacker_id: int, amount: float, headshot: bool, health: float)
signal killed(killer_id: int, victim_id: int, headshot: bool, assist_ids: Array)
signal hit_confirmed(victim_id: int, headshot: bool, killed: bool)
signal ended(winner: int, rows: Array)
signal rejected(reason: String)
signal closed(reason: String)
signal chat_received(from_id: int, text: String)
signal ping_received(from_id: int, team: int, position: Vector3)
signal entered(config: Config)
signal team_refused(reason: String)
signal team_switched(peer_id: int, respawn_seconds: float)

var active := false
var is_host := false
var config: Config
var rows: Array = []
var state := Match.State.LOBBY
var countdown_left := 0.0
var time_left := 0.0
var red_score := 0
var blue_score := 0
var sudden_death := false
var winner := Match.DRAW
## peer id -> {hp, protected, alive}; refreshed about four times a second.
var vitals: Dictionary = {}
var local_nickname := "Player"
var my_token := ""
var rules: Match
## Optional: func(origin: Vector3, target: Vector3) -> bool. True when world geometry blocks the shot.
var occlusion_check: Callable
## Optional: how far below the arena a player may fall before it counts as a death.
var fall_floor := -FALL_KILL_DEPTH
## Optional NetworkManager: used only to rejoin after a dropped connection.
var network_manager: Node
var last_address := ""
var last_port := 7777
## What this peer announces when it joins. Tests lower it to check that a mismatch is refused.
var protocol_version := PROTOCOL_VERSION

var _roster: Roster
var _spawns: Spawns
var _positions: Dictionary = {}
var _position_times: Dictionary = {}
var _ready_flags: Dictionary = {}
var _broadcast_timer := 0.0
var _chat_times: Dictionary = {}
var _ping_times: Dictionary = {}
var _reconnect_left := 0.0
var _reconnect_retry := 0.0
var _intentional_close := false

func _ready() -> void:
	name = "TdmSession"
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func local_id() -> int:
	return multiplayer.get_unique_id()

## True from a dropped connection until the host takes this player back or the wait runs out.
func reconnecting() -> bool:
	return _reconnect_left > 0.0

func local_team() -> int:
	for row: Dictionary in rows:
		if int(row.peer_id) == local_id():
			return int(row.team)
	return Roster.NO_TEAM

func team_of(peer_id: int) -> int:
	for row: Dictionary in rows:
		if int(row.peer_id) == peer_id:
			return int(row.team)
	return Roster.NO_TEAM

func nickname_of(peer_id: int) -> String:
	for row: Dictionary in rows:
		if int(row.peer_id) == peer_id:
			return String(row.nickname)
	return "Player %d" % peer_id

static func config_to_dict(value: Config) -> Dictionary:
	return {"team_size": value.team_size, "kill_limit_choice": value.kill_limit_choice,
		"time_limit_choice": value.time_limit_choice, "time_of_day": value.time_of_day}

static func config_from_dict(data: Dictionary) -> Config:
	var value := Config.new()
	value.team_size = clampi(int(data.get("team_size", 4)), 1, 8)
	value.kill_limit_choice = clampi(int(data.get("kill_limit_choice", 1)), 0, 2)
	value.time_limit_choice = clampi(int(data.get("time_limit_choice", 1)), 0, 2)
	value.time_of_day = clampi(int(data.get("time_of_day", 1)), 0, 2)
	return value

## "TDM 4v4 · Night", shown next to the room in FIND GAMES.
static func describe(value: Config) -> String:
	return "TDM %dv%d · %s" % [value.team_size, value.team_size, ["Morning", "Afternoon", "Night"][value.time_of_day]]

# --- Host: starting and running a match ------------------------------------

## Starts hosting a match in the lobby phase. `zones` are the spawn points per team.
func host_begin(p_config: Config, nickname: String, zones: Array[PackedVector3Array]) -> void:
	_reset()
	active = true
	is_host = true
	config = p_config
	local_nickname = nickname
	_roster = Roster.new()
	_spawns = Spawns.new()
	for team in zones.size():
		_spawns.set_zones(team, zones[team])
	rules = Match.new(config, _roster, _spawns)
	rules.state_changed.connect(_on_rules_state_changed)
	rules.player_spawned.connect(_on_rules_spawned)
	rules.player_damaged.connect(_on_rules_damaged)
	rules.player_killed.connect(_on_rules_killed)
	rules.score_changed.connect(_on_rules_score_changed)
	rules.match_ended.connect(_on_rules_ended)
	rules.team_switched.connect(_on_rules_team_switched)
	rules.join(HOST_ID, nickname)
	_apply_state_locally()
	_publish_roster()
	entered.emit(config)

func host_start() -> bool:
	if not is_host or rules == null or not rules.start():
		return false
	_publish_state()
	return true

func host_rematch() -> bool:
	if not is_host or rules == null or not rules.rematch():
		return false
	_ready_flags.clear()
	_publish_state()
	_publish_roster()
	return true

## The host moves someone from the lobby; this skips the balance rule on purpose.
func host_move_player(peer_id: int) -> bool:
	if not is_host or rules == null or rules.state != Match.State.LOBBY or not _roster.swap_team(peer_id, true):
		return false
	_publish_roster()
	return true

## Leaves the match. A host also tells everyone the room is closed.
func leave() -> void:
	_intentional_close = true
	if is_host and active:
		rpc("rpc_closed", "The host closed the room.")
	_reset()
	active = false

func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_host:
		_tick_reconnect(delta)
		return
	rules.tick(delta)
	_check_fallen_players()
	_broadcast_timer += delta
	if _broadcast_timer >= BROADCAST_INTERVAL:
		_broadcast_timer = 0.0
		_publish_state()
		_publish_vitals()

## The host's view of where a peer is. The network layer calls this for every position update.
func on_peer_position(peer_id: int, position: Vector3) -> void:
	if not is_host or rules == null:
		return
	var now := Time.get_ticks_msec()
	if _positions.has(peer_id) and _position_times.has(peer_id):
		var seconds := maxf(0.001, float(now - int(_position_times[peer_id])) / 1000.0)
		if (position - _positions[peer_id]).length() / seconds > MAX_SPEED:
			return
	_positions[peer_id] = position
	_position_times[peer_id] = now
	rules.report_position(peer_id, position)

## Reports what the local crosshair hit and with which rifle. The host decides whether it counts.
func claim_hit(victim_id: int, headshot: bool, origin: Vector3, hit_position: Vector3, weapon := Weapons.M416) -> void:
	if not active or reconnecting():
		return
	if is_host:
		_handle_claim(HOST_ID, victim_id, headshot, origin, hit_position, weapon)
	else:
		rpc_id(HOST_ID, "rpc_report_hit", victim_id, headshot, origin, hit_position, weapon)

## Asks to join `team`. The host answers with a new roster, or team_refused with the reason.
func request_team(team: int) -> void:
	if reconnecting() or not active:
		return
	if is_host:
		_change_team(HOST_ID, team)
	else:
		rpc_id(HOST_ID, "rpc_request_team", team)

func set_ready_flag(value: bool) -> void:
	if reconnecting():
		return
	if is_host:
		_ready_flags[HOST_ID] = value
		_publish_roster()
	elif active:
		rpc_id(HOST_ID, "rpc_request_ready", value)

## Sends a quick-chat line to teammates (entries 0, 1 and 5 also drop a map ping at `position`).
func send_chat(index: int, position: Vector3) -> void:
	if not active or reconnecting() or index < 0 or index >= CHAT_LINES.size():
		return
	if is_host:
		_handle_chat(HOST_ID, index, position)
	else:
		rpc_id(HOST_ID, "rpc_request_chat", index, position)

# --- Host: validating claims -------------------------------------------------

## Returns {accepted, reason, killed}. The reason is empty for an accepted hit. Damage and the fastest
## allowed fire rate come from the named rifle, so claiming the other one never beats either's real output.
func _handle_claim(attacker_id: int, victim_id: int, headshot: bool, origin: Vector3, hit_position: Vector3,
		weapon := Weapons.M416) -> Dictionary:
	if not Weapons.is_valid(weapon):
		return {"accepted": false, "reason": "bad_weapon", "killed": false}
	var reason := _claim_problem(attacker_id, victim_id, headshot, origin, hit_position)
	if reason != "":
		return {"accepted": false, "reason": reason, "killed": false}
	var stats := Weapons.stats(weapon)
	if not rules.try_fire(attacker_id, float(stats.min_claim_interval)):
		return {"accepted": false, "reason": "fire_rate", "killed": false}
	var damage: float = stats.head_damage if headshot else stats.body_damage
	var result := rules.apply_hit(attacker_id, victim_id, damage, headshot)
	return {"accepted": result.accepted, "reason": result.reason, "killed": result.killed}

func _claim_problem(attacker_id: int, victim_id: int, headshot: bool, origin: Vector3, hit_position: Vector3) -> String:
	if not active or not is_host or rules == null:
		return "not_host"
	if not _positions.has(attacker_id) or not _positions.has(victim_id):
		return "position_unknown"
	if Vector3(_positions[attacker_id]).distance_to(origin) > MAX_ORIGIN_ERROR:
		return "origin_far_from_shooter"
	if origin.distance_to(hit_position) > MAX_HIT_DISTANCE:
		return "out_of_range"
	var victim_position: Vector3 = _positions[victim_id]
	if victim_position.distance_to(hit_position) > HIT_POSITION_TOLERANCE:
		return "hit_far_from_target"
	if headshot and hit_position.y - victim_position.y < 0.9:
		return "headshot_too_low"
	if occlusion_check.is_valid() and occlusion_check.call(origin, hit_position):
		return "blocked"
	return ""

func _check_fallen_players() -> void:
	for peer_id: int in _positions:
		if rules.is_alive(peer_id) and Vector3(_positions[peer_id]).y < fall_floor:
			rules.environment_death(peer_id)

func _handle_chat(sender_id: int, index: int, position: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_chat_times.get(sender_id, -100000)) < CHAT_INTERVAL_MSEC:
		return
	_chat_times[sender_id] = now
	var team := team_of(sender_id)
	var with_ping := PING_CHATS.has(index) and now - int(_ping_times.get(sender_id, -100000)) >= PING_INTERVAL_MSEC
	if with_ping:
		_ping_times[sender_id] = now
	for row: Dictionary in rows:
		if int(row.team) != team:
			continue
		_send_to(int(row.peer_id), "rpc_chat", [sender_id, index])
		if with_ping:
			_send_to(int(row.peer_id), "rpc_ping", [sender_id, team, position])

func _change_team(peer_id: int, team: int) -> void:
	if team != Roster.Team.RED and team != Roster.Team.BLUE:
		return
	var refusal: String = rules.change_team(peer_id, team)
	if refusal != "":
		_send_to(peer_id, "rpc_team_refused", [refusal])
	else:
		_publish_roster()

func _send_to(peer_id: int, method: String, args: Array) -> void:
	if peer_id == local_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)

# --- Host: rule events become network messages --------------------------------

func _on_rules_state_changed(_value: int) -> void:
	# rpc_state (call_local) updates the mirror and raises state_changed on the host too.
	_publish_state()

func _on_rules_spawned(peer_id: int, position: Vector3) -> void:
	# Stamped, not cleared: a report sent before the teleport must fail the speed check, or the host
	# would believe the old spot and refuse this player's hits until enough time passed to reach the new one.
	_positions[peer_id] = position
	_position_times[peer_id] = Time.get_ticks_msec()
	rpc("rpc_spawn", peer_id, position)

func _on_rules_damaged(victim_id: int, attacker_id: int, amount: float, headshot: bool, health: float) -> void:
	rpc("rpc_damage", victim_id, attacker_id, amount, headshot, health)

func _on_rules_killed(killer_id: int, victim_id: int, headshot: bool, assist_ids: Array[int]) -> void:
	_publish_roster()
	rpc("rpc_kill", killer_id, victim_id, headshot, assist_ids)

func _on_rules_score_changed(_red: int, _blue: int) -> void:
	_publish_state()

func _on_rules_ended(result: int) -> void:
	_publish_state()
	_publish_roster()
	rpc("rpc_end", result, _roster.scoreboard())

func _on_rules_team_switched(peer_id: int, seconds: float) -> void:
	rpc("rpc_team_switched", peer_id, seconds)

func _on_peer_disconnected(peer_id: int) -> void:
	if not (active and is_host) or rules == null or not _roster.has_member(peer_id):
		return
	rules.peer_disconnected(peer_id)
	_publish_roster()

func _publish_roster() -> void:
	var list: Array = []
	for row: Dictionary in _roster.scoreboard():
		row["ready"] = bool(_ready_flags.get(int(row.peer_id), false))
		row["connected"] = _roster.member(int(row.peer_id)).connected
		list.append(row)
	rpc("rpc_roster", list)

func _publish_state() -> void:
	rpc("rpc_state", int(rules.state), rules.countdown_left, rules.time_left,
		_roster.team_kills[Roster.Team.RED], _roster.team_kills[Roster.Team.BLUE], rules.sudden_death)

func _publish_vitals() -> void:
	var data: Dictionary = {}
	for peer_id in _roster.peer_ids():
		data[peer_id] = [rules.health_of(peer_id), rules.is_protected(peer_id), rules.is_alive(peer_id)]
	rpc("rpc_vitals", data)

func _apply_state_locally() -> void:
	state = rules.state

# --- Messages from the host (run on every peer, the host included) -------------

@rpc("authority", "call_local", "reliable")
func rpc_roster(list: Array) -> void:
	rows = list
	lobby_changed.emit()

@rpc("authority", "call_local", "reliable")
func rpc_state(state_value: int, countdown: float, time_remaining: float, red: int, blue: int, sudden: bool) -> void:
	var changed := state != state_value
	state = state_value
	countdown_left = countdown
	time_left = time_remaining
	red_score = red
	blue_score = blue
	sudden_death = sudden
	if changed:
		state_changed.emit(state_value)

@rpc("authority", "call_local", "reliable")
func rpc_spawn(peer_id: int, position: Vector3) -> void:
	vitals[peer_id] = {"hp": config.max_health if config != null else 100.0, "protected": false, "alive": true}
	spawned.emit(peer_id, position)

@rpc("authority", "call_local", "reliable")
func rpc_damage(victim_id: int, attacker_id: int, amount: float, headshot: bool, health: float) -> void:
	if vitals.has(victim_id):
		vitals[victim_id].hp = health
	damaged.emit(victim_id, attacker_id, amount, headshot, health)
	if attacker_id == local_id():
		hit_confirmed.emit(victim_id, headshot, health <= 0.0)

@rpc("authority", "call_local", "reliable")
func rpc_kill(killer_id: int, victim_id: int, headshot: bool, assist_ids: Array) -> void:
	if vitals.has(victim_id):
		vitals[victim_id].alive = false
		vitals[victim_id].hp = 0.0
	killed.emit(killer_id, victim_id, headshot, assist_ids)

@rpc("authority", "call_local", "reliable")
func rpc_team_refused(reason: String) -> void:
	team_refused.emit(reason)

@rpc("authority", "call_local", "reliable")
func rpc_team_switched(peer_id: int, seconds: float) -> void:
	if vitals.has(peer_id):
		vitals[peer_id].alive = false
		vitals[peer_id].hp = 0.0
	team_switched.emit(peer_id, seconds)

@rpc("authority", "call_local", "unreliable_ordered")
func rpc_vitals(data: Dictionary) -> void:
	for peer_id: int in data:
		var entry: Array = data[peer_id]
		vitals[peer_id] = {"hp": float(entry[0]), "protected": bool(entry[1]), "alive": bool(entry[2])}

@rpc("authority", "call_local", "reliable")
func rpc_end(result: int, final_rows: Array) -> void:
	winner = result
	ended.emit(result, final_rows)

@rpc("authority", "call_remote", "reliable")
func rpc_enter(config_data: Dictionary, token: String) -> void:
	_reset()
	active = true
	is_host = false
	config = config_from_dict(config_data)
	my_token = token
	_intentional_close = false
	_reconnect_left = 0.0
	entered.emit(config)

@rpc("authority", "call_remote", "reliable")
func rpc_rejected(reason: String) -> void:
	rejected.emit(reason)

@rpc("authority", "call_local", "reliable")
func rpc_closed(reason: String) -> void:
	if is_host:
		return
	_intentional_close = true
	_reset()
	closed.emit(reason)

@rpc("authority", "call_local", "reliable")
func rpc_chat(from_id: int, index: int) -> void:
	if index >= 0 and index < CHAT_LINES.size():
		chat_received.emit(from_id, CHAT_LINES[index])

@rpc("authority", "call_local", "reliable")
func rpc_ping(from_id: int, team: int, position: Vector3) -> void:
	ping_received.emit(from_id, team, position)

# --- Messages from clients (validated on the host) ------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(version: int, nickname: String, token: String) -> void:
	if not (active and is_host):
		return
	var sender := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		rpc_id(sender, "rpc_rejected", "Different game version. Update the game and try again.")
		get_tree().create_timer(0.4).timeout.connect(_disconnect_peer.bind(sender))
		return
	if token != "" and rules.peer_reconnected(token, sender):
		pass
	elif _roster.peer_ids().size() >= config.team_size * 2:
		rpc_id(sender, "rpc_rejected", "This match is full.")
		get_tree().create_timer(0.4).timeout.connect(_disconnect_peer.bind(sender))
		return
	else:
		rules.join(sender, nickname.left(18))
	_positions.erase(sender)
	_position_times.erase(sender)
	rpc_id(sender, "rpc_enter", config_to_dict(config), _roster.member(sender).token)
	_publish_roster()
	_publish_state()
	# A mid-match joiner was spawned before they could hear about it: tell them where they stand.
	if rules.is_alive(sender):
		rpc_id(sender, "rpc_spawn", sender, rules.position_of(sender))

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_team(team: int) -> void:
	if active and is_host:
		_change_team(multiplayer.get_remote_sender_id(), team)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_ready(value: bool) -> void:
	if active and is_host:
		_ready_flags[multiplayer.get_remote_sender_id()] = value
		_publish_roster()

@rpc("any_peer", "call_remote", "reliable")
func rpc_report_hit(victim_id: int, headshot: bool, origin: Vector3, hit_position: Vector3, weapon: int) -> void:
	if active and is_host:
		_handle_claim(multiplayer.get_remote_sender_id(), victim_id, headshot, origin, hit_position, weapon)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_chat(index: int, position: Vector3) -> void:
	if active and is_host:
		_handle_chat(multiplayer.get_remote_sender_id(), index, position)

func _disconnect_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	# The refused client may already have left on its own.
	if peer is ENetMultiplayerPeer and multiplayer.get_peers().has(peer_id):
		(peer as ENetMultiplayerPeer).disconnect_peer(peer_id)

# --- Client: joining and rejoining ----------------------------------------------

func _on_connected_to_server() -> void:
	# Free-roam hosts ignore this; a TDM host answers with rpc_enter.
	rpc_id(HOST_ID, "rpc_hello", protocol_version, local_nickname, my_token)

func _on_server_disconnected() -> void:
	if _intentional_close or not active or is_host:
		return
	if my_token != "" and last_address != "":
		_reconnect_left = RECONNECT_SECONDS
		_reconnect_retry = 0.0
		closed.emit("Connection lost. Trying to rejoin…")
	else:
		_reset()
		closed.emit("Room closed")

func _tick_reconnect(delta: float) -> void:
	if _reconnect_left <= 0.0:
		return
	_reconnect_left -= delta
	if _reconnect_left <= 0.0:
		_reset()
		closed.emit("Could not rejoin")
		return
	_reconnect_retry -= delta
	if _reconnect_retry <= 0.0 and network_manager != null:
		_reconnect_retry = RECONNECT_RETRY_SECONDS
		network_manager.join_game(last_address, last_port, local_nickname)

func _reset() -> void:
	is_host = false
	rules = null
	_roster = null
	_spawns = null
	rows = []
	vitals.clear()
	_positions.clear()
	_position_times.clear()
	_ready_flags.clear()
	state = Match.State.LOBBY
	winner = Match.DRAW
	red_score = 0
	blue_score = 0
	sudden_death = false
	_reconnect_left = 0.0
	if not _intentional_close:
		my_token = ""
	active = false
