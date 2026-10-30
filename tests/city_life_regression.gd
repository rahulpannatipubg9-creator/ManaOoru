extends SceneTree

var failures := 0
var game: Node
var life: Node

func _init() -> void:
	call_deferred("run_checks")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run_checks() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	life = game.city_life
	if life == null:
		push_error("CityLife is not initialized in the current main scene; this feature suite is unavailable")
		game.queue_free()
		await process_frame
		quit(1)
		return
	life.save_enabled = false
	game.person.set_movement_enabled(false)
	var world: Node = game.get_node("World")
	check(life != null and life.environment != null and life.community != null, "City modules must load in the actual main game")
	check(life.community.talking_residents >= 2, "Conversation groups must be present")
	check(life.community.shop_routines > 0, "Shop routines must be present")
	check(life.targets.size() >= 8, "Discovery journal must include city locations and hidden tokens")
	check(life.community.identity_markers.size() >= 3, "Chowrastha, markets and colony identity details must exist")
	print("City components: %d talking residents, %d routines, %d identity details, %d discovery targets, %d fuel stops" % [life.community.talking_residents, life.community.shop_routines, life.community.identity_markers.size(), life.targets.size(), life._fuel_stops.size()])
	var road_snapshot: Array = world.map_data.roads.duplicate(true)
	var building_snapshot: Array = world.buildings.footprints.duplicate(true)
	life.environment.set_hour(12)
	check(life.environment.night < 0.05, "Noon must be daylight")
	life.environment.set_hour(23)
	check(life.environment.night > 0.95, "23:00 must activate night")
	check(life.environment._lamps.size() <= 12, "Streetlight pool must remain bounded")
	life.environment.set_weather(true)
	life.environment._process(5.0)
	check(life.environment.rain > 0.0 and life.environment.wetness > 0.0, "Rain must build gradually and wet surfaces")
	check(life.environment._rain.emitting, "Outside rain particles must activate")
	life.environment.indoors = true
	life.environment._process(1.0)
	check(not life.environment._rain.emitting, "Interior must suppress rain")
	life.environment.indoors = false
	var paused_clock: float = life.environment.hour
	life.open_journal()
	check(paused and life.has_modal(), "Journal must pause gameplay")
	for frame in 3:
		await process_frame
	check(is_equal_approx(paused_clock, life.environment.hour), "Clock must stop while a modal pauses gameplay")
	life.close_modal()
	check(not paused, "Closing journal must resume gameplay")
	game.hud.set_coins(10)
	life.energy = 30.0
	check(life.purchase("tea"), "Tea purchase must succeed")
	check(game.hud.coins_available() == 9 and life.energy == 45.0, "Tea must cost exactly one coin and restore energy")
	check(life.purchase("snack") and game.hud.coins_available() == 7, "Snacks must cost two coins")
	life.fuel[str(game.active_vehicle.name)] = 20.0
	check(life.purchase("fuel") and game.hud.coins_available() == 4, "Fuel must cost three coins")
	check(float(life.fuel[str(game.active_vehicle.name)]) == 55.0, "Refuel must add 35 percentage points")
	game.hud.set_coins(0)
	var stock: Dictionary = life.inventory.duplicate(true)
	check(not life.purchase("snack") and life.inventory == stock, "Insufficient funds must not grant an item")
	var id: String = life.targets[0].id
	var already: bool = life.discoveries.has(id)
	check(life.discover(id) != already, "Discovery must be awarded once")
	var reward: int = game.hud.coins_available()
	check(not life.discover(id) and game.hud.coins_available() == reward, "Revisiting a discovery must not duplicate rewards")
	# Test versioned persistence in an isolated save; never alter player progress.
	life.save_path = "user://city_life_regression_only.json"
	life.save_enabled = true
	check(life.save_progress(), "Progress must save atomically")
	game.hud.set_coins(0)
	life.energy = 1.0
	check(life.load_progress() and game.hud.coins_available() == reward, "Coins and discoveries must survive reload")
	var file := FileAccess.open(life.save_path, FileAccess.WRITE)
	file.store_string('{"version":1,"coins":{},"energy":[],"inventory":{"tea":{}},"fuel":{}}')
	file.close()
	check(life.load_progress() and game.hud.coins_available() == 8, "Malformed fields must fall back safely")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(life.save_path))
	life.save_enabled = false
	var outdoor: Transform3D = game.person.global_transform
	var shop := {"name": "Local tea shop", "kind": "tea", "position": outdoor.origin}
	life.enter_interior(shop)
	check(life.inside_shop and life.environment.indoors, "Entering a shop must switch indoor state")
	check(game.first_person_view, "Small interior must use first-person view")
	var interior: Node3D = life._interior
	check(absf(interior.global_position.x - outdoor.origin.x) < 0.01, "Interior X/Z must retain geographic alignment")
	game.person.set_movement_enabled(true)
	for frame in 12:
		await physics_frame
	check(game.person.global_position.y > interior.global_position.y - 0.1, "Shop floor must physically support the player")
	life.leave_interior()
	check(not life.inside_shop and not life.environment.indoors, "Exit must restore outside weather state")
	check(game.person.global_position.distance_to(outdoor.origin) < 0.1, "Exit must restore the exact street position")
	check(world.map_data.roads == road_snapshot and world.buildings.footprints == building_snapshot, "New city systems must not move roads or buildings")
	print("%s city life: day/night, rain, indoor shelter, paused UI, purchases, fuel, discovery deduplication, save validation, physical shop floor, safe return" % ("PASS" if failures == 0 else "FAIL"))
	game.free()
	await process_frame
	quit(1 if failures else 0)
