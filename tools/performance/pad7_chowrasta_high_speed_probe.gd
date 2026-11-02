extends Node

## High-speed driving benchmark in Chowrasta region on Xiaomi Pad 7.
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
var max_speed_kmh := 0.0
var frames_over_120kmh := 0
var total_speed_frames := 0

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
	var ground_y: float = world.ground_height(Vector2(car.global_position.x, car.global_position.z)) if car != null else 0.0
	return {"position": str(game.tracked_body().global_position), "distance_m": distance,
		"moving_seconds": moving_seconds, "blocked_seconds": blocked_seconds,
		"speed_kmh": (car.current_speed if car != null else 0.0) * 3.6,
		"max_speed_kmh": max_speed_kmh,
		"frames_over_120kmh": frames_over_120kmh,
		"car_y": car.global_position.y if car != null else 0.0,
		"ground_y": ground_y,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,
		"tree_pending": world.trees.pending_chunk_count(), "building_pending": world.buildings.pending_chunk_count()}

func _save() -> void:
	var file := FileAccess.open("user://pad7_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"config": config, "results": rows, "snapshot": _snapshot()}, "\t"))
	file.close()

func _sample(label: String, seconds: float) -> void:
	var frames: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var draws: Array[float] = []
	var speeds: Array[float] = []
	var tree_pending_samples: Array[float] = []
	var bld_pending_samples: Array[float] = []
	var wheel_contact_pcts: Array[float] = []
	var tunneling_count: int = 0
	var fall_count: int = 0
	var start := Time.get_ticks_usec()
	var previous := start
	var checkpoint := 0.0
	var from: Vector3 = game.tracked_body().global_position
	var world := game.get_node("World")
	
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		game._window_unfocused = false
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous)/1000.0)
		previous = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		
		var tp: int = world.trees.pending_chunk_count()
		var bp: int = world.buildings.pending_chunk_count()
		tree_pending_samples.append(float(tp))
		bld_pending_samples.append(float(bp))
		
		if car != null:
			speeds.append(absf(car.current_speed) * 3.6)
			var contacts := 0
			for c in car.wheel_contacts:
				if c: contacts += 1
			wheel_contact_pcts.append(float(contacts) / 4.0 * 100.0)
			
			var ground_y: float = world.ground_height(Vector2(car.global_position.x, car.global_position.z))
			# Tunneling: Car chassis drops below ground level by more than 1.2m
			if car.global_position.y < ground_y - 1.2:
				tunneling_count += 1
			# Falling: Car breaches the fall limit margin
			if car.global_position.y < car.fall_limit + 5.0:
				fall_count += 1
				
		var elapsed := float(now-start)/1000000.0
		if elapsed >= checkpoint:
			checkpoint += 10.0
			print("PAD7_CHECKPOINT ", label, " ", JSON.stringify(_snapshot()))
		if autopilot and route_offset >= route.get_baked_length() - 40.0:
			print("PAD7_REACHED_END_OF_CORRIDOR")
			break
	
	var row := {
		"stage": label,
		"seconds": float(Time.get_ticks_usec()-start)/1000000.0,
		"fps": frames.size()*1000000.0/(Time.get_ticks_usec()-start),
		"frame_ms": _stats(frames),
		"cpu_ms": _stats(cpu),
		"physics_ms": _stats(physics),
		"draw_calls": _stats(draws),
		"speed_kmh_stats": _stats(speeds),
		"pending_trees_stats": _stats(tree_pending_samples),
		"pending_buildings_stats": _stats(bld_pending_samples),
		"wheel_contact_stats": _stats(wheel_contact_pcts),
		"tunneling_events": tunneling_count,
		"fall_events": fall_count,
		"collision_integrity_pct": 100.0 if (tunneling_count == 0 and fall_count == 0) else 0.0,
		"displacement_m": game.tracked_body().global_position.distance_to(from),
		"distance_travelled_m": distance,
		"max_speed_kmh": max_speed_kmh,
		"frames_over_120kmh": frames_over_120kmh,
		"end": _snapshot()
	}
	rows.append(row)
	print("PAD7_RESULT ", JSON.stringify(row))
	_save()

func _physics_process(delta: float) -> void:
	if not autopilot or car == null:
		return
	var step := car.global_position.distance_to(last_position)
	if step < 20.0:
		distance += step
	last_position = car.global_position
	
	var current_speed: float = car.current_speed
	var current_kmh := current_speed * 3.6
	total_speed_frames += 1
	if current_kmh > max_speed_kmh:
		max_speed_kmh = current_kmh
	if current_kmh >= 120.0:
		frames_over_120kmh += 1
	
	if absf(current_speed) > 1.0:
		moving_seconds += delta
		blocked_seconds = 0.0
	else:
		blocked_seconds += delta
	
	route_offset = maxf(route_offset, route.get_closest_offset(car.global_position))
	var lookahead := clampf(current_speed * 1.5, 15.0, 50.0)
	var target := route.sample_baked(minf(route_offset + lookahead, route.get_baked_length()))
	var target_dir := target - car.global_position
	var steer_err := angle_difference(atan2(car.global_basis.z.x, car.global_basis.z.z), atan2(target_dir.x, target_dir.z))
	
	# Target 120-135 km/h driving
	var throttle := -1.0
	if current_kmh > 135.0:
		throttle = -0.15
	elif current_kmh < 120.0:
		# Extra engine assist to ensure sustained 120+ km/h test speed
		car.apply_central_force(car.global_basis.z * 18000.0)
	
	var steer := -clampf(steer_err * 2.2, -1.0, 1.0)
	car.set_touch_move_input(Vector2(steer, throttle))

func _run() -> void:
	if FileAccess.file_exists("user://pad7_config.json"):
		config = JSON.parse_string(FileAccess.get_file_as_string("user://pad7_config.json"))
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	game.city_life.save_enabled = false
	
	print("PAD7_CONTEXT ", JSON.stringify({"device": OS.get_model_name(), "hardware": game.device_performance_manager.hardware_info,
		"settings": game.performance_controller.settings.values, "startup_ms": Time.get_ticks_msec()-started}))
	
	await get_tree().create_timer(10).timeout
	
	# Use Porsche 911 or default vehicle
	car = game.get_node_or_null("Porsche 911") as RigidVehicle
	if not car:
		car = game.get_node("Vehicle") as RigidVehicle
	
	var world := game.get_node("World")
	route.bake_interval = 2.0
	for road: Dictionary in world.map_data.roads:
		if road.way_id == 73822838: # Chowrasta 1.8km arterial road
			for pt: Vector2 in road.points:
				var h: float = world.ground_height(pt)
				route.add_point(Vector3(pt.x, h, pt.y))
			break
	
	print("PAD7_ROUTE Chowrasta length: ", route.get_baked_length(), "m")
	var start_pos := route.sample_baked(5.0)
	var next_pos := route.sample_baked(20.0)
	var ahead := next_pos - start_pos
	var yaw := atan2(ahead.x, ahead.z)
	car._teleport(Transform3D(Basis(Vector3.UP, yaw), start_pos + Vector3.UP * 0.3))
	car.settle_on_ground()
	
	game.enter_vehicle(car)
	await get_tree().create_timer(2).timeout
	
	last_position = car.global_position
	route_offset = 5.0
	autopilot = true
	
	# Stage 1: Sustained High-Speed driving in Chowrasta corridor at 120+ km/h
	await _sample("chowrasta_120kmh_drive", 45.0)
	autopilot = false
	car.set_touch_move_input(Vector2(0, 1.0)) # Brake
	await get_tree().create_timer(4).timeout
	car.set_touch_move_input(Vector2.ZERO)
	
	# Stage 2: Post-speed cooldown idle (verify memory, streaming recovery)
	await _sample("chowrasta_post_speed_idle", 15.0)
	
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pad7_final.png")
	_save()
	print("PAD7_COMPLETE")
	set_process(false)
	set_physics_process(false)

