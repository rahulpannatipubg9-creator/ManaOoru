extends SceneTree

## Opt-in rendered test: --script res://scripts/performance/frame_profile.gd
## Uses real gameplay controllers. Does not run in normal gameplay or save settings.
var game: Node
var results: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _sample(label: String, seconds: float, moving := false) -> void:
	var frames: Array[float] = []
	var render: Array[float] = []
	var draws: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		game._window_unfocused = false # The automated desktop fixture owns its input.
		if moving:
			game.tracked_body().set_touch_move_input(Vector2(0, -1))
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		render.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	var result: Dictionary = {"stage": label, "fps": frames.size() * 1000000.0 / (Time.get_ticks_usec() - start),
		"frame_ms": _stats(frames, true), "render_cpu_ms": _stats(render), "draw_calls": _stats(draws),
		"tree_chunks": game.get_node("World").trees.get_child_count(),
		"tree_pending": game.get_node("World").trees.pending_chunk_count()}
	results.append(result)
	print("FRAME_PROFILE ", JSON.stringify(result))

func _stats(values: Array[float], frame_times := false) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	for value in values:
		total += value
		if value > 33.34: over_33 += 1
		if value > 50.0: over_50 += 1
	var summary := {"frames": values.size(), "mean": total / values.size(), "p50": values[values.size() / 2],
		"p95": values[int(values.size() * 0.95)], "p99": values[int(values.size() * 0.99)],
		"max": values[-1]}
	if frame_times:
		summary["over_33ms"] = over_33
		summary["over_50ms"] = over_50
	return summary

func _run() -> void:
	# Optional developer harness in the isolated, debug-only performance app.
	# Allows longer device tests without transferring the complete asset pack again.
	if OS.has_feature("android") and FileAccess.file_exists("user://stress_test.gd"):
		root.add_child(load("user://stress_test.gd").new())
		return
	# The side-by-side Android performance copy profiles on first launch, then
	# behaves as a normal game on subsequent launches. Original app data is separate.
	if OS.has_feature("android") and FileAccess.file_exists("user://performance_profile.json"):
		change_scene_to_file("res://scenes/main.tscn")
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Test the requested target without replacing the player's saved quality choices.
	game.performance_controller.settings.values.fps = 60
	game.performance_controller.apply_settings()
	print("PROFILE_CONTEXT ", JSON.stringify({"device": OS.get_model_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "mobile": OS.has_feature("mobile"),
		"settings": game.performance_controller.settings.values, "probe": "tree-streaming-v1"}))
	await create_timer(8.0).timeout
	await _sample("idle", 12.0)
	var person: CharacterBody3D = game.person
	for index in 16:
		var yaw := TAU * index / 16.0
		if not person.test_move(person.global_transform, Vector3.FORWARD.rotated(Vector3.UP, yaw) * 5.0):
			person.camera_pivot._yaw = yaw
			person.camera_pivot._apply_orbit_rotation()
			break
	var start := person.global_position
	await _sample("walking", 10.0, true)
	person.set_touch_move_input(Vector2.ZERO)
	results[-1]["distance_m"] = person.global_position.distance_to(start)
	var car: PhysicsBody3D = game.get_node("Vehicle")
	person.set_movement_enabled(false)
	person.global_position = game._door_position(car, -1.0)
	game.enter_vehicle(car)
	for frame in 360:
		if game.control_state == game.ControlState.DRIVING: break
		await physics_frame
	if game.control_state == game.ControlState.DRIVING:
		start = car.global_position
		await _sample("driving", 10.0, true)
		car.set_touch_move_input(Vector2.ZERO)
		results[-1]["distance_m"] = car.global_position.distance_to(start)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://performance_probe.png")
	else:
		results.append({"stage": "driving", "error": "vehicle entry did not complete"})
	var file := FileAccess.open("user://performance_profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PROFILE_COMPLETE ", ProjectSettings.globalize_path("user://performance_profile.json"))
	game.queue_free()
	for frame in 8: await process_frame
	quit()
