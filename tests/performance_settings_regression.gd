extends SceneTree
const Settings := preload("res://scripts/performance/graphics_settings.gd")
class StreamProbe extends BuildingBuilder:
	func _build_chunk(cell: Vector2i) -> void:
		if _built.has(cell): return
		_built[cell] = true
		var chunk := Node3D.new()
		add_child(chunk)
		_stream_nodes[cell] = chunk

func _init() -> void: run.call_deferred()
func run() -> void:
	var settings := Settings.new()
	assert(settings.resolve_auto(true, 3 * 1024 * 1024 * 1024) == "Low")
	assert(settings.resolve_auto(true, 8 * 1024 * 1024 * 1024) == "Medium")
	settings.select("Low")
	assert(settings.values.scale < 1.0 and not settings.values.shadows and settings.values.fps == 30)
	var low_actors: int = settings.values.actors
	settings.select("High")
	assert(settings.values.actors > low_actors)
	settings.select("Custom")
	settings.values.scale = 0.7
	settings.values.actors = 13
	assert(settings.save_to("user://graphics_test.cfg") == OK)
	var restored := Settings.new()
	restored.load_from("user://graphics_test.cfg")
	assert(restored.preset == "Custom" and is_equal_approx(restored.values.scale, 0.7) and restored.values.actors == 13)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://graphics_test.cfg"))
	var builder := StreamProbe.new()
	root.add_child(builder)
	builder.set_process(false)
	builder.stream_radius = 320.0
	builder._chunks[Vector2i(0, 0)] = PackedInt32Array([0])
	builder._chunks[Vector2i(30, 0)] = PackedInt32Array([1])
	builder._pending.assign(builder._chunks.keys())
	builder._refresh_stream(Vector2.ZERO)
	assert(builder._pending.has(Vector2i(0, 0)) and not builder._pending.has(Vector2i(30, 0)), "Only nearby geometry is queued")
	builder._build_chunk(Vector2i(0, 0))
	builder._refresh_stream(Vector2(4800, 0))
	assert(not builder._built.has(Vector2i(0, 0)) and builder._pending.has(Vector2i(30, 0)), "Travel unloads distant chunks and queues destination")
	builder._refresh_stream(Vector2.ZERO)
	assert(builder._pending.has(Vector2i(0, 0)), "Returning queues an unloaded neighbourhood again")
	builder.queue_free()
	await process_frame
	print("PASS graphics settings: Auto tiers, presets, custom persistence, nearby queue, unload and return")
	quit(0)
