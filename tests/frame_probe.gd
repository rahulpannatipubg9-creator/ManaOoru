extends SceneTree

## Measures in-game frame time at Chowrastha in a real window. Not a pass/fail test.
##   run_godot.sh 400 --path . --windowed --resolution 1920x1080 --script tests/frame_probe.gd -- [Medium] [cases]
## cases, comma separated, each held for HOLD seconds with the frame cap off:
##   base, scale50, scale100, noshadow, notrees, nosky, far200
## Prints one line per case: fps, frame-time percentiles, process and physics time, draw calls.

const WARM_SECONDS := 6.0
const HOLD_SECONDS := 8.0

var game: Node3D
var world: Node3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var preset: String = args[0] if args.size() > 0 else "Medium"
	var cases: PackedStringArray = (args[1] if args.size() > 1 else "base").split(",")
	var started := Time.get_ticks_msec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	print("probe: scene ready %d ms" % (Time.get_ticks_msec() - started))
	await process_frame
	print("probe: first frame %d ms" % (Time.get_ticks_msec() - started))
	await process_frame
	print("probe: second frame %d ms" % (Time.get_ticks_msec() - started))
	world = game.get_node("World")
	game.city_life.save_enabled = false
	game.performance_controller.settings.select(preset)
	game.performance_controller.apply_settings()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("probe: preset %s, window %s, viewport 3D size %s, renderer %s, adapter %s" % [preset, DisplayServer.window_get_size(),
		root.get_visible_rect().size, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	await create_timer(WARM_SECONDS).timeout
	print("probe: streaming left: %d building chunks, %d tree chunks" % [world.buildings.pending_chunk_count(), world.trees.pending_chunk_count()])
	for name: String in cases:
		_apply_case(name)
		await create_timer(1.5).timeout
		await _sample(name)
		_undo_case(name)
	quit(0)

func _apply_case(name: String) -> void:
	match name:
		"scale50":
			root.scaling_3d_scale = 0.5
		"scale100":
			root.scaling_3d_scale = 1.0
		"noshadow":
			game.get_node("Sun").shadow_enabled = false
		"notrees":
			world.trees.visible = false
		"nosky":
			game.get_node("DayEnvironment").environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		"far200":
			game.performance_controller.settings.values.distance = 250.0
			game.performance_controller.apply_settings()
			Engine.max_fps = 0

func _undo_case(name: String) -> void:
	match name:
		"scale50", "scale100":
			root.scaling_3d_scale = game.performance_controller.settings.values.scale
		"noshadow":
			game.get_node("Sun").shadow_enabled = true
		"notrees":
			world.trees.visible = true

func _sample(name: String) -> void:
	var frames := PackedFloat64Array()
	var process_ms := 0.0
	var physics_ms := 0.0
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	var gpu_ms := 0.0
	var cpu_ms := 0.0
	var last := Time.get_ticks_usec()
	var begin := last
	while Time.get_ticks_usec() - begin < int(HOLD_SECONDS * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	var count := float(frames.size())
	var total := 0.0
	for frame in frames:
		total += frame
	var sorted := frames.duplicate()
	sorted.sort()
	print("probe: %-9s fps %6.1f | ms p50 %6.1f p95 %6.1f p99 %6.1f max %6.1f | process %5.2f physics %5.2f render-cpu %5.2f gpu %5.2f | draws %5.0f objects %5.0f tris %8.0f | frames %d" % [
		name, count * 1000.0 / total, sorted[int(count * 0.5)], sorted[int(count * 0.95)], sorted[int(count * 0.99)], sorted[-1],
		process_ms / count, physics_ms / count, cpu_ms / count, gpu_ms / count, draws / count, objects / count, primitives / count, int(count)])
