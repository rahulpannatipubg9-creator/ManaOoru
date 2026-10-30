extends RefCounted

## Host-side Team Deathmatch rules: countdown, kills, respawns, regen, boundary, win and tie.
## Pure logic with no networking or scene nodes, so it can be tested headless. The network
## layer feeds it validated events and broadcasts the signals below (docs/TDM_DESIGN.md, section 4).

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Roster := preload("res://scripts/tactical/tdm_roster.gd")
const Spawns := preload("res://scripts/tactical/tdm_spawns.gd")

enum State { LOBBY, COUNTDOWN, LIVE, ENDED }
const DRAW := -1
## Killer id used in player_killed when nobody gets credit (a fall or leaving the arena).
const NO_KILLER := 0

signal state_changed(state: int)
signal player_spawned(peer_id: int, position: Vector3)
signal player_damaged(victim_id: int, attacker_id: int, amount: float, headshot: bool, health: float)
signal player_killed(killer_id: int, victim_id: int, headshot: bool, assist_ids: Array[int])
signal score_changed(red: int, blue: int)
signal sudden_death_started
signal match_ended(winner: int)

## Per-life state for one player. Persistent score lives in the roster.
class Life:
	var alive := false
	var ghost := false
	var health := 0.0
	var position := Vector3.ZERO
	var protected_for := 0.0
	var respawn_in := 0.0
	var out_of_bounds_for := 0.0
	var last_damage_at := -1000.0
	var last_shot_at := -1000.0
	var damage_log: Array[Dictionary] = []

var config: Config
var roster: Roster
var spawns: Spawns
var state := State.LOBBY
var winner := DRAW
var sudden_death := false
var countdown_left := 0.0
var time_left := 0.0
var sudden_death_left := 0.0

var _clock := 0.0
var _lives: Dictionary = {}
var _empty_team_for: Array[float] = [0.0, 0.0]

func _init(p_config: Config, p_roster: Roster, p_spawns: Spawns) -> void:
	config = p_config
	roster = p_roster
	spawns = p_spawns

# --- Lifecycle -------------------------------------------------------------

## Begins the countdown. Needs at least one connected player on each team.
func start() -> bool:
	if state != State.LOBBY or not roster.can_start():
		return false
	_clock = 0.0
	sudden_death = false
	winner = DRAW
	countdown_left = config.countdown_seconds
	time_left = config.time_limit_seconds()
	_empty_team_for = [0.0, 0.0]
	_lives.clear()
	_set_state(State.COUNTDOWN)
	for id in roster.peer_ids():
		_spawn(id, false)
	score_changed.emit(roster.team_kills[Roster.Team.RED], roster.team_kills[Roster.Team.BLUE])
	return true

## Back to the lobby with zeroed scores and swapped sides.
func rematch() -> bool:
	if state != State.ENDED:
		return false
	roster.reset_scores(true)
	_lives.clear()
	_set_state(State.LOBBY)
	score_changed.emit(0, 0)
	return true

## Adds a player. Joining mid-match is a normal respawn: own team's side, full health, protection.
func join(peer_id: int, nickname: String) -> Roster.Member:
	var member := roster.add_member(peer_id, nickname)
	if state == State.COUNTDOWN or state == State.LIVE:
		_spawn(peer_id, state == State.LIVE)
	return member

func peer_disconnected(peer_id: int) -> void:
	if not roster.has_member(peer_id):
		return
	roster.mark_disconnected(peer_id, _clock)
	var life := _life(peer_id)
	if life != null:
		life.ghost = true

## Restores a dropped player to their slot. Returns false for an unknown token or an expired slot.
func peer_reconnected(token: String, new_peer_id: int) -> bool:
	var old_id := roster.reconnect(token, new_peer_id)
	if old_id == 0:
		return false
	var life := _life(old_id)
	if life != null:
		_lives.erase(old_id)
		life.ghost = false
		_lives[new_peer_id] = life
	return true

# --- Per-frame update ------------------------------------------------------

func tick(delta: float) -> void:
	if state == State.LOBBY or state == State.ENDED:
		return
	_clock += delta
	_expire_ghosts()
	if state == State.COUNTDOWN:
		countdown_left -= delta
		if countdown_left <= 0.0:
			_begin_live()
		return
	_tick_players(delta)
	_check_forfeit(delta)
	if state != State.LIVE:
		return
	if sudden_death:
		sudden_death_left -= delta
		if sudden_death_left <= 0.0:
			_end(DRAW)
	else:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_on_time_up()

# --- Events from the network layer -----------------------------------------

## Last position the player reported (the host only trusts it for the boundary and spawn choice).
func report_position(peer_id: int, position: Vector3) -> void:
	var life := _life(peer_id)
	if life != null:
		life.position = position

## True if the player may fire now. Firing ends spawn protection. `min_interval` is the rifle's own
## limit (weapon_catalog.gd); without it the config's M416 limit applies.
func try_fire(peer_id: int, min_interval := -1.0) -> bool:
	var life := _life(peer_id)
	if state != State.LIVE or life == null or not life.alive or life.ghost:
		return false
	if _clock - life.last_shot_at < (min_interval if min_interval > 0.0 else config.min_shot_interval):
		return false
	life.last_shot_at = _clock
	life.protected_for = 0.0
	return true

## Validates and applies one claimed hit. Returns {accepted, reason, killed, damage}.
func apply_hit(shooter_id: int, victim_id: int, damage: float, headshot := false) -> Dictionary:
	var rejected := _check_hit(shooter_id, victim_id, damage)
	if rejected != "":
		return {"accepted": false, "reason": rejected, "killed": false, "damage": 0.0}
	var shooter := _life(shooter_id)
	var victim := _life(victim_id)
	shooter.protected_for = 0.0
	victim.health = maxf(0.0, victim.health - damage)
	victim.last_damage_at = _clock
	victim.damage_log.append({"attacker": shooter_id, "amount": damage, "at": _clock})
	player_damaged.emit(victim_id, shooter_id, damage, headshot, victim.health)
	var killed := victim.health <= 0.0
	if killed:
		_kill(shooter_id, victim_id, headshot)
	return {"accepted": true, "reason": "", "killed": killed, "damage": damage}

## A fall, going below the world or staying out of bounds. Credits an enemy who hit them recently.
func environment_death(peer_id: int) -> void:
	var life := _life(peer_id)
	if state != State.LIVE or life == null or not life.alive:
		return
	var credited := _recent_attacker(life)
	if credited != NO_KILLER:
		_kill(credited, peer_id, false)
	else:
		_die_without_killer(peer_id)

# --- Queries ---------------------------------------------------------------

func is_alive(peer_id: int) -> bool:
	var life := _life(peer_id)
	return life != null and life.alive

func is_protected(peer_id: int) -> bool:
	var life := _life(peer_id)
	return life != null and life.alive and life.protected_for > 0.0

func health_of(peer_id: int) -> float:
	var life := _life(peer_id)
	return life.health if life != null else 0.0

func position_of(peer_id: int) -> Vector3:
	var life := _life(peer_id)
	return life.position if life != null else Vector3.ZERO

func respawn_remaining(peer_id: int) -> float:
	var life := _life(peer_id)
	return life.respawn_in if life != null and not life.alive else 0.0

# --- Internals -------------------------------------------------------------

func _life(peer_id: int) -> Life:
	return _lives.get(peer_id) as Life

func _set_state(value: State) -> void:
	state = value
	state_changed.emit(int(value))

func _begin_live() -> void:
	for life: Life in _lives.values():
		if life.alive:
			life.protected_for = config.spawn_protection_seconds
	_set_state(State.LIVE)

## Empty string if the hit stands, otherwise the reason it was rejected.
func _check_hit(shooter_id: int, victim_id: int, damage: float) -> String:
	if state != State.LIVE:
		return "not_live"
	var shooter := _life(shooter_id)
	var victim := _life(victim_id)
	if shooter == null or victim == null or not roster.has_member(shooter_id) or not roster.has_member(victim_id):
		return "unknown_player"
	if shooter_id == victim_id:
		return "self_hit"
	if not shooter.alive or shooter.ghost:
		return "shooter_dead"
	if not victim.alive:
		return "victim_dead"
	if victim.ghost:
		return "victim_untargetable"
	if roster.member(shooter_id).team == roster.member(victim_id).team:
		return "friendly_fire"
	if victim.protected_for > 0.0:
		return "victim_protected"
	if damage <= 0.0 or damage > config.max_hit_damage:
		return "bad_damage"
	return ""

func _tick_players(delta: float) -> void:
	for peer_id: int in _lives.keys():
		var life := _life(peer_id)
		if life.ghost:
			continue
		if life.alive:
			life.protected_for = maxf(0.0, life.protected_for - delta)
			if life.health < config.max_health and _clock - life.last_damage_at >= config.regen_delay_seconds:
				life.health = minf(config.max_health, life.health + config.regen_per_second * delta)
			_tick_boundary(peer_id, life, delta)
		else:
			life.respawn_in -= delta
			if life.respawn_in <= 0.0:
				_spawn(peer_id, true)

## Leaving the ring starts a countdown; protected players and a live ring-return reset it.
func _tick_boundary(peer_id: int, life: Life, delta: float) -> void:
	var flat := Vector2(life.position.x - config.arena_center.x, life.position.z - config.arena_center.z)
	if flat.length() <= config.arena_radius or life.protected_for > 0.0:
		life.out_of_bounds_for = 0.0
		return
	life.out_of_bounds_for += delta
	if life.out_of_bounds_for >= config.out_of_bounds_seconds:
		life.out_of_bounds_for = 0.0
		environment_death(peer_id)

func _spawn(peer_id: int, protect: bool) -> void:
	var member := roster.member(peer_id)
	if member == null:
		return
	var life := _life(peer_id)
	if life == null:
		life = Life.new()
		_lives[peer_id] = life
	var enemies := PackedVector3Array()
	var occupied := PackedVector3Array()
	for other_id: int in _lives:
		var other := _life(other_id)
		if other_id == peer_id or not other.alive:
			continue
		occupied.append(other.position)
		if roster.member(other_id).team != member.team:
			enemies.append(other.position)
	life.alive = true
	life.health = config.max_health
	life.position = spawns.pick(member.team, enemies, occupied)
	life.protected_for = config.spawn_protection_seconds if protect else 0.0
	life.respawn_in = 0.0
	life.out_of_bounds_for = 0.0
	life.last_damage_at = -1000.0
	life.damage_log.clear()
	player_spawned.emit(peer_id, life.position)

func _kill(killer_id: int, victim_id: int, headshot: bool) -> void:
	var victim := _life(victim_id)
	var assists := _assisters(victim, killer_id)
	_mark_dead(victim)
	roster.record_kill(killer_id, victim_id, assists)
	player_killed.emit(killer_id, victim_id, headshot, assists)
	score_changed.emit(roster.team_kills[Roster.Team.RED], roster.team_kills[Roster.Team.BLUE])
	var killer_team := roster.member(killer_id).team
	if sudden_death or roster.team_kills[killer_team] >= config.kill_limit():
		_end(killer_team)

func _die_without_killer(victim_id: int) -> void:
	_mark_dead(_life(victim_id))
	roster.record_death(victim_id)
	var none: Array[int] = []
	player_killed.emit(NO_KILLER, victim_id, false, none)

func _mark_dead(life: Life) -> void:
	life.alive = false
	life.health = 0.0
	life.protected_for = 0.0
	life.respawn_in = config.respawn_seconds
	life.out_of_bounds_for = 0.0

## Players (other than the killer) who dealt enough damage to the victim inside the assist window.
func _assisters(victim: Life, killer_id: int) -> Array[int]:
	var totals: Dictionary = {}
	for entry: Dictionary in victim.damage_log:
		if _clock - float(entry.at) <= config.assist_window_seconds and int(entry.attacker) != killer_id:
			totals[entry.attacker] = float(totals.get(entry.attacker, 0.0)) + float(entry.amount)
	var result: Array[int] = []
	for attacker_id: int in totals:
		if float(totals[attacker_id]) >= config.assist_damage and roster.has_member(attacker_id):
			result.append(attacker_id)
	return result

func _recent_attacker(victim: Life) -> int:
	for index in range(victim.damage_log.size() - 1, -1, -1):
		var entry := victim.damage_log[index]
		if _clock - float(entry.at) <= config.suicide_credit_window_seconds and roster.has_member(int(entry.attacker)):
			return int(entry.attacker)
	return NO_KILLER

func _on_time_up() -> void:
	var leader := roster.leading_team()
	if leader == Roster.NO_TEAM:
		sudden_death = true
		sudden_death_left = config.sudden_death_seconds
		sudden_death_started.emit()
	else:
		_end(leader)

func _end(result: int) -> void:
	if state == State.ENDED:
		return
	winner = result
	_set_state(State.ENDED)
	match_ended.emit(result)

func _expire_ghosts() -> void:
	for id in roster.expire_disconnected(_clock, config.reconnect_hold_seconds):
		_lives.erase(id)

## A team with nobody connected for forfeit_seconds loses.
func _check_forfeit(delta: float) -> void:
	for team in [Roster.Team.RED, Roster.Team.BLUE]:
		if roster.connected_count(team) == 0:
			_empty_team_for[team] += delta
			if _empty_team_for[team] >= config.forfeit_seconds:
				_end(Roster.other_team(team))
				return
		else:
			_empty_team_for[team] = 0.0
