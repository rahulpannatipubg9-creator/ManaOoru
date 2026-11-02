extends SceneTree
var failures := 0
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for frame in 20:
		await physics_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/custom_placements.json"))
	var placements := game.get_node("World/CustomPlacements")
	var tested := 0
	for item: Dictionary in data.assets:
		if not str(item.get("drivable_scene", "")).contains("/imported/"):
			continue
		var car := placements.get_node(str(item.id)) as RigidVehicle
		_check(car != null, str(item.id) + ": rigid vehicle exists")
		if car == null:
			continue
		_check(car in game.vehicles, str(item.id) + ": registered in game roster")
		_check(car.has_meta("placement_spawn"), str(item.id) + ": retains district spawn")
		var coordinates: Array = item.position
		_check(Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(float(coordinates[0]), float(coordinates[2]))) < 3.0, str(item.id) + ": original district position")
		_check(not car.driving_enabled and not car.input_authority and not car.keyboard_input_enabled, str(item.id) + ": parked input disabled")
		_check(not car.get_node("EngineAudio").engine_running, str(item.id) + ": parked audio disabled")
		_check(car.find_children("*", "StaticBody3D", true, false).is_empty(), str(item.id) + ": no decorative static collider")
		tested += 1
	_check(tested == 31, "All 31 imported road vehicles must be registered")
	game.queue_free()
	for frame in 3:
		await process_frame
	print("%s imported world vehicle regression: %d vehicles, %d failures" % ["PASS" if failures == 0 else "FAIL", tested, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
