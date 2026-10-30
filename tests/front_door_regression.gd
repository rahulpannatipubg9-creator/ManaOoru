extends SceneTree

## The front door: the staged world build ends in the same town as the synchronous one,
## nothing reaches the world early, and the title handles the save.
## run_godot.sh 500 --headless --path . --script tests/front_door_regression.gd

const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const LoadingScreen := preload("res://scripts/ui/loading_screen.gd")
const CreditsScreen := preload("res://scripts/ui/credits_screen.gd")
const CityLife := preload("res://scripts/world/city_life.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % message)

func _run() -> void:
	_check_text()
	await _check_title()
	var staged := await _staged_game()
	var synchronous := _synchronous_world()
	_check(staged == synchronous, "staged and synchronous builds must match: %s vs %s" % [staged, synchronous])
	print("front door: %s" % ("passed" if _failures == 0 else "%d failed" % _failures))
	quit(_failures)

func _check_text() -> void:
	_check(TitleScreen.SAVE_PATH == CityLife.SAVE_PATH, "title must look for the file the game saves")
	for tip: String in LoadingScreen.TIPS:
		_check(tip.split(" ").size() <= 6, "tip too long: %s" % tip)
	var all_lines := " ".join(CreditsScreen.CREDITS.map(func(section: Array) -> String: return " ".join(section[1])))
	for required: String in ["OpenStreetMap contributors", "ODbL", "Microsoft", "Google Open Buildings", "Copernicus DEM", "ESA WorldCover", "Mapillary", "aakash2", "Blend Swap #93636"]:
		_check(all_lines.contains(required), "credits must name %s" % required)

func _menu_labels(title: Control) -> Array[String]:
	var labels: Array[String] = []
	for button: Button in title._menu.get_children():
		labels.append(button.text)
	return labels

func _check_title() -> void:
	# The tests never touch a real save: only run the file checks when none exists.
	if TitleScreen.has_save():
		print("front door: a save exists, skipping title save checks")
		return
	var title: Control = TitleScreen.new()
	root.add_child(title)
	_check(_menu_labels(title) == ["New Game", "Squad", "Settings", "Credits", "Quit"], "no save hides Continue: %s" % [_menu_labels(title)])
	title.free()
	FileAccess.open(TitleScreen.SAVE_PATH, FileAccess.WRITE).store_string("{}")
	title = TitleScreen.new()
	root.add_child(title)
	_check(_menu_labels(title) == ["Continue", "New Game", "Squad", "Settings", "Credits", "Quit"], "a save shows Continue: %s" % [_menu_labels(title)])
	title._ask_new_game()
	_check(TitleScreen.has_save(), "asking must not erase the save")
	_check(is_instance_valid(title._sheet), "New Game over a save must ask first")
	title._close_sheet()
	_check(TitleScreen.has_save(), "keeping the save must leave it")
	TitleScreen.erase_save()
	_check(not TitleScreen.has_save(), "starting over erases the save")
	title.free()
	await process_frame

func _staged_game() -> Array:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate()
	var world: Node = game.get_node("World")
	var fractions: Array[float] = []
	world.progress.connect(func(fraction: float, _label: String) -> void: fractions.append(fraction))
	var built_count := [0]
	world.built.connect(func() -> void: built_count[0] += 1)
	World.async_build = true
	root.add_child(game)
	World.async_build = false
	_check(world.building, "a staged world is still building after _ready")
	_check(paused, "the tree stays paused while building")
	_check(root.disable_3d, "the 3D view stays off while building")
	_check(not world.visible, "the world stays hidden while building")
	_check(game.get("hud") == null, "main must not set up before the world is built")
	var player: Node3D = game.get_node("Player")
	var player_y := player.global_position.y
	var frames := 0
	while world.building:
		await process_frame
		frames += 1
		_check(player.global_position.y == player_y, "the player must not fall while the world builds")
	await process_frame
	_check(frames > 10, "a staged build must leave frames free: %d" % frames)
	_check(built_count[0] == 1, "built fires once")
	_check(not paused, "the build must unpause the tree")
	_check(not root.disable_3d and world.visible, "the world shows once built")
	_check(game.get("hud") != null and game.get("tdm_local") != null, "main finishes set-up after built")
	_check(game.hud.multiplayer_panel.tdm_local != null, "squad panel is ready after built")
	var sorted := fractions.duplicate()
	sorted.sort()
	_check(fractions == sorted and fractions[-1] == 1.0, "progress rises to 1: %s" % [fractions])
	var summary := _summary(world)
	game.free()
	await process_frame
	return summary

func _synchronous_world() -> Array:
	var world: Node = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	_check(not world.building, "a synchronous world is done when _ready returns")
	_check(world.roads != null and world.traffic != null, "a synchronous world is built when _ready returns")
	var summary := _summary(world)
	world.free()
	return summary

func _summary(world: Node) -> Array:
	return [world.get_child_count(), world.rendered_building_footprints.size(), world.vehicle_spawns.size(), world.player_spawn.position.snapped(Vector3.ONE * 0.01), world.signage.board_count]
