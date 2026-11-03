extends SceneTree

## Keys that used to do two jobs, and free-roam systems that used to reach into a Team Deathmatch:
## R reloads without moving the player, B leaves the bridge alone, X switches fire mode, and in a match
## the free-roam shortcuts, street rifles and saving are all off.
## Run: godot --headless --path . --script tests/match_input_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")

var failures := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(30)
	var person: CharacterBody3D = game.person
	var gameplay: Node = game.gameplay
	GameplayControls.blocked = false

	# R on foot: the safe-ground recovery no longer runs.
	var before := person.global_position
	Input.action_press("vehicle_recover")
	await frames(3)
	Input.action_release("vehicle_recover")
	await frames(2)
	check(person.global_position.distance_to(before) < 0.5, "R on foot does not move the player")

	# B no longer teleports; F9 does.
	game._input(key(KEY_B))
	await frames(2)
	check(person.global_position.distance_to(before) < 0.5, "B does not teleport")
	var fire_mode: int = gameplay.fire_mode
	gameplay._unhandled_input(key(KEY_X))
	check(gameplay.fire_mode != fire_mode, "X switches fire mode on foot")
	gameplay._unhandled_input(key(KEY_B))
	check(gameplay.fire_mode != fire_mode, "B does not switch fire mode")
	game._input(key(KEY_F9))
	await frames(2)
	check(person.global_position.distance_to(before) > 500.0, "F9 travels to the bridge")
	game._input(key(KEY_F9))
	await frames(2)

	# In a match.
	var config := Config.new()
	check(game.network_manager.host_game(17879, "Tester") == OK, "the room opens")
	game.tdm_local.host_match(config, "Tester")
	await frames(30)
	check(game.tdm_local.in_match, "hosting enters the match")
	game.prepare_for_match()
	check(not paused, "a match never starts paused")
	game.hud.set_match_mode(true)
	await process_frame
	await process_frame
	check(not game.hud.btn_medkit.visible and not game.hud.compass_bar.visible, "free-roam HUD is hidden in a match")
	check(not game.hud.minimap.get_node("ZoomIn").visible, "the minimap is compact in a match")
	check(game.hud.btn_fire_right.visible, "fire stays in a match")

	check(not game.city_life.save_progress(), "saving is off in a match")
	var pickup: Node = get_nodes_in_group("weapon_pickups")[0] if not get_nodes_in_group("weapon_pickups").is_empty() else null
	if pickup != null:
		var ammo: int = gameplay.ammo
		pickup._collect(person)
		check(gameplay.ammo == ammo and pickup.is_available(), "street rifles ignore a match")
	var action: bool = gameplay.action_mode
	gameplay.toggle_action()
	check(gameplay.action_mode == action, "P cannot disarm a match")

	GameplayControls.blocked = false
	game._input_suspended = false
	var spot := person.global_position
	for code: Key in [KEY_F5, KEY_F6, KEY_F9, KEY_HOME, KEY_TAB]:
		game._input(key(code))
	await frames(2)
	check(person.global_position.distance_to(spot) < 0.5, "shortcuts do not teleport in a match")
	check(not game.city_life.has_modal() and not paused, "shortcuts open nothing in a match")

	game.tdm_local.leave_match()
	game.hud.set_match_mode(false)
	await frames(5)
	check(game.hud.compass_bar.visible and game.hud.btn_medkit.visible, "the HUD comes back after a match")
	check(game.hud.minimap.get_node("ZoomIn").visible, "the minimap comes back after a match")

	if failures == 0:
		print("PASS match input regression")
	quit(failures)
