extends SceneTree

const RamagundamFlyoverClass := preload("res://scripts/world/ramagundam_flyover_builder.gd")

var failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	print("--- TESTING RAMAGUNDAM FLYOVER BUILDER ---")
	var map_data := MapData.load_shared()
	check(map_data != null, "MapData must load")

	var world := Node3D.new()
	root.add_child(world)

	var flyover = RamagundamFlyoverClass.new()
	world.add_child(flyover)
	flyover.build(world, map_data)

	for i in 2:
		await physics_frame

	print("Flyover total length: ", flyover._total_length)
	check(flyover._total_length > 840.0 and flyover._total_length < 855.0, "Flyover length must be ~846m")

	# Check elevation profile
	var sample_start := flyover.sample_path(0.0)
	var sample_crest := flyover.sample_path(140.0)
	var sample_mid := flyover.sample_path(400.0)
	var sample_end := flyover.sample_path(flyover._total_length)

	print("Start clearance: ", sample_start.clearance, " deck_y: ", sample_start.deck_y)
	print("Crest clearance: ", sample_crest.clearance, " deck_y: ", sample_crest.deck_y)
	print("Mid clearance:   ", sample_mid.clearance, " deck_y: ", sample_mid.deck_y)
	print("End clearance:   ", sample_end.clearance, " deck_y: ", sample_end.deck_y)

	check(sample_start.clearance < 0.1, "Start ramp must meet ground (clearance ~0)")
	check(absf(sample_mid.clearance - 6.5) < 0.01, "Mid flyover must be elevated at 6.5m")
	check(sample_end.clearance < 0.1, "End ramp must meet ground (clearance ~0)")

	# Check deck_height_at
	var mid_pt: Vector2 = sample_mid.pos
	var deck_h: float = flyover.deck_height_at(mid_pt)
	print("deck_height_at mid_pt: ", deck_h, " expected: ", sample_mid.deck_y)
	check(absf(deck_h - sample_mid.deck_y) < 0.1, "deck_height_at must return deck_y")

	var far_pt: Vector2 = mid_pt + Vector2(100.0, 100.0)
	var outside_h: float = flyover.deck_height_at(far_pt)
	check(outside_h == -INF, "deck_height_at must return -INF outside bridge deck")

	# Check FlyoverStructure collision body
	var struct_body: StaticBody3D = flyover.get_node_or_null("FlyoverStructure")
	check(struct_body != null, "FlyoverStructure StaticBody3D must exist")
	if struct_body:
		print("Structure collision layer: ", struct_body.collision_layer)
		check(struct_body.collision_layer == 3, "FlyoverStructure collision layer must be 3 (layers 1 and 2)")
		var col_count: int = struct_body.get_child_count()
		print("Structure children / collision shapes count: ", col_count)
		check(col_count >= 6, "Must contain all collision and visual surfaces")

	# Check dressing props (median planters and street lights)
	var dressing: Node3D = flyover.get_node_or_null("FlyoverDressing")
	check(dressing != null, "FlyoverDressing must exist")
	if dressing:
		var dressing_count: int = dressing.get_child_count()
		print("Flyover dressing children count: ", dressing_count)
		check(dressing_count > 30, "Must have potted palms and street light poles along median")

	# Test Vehicle Driving on Flyover Deck
	print("--- TESTING VEHICLE DRIVING ON FLYOVER ---")
	var car_scene: PackedScene = load("res://scenes/vehicles/imported/ford_mustang_mach_40.tscn")
	var car: RigidVehicle = car_scene.instantiate()
	world.add_child(car)

	# Place car on flyover elevated deck at s = 250m
	var drive_sample := flyover.sample_path(250.0)
	var car_pos := Vector3(drive_sample.pos.x + drive_sample.normal.x * 4.3, drive_sample.deck_y + 0.35, drive_sample.pos.y + drive_sample.normal.y * 4.3)
	var car_yaw: float = atan2(drive_sample.tangent.x, drive_sample.tangent.y)
	car.global_position = car_pos
	car.rotation = Vector3(0.0, car_yaw, 0.0)
	car.set_driving_enabled(true)
	car.set_input_authority(true)

	for i in 60:
		await physics_frame

	print("Car position after drop: ", car.global_position)
	print("Car wheel contacts: ", car.wheel_contacts)
	check(car.global_position.y > drive_sample.ground_y + 4.0, "Car must stay on elevated flyover deck, not fall to ground")
	check(car.wheel_contacts.any(func(c: bool) -> bool: return c), "Car tyres must be grounded on flyover deck")

	# Apply throttle forward along flyover
	car.set_touch_move_input(Vector2(0, -1))
	for i in 120:
		await physics_frame

	print("Car speed: ", car.current_speed, " pos: ", car.global_position)
	check(car.current_speed > 3.0, "Car must accelerate forward on flyover deck")
	check(car.global_position.y > drive_sample.ground_y + 4.0, "Car must remain elevated on flyover deck while driving")

	print("PASS Ramagundam ROB Flyover Builder Verification" if failures == 0 else "FAIL Ramagundam Flyover Builder Verification")
	quit(0 if failures == 0 else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
