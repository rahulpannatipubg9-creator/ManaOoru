extends SceneTree

## The AK-47 next to the M416 (scripts/gameplay/weapon_catalog.gd): both rifles lie at Chowrastha, a new
## rifle goes on the back, key 2 switches with each rifle keeping its own magazine, the AK fires slower
## and kicks harder, ownership and the rifle in hand are saved, remote players show the rifle from the
## synced stance code, and the Team Deathmatch host uses the named rifle's damage and fire-rate limit.
## Run: godot --headless --path . --script tests/weapon_switch_regression.gd

const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
const Config := preload("res://scripts/tactical/tdm_config.gd")
const Roster := preload("res://scripts/tactical/tdm_roster.gd")
const Spawns := preload("res://scripts/tactical/tdm_spawns.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")

var _failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	_test_catalog()
	await _test_free_roam()
	await _test_remote_player()
	_test_host_claims()
	if _failures > 0:
		print("FAIL weapon switch regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS weapon switch regression: catalog, AK pickup goes on the back, key 2 switches with separate magazines, AK stats, saved, remote rifle synced, host damage per rifle")
	quit()

func _test_catalog() -> void:
	var m4 := Weapons.stats(Weapons.M416)
	var ak := Weapons.stats(Weapons.AK47)
	_check(float(ak.body_damage) > float(m4.body_damage) and float(ak.auto_interval) > float(m4.auto_interval),
		"The AK hits harder and fires slower than the M416")
	_check(ceili(100.0 / float(ak.body_damage)) == 3 and ceili(100.0 / float(m4.body_damage)) == 4,
		"Three AK body hits kill, four M416 body hits")
	var max_hit: float = Config.new().max_hit_damage
	for id in Weapons.IDS:
		var gun := Weapons.stats(id)
		_check(float(gun.head_damage) <= max_hit, "%s headshot stays within the host's per-hit limit" % gun.name)
		_check(float(gun.min_claim_interval) < float(gun.auto_interval), "%s host limit allows its own fire rate" % gun.name)
		var holder := Weapons.build(id)
		_check(holder.get_node_or_null("Muzzle") is Marker3D and holder.get_child_count() == 2, "%s builds a model and a muzzle" % gun.name)
		_check(int(holder.get_meta("weapon_id")) == id and holder.has_meta("grip_left") and holder.has_meta("grip_right"),
			"%s holder carries its id and hand grips" % gun.name)
		holder.free()
	_check(not Weapons.is_valid(7) and Weapons.stats(7).name == "M416", "Unknown ids fall back to the M416")

func _test_free_roam() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for _frame in 20:
		await physics_frame
	var play: Node = game.gameplay
	var person: CharacterBody3D = game.person
	play.has_rifle = false
	play.owned_rifles.clear()
	play.set_action_mode(false)
	await physics_frame

	var kinds := {}
	for pickup: Node in get_nodes_in_group("weapon_pickups"):
		kinds[pickup.weapon_id] = pickup
	_check(kinds.has(Weapons.M416) and kinds.has(Weapons.AK47), "Both an M416 and an AK-47 lie at Chowrastha")
	if not (kinds.has(Weapons.M416) and kinds.has(Weapons.AK47)):
		game.queue_free()
		return

	_walk_into(person, kinds[Weapons.M416])
	for _frame in 6:
		await physics_frame
	_check(play.rifles() == [Weapons.M416] and person.weapon_id == Weapons.M416 and person.is_weapon_equipped(),
		"The first rifle picked up is the M416, in the hands")
	_press(game, KEY_2)
	await process_frame
	_check(person.weapon_id == Weapons.M416, "With one rifle, key 2 does nothing")

	_walk_into(person, kinds[Weapons.AK47])
	for _frame in 6:
		await physics_frame
	_check(play.rifles() == [Weapons.M416, Weapons.AK47], "The AK-47 is added (%s)" % [play.rifles()])
	_check(person.weapon_id == Weapons.M416, "A second rifle goes on the back; the M416 stays in the hands")

	play._shot_cooldown = 0.0
	_check(play.attack() and play.ammo == 23, "The M416 fires (%d left)" % play.ammo)
	_press(game, KEY_2)
	await process_frame
	_check(person.weapon_id == Weapons.AK47 and int(person.weapon.get_meta("weapon_id")) == Weapons.AK47,
		"Key 2 brings out the AK-47 model")
	_check(person.is_weapon_equipped() and person.muzzle != null and person.muzzle.get_parent() == person.weapon,
		"The AK is drawn with its own muzzle marker")
	_check(play.ammo == 24, "The AK has its own full magazine (%d)" % play.ammo)
	_check(not play.attack(), "Switching takes a moment before the AK can fire")
	play._shot_cooldown = 0.0
	_check(play.attack(), "The AK fires")
	_check(is_equal_approx(play._shot_cooldown, 0.13) and is_equal_approx(person.weapon_kick, 0.06),
		"The AK's fire interval and kick are its own (%.2f s, %.3f)" % [play._shot_cooldown, person.weapon_kick])
	play.reload_weapon()
	_check(play._reload_time > 0.0, "The AK starts reloading")
	_press(game, KEY_2)
	await process_frame
	_check(person.weapon_id == Weapons.M416 and play.ammo == 23 and play._reload_time == 0.0,
		"Switching back cancels the reload and returns the M416's own magazine (%d)" % play.ammo)

	play.select_rifle(Weapons.AK47)
	var record: Dictionary = play.export_progress()
	_check(record.get("rifles") == [Weapons.M416, Weapons.AK47] and record.get("weapon") == Weapons.AK47, "Both rifles and the AK in hand are saved")
	play.select_rifle(Weapons.M416)
	play.restore_progress(JSON.parse_string(JSON.stringify(record)))
	_check(play.rifles() == [Weapons.M416, Weapons.AK47] and person.weapon_id == Weapons.AK47, "A save restores both rifles and the AK in hand")
	play.restore_progress({"has_rifle": true})
	_check(play.rifles() == [Weapons.M416], "An older save with a rifle means the M416")
	play.restore_progress({"has_rifle": true, "rifles": [1, 1, 99, "x"], "weapon": 99})
	_check(play.rifles() == [Weapons.AK47], "Bad saved rifle ids are dropped (%s)" % [play.rifles()])
	game.queue_free()
	await process_frame

func _test_remote_player() -> void:
	var puppet: CharacterBody3D = NetworkPlayerScript.new()
	root.add_child(puppet)
	await process_frame
	if puppet.weapon == null:
		_check(puppet.weapon_id == Weapons.M416, "A capsule puppet starts with the M416")
	else:
		_check(int(puppet.weapon.get_meta("weapon_id")) == Weapons.M416, "A remote player starts with the M416")
	# Standing, aiming, AK in hand.
	puppet.update_network_state(Vector3.ZERO, 0.0, 0.0, 4 | (Weapons.AK47 << 3), 0.0, true, true)
	_check(puppet.weapon_id == Weapons.AK47 and puppet.aiming and puppet.stance == 0, "The stance code carries the AK without disturbing aim and stance")
	if puppet.weapon != null:
		_check(int(puppet.weapon.get_meta("weapon_id")) == Weapons.AK47, "The remote player's model becomes the AK")
		_check(puppet._muzzle_flash.get_parent() == puppet.weapon, "The muzzle flash moves onto the AK")
	puppet.update_network_state(Vector3.ZERO, 0.0, 0.0, 1, 0.0, true, false)
	_check(puppet.weapon_id == Weapons.M416 and puppet.crouching, "An older client's code (no rifle bits) means the M416")
	puppet.queue_free()
	await process_frame

func _test_host_claims() -> void:
	var cfg := Config.new()
	var roster := Roster.new()
	var spawns := Spawns.new()
	spawns.set_zones(Roster.Team.RED, PackedVector3Array([Vector3(-60, 0, -55)]))
	spawns.set_zones(Roster.Team.BLUE, PackedVector3Array([Vector3(60, 0, 55)]))
	var rules := Match.new(cfg, roster, spawns)
	rules.join(1, "Host")
	rules.join(2, "Guest")
	rules.start()
	rules.tick(cfg.countdown_seconds)
	rules.tick(cfg.spawn_protection_seconds + 0.1)
	var session: Node = Session.new()
	root.add_child(session)
	session.active = true
	session.is_host = true
	session.rules = rules
	session._positions = {1: Vector3(0, 0, 5), 2: Vector3(0, 0, 0)}
	var hit := Vector3(0, 1.0, 0)
	var origin := Vector3(0, 1.5, 5)
	var bad: Dictionary = session._handle_claim(1, 2, false, origin, hit, 7)
	_check(not bad.accepted and bad.reason == "bad_weapon", "A claim naming an unknown rifle is refused")
	var ak: Dictionary = session._handle_claim(1, 2, false, origin, hit, Weapons.AK47)
	_check(ak.accepted and is_equal_approx(rules.health_of(2), 66.0), "An AK body hit costs 34 (%.0f left)" % rules.health_of(2))
	rules.tick(0.08)
	var fast: Dictionary = session._handle_claim(1, 2, false, origin, hit, Weapons.AK47)
	_check(not fast.accepted and fast.reason == "fire_rate", "AK claims faster than the AK fires are refused")
	rules.tick(0.02)
	var m4: Dictionary = session._handle_claim(1, 2, true, origin, Vector3(0, 1.7, 0), Weapons.M416)
	_check(m4.accepted and m4.killed, "An M416 headshot (70) finishes the AK-wounded player")
	session.queue_free()

func _walk_into(person: CharacterBody3D, pickup: Node3D) -> void:
	person.global_position = pickup.global_position + Vector3.UP * 0.2

func _press(game: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game.get_viewport().push_input(event)
	var release := event.duplicate()
	release.pressed = false
	game.get_viewport().push_input(release)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
