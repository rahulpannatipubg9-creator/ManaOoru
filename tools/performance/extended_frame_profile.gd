extends "res://scripts/performance/frame_profile.gd"

## Rendered endurance probe. No normal-game hooks or changes to saved progress.
var idle_seconds := 300.0
var drive_seconds := 300.0
var output := "/tmp/mana_extended_profile"
var route := Curve3D.new()
var car: RigidVehicle
var autopilot := false
var route_progress := 0.0
var travelled := 0.0
var moving_seconds := 0.0
var stopped_seconds := 0.0
var previous_car_position := Vector3.ZERO
var spike_events: Array[Dictionary] = []
var memory_samples: Array[Dictionary] = []
var last_checkpoint := 0.0

func _argument(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _snapshot() -> Dictionary:
	var world := game.get_node("World")
	return {"position": str(game.tracked_body().global_position),
		"speed_mps": float(car.current_speed) if car != null else 0.0,
		"building_pending": world.buildings.pending_chunk_count(),
		"tree_pending": world.trees.pending_chunk_count(), "tree_chunks": world.trees.get_child_count(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}

func _save_partial() -> void:
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"results": results, "spikes": spike_events,
		"checkpoints": memory_samples}, "\t"))
	file.close()

func _long_sample(label: String, seconds: float) -> void:
	var frames: Array[float] = []
	var moving_frames: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	var checkpoint := 0.0
	var distance_start := travelled
	var motion_start := moving_seconds
	var stopped_start := stopped_seconds
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		game._window_unfocused = false
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		frames.append(frame_ms)
		if car != null and absf(car.current_speed) > 1.0:
			moving_frames.append(frame_ms)
		var elapsed := float(now - start) / 1000000.0
		if frame_ms > 25.0:
			var event := _snapshot()
			event["stage"] = label
			event["seconds"] = elapsed
			event["frame_ms"] = frame_ms
			spike_events.append(event)
		if elapsed >= checkpoint:
			checkpoint += 30.0
			var sample := _snapshot()
			sample["stage"] = label
			sample["seconds"] = elapsed
			sample["distance_m"] = travelled - distance_start
			memory_samples.append(sample)
			print("EXTENDED_CHECKPOINT ", JSON.stringify(sample))
			_save_partial()
		if autopilot and stopped_seconds > 20.0:
			print("DRIVE_BLOCKED ", JSON.stringify(_snapshot()))
			break
	var elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
	var row := {"stage": label, "seconds": elapsed, "fps": frames.size() / elapsed,
		"frame_ms": _stats(frames, true), "distance_m": travelled - distance_start,
		"moving_seconds": moving_seconds - motion_start,
		"stopped_seconds": stopped_seconds - stopped_start,
		"moving_frame_ms": _stats(moving_frames, true), "end": _snapshot()}
	if label == "driving":
		row["sustained_drive"] = travelled - distance_start > 1000.0 and moving_seconds - motion_start >= elapsed * 0.6
	results.append(row)
	print("EXTENDED_RESULT ", JSON.stringify(row))
	_save_partial()

func _road_height(point: Vector2) -> float:
	var world := game.get_node("World")
	if point.y < GodavariBridgeBuilder.SOUTH_LAND_Z + 50.0:
		var south := GodavariBridgeBuilder.south_end()
		var north := GodavariBridgeBuilder.north_end()
		var t := clampf((point - south).dot(GodavariBridgeBuilder.forward2()) / GodavariBridgeBuilder.BRIDGE_LENGTH, 0, 1)
		return lerpf(world.ground_height(south), world.ground_height(north), t)
	return world.flyover_height_at(point, world.ground_height(point))

func _make_route() -> void:
	route.bake_interval = 2.0
	var world := game.get_node("World")
	for way_id in [-901, -903, -902]:
		for road: Dictionary in world.map_data.roads:
			if road.way_id != way_id: continue
			for point: Vector2 in road.points:
				route.add_point(Vector3(point.x, _road_height(point), point.y))
	# Continue back into town after the real north landing turnaround.
	var last := route.get_point_position(route.point_count - 1)
	var continuation: Dictionary = game.road_network.find_route(Vector2(last.x, last.z), Vector2(-190, -2090), RoadNetwork.Mode.DRIVE)
	if continuation.get("ok", false):
		for point: Vector2 in continuation.points:
			route.add_point(Vector3(point.x, _road_height(point), point.y))
	print("DRIVE_ROUTE_METRES ", route.get_baked_length())

func _physics_process(delta: float) -> bool:
	if not autopilot or car == null: return false
	var actual_step := car.global_position.distance_to(previous_car_position)
	if actual_step < 20.0: travelled += actual_step
	previous_car_position = car.global_position
	if absf(car.current_speed) > 1.0:
		moving_seconds += delta
		stopped_seconds = 0.0
	else:
		stopped_seconds += delta
	route_progress = maxf(route_progress, route.get_closest_offset(car.global_position))
	var lookahead := clampf(absf(car.current_speed) * 1.1, 4.0, 12.0)
	var target := route.sample_baked(minf(route_progress + lookahead, route.get_baked_length()))
	var direction := target - car.global_position
	direction.y = 0.0
	var yaw := atan2(direction.x, direction.z)
	var error := angle_difference(atan2(car.global_basis.z.x, car.global_basis.z.z), yaw)
	var steering := -clampf(error * 2.3, -1.0, 1.0)
	var cruise := 12.0 if absf(error) < 0.15 else 6.0 if absf(error) < 0.4 else 3.0
	if route_progress > route.get_baked_length() - 12.0: cruise = 0.0
	var throttle := 0.8 if car.current_speed < cruise - 0.3 else -0.7 if car.current_speed > cruise + 0.5 else 0.18
	car.set_touch_move_input(Vector2(steering, -throttle))
	return false

func _run() -> void:
	idle_seconds = float(_argument("--idle-seconds", "300"))
	drive_seconds = float(_argument("--drive-seconds", "300"))
	output = _argument("--output", output)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.city_life.save_enabled = false
	game.performance_controller.settings.values.fps = 60
	game.performance_controller.apply_settings()
	await create_timer(15.0).timeout
	await _long_sample("idle", idle_seconds)
	_make_route()
	car = game.get_node("Vehicle") as RigidVehicle
	var begin := route.sample_baked(8.0)
	var ahead := route.sample_baked(20.0) - begin
	car._teleport(Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)), begin + Vector3.UP * 0.3))
	car.respawn_position = begin
	car.settle_on_ground()
	game.person.set_movement_enabled(false)
	game.person.global_position = game._door_position(car, -1.0)
	game.enter_vehicle(car)
	for frame in 360:
		if game.control_state == game.ControlState.DRIVING: break
		await physics_frame
	if game.control_state != game.ControlState.DRIVING:
		print("FAIL long-drive setup: entry did not complete")
		quit(1)
		return
	await create_timer(10.0).timeout
	previous_car_position = car.global_position
	autopilot = true
	await _long_sample("driving", drive_seconds)
	autopilot = false
	car.set_touch_move_input(Vector2.ZERO)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + ".png")
	game.queue_free()
	for frame in 8: await process_frame
	print("EXTENDED_COMPLETE ", output)
	quit()
