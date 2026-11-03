extends SceneTree

## Host-side Team Deathmatch rules (scripts/tactical). Pure logic: no scene, no network.
## Run: godot --headless --path . --script tests/tdm_match_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Roster := preload("res://scripts/tactical/tdm_roster.gd")
const Spawns := preload("res://scripts/tactical/tdm_spawns.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")

const RED := Roster.Team.RED
const BLUE := Roster.Team.BLUE

var _failures := 0
var _checks := 0

func _init() -> void:
	_test_config()
	_test_roster_balance_and_swap()
	_test_spawn_choice()
	_test_countdown_and_protection()
	_test_hit_validation()
	_test_kill_score_and_assists()
	_test_respawn_and_regen()
	_test_win_by_kill_limit()
	_test_time_up_win_tie_and_sudden_death()
	_test_boundary()
	_test_environment_death_credit()
	_test_disconnect_reconnect_and_forfeit()
	_test_late_join_and_rematch()
	_test_team_changes()
	_test_regen_curve()
	print("TDM match regression: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)

# --- Helpers ---------------------------------------------------------------

## Peers 1..n join alternately Red, Blue, Red, Blue. Zones sit on opposite sides of the arena.
func _lobby(player_count: int, config: Config = null) -> Dictionary:
	var cfg := config if config != null else Config.new()
	var roster := Roster.new()
	var spawns := Spawns.new()
	spawns.set_zones(RED, PackedVector3Array([Vector3(-60, 0, -55), Vector3(-70, 0, -40), Vector3(-45, 0, -65)]))
	spawns.set_zones(BLUE, PackedVector3Array([Vector3(60, 0, 55), Vector3(70, 0, 40), Vector3(45, 0, 65)]))
	var match_rules := Match.new(cfg, roster, spawns)
	for id in range(1, player_count + 1):
		match_rules.join(id, "P%d" % id)
	return {"config": cfg, "roster": roster, "spawns": spawns, "match": match_rules}

## Starts the match and runs past the countdown and the opening spawn protection.
func _live(player_count: int, config: Config = null) -> Dictionary:
	var lobby := _lobby(player_count, config)
	var match_rules: Match = lobby.match
	match_rules.start()
	match_rules.tick(match_rules.config.countdown_seconds)
	match_rules.tick(match_rules.config.spawn_protection_seconds + 0.1)
	return lobby

func _kill_with(match_rules: Match, shooter: int, victim: int) -> void:
	for _i in 4:
		if not match_rules.is_alive(victim):
			return
		match_rules.apply_hit(shooter, victim, 34.0)

# --- Tests -----------------------------------------------------------------

func _test_team_changes() -> void:
	var even := _lobby(2)
	var even_rules: Match = even.match
	check(even_rules.change_team(1, BLUE).contains("uneven"), "a 1v1 refuses a swap and says why")
	check(even.roster.member(1).team == RED, "the refused player stays put")
	check(even_rules.change_team(1, RED) == "", "joining your own team is not an error")

	var lobby := _lobby(3)
	var rules: Match = lobby.match
	check(rules.change_team(3, BLUE) == "", "2v1 lets a player even up in the lobby")
	check(lobby.roster.member(3).team == BLUE, "the player moved to Blue")
	check(rules.change_team(1, BLUE) != "", "the last Red player cannot leave a 1v2")

	var live := _live(3)
	rules = live.match
	var switched := {"count": 0, "seconds": 0.0}
	rules.team_switched.connect(func(_id: int, seconds: float) -> void:
		switched.count += 1
		switched.seconds = seconds)
	var deaths_before: int = live.roster.member(3).deaths
	rules.apply_hit(2, 3, 20.0)
	check(rules.change_team(3, BLUE) == "", "a live switch is allowed when it keeps teams balanced")
	check(switched.count == 1 and switched.seconds == rules.config.respawn_seconds, "a live switch costs the normal respawn")
	check(not rules.is_alive(3) and live.roster.member(3).team == BLUE, "the player leaves the field for the new side")
	check(live.roster.member(3).deaths == deaths_before and live.roster.team_kills == [0, 0], "a switch keeps K/D and gives nobody a kill")
	rules.tick(rules.config.respawn_seconds + 0.1)
	check(rules.is_alive(3) and rules.health_of(3) == rules.config.max_health, "the player respawns at full health")
	check(rules.position_of(3).x > 0.0, "the respawn is on the new team's side")
	check(rules.change_team(3, RED).contains("again in"), "a second switch waits for the cooldown")
	rules.tick(rules.config.team_switch_cooldown_seconds)
	check(rules.change_team(3, RED) == "", "the cooldown runs out")

	var countdown := _lobby(3)
	var counting: Match = countdown.match
	counting.start()
	check(counting.change_team(3, BLUE).contains("locked"), "teams are locked during the countdown")

func _test_regen_curve() -> void:
	var live := _live(2)
	var rules: Match = live.match
	rules.apply_hit(1, 2, 100.0 - 1.0)
	rules.tick(rules.config.regen_delay_seconds - 0.05)
	var seconds := 0.0
	var first_second := 0.0
	while rules.health_of(2) < rules.config.max_health and seconds < 30.0:
		rules.tick(0.05)
		seconds += 0.05
		if is_equal_approx(seconds, 1.05):
			first_second = rules.health_of(2) - 1.0
	check(first_second < rules.config.regen_per_second * 0.5, "regeneration eases in (%.1f in the first second)" % first_second)
	check(seconds > 9.0 and seconds < 11.0, "a full refill takes about 10 s (%.1f)" % seconds)

func _test_config() -> void:
	var cfg := Config.new()
	check(cfg.kill_limit() == 40 and cfg.time_limit_seconds() == 600.0, "defaults are 40 kills / 10 minutes")
	cfg.kill_limit_choice = 0
	cfg.time_limit_choice = 2
	check(cfg.kill_limit() == 20 and cfg.time_limit_seconds() == 900.0, "lobby choices map to 20 kills / 15 minutes")

func _test_roster_balance_and_swap() -> void:
	var roster := Roster.new()
	for id in 4:
		roster.add_member(id + 1, "Same")
	check(roster.team_count(RED) == 2 and roster.team_count(BLUE) == 2, "four players split 2v2")
	check(roster.member(2).nickname == "Same 2" and roster.member(3).nickname == "Same 3", "duplicate names are suffixed")
	check(not roster.can_swap(1), "an even split allows no player swap")
	roster.add_member(5, "Late")
	check(roster.team_count(RED) == 3, "an odd player joins the team with fewer kills (Red on a tie)")
	check(roster.can_swap(1) and not roster.can_swap(2), "only the bigger team may swap, and only into balance")
	check(roster.swap_team(1) and roster.team_count(RED) == 2 and roster.team_count(BLUE) == 3, "an allowed swap moves the player")
	check(not roster.swap_team(3), "a swap out of the smaller team is refused")
	check(roster.swap_team(1, true), "the host may move anyone")
	check(roster.can_start(), "both teams populated can start")
	check(not Roster.new().can_start(), "an empty roster cannot start")

func _test_spawn_choice() -> void:
	var spawns := Spawns.new()
	spawns.set_zones(RED, PackedVector3Array([Vector3(-60, 0, 0), Vector3(-20, 0, 0)]))
	var enemy := PackedVector3Array([Vector3(0, 0, 0)])
	check(spawns.pick(RED, enemy, PackedVector3Array()) == Vector3(-60, 0, 0), "farthest zone from the enemy wins")
	spawns.enemy_line_of_sight = func(point: Vector3, _enemies: PackedVector3Array) -> bool: return point.x < -50.0
	check(spawns.pick(RED, enemy, PackedVector3Array()) == Vector3(-20, 0, 0), "a zone an enemy can see is avoided")
	spawns.enemy_line_of_sight = func(_point: Vector3, _enemies: PackedVector3Array) -> bool: return true
	check(spawns.pick(RED, enemy, PackedVector3Array()) == Vector3(-60, 0, 0), "if every zone is seen it still spawns, farthest first")
	spawns.enemy_line_of_sight = Callable()
	check(spawns.pick(RED, enemy, PackedVector3Array([Vector3(-60, 0, 0)])) == Vector3(-20, 0, 0), "an occupied zone is skipped")
	check(spawns.pick(RED, enemy, PackedVector3Array([Vector3(-60, 0, 0), Vector3(-20, 0, 0)])) == Vector3(-60, 0, 0), "all occupied still spawns")
	check(spawns.pick(RED, PackedVector3Array(), PackedVector3Array()) == Vector3(-60, 0, 0), "no enemies picks deterministically")
	check(Spawns.new().pick(BLUE, enemy, PackedVector3Array()) == Vector3.ZERO, "no zones returns the origin instead of crashing")

func _test_countdown_and_protection() -> void:
	var lobby := _lobby(4)
	var m: Match = lobby.match
	check(not Match.new(Config.new(), Roster.new(), Spawns.new()).start(), "cannot start with nobody")
	var spawned := {"count": 0}
	m.player_spawned.connect(func(_id: int, _p: Vector3) -> void: spawned.count += 1)
	check(m.start(), "starts with players on both teams")
	check(m.state == Match.State.COUNTDOWN and spawned.count == 4, "countdown spawns everyone")
	check(not m.start(), "cannot start twice")
	check(not m.apply_hit(1, 2, 30.0).accepted, "no damage during the countdown")
	check(not m.try_fire(1), "weapons are disabled during the countdown")
	m.tick(m.config.countdown_seconds - 0.1)
	check(m.state == Match.State.COUNTDOWN, "still counting down")
	m.tick(0.2)
	check(m.state == Match.State.LIVE, "countdown ends in the live state")
	check(m.is_protected(2), "everyone starts protected")
	var blocked := m.apply_hit(1, 2, 30.0)
	check(not blocked.accepted and blocked.reason == "victim_protected", "a protected player cannot be hurt")
	check(m.try_fire(2) and not m.is_protected(2), "firing ends the shooter's protection")
	check(not m.try_fire(2), "a second shot inside the minimum interval is refused")
	m.tick(m.config.min_shot_interval + 0.01)
	check(m.try_fire(2), "the next shot after the interval is allowed")
	m.tick(m.config.spawn_protection_seconds)
	check(not m.is_protected(1), "protection expires on its own")

func _test_hit_validation() -> void:
	var lobby := _live(4)
	var m: Match = lobby.match
	check(m.apply_hit(1, 2, 30.0).accepted, "an enemy hit is accepted")
	check(m.health_of(2) == 70.0, "health drops by the damage")
	check(m.apply_hit(1, 3, 30.0).reason == "friendly_fire", "friendly fire is rejected")
	check(m.apply_hit(1, 1, 30.0).reason == "self_hit", "hitting yourself is rejected")
	check(m.apply_hit(1, 99, 30.0).reason == "unknown_player", "an unknown peer is rejected")
	check(m.apply_hit(1, 4, 0.0).reason == "bad_damage", "zero damage is rejected")
	check(m.apply_hit(1, 4, 500.0).reason == "bad_damage", "damage above the cap is rejected")
	check(m.health_of(4) == 100.0, "rejected hits change nothing")
	_kill_with(m, 1, 2)
	check(m.apply_hit(1, 2, 30.0).reason == "victim_dead", "a dead player cannot be hit")
	check(m.apply_hit(2, 1, 30.0).reason == "shooter_dead", "a dead player cannot shoot")
	check(not m.try_fire(2), "a dead player cannot fire")

func _test_kill_score_and_assists() -> void:
	var lobby := _live(4)
	var m: Match = lobby.match
	var roster: Roster = lobby.roster
	var events := {"kills": [], "scores": []}
	m.player_killed.connect(func(k: int, v: int, hs: bool, a: Array[int]) -> void: events.kills.append([k, v, hs, a]))
	m.score_changed.connect(func(r: int, b: int) -> void: events.scores.append([r, b]))
	# Peers 1 and 3 are Red, 2 and 4 are Blue. 3 wounds 2 for 40, then 1 finishes it.
	m.apply_hit(3, 2, 40.0)
	m.apply_hit(1, 2, 34.0)
	var result := m.apply_hit(1, 2, 34.0)
	check(result.killed and not m.is_alive(2), "the third hit kills")
	check(roster.member(1).kills == 1 and roster.member(2).deaths == 1, "killer and victim are scored")
	check(roster.member(3).assists == 1 and roster.member(1).assists == 0, "40 damage earns an assist, the killer gets none")
	check(roster.team_kills[RED] == 1 and roster.team_kills[BLUE] == 0, "the team score counts the kill")
	check(events.kills.size() == 1 and events.kills[0][0] == 1 and events.kills[0][1] == 2 and events.kills[0][3] == [3], "the kill event carries the assist list")
	check(events.scores.back() == [1, 0], "score_changed reports the new totals")
	var headshot_lobby := _live(2)
	var hm: Match = headshot_lobby.match
	var headshots := {"seen": false}
	hm.player_killed.connect(func(_k: int, _v: int, hs: bool, _a: Array[int]) -> void: headshots.seen = hs)
	hm.apply_hit(1, 2, 60.0, true)
	hm.apply_hit(1, 2, 60.0, true)
	check(headshots.seen, "the headshot flag reaches the kill event")
	# 10 damage is below the assist threshold.
	var small := _live(4)
	var sm: Match = small.match
	sm.apply_hit(3, 2, 10.0)
	_kill_with(sm, 1, 2)
	check(small.roster.member(3).assists == 0, "damage under the threshold is not an assist")

func _test_respawn_and_regen() -> void:
	var lobby := _live(2)
	var m: Match = lobby.match
	var cfg: Config = lobby.config
	var spawned := {"count": 0}
	_kill_with(m, 1, 2)
	m.player_spawned.connect(func(_id: int, _p: Vector3) -> void: spawned.count += 1)
	m.tick(cfg.respawn_seconds - 0.2)
	check(not m.is_alive(2) and m.respawn_remaining(2) > 0.0, "still dead inside the respawn delay")
	m.tick(0.3)
	check(m.is_alive(2) and m.health_of(2) == cfg.max_health and spawned.count == 1, "respawns at full health")
	check(m.is_protected(2), "a respawn comes with spawn protection")
	check(m.position_of(2).x > 0.0, "a Blue respawn is on Blue's side")
	m.tick(cfg.spawn_protection_seconds)
	m.apply_hit(1, 2, 50.0)
	m.tick(cfg.regen_delay_seconds - 0.5)
	check(m.health_of(2) == 50.0, "no regeneration before the delay")
	m.tick(1.5)
	check(m.health_of(2) > 50.0, "health regenerates after the delay")
	m.tick(20.0)
	check(m.health_of(2) == cfg.max_health, "regeneration stops at full health")
	m.apply_hit(1, 2, 30.0)
	m.tick(cfg.regen_delay_seconds - 0.5)
	m.apply_hit(1, 2, 10.0)
	m.tick(cfg.regen_delay_seconds - 0.5)
	check(m.health_of(2) == 60.0, "a new hit restarts the regeneration delay")

func _test_win_by_kill_limit() -> void:
	var cfg := Config.new()
	cfg.kill_limit_choice = 0
	var lobby := _live(2, cfg)
	var m: Match = lobby.match
	var result := {"winner": -2}
	m.match_ended.connect(func(w: int) -> void: result.winner = w)
	for _i in 19:
		_kill_with(m, 1, 2)
		m.tick(cfg.respawn_seconds + 0.1)
		m.tick(cfg.spawn_protection_seconds + 0.1)
	check(m.state == Match.State.LIVE and result.winner == -2, "one kill short does not end the match")
	_kill_with(m, 1, 2)
	check(m.state == Match.State.ENDED and result.winner == RED and m.winner == RED, "the 20th kill wins the match")
	check(lobby.roster.team_kills[RED] == 20, "the final score is 20")
	m.tick(cfg.respawn_seconds + 1.0)
	check(m.apply_hit(2, 1, 30.0).reason == "not_live", "no hits count after the match ends")
	check(lobby.roster.team_kills[RED] == 20 and lobby.roster.team_kills[BLUE] == 0, "the score is frozen after the end")

func _test_time_up_win_tie_and_sudden_death() -> void:
	var cfg := Config.new()
	var lobby := _live(2, cfg)
	var m: Match = lobby.match
	_kill_with(m, 2, 1)
	m.tick(cfg.time_limit_seconds())
	check(m.state == Match.State.ENDED and m.winner == BLUE, "the leader wins when time is up")
	var tie := _live(2, cfg)
	var tm: Match = tie.match
	var sudden := {"started": false}
	tm.sudden_death_started.connect(func() -> void: sudden.started = true)
	tm.tick(cfg.time_limit_seconds())
	check(tm.state == Match.State.LIVE and tm.sudden_death and sudden.started, "a tie at the timer starts sudden death")
	tm.tick(10.0)
	_kill_with(tm, 1, 2)
	check(tm.state == Match.State.ENDED and tm.winner == RED, "the next kill wins sudden death")
	var draw := _live(2, cfg)
	var dm: Match = draw.match
	dm.tick(cfg.time_limit_seconds())
	dm.tick(cfg.sudden_death_seconds + 0.1)
	check(dm.state == Match.State.ENDED and dm.winner == Match.DRAW, "no kill in sudden death is a draw")

func _test_boundary() -> void:
	var cfg := Config.new()
	var lobby := _live(2, cfg)
	var m: Match = lobby.match
	m.report_position(2, Vector3(cfg.arena_radius + 5.0, 0.0, 0.0))
	m.tick(cfg.out_of_bounds_seconds - 0.5)
	check(m.is_alive(2), "alive inside the out-of-bounds warning")
	m.report_position(2, Vector3(10.0, 0.0, 10.0))
	m.tick(1.0)
	m.report_position(2, Vector3(cfg.arena_radius + 5.0, 0.0, 0.0))
	m.tick(cfg.out_of_bounds_seconds - 0.5)
	check(m.is_alive(2), "returning inside resets the countdown")
	m.tick(1.0)
	check(not m.is_alive(2), "five seconds outside is a death")
	check(lobby.roster.member(2).deaths == 1 and lobby.roster.team_kills[RED] == 0, "a boundary death scores no kill")
	var protected_lobby := _lobby(2, cfg)
	var pm: Match = protected_lobby.match
	pm.start()
	pm.tick(cfg.countdown_seconds)
	pm.report_position(2, Vector3(cfg.arena_radius + 5.0, 0.0, 0.0))
	pm.tick(cfg.out_of_bounds_seconds - 0.5)
	check(pm.is_alive(2), "the boundary does not run on a protected player")

func _test_environment_death_credit() -> void:
	var lobby := _live(2)
	var m: Match = lobby.match
	m.apply_hit(1, 2, 20.0)
	m.tick(1.0)
	m.environment_death(2)
	check(lobby.roster.member(1).kills == 1 and lobby.roster.team_kills[RED] == 1, "a fall just after an enemy hit credits that enemy")
	var cold := _live(2)
	var cm: Match = cold.match
	cm.apply_hit(1, 2, 20.0)
	cm.tick(cold.config.suicide_credit_window_seconds + 1.0)
	cm.environment_death(2)
	check(cold.roster.member(1).kills == 0 and cold.roster.member(2).deaths == 1, "an old hit gets no credit")

func _test_disconnect_reconnect_and_forfeit() -> void:
	var cfg := Config.new()
	var lobby := _live(4, cfg)
	var m: Match = lobby.match
	var roster: Roster = lobby.roster
	_kill_with(m, 1, 2)
	var token: String = roster.member(1).token
	m.peer_disconnected(1)
	check(m.apply_hit(4, 1, 30.0).reason == "victim_untargetable", "a dropped player is an untargetable ghost")
	check(roster.team_count(RED) == 2, "the slot is still held")
	check(not m.peer_reconnected("wrong", 11), "an unknown token cannot reconnect")
	check(m.peer_reconnected(token, 11), "the right token restores the slot")
	check(roster.member(11).kills == 1 and roster.member(11).team == RED and m.is_alive(11), "team, score and life carry over")
	check(not roster.has_member(1), "the old peer id is gone")
	m.peer_disconnected(11)
	m.tick(cfg.reconnect_hold_seconds + 0.1)
	check(not roster.has_member(11) and roster.team_kills[RED] == 1, "an expired slot is freed but the team keeps the kills")
	check(not m.peer_reconnected(token, 12), "an expired token no longer works")
	# Forfeit: Blue drops out entirely.
	var forfeit := _live(2, cfg)
	var fm: Match = forfeit.match
	fm.peer_disconnected(2)
	fm.tick(cfg.forfeit_seconds - 1.0)
	check(fm.state == Match.State.LIVE, "an empty team is given time to come back")
	fm.tick(2.0)
	check(fm.state == Match.State.ENDED and fm.winner == RED, "a team with nobody for 30 s forfeits")

func _test_late_join_and_rematch() -> void:
	var cfg := Config.new()
	var lobby := _live(3, cfg)
	var m: Match = lobby.match
	var roster: Roster = lobby.roster
	_kill_with(m, 1, 2)
	var joined := m.join(7, "Late")
	check(joined.team == BLUE, "a late joiner takes the smaller team")
	check(m.is_alive(7) and m.is_protected(7), "a late joiner spawns protected")
	m.tick(cfg.time_limit_seconds())
	check(m.state == Match.State.ENDED, "the match ends at the time limit")
	var red_before: int = roster.team_count(RED)
	var first_team: int = roster.member(1).team
	check(m.rematch() and m.state == Match.State.LOBBY, "a finished match returns to the lobby")
	check(roster.team_kills[RED] == 0 and roster.member(1).kills == 0, "a rematch zeroes the scores")
	check(roster.member(1).team == Roster.other_team(first_team) and roster.team_count(BLUE) == red_before, "a rematch swaps sides")
	check(not m.rematch(), "a rematch needs a finished match")
	check(m.start(), "the rematch can start")
