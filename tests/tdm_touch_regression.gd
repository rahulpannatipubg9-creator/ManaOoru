extends SceneTree

## Team Deathmatch on phones and tablets: the match screens fit every landscape shape with nothing cut off
## or overlapping, buttons are finger sized, aim help is gentle and never touches the player's settings,
## firing stops whenever the finger stops, and an empty magazine reloads by itself.
## Run: godot --headless --path . --script tests/tdm_touch_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Hud := preload("res://scripts/tactical/tdm_hud.gd")
const Local := preload("res://scripts/tactical/tdm_local.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const GunFeel := preload("res://scripts/gameplay/gun_feel.gd")
const NetworkPlayer := preload("res://scripts/network/network_player.gd")

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

func run() -> void:
	var ahead := Vector3(0, 0, -1)
	check(Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0.4, 0, -5)), "an enemy just off the crosshair is caught up close")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(2.0, 0, -5)), "an enemy well off the crosshair is not")
	check(Local.near_aim_line(Vector3.ZERO, ahead, Vector3(1.5, 0, -60)), "the catch widens a little with distance")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0, 0, 5)), "nobody behind the player is caught")
	check(not Local.near_aim_line(Vector3.ZERO, ahead, Vector3(0, 0, -200)), "nobody past the assist range is caught")
	check(GunFeel.pool_size(32, true) == 16 and GunFeel.pool_size(32, false) == 32, "phones keep half of each effect pool")
	check(GunFeel.pool_size(5, true) == 3, "a small pool still keeps at least its rounded half")

	for canvas in CANVASES:
		await _check_layout(canvas)
	await _check_play()
	print("%s tdm touch: %d checks, %d failed" % ["PASS" if failures == 0 else "FAIL", checks, failures])
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

func _check_play() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(30)
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

	game.hud._touch_overlay_enabled = false
	local.leave_match()
	await frames(5)
