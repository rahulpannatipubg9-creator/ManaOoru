extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var roads := RoadBuilder.new()
	root.add_child(roads)
	var active := Node3D.new()
	var detached := Node3D.new()
	roads.add_child(active)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	detached.add_child(mesh)
	roads.set("_sectors", {Vector2i.ZERO: active, Vector2i.ONE: detached})
	roads.set("_active_sectors", {Vector2i.ZERO: true})
	roads.free()
	await process_frame
	assert(not is_instance_valid(active), "Attached sector must be freed with roads")
	assert(not is_instance_valid(detached), "Detached streamed road sector leaked")
	var buildings := BuildingBuilder.new()
	root.add_child(buildings)
	var cached := Node3D.new()
	buildings.set("_chunk_cache", {Vector2i.ZERO: cached})
	buildings.free()
	await process_frame
	assert(not is_instance_valid(cached), "Detached building cache leaked")
	print("PASS streaming cleanup: attached and detached road sectors, building cache")
	quit()
