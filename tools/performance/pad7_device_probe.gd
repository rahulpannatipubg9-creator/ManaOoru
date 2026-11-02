extends Node

## Loaded only by frame_profile.gd in the isolated Android performance package.
## Copy as user://stress_test.gd. Never writes player progress or quality settings.
var game: Node
var rows: Array[Dictionary] = []
var config: Dictionary = {}
var car: RigidVehicle
var route := Curve3D.new()
var autopilot := false
var route_offset := 0.0
var distance := 0.0
var moving_seconds := 0.0
var blocked_seconds := 0.0
var last_position := Vector3.ZERO
var started := Time.get_ticks_msec()

func _ready() -> void:
	_run.call_deferred()

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total := 0.0
	var late60 := 0
	var late90 := 0
	var stalls := 0
	for v in values:
		total += v
		if v > 20.84: late60 += 1
		if v > 13.89: late90 += 1
		if v > 33.34: stalls += 1
	return {"n": values.size(), "mean": total / values.size(), "p50": values[values.size()/2],
		"p95": values[int(values.size()*0.95)], "p99": values[int(values.size()*0.99)],
		"max": values[-1], "over_20_84ms": late60, "over_13_89ms": late90, "over_33_34ms": stalls}

func _snapshot() -> Dictionary:
	var world := game.get_node("World")
	return {"position": str(game.tracked_body().global_position), "distance_m": distance,
		"moving_seconds": moving_seconds, "blocked_seconds": blocked_seconds,
		"speed_mps": car.current_speed if car != null else 0.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
		"tree_pending": world.trees.pending_chunk_count(), "building_pending": world.buildings.pending_chunk_count()}

func _save() -> void:
	var file := FileAccess.open("user://pad7_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"config": config, "results": rows, "snapshot": _snapshot()}, "\t"))
	file.close()

func _sample(label: String, seconds: float, walk := false, orbit := false) -> void:
	var frames: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var draws: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	var checkpoint := 0.0
	var from: Vector3 = game.tracked_body().global_position
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		game._window_unfocused = false
		if walk: game.tracked_body().set_touch_move_input(Vector2(0, -1))
		if orbit:
			var pivot: Node = game.tracked_body().get_node("CameraPivot")
			pivot._yaw += 0.6 * get_process_delta_time()
			pivot._apply_orbit_rotation()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous)/1000.0)
		previous = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var elapsed := float(now-start)/1000000.0
		if elapsed >= checkpoint:
			checkpoint += 30.0
			print("PAD7_CHECKPOINT ", label, " ", JSON.stringify(_snapshot()))
		if autopilot and blocked_seconds > 15.0: break
	if walk: game.tracked_body().set_touch_move_input(Vector2.ZERO)
	var row := {"stage": label, "seconds": float(Time.get_ticks_usec()-start)/1000000.0,
		"fps": frames.size()*1000000.0/(Time.get_ticks_usec()-start), "frame_ms": _stats(frames),
		"cpu_ms": _stats(cpu), "physics_ms": _stats(physics), "draw_calls": _stats(draws),
		"displacement_m": game.tracked_body().global_position.distance_to(from),
		"settings": game.performance_controller.settings.values.duplicate(), "end": _snapshot()}
	rows.append(row)
	print("PAD7_RESULT ", JSON.stringify(row))
	_save()

func _quality(fps: int, low: bool) -> void:
	var settings: Dictionary = game.performance_controller.settings.values
	settings.fps = fps
	if low:
		settings.scale = 0.5
		settings.distance = 320.0
		settings.simulation = 120.0
		settings.actors = 12
		settings.shadows = false
		settings.effects = 0.25
	game.performance_controller.apply_settings()

func _road_height(point: Vector2) -> float:
	var world := game.get_node("World")
	if point.y < GodavariBridgeBuilder.SOUTH_LAND_Z + 50.0:
		var south := GodavariBridgeBuilder.south_end()
		var north := GodavariBridgeBuilder.north_end()
		var t := clampf((point-south).dot(GodavariBridgeBuilder.forward2())/GodavariBridgeBuilder.BRIDGE_LENGTH, 0, 1)
		return lerpf(world.ground_height(south), world.ground_height(north), t)
	return world.flyover_height_at(point, world.ground_height(point))

func _physics_process(delta: float) -> void:
	if not autopilot: return
	var step := car.global_position.distance_to(last_position)
	if step < 20.0: distance += step
	last_position = car.global_position
	if absf(car.current_speed) > 1.0:
		moving_seconds += delta
		blocked_seconds = 0.0
	else: blocked_seconds += delta
	route_offset = maxf(route_offset, route.get_closest_offset(car.global_position))
	var target := route.sample_baked(minf(route_offset+clampf(absf(car.current_speed)*1.1, 4, 12), route.get_baked_length()))
	var direction := target-car.global_position
	var error := angle_difference(atan2(car.global_basis.z.x, car.global_basis.z.z), atan2(direction.x,direction.z))
	var cruise := 12.0 if absf(error)<0.15 else 6.0 if absf(error)<0.4 else 3.0
	if route_offset > route.get_baked_length()-12.0: cruise = 0.0
	var throttle := 0.8 if car.current_speed<cruise-0.3 else -0.7 if car.current_speed>cruise+0.5 else 0.18
	car.set_touch_move_input(Vector2(-clampf(error*2.3,-1,1), -throttle))

func _run() -> void:
	if FileAccess.file_exists("user://pad7_config.json"):
		config = JSON.parse_string(FileAccess.get_file_as_string("user://pad7_config.json"))
	if FileAccess.file_exists("user://pad7_patch.pck"):
		assert(ProjectSettings.load_resource_pack("user://pad7_patch.pck", true))
		print("PAD7_PATCH_LOADED")
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	game.city_life.save_enabled = false
	print("PAD7_CONTEXT ", JSON.stringify({"device": OS.get_model_name(), "hardware": game.device_performance_manager.hardware_info,
		"settings": game.performance_controller.settings.values, "startup_ms": Time.get_ticks_msec()-started}))
	await get_tree().create_timer(15).timeout
	if not config.get("soak", false):
		_quality(60, false)
		await _sample("default_60", 30)
		_quality(90, false)
		await _sample("default_90", 30)
		_quality(60, true)
		await get_tree().create_timer(5).timeout
		await _sample("low_60", 30)
		_quality(90, true)
		await _sample("low_90", 30)
	_quality(int(config.get("fps", 60)), true)
	await _sample("camera_orbit", 15, false, true)
	for index in 16:
		var yaw := TAU*index/16.0
		if not game.person.test_move(game.person.global_transform, Vector3.FORWARD.rotated(Vector3.UP,yaw)*8):
			game.person.camera_pivot._yaw = yaw
			game.person.camera_pivot._apply_orbit_rotation()
			break
	await _sample("walking", 15, true)
	car = game.get_node("Vehicle") as RigidVehicle
	game.person.global_position = game._door_position(car,-1.0)
	game.enter_vehicle(car)
	for frame in 360:
		if game.control_state == game.ControlState.DRIVING: break
		await get_tree().physics_frame
	if game.control_state != game.ControlState.DRIVING:
		print("PAD7_FAIL entry")
		return
	await _sample("city_driving", 20, true)
	# A separate bridge route tests continuous real vehicle physics and streaming.
	route.bake_interval = 2.0
	for way_id in [-901,-903,-902]:
		for road: Dictionary in game.get_node("World").map_data.roads:
			if road.way_id != way_id: continue
			for point: Vector2 in road.points:
				route.add_point(Vector3(point.x,_road_height(point),point.y))
	print("PAD7_ROUTE ", route.get_baked_length())
	if route.point_count > 1:
		var begin := route.sample_baked(8.0)
		var ahead := route.sample_baked(20.0)-begin
		car._teleport(Transform3D(Basis(Vector3.UP,atan2(ahead.x,ahead.z)),begin+Vector3.UP*0.3))
		car.respawn_position = begin
		car.settle_on_ground()
		await get_tree().create_timer(10).timeout
		last_position = car.global_position
		autopilot = true
		await _sample("route_driving", float(config.get("drive_seconds", 180)))
		autopilot = false
	car.set_touch_move_input(Vector2(0,1))
	await get_tree().create_timer(6).timeout
	car.set_touch_move_input(Vector2.ZERO)
	game.exit_vehicle()
	await get_tree().create_timer(6).timeout
	rows.append({"stage":"exit", "on_foot":game.control_state==game.ControlState.ON_FOOT})
	await _sample("endurance_idle", float(config.get("idle_seconds",60)))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pad7_final.png")
	_save()
	print("PAD7_COMPLETE")
	# Leave the app playable after the measurement, without saving the probe quality.
	set_process(false)
	set_physics_process(false)
