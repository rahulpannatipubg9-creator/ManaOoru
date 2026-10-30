extends SceneTree

## The Team Deathmatch screen inside the real game: damage arcs point the right way, the cursor is there
## whenever a panel needs it, the match menu works and blocks firing, nothing stale survives the end of a
## match, buttons stay on screen, and a stale report cannot strand a respawned player's position.
## Run: godot --headless --path . --script tests/tdm_hud_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Hud := preload("res://scripts/tactical/tdm_hud.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const NetworkPlayer := preload("res://scripts/network/network_player.gd")

var failures := 0
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func _until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await physics_frame

func run() -> void:
	# Facing north (-Z): screen angle -90 degrees is the top of the ring.
	var north := Vector2(0, -1)
	check(absf(Hud.arc_angle(north, Vector2(0, -5)) + PI * 0.5) < 0.01, "an attacker ahead is drawn at the top")
	check(absf(Hud.arc_angle(north, Vector2(5, 0))) < 0.01, "an attacker on the right is drawn on the right")
	check(absf(absf(Hud.arc_angle(north, Vector2(-5, 0))) - PI) < 0.01, "an attacker on the left is drawn on the left")
	check(absf(absf(Hud.arc_angle(north, Vector2(0, 5)) + PI * 0.5) - PI) < 0.01 or absf(Hud.arc_angle(north, Vector2(0, 5)) - PI * 0.5) < 0.01,
		"an attacker behind is drawn at the bottom")

	var rows := [{"peer_id": 1, "nickname": "A", "team": 1, "kills": 9, "deaths": 0, "assists": 0},
		{"peer_id": 2, "nickname": "B", "team": 0, "kills": 1, "deaths": 0, "assists": 0},
		{"peer_id": 3, "nickname": "C", "team": 0, "kills": 5, "deaths": 0, "assists": 0}]
	var order: Array = Hud.board_order(rows).map(func(row: Dictionary) -> String: return row.nickname)
	check(order == ["C", "B", "A"], "the scoreboard sorts by team, then kills (%s)" % [order])

	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(30)
	var local: Node = game.tdm_local
	var session: Node = game.tdm_session
	var hud: Node = local.hud
	var person: CharacterBody3D = game.person
	var config := Config.new()
	config.countdown_seconds = 0.5
	config.spawn_protection_seconds = 0.2
	check(not local.needs_cursor(), "free roam never asks for the cursor")
	check(game.network_manager.host_game(17879, "Tester") == OK, "the room opens")
	local.host_match(config, "Tester")
	await frames(20)

	# Nothing from free roam sits on the match screen.
	var entry: Node = game.hud.settings_menu.get_child(0)
	check(entry is Button and not entry.visible, "the desktop SETTINGS button is hidden in a match")
	game.city_life.toast("Action mode enabled")
	await process_frame
	await process_frame
	check(not game.city_life.get("_toast").visible, "free-roam toasts stay off the match screen")

	# Lobby
	check(local.needs_cursor(), "the lobby needs the cursor")
	check(hud._lobby_panel.visible, "the lobby shows")
	check(hud._lobby_buttons.start.disabled and hud._lobby_buttons.hint.visible, "a disabled START says why")
	check(not hud._status_box.visible and not hud._score_box.visible, "no match status behind the lobby")
	local.toggle_menu()
	check(hud.menu_open() and not hud._lobby_panel.visible, "Esc in the lobby opens the menu in place of the panel")
	local.toggle_menu()
	check(not hud.menu_open() and hud._lobby_panel.visible, "Esc again brings the lobby back")

	# Practice can always be left
	local.start_practice()
	await frames(5)
	check(not local.needs_cursor(), "practice captures the cursor")
	local.toggle_menu()
	check(local.needs_cursor() and hud._menu_back.visible, "the practice menu has a way back to the lobby")
	check(not local.can_fire(), "no firing behind the menu")
	hud._menu_back.pressed.emit()
	await frames(2)
	check(not local.practicing and not hud.menu_open() and hud._lobby_panel.visible, "BACK TO LOBBY leaves practice")

	# Live match
	session.rules.join(2, "Guest")
	session._publish_roster()
	await frames(2)
	check(not hud._lobby_buttons.start.disabled, "START works with both teams")
	check(session.host_start(), "the match starts")
	await _until(func() -> bool: return session.state == Match.State.LIVE, 4.0)
	await frames(5)
	check(hud._banner.visible and hud._banner.text == "GO!", "GO! is shown when the match goes live")
	check(not local.needs_cursor(), "a live match captures the cursor")
	check(hud._status_box.visible and hud._ammo_label.text.contains("30 / 30"), "the player sees rifle and ammo (%s)" % hud._ammo_label.text)
	check(hud._score_box.visible and not hud._goal_label.visible, "the score bar is one line outside sudden death")
	for button: Button in [hud._menu_button, hud._scoreboard_button, hud._chat_button]:
		check(not button.visible, "desktop shows no %s button" % button.text)
	local.toggle_menu()
	check(hud.menu_open() and local.needs_cursor() and not local.can_fire(), "the menu takes the cursor and stops firing")
	local.toggle_menu()
	hud.toggle_chat()
	check(local.needs_cursor() and not local.can_fire(), "the chat wheel takes the cursor")
	local.toggle_menu()
	check(not hud.overlay_open(), "Esc closes the chat wheel first, not the match")

	# Touch: small buttons, all on screen, none overlapping
	hud.touch_mode = true
	hud.refresh()
	await process_frame
	var screen := Rect2(Vector2.ZERO, hud._root.size)
	var taken: Array[Rect2] = []
	for button: Button in [hud._menu_button, hud._scoreboard_button, hud._chat_button]:
		check(button.visible, "touch shows %s" % button.text)
		var rect: Rect2 = button.get_rect()
		check(screen.encloses(rect), "%s is fully on screen (%s in %s)" % [button.text, rect, screen])
		for other in taken:
			check(not rect.intersects(other), "%s overlaps nothing" % button.text)
		taken.append(rect)
	hud.touch_mode = false
	hud.refresh()

	# Teammates are obvious; enemies show nothing.
	session.rules.join(3, "Mate")
	session._publish_roster()
	await frames(2)
	var mate: Node3D = NetworkPlayer.new()
	mate.peer_id = 3
	mate.network_manager = game.network_manager
	mate.position = person.global_position + Vector3(4, 0, 0)
	game.add_child(mate)
	game.network_manager.puppets[3] = mate
	var enemy: Node3D = NetworkPlayer.new()
	enemy.peer_id = 2
	enemy.position = person.global_position + Vector3(-4, 0, 0)
	game.add_child(enemy)
	game.network_manager.puppets[2] = enemy
	session.vitals[3] = {"hp": 50.0, "protected": false, "alive": true}
	session.vitals[2] = {"hp": 100.0, "protected": false, "alive": true}
	local._refresh_puppets()
	await process_frame
	await process_frame
	check(mate._armband != null and enemy._armband != null, "both sides wear an armband")
	check(mate._overhead_label.visible and mate._overhead_label.text == "Mate", "a teammate shows their name")
	check(mate._overhead_label.no_depth_test and mate._tdm_health != null and mate._tdm_health.visible and mate._tdm_health.no_depth_test, "a teammate's marker shows through walls")
	check(mate._tdm_health.text.length() == 10, "the marker shows half health (%d ticks)" % mate._tdm_health.text.length())
	check(not enemy._overhead_label.visible and enemy._tdm_health == null, "an enemy shows no name or marker")
	var near_alpha: float = mate._tdm_marker_alpha
	mate.tdm_update_marker(mate.global_position + Vector3(300, 0, 0), 1.0)
	check(mate._tdm_marker_alpha < near_alpha and mate._tdm_marker_alpha >= mate.TDM_MARKER_MIN_ALPHA, "the marker fades with distance but stays findable")
	var rings: Array = local._minimap_markers().filter(func(marker: Array) -> bool: return marker[1] == local.MINIMAP_ALLY_RING)
	check(rings.size() == 1, "the ally dot has a ring on the minimap")
	var shots_before: float = session.rules._lives[1].last_shot_at
	mate.tdm_claim_hit(mate.global_position + Vector3.UP, person.global_position)
	check(session.rules._lives[1].last_shot_at == shots_before, "shooting a teammate sends no claim")
	var hits := {"count": 0}
	session.hit_confirmed.connect(func(_v: int, _h: bool, _k: bool) -> void: hits.count += 1)
	session.rules._lives[3].protected_for = 0.0
	session._handle_claim(1, 3, false, person.global_position, session.rules.position_of(3))
	check(hits.count == 0, "a forced friendly claim gets no hit confirmation")
	hud.set_teammate_tag(true)
	await process_frame
	check(hud._teammate_tag.visible, "the Teammate tag shows")
	check(hud._red_name.text.contains("YOU") and not hud._blue_name.text.contains("YOU"), "the score bar marks the player's team")
	game.network_manager.puppets.erase(2)
	game.network_manager.puppets.erase(3)
	enemy.queue_free()
	mate.queue_free()

	# Switching sides mid-match: Red has two players here, Blue one.
	session.rules.config.respawn_seconds = 0.3
	hud._menu_panel.visible = false
	hud.toggle_menu()
	check(hud._menu_switch.visible, "a live match offers SWITCH TEAM")
	hud._menu_switch.pressed.emit()
	await frames(2)
	check(not local._alive and hud._death_label.text.begins_with("Switching team"), "switching takes the player out and says so")
	check(session.team_of(1) == 1, "the host moved to Blue")
	await _until(func() -> bool: return local._alive, 2.0)
	check(local._alive and hud._message.text == "YOU ARE BLUE", "the respawn announces the new team")
	session.request_team(0)
	await frames(2)
	check(hud._message.text.contains("again in") and session.team_of(1) == 1, "a refused switch explains itself")
	session.rules._switched_at.clear()
	session.request_team(0)
	await _until(func() -> bool: return session.team_of(1) == 0 and local._alive, 2.0)
	check(session.team_of(1) == 0, "the cooldown over, the host goes back to Red")
	session.rules._lives[1].protected_for = 0.0
	session._positions[1] = person.global_position

	# Health shows on the screen, not just in a bar.
	session.rules._lives[1].last_damage_at = -1000.0
	session.rules.apply_hit(2, 1, 80.0, false)
	await frames(40)
	check(hud._wound.visible and hud._wound_strength > 0.3, "missing health reddens the screen edges")
	check(hud._heartbeat.playing, "the heartbeat runs at low health")

	# Connection trouble
	session._reconnect_left = 5.0
	check(session.reconnecting() and not local.can_fire(), "no firing while reconnecting")
	session._reconnect_left = 0.0

	# Position after a respawn: a report from before the teleport must not replace it.
	var spot := Vector3(40.0, 0.0, 40.0)
	session._on_rules_spawned(2, spot)
	session.on_peer_position(2, Vector3(-40.0, 0.0, -40.0))
	check(session._positions[2].is_equal_approx(spot), "a stale report after a respawn is ignored")
	session.on_peer_position(2, spot + Vector3(0.1, 0.0, 0.0))
	check(session._positions[2].distance_to(spot) < 0.2, "the first real report after a respawn is accepted")

	# A death, then the match ends: nothing stale remains.
	session.rules._lives[1].protected_for = 0.0
	session.rules.apply_hit(2, 1, 100.0, false)
	await process_frame
	await process_frame
	check(not hud._heartbeat.playing, "the heartbeat stops at death")
	check(hud._death_label.visible, "the death message shows")
	check(person.get_node("TestCharacter").is_dead(), "the character is dead")
	local._on_ping(2, 0, Vector3.ZERO)
	session.rules._end(1)
	await frames(3)
	check(not hud._death_label.visible and not hud._boundary_label.visible, "the end screen drops the death and boundary messages")
	check(hud._end_panel.visible and hud._end_title.text == "BLUE WINS", "the end screen shows the winner")
	check(hud._end_board.get_child_count() > 4, "the end board lists the players")
	check(local.needs_cursor(), "the end screen needs the cursor")

	session.host_rematch()
	await frames(3)
	check(session.state == Match.State.LOBBY and hud._lobby_panel.visible and not hud._end_panel.visible, "a rematch returns to the lobby")
	check(not person.get_node("TestCharacter").is_dead(), "a rematch stands the character up")

	# Street pickups stay out of the match.
	for pickup in get_nodes_in_group("weapon_pickups"):
		check(pickup.process_mode == Node.PROCESS_MODE_DISABLED, "street rifles are disabled in a match")
		break

	local._on_ping(2, 0, Vector3.ZERO)
	var ping: Node = local._pings[2].node
	local.leave_match()
	await frames(3)
	check(not local.in_match and not local.needs_cursor(), "leaving hands the cursor back")
	check(not is_instance_valid(ping) and local._pings.is_empty(), "pings do not outlive the match")
	check(not hud._root.visible, "the match HUD is gone")
	for pickup in get_nodes_in_group("weapon_pickups"):
		check(pickup.process_mode != Node.PROCESS_MODE_DISABLED, "street rifles return after the match")
		break

	print("TDM HUD regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
