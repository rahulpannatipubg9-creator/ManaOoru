extends SceneTree
var failures := 0
var game: Node
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var g: Node = game.gameplay
	g.set_process(false)
	var life: Node = game.city_life
	life.save_enabled = false
	check(game.environment_controls.environment == life.environment, "Exactly one shared weather controller")
	game.person.set_physics_process(false)
	game.person.set_movement_enabled(true)
	game._set_control_authority(game.person)
	GameplayControls.blocked = false
	var start: Vector3 = game.person.global_position
	check(g.start_mission("delivery"), "Delivery must have reachable map destinations")
	check(not g.start_mission("taxi"), "Starting another mission must not replace active work")
	var target: Vector3 = g.mission.points[0]
	game.person.global_position = target + Vector3.UP * 40.0
	g._update_mission(0.1)
	check(g.mission.index == 0, "Flying over checkpoint must not count as arrival")
	game.person.global_position = target
	g._update_mission(0.1)
	check(g.mission.index == 1, "Delivery pickup advances exactly once")
	var wallet: int = game.hud.coins_available()
	game.person.global_position = g.mission.points[1]
	g._update_mission(0.1)
	check(g.mission.is_empty() and game.hud.coins_available() == wallet + 20, "Drop-off pays once")
	g.end_mission(true)
	check(game.hud.coins_available() == wallet + 20, "Completed mission cannot pay twice")
	check(g.start_mission("race"), "Race starts")
	game.person.global_position = g.mission.points[0]
	g._update_mission(0.1)
	check(g.mission.index == 0, "Race cannot progress on foot")
	g.end_mission(false)
	game.person.global_position = start
	check(g.start_mission("ambulance"), "Medical response starts")
	game.person.global_position = g.mission.points[0]
	g._update_mission(0.1)
	check(g.mission.index == 0, "Medical response requires first aid, not proximity alone")
	Input.action_press("service")
	g._update_mission(5.1)
	Input.action_release("service")
	check(g.mission.index == 1, "Holding service key completes first aid")
	g.end_mission(false)
	game.person.global_position = start
	var vehicle: RigidVehicle = game.vehicles[0]
	vehicle.take_damage(45)
	check(vehicle.condition == 55.0, "Damage reduces vehicle condition")
	vehicle.take_damage(1000)
	check(vehicle.condition == 0.0, "Vehicle condition cannot become negative")
	vehicle.repair()
	check(vehicle.condition == 100.0, "Repair restores vehicle condition")
	life.environment.set_weather_mode("Storm")
	life.environment._process(7.0)
	check(life.environment.storm and life.environment.rain > 0.9 and vehicle.weather_grip < 1.0, "Storm causes rain and reduces actual tyre grip")
	life.environment.set_weather_mode("Clear")
	check(not life.environment.storm, "Clear mode disables storm")
	check(not g.attack() and not g.throw_grenade(), "Peaceful mode blocks weapons")
	g.set_action_mode(true)
	game.person.set_weapon_equipped(true)
	game._set_control_authority(game.person)
	GameplayControls.blocked = false
	var ammo: int = g.ammo
	check(g.attack() and g.ammo == ammo - 1, "Firing consumes one round")
	check(not g.attack(), "Fire rate enforced")
	g._shot_cooldown = 0.0
	paused = true
	check(not g.attack() and not g.throw_grenade(), "Paused game blocks combat")
	paused = false
	g.ammo = 0
	g.reserve = 5
	g.reload_weapon()
	g._process(1.6)
	check(g.ammo == 5 and g.reserve == 0, "Reload transfers available rounds, never manufactures ammunition")
	g.report_crime(90)
	check(g.wanted_level == 5, "Crime escalates to five wanted levels")
	g._spawn_police()
	check(get_nodes_in_group("pursuers").size() > 0, "Wanted state spawns a physical police pursuer")
	g._build_roadblock()
	check(g._roadblocks.size() == 1, "High wanted level creates a physical roadblock")
	check(g.surrender() and g.wanted_level == 0, "On-foot surrender clears wanted level")
	g.set_action_mode(false)
	game.hud.set_coins(0)
	var stock: int = g.medkits
	check(not g.buy_supply("medkit") and g.medkits == stock, "Insufficient coins cannot grant supplies")
	game.hud.set_coins(20)
	check(g.buy_supply("medkit") and game.hud.coins_available() == 15, "Supply costs are exact")
	game.person.health = 40
	check(g.use_medkit() and game.person.health == 100 and g.medkits == stock, "Medkit consumes one item and restores health")
	g.restore_progress({"ammo": 99999, "reserve": -4, "grenades": 99999, "properties": {"valid": true, "invalid": false}})
	check(g.ammo == 24 and g.reserve == 0 and g.grenades == 30 and not g.properties.has("invalid"), "Loaded progression is bounded and validated")
	var path := "user://expansion_regression.json"
	life.save_enabled = true
	life.save_path = path
	g.completed = 7
	check(life.save_progress(), "Expanded progress saves atomically")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.gameplay.completed == 7 and saved.gameplay.ammo == 24, "Gameplay progress is included in the existing save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	life.save_enabled = false
	g.open_board()
	check(paused and life.has_modal(), "Activities menu pauses gameplay")
	life.close_modal()
	check(not paused, "Closing Activities resumes gameplay")
	check(g.water.surface_at(Vector3(100000, 0, 100000)) == -INF, "Dry land is never treated as swimming water")
	# Exercise swimming against a real water surface and ensure dry land exits it.
	g.water.regions.append({"points": PackedVector2Array([Vector2(-10,-10),Vector2(10,-10),Vector2(10,10),Vector2(-10,10)]), "height": 100.0, "center": Vector2.ZERO})
	game.person.global_position = Vector3(0, 99, 0)
	game.person._physics_process(0.016)
	check(game.person.swimming and game.person.velocity.y > 0.0, "Water changes character physics to buoyant swimming")
	game.person.global_position = start
	game.person._physics_process(0.016)
	check(not game.person.swimming, "Leaving water restores land movement")
	# Validate all new vehicle controllers without requiring a particular map spawn.
	for kind: String in ["motorcycle", "boat", "plane"]:
		var extra = load("res://scripts/gameplay/arcade_vehicle.gd").new()
		extra.kind = kind
		extra.water = g.water
		extra.position = start + Vector3(0, 100, 0)
		root.add_child(extra)
		extra.set_physics_process(false)
		check(extra.gearbox != null and extra.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") != null, kind + " supports existing entry/camera/HUD contracts")
		extra.take_damage(10)
		check(extra.condition == 90, kind + " accepts damage")
		extra.queue_free()
	print("Mapped swimming regions: ", g.water.regions.size())
	print("PASS gameplay expansion" if failures == 0 else "FAIL gameplay expansion: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
