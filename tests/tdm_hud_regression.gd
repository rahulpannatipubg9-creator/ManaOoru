extends SceneTree

## The Team Deathmatch screen inside the real game: damage arcs point the right way, the cursor is there
## whenever a panel needs it, the match menu works and blocks firing, nothing stale survives the end of a
## match, buttons stay on screen, and a stale report cannot strand a respawned player's position.
## On phones and tablets: the match screens fit every landscape shape with nothing cut off or overlapping,
## panel buttons answer a finger, aim help is gentle, firing stops whenever the finger stops, and an empty
## magazine reloads by itself.
## Run: godot --headless --path . --script tests/tdm_hud_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Hud := preload("res://scripts/tactical/tdm_hud.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const NetworkPlayer := preload("res://scripts/network/network_player.gd")
const Local := preload("res://scripts/tactical/tdm_local.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const GunFeel := preload("res://scripts/gameplay/gun_feel.gd")

## The canvas each device shape gets from the project's 1280x720 "expand" stretch:
## phones at 2400x1080 and 1600x720, tablets at 2000x1200, 1280x800 and 1024x768.
const CANVASES: Array[Vector2i] = [Vector2i(1600, 720), Vector2i(1280, 768), Vector2i(1280, 800), Vector2i(1280, 960)]
## A long name, and the most players a room can hold.
const LONG_NAME := "Venkata Ramakrishn"
const FULL_TEAM := 8

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
	var ahead := Vector3(0, 0, -1)
	check(Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0.4, 0, -5)), "an enemy just off the crosshair is caught up close")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(2.0, 0, -5)), "an enemy well off the crosshair is not")
	check(Local.near_aim_line(Vector3.ZERO, ahead, Vector3(1.5, 0, -60)), "the catch widens a little with distance")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0, 0, 5)), "nobody behind the player is caught")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0, 0, -200)), "nobody past the assist range is caught")
	check(GunFeel.pool_size(32, true) == 16 and GunFeel.pool_size(32, false) == 32, "phones keep half of each effect pool")
	check(GunFeel.pool_size(5, true) == 3, "a small pool still keeps at least its rounded half")
	check(GunFeel.particle_count(10, true) == 6 and GunFeel.particle_count(10, false) == 10, "phones throw fewer particles")

	# Facing north (-Z): screen angle -90 degrees is the top of the ring.
	var north := Vector2(0, -1)
	check(absf(Hud.arc_angle(north, Vector2(0, -5)) + PI * 0.5) < 0.01, "an attacker ahead is drawn at the top")
	check(absf(Hud.arc_angle(north, Vector2(5, 0))) < 0.01, "an attacker on the right is drawn on the right")
	check(absf(absf(Hud.arc_angle(north, Vector2(-5, 0))) - PI) < 0.01, "an attacker on the left is drawn on the left")
	check(absf(absf(Hud.arc_angle(north, Vector2(0, 5)) + PI * 0.5) - PI) < 0.01 or absf(Hud.arc_angle(north, Vector2(0, 5)) - PI * 0.5) < 0.01,
		"an attacker behind is drawn at the bottom")

	check(Hud.streak_word(1) == "" and Hud.streak_word(2) == "DOUBLE" and Hud.streak_word(9) == "RAMPAGE", "only a run of kills gets a word, and long runs stay on the last one")
	check(Config.new().respawn_seconds <= 3.0, "respawns are quick")

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

	for canvas in CANVASES:
		await _check_layout(canvas)
	await _check_play(game)
	await _check_real_screen(game)

	print("TDM HUD regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _rows() -> Array:
	var rows: Array = []
	for index in FULL_TEAM * 2:
		rows.append({"peer_id": index + 1, "nickname": LONG_NAME, "team": index % 2, "kills": 22, "deaths": 19, "assists": 7,
			"connected": true, "ready": false})
	return rows

func _check_layout(canvas: Vector2i) -> void:
	var view := SubViewport.new()
	view.size = canvas
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var session: Node = Session.new()
	view.add_child(session)
	session.active = true
	session.config = Config.new()
	session.rows = _rows()
	session.state = Match.State.LIVE
	session.is_host = true
	var hud: Node = Hud.new()
	view.add_child(hud)
	hud.setup(session)
	var minimap := Rect2(canvas.x - 220.0, 16.0, 200.0, 200.0)
	hud.minimap_provider = func() -> Rect2: return minimap
	hud.status_floor_provider = func() -> float: return canvas.y - 110.0
	hud.touch_mode = true
	hud.refresh()
	for _i in 3:
		hud.add_kill(LONG_NAME, LONG_NAME, 0, true)
		hud.add_chat(LONG_NAME, "Hold position", 1)
	await frames(3)
	var bounds := Rect2(Vector2.ZERO, Vector2(canvas))
	var parts := {"score": hud._score_box, "menu": hud._menu_button, "board": hud._scoreboard_button, "chat": hud._chat_button,
		"feed": hud._feed, "chat log": hud._chat_log, "status": hud._status_box}
	var names: Array = parts.keys()
	for index in names.size():
		var rect: Rect2 = parts[names[index]].get_global_rect()
		check(bounds.encloses(rect), "%s: %s is on screen (%s)" % [canvas, names[index], rect])
		check(not rect.intersects(minimap), "%s: %s clears the minimap (%s)" % [canvas, names[index], rect])
		for other in range(index + 1, names.size()):
			var second: Rect2 = parts[names[other]].get_global_rect()
			check(not rect.intersects(second), "%s: %s clears %s (%s, %s)" % [canvas, names[index], names[other], rect, second])
	for button: Button in [hud._menu_button, hud._scoreboard_button, hud._chat_button]:
		check(button.size.y >= 56.0, "%s: %s is easy to tap" % [canvas, button.text])

	hud.toggle_menu()
	await frames(3)
	check(bounds.encloses(hud._menu_panel.get_global_rect()), "%s: the match menu fits (%s)" % [canvas, hud._menu_panel.get_global_rect()])
	for button: Node in hud._menu_panel.find_children("*", "Button", true, false):
		check(button.size.y >= hud.TOUCH_TARGET_MIN, "%s: menu buttons are finger sized" % canvas)
	hud.close_menu()
	hud.toggle_chat()
	await frames(3)
	check(bounds.encloses(hud._chat_wheel.get_global_rect()), "%s: the chat wheel fits (%s)" % [canvas, hud._chat_wheel.get_global_rect()])
	hud.toggle_chat()

	session.state = Match.State.LOBBY
	hud.refresh()
	await frames(3)
	check(bounds.encloses(hud._lobby_panel.get_global_rect()), "%s: a full 8v8 lobby fits (%s)" % [canvas, hud._lobby_panel.get_global_rect()])
	var row: Control = hud._team_columns[0].rows.get_child(0)
	check(row.size.y >= hud.LOBBY_ROW_MIN, "%s: lobby rows stay tappable (%.0f)" % [canvas, row.size.y])

	session.state = Match.State.ENDED
	hud.show_end(0, _rows())
	hud.refresh()
	await frames(3)
	check(bounds.encloses(hud._end_panel.get_global_rect()), "%s: the end screen fits a full room (%s)" % [canvas, hud._end_panel.get_global_rect()])
	view.queue_free()
	await frames(1)

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)

func _check_play(game: Node) -> void:
	var local: Node = game.tdm_local
	var session: Node = game.tdm_session
	var gameplay: Node = game.gameplay
	var pivot: Node = game.person.camera_pivot
	game.hud._touch_overlay_enabled = true
	game.hud.get_node("TouchControls").visible = true
	var config := Config.new()
	config.countdown_seconds = 0.2
	config.spawn_protection_seconds = 0.1
	check(game.network_manager.host_game(17883, "Tester") == OK, "the room opens")
	local.host_match(config, "Tester")
	await frames(30)
	session.rules.join(999, "Enemy")
	session.rules.join(998, "Mate")
	session._publish_roster()
	await frames(2)
	check(session.host_start(), "the match starts")
	var waited := 0
	while session.state != Match.State.LIVE and waited < 300:
		await physics_frame
		waited += 1
	await frames(20)
	check(local.can_fire(), "the player can fire in a live match")
	game.hud._layout_for_viewport()
	await frames(2)

	# A second finger fires while the first would be on the stick, and lifting it stops.
	var fire: Button = game.hud.btn_fire_right
	check(fire.is_visible_in_tree(), "the fire button is on screen")
	var spot := fire.get_global_rect().get_center()
	_touch(1, spot, true)
	await frames(2)
	check(gameplay.touch_fire_pressed, "a finger on FIRE holds the trigger")
	_touch(1, spot, false)
	await frames(2)
	check(not gameplay.touch_fire_pressed, "lifting the finger stops firing")
	_touch(1, spot, true)
	await frames(2)
	_touch(1, spot + Vector2(300, -200), false)
	await frames(2)
	check(not gameplay.touch_fire_pressed, "a finger that slid off the button still stops firing")
	_touch(1, spot, true)
	await frames(2)
	local.hud.toggle_menu()
	await frames(3)
	check(not gameplay.touch_fire_pressed, "opening the menu releases the trigger")
	_touch(1, spot, false)
	local.hud.close_menu()
	await frames(3)
	check(not gameplay.touch_fire_pressed, "closing the menu does not start firing")
	_touch(1, spot, true)
	await frames(2)
	game.hud.get_node("TouchControls").visible = false
	await frames(3)
	check(not gameplay.touch_fire_pressed, "a button hidden under the finger releases the trigger")
	game.hud.get_node("TouchControls").visible = true
	_touch(1, spot, false)
	await frames(2)

	# An empty magazine reloads without being asked.
	gameplay.ammo = 0
	await frames(3)
	check(gameplay._reload_time > 0.0, "an empty magazine reloads by itself on touch")
	while gameplay._reload_time > 0.0:
		await physics_frame
	check(gameplay.ammo == gameplay.mag_size, "the reload fills the magazine")

	# Aim help: a live enemy in the catch, only while aiming, eased in and out.
	var enemy: Node3D = NetworkPlayer.new()
	enemy.peer_id = 999
	game.add_child(enemy)
	game.network_manager.puppets[999] = enemy
	var camera := root.get_viewport().get_camera_3d()
	var look_before: float = pivot.look_sensitivity
	var ads_before: float = pivot.ads_sensitivity
	var aim_at := func() -> void:
		enemy.global_position = camera.global_position - camera.global_basis.z * 6.0 - Vector3.UP * 1.2
		session.vitals[999] = {"hp": 100.0, "protected": false, "alive": true}
	aim_at.call()
	await frames(12)
	check(pivot.look_sensitivity == look_before, "no help while the player is neither aiming nor firing")
	pivot.touch_aim = true
	await frames(1)
	aim_at.call()
	await process_frame
	await process_frame
	var slowed: float = local._aim_assist_amount
	check(slowed < 1.0, "the assist eases in rather than snapping (%.2f)" % slowed)
	for _i in 40:
		aim_at.call()
		await process_frame
	check(local._aim_assist_amount > 0.0, "an enemy on the aim line slows the look")
	check(pivot.ads_sensitivity < ads_before, "the sight sensitivity slows too, or aiming would get no help")
	check(pivot.ads_sensitivity >= ads_before * Local.AIM_ASSIST_SLOWDOWN - 0.001, "the slowdown stays gentle")
	session.vitals[999] = {"hp": 0.0, "protected": false, "alive": false}
	for _i in 30:
		await process_frame
	check(local._aim_assist_amount == 0.0, "a dead enemy gets no aim help")
	check(is_equal_approx(pivot.look_sensitivity, look_before) and is_equal_approx(pivot.ads_sensitivity, ads_before),
		"the player's own speeds come back exactly")
	session.vitals[998] = {"hp": 100.0, "protected": false, "alive": true}
	game.network_manager.puppets.erase(999)
	enemy.peer_id = 998
	game.network_manager.puppets[998] = enemy
	session.vitals[999] = {"hp": 100.0, "protected": false, "alive": true}
	check(session.team_of(998) == session.local_team(), "the second player is a teammate")
	for _i in 30:
		enemy.global_position = camera.global_position - camera.global_basis.z * 6.0 - Vector3.UP * 1.2
		await process_frame
	check(local._aim_assist_amount == 0.0, "a teammate gets no aim help")
	pivot.touch_aim = false

	local.leave_match()
	await frames(5)

func _button_rects(game: Node) -> Dictionary:
	var rects := {}
	for child: Node in game.hud.get_node("TouchControls").get_children():
		if child is BaseButton and child.is_visible_in_tree():
			rects[child.name] = child.get_global_rect()
	return rects

## The real claw, minimap and match HUD together, at every device shape.
func _check_real_screen(game: Node) -> void:
	var local: Node = game.tdm_local
	var session: Node = game.tdm_session
	var hud: Node = local.hud
	var config := Config.new()
	config.countdown_seconds = 0.2
	config.spawn_protection_seconds = 0.1
	check(game.network_manager.host_game(17884, "Tester") == OK, "the room opens again")
	local.host_match(config, "Tester")
	await frames(30)

	# Lobby and menu buttons on the left of the screen sit in the stick's zone: the claw must give way.
	check(not game.hud.get_node("TouchControls").visible, "the claw hides behind the lobby")
	var team_before: int = session.local_team()
	var join: Button = hud._team_columns[1 - team_before].join
	var spot := join.get_global_rect().get_center()
	_touch(0, spot, true)
	await frames(1)
	_touch(0, spot, false)
	await frames(3)
	check(session.local_team() != team_before, "a finger on JOIN changes team")
	var bridge: Node = game.hud.get_node("MenuTouchBridge")
	game.hud.settings_menu.open_menu()
	await frames(2)
	check(bridge.menu_active(), "Settings in a match answers a finger though the game cannot pause")
	game.hud.settings_menu.panel.visible = false
	await frames(2)
	check(not bridge.menu_active(), "the bridge lets go after Settings")

	session.rules.join(999, "Enemy")
	session.rules.join(998, "Mate")
	session._publish_roster()
	await frames(2)
	check(session.host_start(), "the match starts")
	var waited := 0
	while session.state != Match.State.LIVE and waited < 300:
		await physics_frame
		waited += 1
	await frames(10)
	check(game.hud.get_node("TouchControls").visible, "the claw comes back for play")

	var was_mode: int = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for canvas in CANVASES:
		root.size = canvas
		await frames(3)
		game.hud._layout_for_viewport()
		hud.refresh()
		for _i in 3:
			hud.add_kill(LONG_NAME, LONG_NAME, 0, true)
			hud.add_chat(LONG_NAME, "Hold position", 1)
		await frames(3)
		var view: Vector2 = root.get_visible_rect().size
		check(Vector2i(view) == canvas, "the test sees the %s screen (%s)" % [canvas, view])
		var bounds := Rect2(Vector2.ZERO, view)
		var mine := {"score": hud._score_box, "menu": hud._menu_button, "board": hud._scoreboard_button, "chat": hud._chat_button,
			"feed": hud._feed, "chat log": hud._chat_log, "status": hud._status_box}
		var theirs := _button_rects(game)
		if game.hud.minimap != null and game.hud.minimap.visible:
			theirs["minimap"] = game.hud.minimap.get_global_rect()
		for key: String in mine:
			var rect: Rect2 = mine[key].get_global_rect()
			check(bounds.encloses(rect), "%s: %s is on screen (%s)" % [canvas, key, rect])
			for other in theirs:
				check(not rect.intersects(theirs[other]), "%s: %s clears %s (%s, %s)" % [canvas, key, other, rect, theirs[other]])
		var names: Array = theirs.keys()
		for index in names.size():
			check(bounds.encloses(theirs[names[index]]), "%s: %s is on screen (%s)" % [canvas, names[index], theirs[names[index]]])
			for second in range(index + 1, names.size()):
				check(not theirs[names[index]].intersects(theirs[names[second]]), "%s: %s clears %s" % [canvas, names[index], names[second]])
	root.content_scale_mode = was_mode
	game.hud._touch_overlay_enabled = false
	local.leave_match()
	await frames(5)
