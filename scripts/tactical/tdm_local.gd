extends Node

## Turns the session's events into gameplay on this device: builds the arena, trims the city, spawns and
## freezes the player, shows the HUD, draws teammates and pings, and puts everything back when the player
## leaves (docs/TDM_DESIGN.md, sections 3 and 5). Free-roam progress is never saved or changed by a match.

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Arena := preload("res://scripts/tactical/tdm_arena.gd")
const Hud := preload("res://scripts/tactical/tdm_hud.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const Dummy := preload("res://scripts/tactical/tdm_dummy.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

const MAG_SIZE := 30
const RELOAD_SECONDS := 2.0
const RADAR_REVEAL_MSEC := 3000
const PING_SECONDS := 6.0
const AIM_ASSIST_SLOWDOWN := 0.75
const AIM_ASSIST_RANGE := 90.0
const PRACTICE_SPOTS: Array[Vector2] = [Vector2(-25, 0), Vector2(-10, 14), Vector2(15, -10), Vector2(30, 12), Vector2(5, 30), Vector2(-20, -25)]
const TIME_NAMES: Array[String] = ["Morning", "Afternoon", "Night"]
const CITY_NODES: Array[String] = ["traffic", "street_life", "birds", "local_activity"]

var game: Node
var session: Node
var hud: Hud
var arena: Arena
var in_match := false
var practicing := false

var _alive := false
var _killer_name := ""
var _respawn_left := 0.0
var _out_of_bounds := 0.0
var _saved := {}
var _hidden_nodes: Array[Dictionary] = []
var _refresh_timer := 0.0
var _pings: Dictionary = {}
var _practice_stats := {"hits": 0, "headshots": 0, "shots": 0}
var _dummies: Array[Node] = []
var _hidden_ui: Array[Dictionary] = []
var _aim_assist_on := false
## Killcam: for a few seconds after dying the view follows the killer over their shoulder.
const KILLCAM_SECONDS := 3.0
var _killcam: Camera3D
var _killcam_target := 0
var _killcam_left := 0.0
var _camera_before: Camera3D
const MINIMAP_ALLY := Color(0.35, 1.0, 0.45)
const MINIMAP_ENEMY := Color(1.0, 0.25, 0.25)
const MINIMAP_PING := Color(1.0, 0.9, 0.3)
var _base_sensitivity := 1.0

func setup(p_game: Node, p_session: Node) -> void:
	game = p_game
	session = p_session
	name = "TdmLocal"
	process_mode = Node.PROCESS_MODE_ALWAYS
	session.network_manager = game.network_manager
	game.network_manager.tdm = session
	game.gameplay.tdm_local = self
	hud = Hud.new()
	game.add_child(hud)
	hud.setup(session)
	hud.camera_provider = func() -> Camera3D: return get_viewport().get_camera_3d()
	hud.position_provider = _position_of
	hud.radar_provider = _radar_data
	hud.start_pressed.connect(_on_start)
	hud.swap_pressed.connect(func() -> void: session.request_swap())
	hud.ready_toggled.connect(func(value: bool) -> void: session.set_ready_flag(value))
	hud.practice_pressed.connect(start_practice)
	hud.leave_pressed.connect(leave_match)
	hud.rematch_pressed.connect(func() -> void: session.host_rematch())
	hud.chat_selected.connect(func(index: int) -> void: session.send_chat(index, _ping_position()))
	session.entered.connect(_on_entered)
	session.lobby_changed.connect(_on_lobby_changed)
	session.state_changed.connect(_on_state_changed)
	session.spawned.connect(_on_spawned)
	session.damaged.connect(_on_damaged)
	session.killed.connect(_on_killed)
	session.hit_confirmed.connect(func(_victim: int, headshot: bool, _killed: bool) -> void: hud.flash_hit(headshot))
	session.ended.connect(_on_ended)
	session.closed.connect(_on_closed)
	session.rejected.connect(_on_rejected)
	session.chat_received.connect(_on_chat)
	session.ping_received.connect(_on_ping)

# --- Entering and leaving --------------------------------------------------------

## Hosts a TDM room: builds the arena first so the spawn zones come from the real world. The zones
## an enemy could see down the highway are dropped once physics has the cover (a few frames).
func host_match(config: Config, nickname: String) -> void:
	_prepare_arena()
	for _i in 3:
		await get_tree().physics_frame
	var exclude: Array[RID] = [game.person.get_rid()]
	arena.prune_exposed_zones(game.person.get_world_3d().direct_space_state, exclude)
	session.host_begin(config, nickname, arena.zones)

func _on_entered(config: Config) -> void:
	if in_match:
		return
	in_match = true
	_prepare_arena()
	_save_free_roam()
	_configure_gameplay(config)
	hud.set_practice(false)
	hud.refresh()
	game.hud.multiplayer_panel.visible = false
	var person: CharacterBody3D = game.person
	person.health_changed.connect(_restore_host_health)
	session.occlusion_check = _blocked
	session.fall_floor = arena.ground_at(Vector2.ZERO) - Arena.RADIUS * 0.4
	_alive = false
	_freeze(true)
	_place_in_lobby()

func _prepare_arena() -> void:
	if arena != null:
		return
	var world: Node = game.get_node("World")
	world.buildings.build_around(Vector2.ZERO, Arena.RADIUS + 90.0)
	arena = Arena.new()
	game.add_child(arena)
	arena.build(world, game.get_node("DayEnvironment").environment)
	arena.set_process(false)

## Remembers where free roam was and trims the city down to the arena.
func _save_free_roam() -> void:
	var person: CharacterBody3D = game.person
	var gameplay: Node = game.gameplay
	var environment: Node = game.city_life.environment
	if game.control_state != game.ControlState.ON_FOOT:
		game.entry.cancel()
		game.active_vehicle.set_driving_enabled(false)
		game.control_state = game.ControlState.EXITING
		game._finish_exit_vehicle()
	if not gameplay.mission.is_empty():
		gameplay.end_mission(false, "Team Deathmatch started")
	_saved = {
		"transform": person.global_transform, "health": person.health, "weapon": person.is_weapon_equipped(),
		"action_mode": gameplay.action_mode, "has_rifle": gameplay.has_rifle, "ammo": gameplay.ammo,
		"reserve": gameplay.reserve, "mag": gameplay.mag_size, "reload": gameplay.reload_seconds,
		"rifles": gameplay.owned_rifles.duplicate(), "weapon_id": person.weapon_id,
		"time_mode": environment.time_mode, "auto_weather": environment.auto_weather,
		"stream_radius": game.get_node("World").buildings.stream_radius,
		"minimap": game.hud.minimap.visible if game.hud.minimap != null else false,
	}
	arena.set_process(true)
	var world: Node = game.get_node("World")
	world.buildings.stream_radius = Arena.RADIUS + 90.0
	_hide_city(world)
	_hide_free_roam_ui()
	if game.hud.minimap != null:
		game.hud.minimap.visible = true
		game.hud.minimap.markers = _minimap_markers

## The free-roam info panel and vehicle prompts would sit on top of the match HUD.
func _hide_free_roam_ui() -> void:
	_hidden_ui.clear()
	var nodes: Array = [game.hud.get_node_or_null("Panel"), game.hud.get_node_or_null("Offline"),
		game.hud.get_node_or_null("InteractionPrompt")]
	for node in nodes:
		if node is CanvasItem:
			_hidden_ui.append({"node": node, "visible": node.visible})
			node.visible = false

func _keep_free_roam_ui_hidden() -> void:
	for entry: Dictionary in _hidden_ui:
		if is_instance_valid(entry.node):
			entry.node.visible = false

func _restore_free_roam_ui() -> void:
	for entry: Dictionary in _hidden_ui:
		if is_instance_valid(entry.node):
			entry.node.visible = entry.visible
	_hidden_ui.clear()

func _hide_city(world: Node) -> void:
	_hidden_nodes.clear()
	var targets: Array = []
	for key in CITY_NODES:
		if world.get(key) is Node:
			targets.append(world.get(key))
	targets.append_array(get_tree().get_nodes_in_group("city_residents"))
	for node: Node in targets:
		if not is_instance_valid(node):
			continue
		_hidden_nodes.append({"node": node, "visible": node.get("visible"), "mode": node.process_mode})
		node.set("visible", false)
		node.process_mode = Node.PROCESS_MODE_DISABLED

func _configure_gameplay(config: Config) -> void:
	var gameplay: Node = game.gameplay
	var environment: Node = game.city_life.environment
	environment.set_time_mode(TIME_NAMES[config.time_of_day])
	environment.set_weather_mode("Clear")
	gameplay.has_rifle = true
	# Everyone carries both rifles and switches freely (docs/TDM_DESIGN.md, section 2).
	gameplay.owned_rifles = Weapons.IDS.duplicate()
	gameplay.mag_size = MAG_SIZE
	gameplay.reload_seconds = RELOAD_SECONDS
	gameplay.reset_magazines()
	gameplay.reserve = 9999
	gameplay.tdm_active = true
	gameplay.set_action_mode(true)
	game.person.set_weapon_equipped(true)

func _restore_free_roam() -> void:
	if _saved.is_empty():
		return
	var person: CharacterBody3D = game.person
	var gameplay: Node = game.gameplay
	var environment: Node = game.city_life.environment
	if person.health_changed.is_connected(_restore_host_health):
		person.health_changed.disconnect(_restore_host_health)
	gameplay.tdm_active = false
	gameplay.mag_size = _saved.mag
	gameplay.reload_seconds = _saved.reload
	gameplay.reset_magazines()
	gameplay.ammo = mini(_saved.ammo, _saved.mag)
	gameplay.reserve = _saved.reserve
	gameplay.has_rifle = _saved.has_rifle
	gameplay.owned_rifles = _saved.rifles
	person.set_weapon_model(_saved.weapon_id)
	gameplay.set_action_mode(_saved.action_mode)
	person.set_weapon_equipped(_saved.weapon)
	environment.set_time_mode(_saved.time_mode)
	environment.set_weather_mode("Automatic" if _saved.auto_weather else "Clear")
	person.set_movement_enabled(true)
	person.global_transform = _saved.transform
	person.velocity = Vector3.ZERO
	person.health = _saved.health
	person.health_changed.emit(person.health, person.max_health)
	person.reset_physics_interpolation()
	game.get_node("World").buildings.stream_radius = _saved.stream_radius
	for entry: Dictionary in _hidden_nodes:
		if is_instance_valid(entry.node):
			entry.node.set("visible", entry.visible)
			entry.node.process_mode = entry.mode
	_hidden_nodes.clear()
	if game.hud.minimap != null:
		game.hud.minimap.visible = _saved.minimap
		game.hud.minimap.markers = Callable()
	_end_killcam()
	_restore_free_roam_ui()
	if arena != null:
		arena.restore()
		arena.queue_free()
		arena = null
	_saved.clear()
	_set_aim_assist(false)
	for dummy in _dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	_dummies.clear()
	for puppet: Node in game.network_manager.puppets.values():
		if is_instance_valid(puppet):
			puppet.set_tdm_alive(true, false)
			puppet.tdm_mode = false

## Leave button: the host closes the room, a client just goes. Back to free roam either way.
func leave_match() -> void:
	var manager: Node = game.network_manager
	session.leave()
	if manager.is_active():
		manager.disconnect_game()
	_finish()

func _finish() -> void:
	practicing = false
	in_match = false
	_alive = false
	hud.set_practice(false)
	hud.hide_all()
	_restore_free_roam()

func _on_closed(reason: String) -> void:
	if reason.begins_with("Connection lost"):
		hud.show_banner(reason, 3.0)
		return
	game.city_life.toast(reason)
	game.network_manager.disconnect_game()
	_finish()

func _on_rejected(reason: String) -> void:
	game.city_life.toast(reason)
	game.network_manager.disconnect_game()

# --- Match flow ----------------------------------------------------------------------

func _on_start() -> void:
	if practicing:
		return
	session.host_start()

func _on_lobby_changed() -> void:
	if not in_match:
		return
	if practicing and session.rows.size() > 1:
		stop_practice()
	if session.state == Match.State.LOBBY:
		_place_in_lobby()
	_refresh_puppets()

func _on_state_changed(value: int) -> void:
	if not in_match:
		return
	match value:
		Match.State.LOBBY:
			_alive = false
			hud.hide_death()
			_freeze(true)
			_place_in_lobby()
		Match.State.COUNTDOWN:
			_freeze(true)
		Match.State.LIVE:
			hud.show_banner("GO!", 1.2)
			_freeze(not _alive)
		Match.State.ENDED:
			_freeze(true)
	hud.refresh()

func _on_spawned(peer_id: int, position: Vector3) -> void:
	if not in_match:
		return
	if peer_id != session.local_id():
		_refresh_puppets()
		return
	_teleport(position)
	_end_killcam()
	var character := _character()
	if character != null:
		character.reset_death()
	_alive = true
	_respawn_left = 0.0
	_out_of_bounds = 0.0
	var gameplay: Node = game.gameplay
	gameplay.reset_magazines()
	gameplay.reserve = 9999
	game.person.health = session.config.max_health
	game.person.health_changed.emit(game.person.health, game.person.max_health)
	game.person.set_weapon_equipped(true)
	hud.hide_death()
	_freeze(session.state != Match.State.LIVE)

func _on_damaged(victim_id: int, attacker_id: int, _amount: float, _headshot: bool, health: float) -> void:
	var from := _position_of(attacker_id)
	if victim_id != session.local_id():
		var puppet: Node = game.network_manager.puppets.get(victim_id)
		if is_instance_valid(puppet) and from != Vector3.INF:
			puppet.notify_hit(from)
		return
	var character := _character()
	if character != null and from != Vector3.INF:
		character.play_hit(from)
	game.person.health = health
	game.person.health_changed.emit(health, game.person.max_health)
	if health > 0.0:
		hud.show_damage_from(attacker_id)

func _on_killed(killer_id: int, victim_id: int, headshot: bool, _assists: Array) -> void:
	var killer_name: String = session.nickname_of(killer_id) if killer_id != Match.NO_KILLER else ""
	hud.add_kill(killer_name, session.nickname_of(victim_id), session.team_of(killer_id), headshot)
	if victim_id == session.local_id():
		_alive = false
		_killer_name = killer_name
		_respawn_left = session.config.respawn_seconds
		_freeze(true)
		game.person.set_weapon_equipped(false)
		hud.show_death(_killer_name, _respawn_left)
		var killer_position := _position_of(killer_id)
		var character := _character()
		if character != null:
			character.play_death(killer_position if killer_position != Vector3.INF else game.person.global_position - game.person.global_basis.z)
		if killer_id != Match.NO_KILLER and killer_id != session.local_id() and killer_position != Vector3.INF:
			_start_killcam(killer_id)
	_refresh_puppets()

func _on_ended(winner: int, rows: Array) -> void:
	hud.show_end(winner, rows)

func _on_chat(from_id: int, text: String) -> void:
	hud.add_chat(session.nickname_of(from_id), text, session.team_of(from_id))

func _on_ping(from_id: int, team: int, position: Vector3) -> void:
	if _pings.has(from_id) and is_instance_valid(_pings[from_id].node):
		_pings[from_id].node.queue_free()
	var marker := Label3D.new()
	marker.text = "▼ %s" % session.nickname_of(from_id)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.font_size = 40
	marker.modulate = Color(1.0, 0.9, 0.3)
	marker.outline_size = 8
	game.add_child(marker)
	marker.global_position = position + Vector3.UP * 2.5
	_pings[from_id] = {"node": marker, "position": position, "until": Time.get_ticks_msec() + int(PING_SECONDS * 1000.0), "team": team}

# --- Per frame ------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if (in_match or practicing) and session.is_host and not practicing:
		session.on_peer_position(session.HOST_ID, game.person.global_position)

func _process(delta: float) -> void:
	if not in_match and not practicing:
		return
	_expire_pings()
	_keep_free_roam_ui_hidden()
	if practicing:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.4
		_refresh_puppets()
	if not _alive and session.state == Match.State.LIVE and _respawn_left > 0.0:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		hud.show_death(_killer_name, _respawn_left)
	_update_boundary(delta)
	_update_aim_assist()
	_update_killcam(delta)
	var mine: Dictionary = session.vitals.get(session.local_id(), {})
	if _alive and mine.has("hp") and absf(float(mine.hp) - game.person.health) > 0.5:
		game.person.health = float(mine.hp)

## Shows the red warning when the player is outside the ring; the host does the actual killing.
func _update_boundary(delta: float) -> void:
	if not _alive or session.state != Match.State.LIVE or arena == null:
		_out_of_bounds = 0.0
		hud.hide_boundary()
		return
	var mine: Dictionary = session.vitals.get(session.local_id(), {})
	if arena.is_inside(game.person.global_position) or bool(mine.get("protected", false)):
		_out_of_bounds = 0.0
		hud.hide_boundary()
	else:
		_out_of_bounds += delta
		hud.show_boundary(session.config.out_of_bounds_seconds - _out_of_bounds)

func _expire_pings() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _pings.keys():
		if now > int(_pings[id].until):
			if is_instance_valid(_pings[id].node):
				_pings[id].node.queue_free()
			_pings.erase(id)

func _refresh_puppets() -> void:
	var my_team: int = session.local_team()
	for peer_id: int in game.network_manager.puppets:
		var puppet: Node = game.network_manager.puppets[peer_id]
		if not is_instance_valid(puppet):
			continue
		var team: int = session.team_of(peer_id)
		if team >= 0:
			puppet.set_tdm_team(team, team == my_team)
		var mine: Dictionary = session.vitals.get(peer_id, {})
		puppet.set_tdm_alive(bool(mine.get("alive", true)), bool(mine.get("protected", false)))

func _position_of(peer_id: int) -> Vector3:
	var puppet: Node = game.network_manager.puppets.get(peer_id)
	if peer_id == session.local_id():
		return game.person.global_position
	return puppet.global_position if is_instance_valid(puppet) else Vector3.INF

func _radar_data() -> Dictionary:
	if not in_match:
		return {}
	var allies: Array = []
	var enemies: Array = []
	var my_team: int = session.local_team()
	var now := Time.get_ticks_msec()
	for peer_id: int in game.network_manager.puppets:
		var puppet: Node = game.network_manager.puppets[peer_id]
		if not is_instance_valid(puppet) or not puppet.visible:
			continue
		if session.team_of(peer_id) == my_team:
			allies.append(puppet.global_position)
		elif now - int(puppet.last_fired_msec) < RADAR_REVEAL_MSEC:
			enemies.append(puppet.global_position)
	var pings: Array = []
	for entry: Dictionary in _pings.values():
		if int(entry.team) == my_team:
			pings.append(entry.position)
	return {"me": game.person.global_position, "allies": allies, "enemies": enemies, "pings": pings}

func _character() -> Node:
	return game.person.get_node_or_null("TestCharacter")

## Team-mates always, enemies for a few seconds after they fire, and team pings, on the game's minimap.
func _minimap_markers() -> Array:
	var data := _radar_data()
	if data.is_empty():
		return []
	var list: Array = []
	for point: Vector3 in data.get("pings", []):
		list.append([Vector2(point.x, point.z), MINIMAP_PING, 6.0])
	for point: Vector3 in data.get("allies", []):
		list.append([Vector2(point.x, point.z), MINIMAP_ALLY, 4.5])
	for point: Vector3 in data.get("enemies", []):
		list.append([Vector2(point.x, point.z), MINIMAP_ENEMY, 5.0])
	return list

func _start_killcam(killer_id: int) -> void:
	_camera_before = get_viewport().get_camera_3d()
	if _killcam == null:
		_killcam = Camera3D.new()
		_killcam.name = "TdmKillcam"
		_killcam.fov = 60.0
		_killcam.far = Arena.VIEW_FAR
		game.add_child(_killcam)
	_killcam_target = killer_id
	_killcam_left = KILLCAM_SECONDS
	_update_killcam(0.0)
	_killcam.make_current()

## Over the killer's shoulder, looking where they look.
func _update_killcam(delta: float) -> void:
	if _killcam_left <= 0.0 or _killcam == null:
		return
	_killcam_left -= delta
	var puppet: Node3D = game.network_manager.puppets.get(_killcam_target)
	if _killcam_left <= 0.0 or not is_instance_valid(puppet):
		_end_killcam()
		return
	var forward := puppet.global_basis.z
	var right := -puppet.global_basis.x
	var target := puppet.global_position + Vector3.UP * 1.5 + forward * 6.0
	var spot := puppet.global_position + Vector3.UP * 1.9 - forward * 2.4 + right * 0.6
	_killcam.global_position = _killcam.global_position.lerp(spot, 1.0 if delta == 0.0 else 1.0 - exp(-8.0 * delta))
	_killcam.look_at(target, Vector3.UP)

func _end_killcam() -> void:
	if _killcam_left > 0.0 or (_killcam != null and _killcam.current):
		_killcam_left = 0.0
		if is_instance_valid(_camera_before):
			_camera_before.make_current()
	_killcam_left = 0.0

# --- Player control -------------------------------------------------------------------

func _freeze(frozen: bool) -> void:
	game.person.set_movement_enabled(not frozen)

func _teleport(position: Vector3) -> void:
	game.person.global_position = position + Vector3.UP * 0.1
	game.person.velocity = Vector3.ZERO
	game.person.reset_physics_interpolation()

func _place_in_lobby() -> void:
	var team: int = maxi(0, session.local_team())
	var zone := arena.zones[team]
	if not zone.is_empty():
		_teleport(zone[0])

## Weapons work only in a live match while alive, or in practice.
func can_fire() -> bool:
	if practicing:
		return true
	return in_match and _alive and session.state == Match.State.LIVE

func on_shot_fired() -> void:
	if practicing:
		_practice_stats.shots += 1
		hud.set_practice_stats(_practice_stats.hits, _practice_stats.headshots, _practice_stats.shots)

## Restores the host's health if anything local (a fall, say) lowered it.
func _restore_host_health(value: float, _maximum: float) -> void:
	if not in_match or practicing or not _alive:
		return
	var mine: Dictionary = session.vitals.get(session.local_id(), {})
	if mine.has("hp") and absf(value - float(mine.hp)) > 0.5:
		game.person.health = float(mine.hp)

## Where the crosshair points, for map pings.
func _ping_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return game.person.global_position
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 120.0, 0xFFFFFFFF, [game.person.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else game.person.global_position

## Used by the host to reject shots that pass through walls. Players are not walls.
func _blocked(origin: Vector3, target: Vector3) -> bool:
	var along := target - origin
	if along.length() < 1.5:
		return false
	var exclude: Array[RID] = [game.person.get_rid()]
	for puppet: Node in game.network_manager.puppets.values():
		if is_instance_valid(puppet) and puppet is CollisionObject3D:
			exclude.append((puppet as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, target - along.normalized() * 0.7, 0xFFFFFFFF, exclude)
	return not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Light slowdown while the crosshair is on an enemy (touch devices only).
func _update_aim_assist() -> void:
	if not DisplayServer.is_touchscreen_available() or not _alive:
		_set_aim_assist(false)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * AIM_ASSIST_RANGE, 0xFFFFFFFF, [game.person.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	var on_enemy := false
	if not hit.is_empty() and hit.collider.has_method("tdm_claim_hit"):
		on_enemy = session.team_of(int(hit.collider.peer_id)) != session.local_team()
	_set_aim_assist(on_enemy)

func _set_aim_assist(on: bool) -> void:
	var pivot: Node = game.person.camera_pivot
	if pivot == null or on == _aim_assist_on:
		return
	if on:
		_base_sensitivity = pivot.look_sensitivity
		pivot.look_sensitivity = _base_sensitivity * AIM_ASSIST_SLOWDOWN
	else:
		pivot.look_sensitivity = _base_sensitivity
	_aim_assist_on = on

# --- Practice mode ---------------------------------------------------------------------

## A lone host shoots standing dummies: hits, headshots and accuracy, no timer.
func start_practice() -> void:
	if not in_match or not session.is_host or session.rows.size() > 1:
		return
	practicing = true
	_practice_stats = {"hits": 0, "headshots": 0, "shots": 0}
	_alive = true
	_freeze(false)
	game.person.set_weapon_equipped(true)
	game.gameplay.reset_magazines()
	hud.set_practice(true)
	hud.set_practice_stats(0, 0, 0)
	for spot in PRACTICE_SPOTS:
		var dummy: Node3D = Dummy.new()
		game.add_child(dummy)
		dummy.global_position = Vector3(spot.x, arena.ground_at(spot), spot.y)
		dummy.hit.connect(_on_dummy_hit)
		_dummies.append(dummy)

func stop_practice() -> void:
	practicing = false
	for dummy in _dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	_dummies.clear()
	_alive = false
	_freeze(true)
	hud.set_practice(false)
	_place_in_lobby()

func _on_dummy_hit(headshot: bool, _killed: bool) -> void:
	_practice_stats.hits += 1
	if headshot:
		_practice_stats.headshots += 1
	hud.flash_hit(headshot)
	hud.set_practice_stats(_practice_stats.hits, _practice_stats.headshots, _practice_stats.shots)
