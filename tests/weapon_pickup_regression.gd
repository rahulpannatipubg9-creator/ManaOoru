extends SceneTree

## Rifles to loot at Chowrastha: placed on open ground near the junction, the rifle
## can't be drawn before one is picked up, walking into one arms you ready to fire,
## P toggles fire mode, Shift+P surrenders, and ownership is saved.

var _failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for _frame in 20:
		await physics_frame
	var play: Node = game.gameplay
	var person: CharacterBody3D = game.person
	# A brand-new player.
	play.has_rifle = false
	play.set_action_mode(false)
	await physics_frame

	var pickups := get_nodes_in_group("weapon_pickups")
	_check(pickups.size() >= 3, "Several rifles lie around Chowrastha (%d)" % pickups.size())
	var space := person.get_world_3d().direct_space_state
	for pickup: Node3D in pickups:
		_check(pickup.global_position.distance_to(person.respawn_position) < 25.0, "Rifle %s is near the Chowrastha start" % pickup.global_position)
		var top := pickup.global_position + Vector3.UP * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 1.5, 0xFFFFFFFF, [person.get_rid()]))
		_check(not hit.is_empty() and absf(hit.position.y - pickup.global_position.y) < 0.2, "Rifle %s rests on the ground" % pickup.global_position)

	# No rifle yet: drawing does nothing; P still turns fire mode on.
	person.set_weapon_equipped(true)
	await process_frame
	await process_frame
	_check(not person.is_weapon_equipped(), "Without a looted rifle there is nothing to draw")
	_press(game, KEY_P)
	await process_frame
	_check(play.action_mode and not person.is_weapon_equipped(), "P turns fire mode on even before a rifle is found")
	_press(game, KEY_P)
	await process_frame
	_check(not play.action_mode, "P again turns fire mode off")

	# Walk into a rifle.
	var pickup: Area3D = pickups[0]
	play.reserve = 0
	person.global_position = pickup.global_position + Vector3.UP * 0.2
	for _frame in 6:
		await physics_frame
	_check(play.has_rifle, "Walking into the rifle picks it up")
	_check(person.is_weapon_equipped() and play.action_mode, "Picking it up puts the rifle in your hands, ready to fire")
	_check(play.ammo == 24 and play.reserve == 60, "A pickup fills the magazine and adds spare rounds (%d/%d)" % [play.ammo, play.reserve])
	_check(not pickup.visible and not pickup.is_available(), "The picked rifle disappears until it respawns")
	_check(play.attack(), "The picked-up rifle fires")
	_check(play.ammo == 23, "Firing uses a round (%d)" % play.ammo)

	# P holsters and re-draws; Shift+P surrenders.
	_press(game, KEY_P)
	await process_frame
	_check(not play.action_mode and not person.is_weapon_equipped(), "P switches fire mode off and holsters")
	_press(game, KEY_P)
	await process_frame
	_check(play.action_mode and person.is_weapon_equipped(), "P switches fire mode on and draws the owned rifle")
	play.wanted_level = 2
	_press(game, KEY_P, true)
	await process_frame
	_check(play.wanted_level == 0 and play.action_mode, "Shift+P surrenders without leaving fire mode")

	# A second rifle only tops up ammunition.
	var second: Area3D = pickups[1]
	var reserve_before: int = play.reserve
	person.global_position = second.global_position + Vector3.UP * 0.2
	for _frame in 6:
		await physics_frame
	_check(play.reserve == reserve_before + 60 and play.ammo == 24, "Another rifle adds ammunition (%d -> %d)" % [reserve_before, play.reserve])

	# Ownership survives a save.
	var record: Dictionary = play.export_progress()
	_check(record.get("has_rifle") == true, "The rifle is saved")
	play.has_rifle = false
	play.restore_progress(record)
	_check(play.has_rifle, "The rifle is restored from the save")
	play.restore_progress({})
	_check(not play.has_rifle, "Old saves without the field start without a rifle")

	if _failures > 0:
		print("FAIL weapon pickup regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS weapon pickup regression: rifles on open ground at Chowrastha; no rifle before looting; pickup arms and fills ammo; fires; P toggles fire mode; Shift+P surrenders; extra rifle adds ammo; saved")
	quit()

func _press(game: Node, key: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.shift_pressed = shift
	event.pressed = true
	game.get_viewport().push_input(event)
	var release := event.duplicate()
	release.pressed = false
	game.get_viewport().push_input(release)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
