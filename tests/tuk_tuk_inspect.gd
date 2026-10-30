extends SceneTree

func _init() -> void:
	var scene := load("res://assets/models/tuk_tuk/gdk_tuk_tuk.glb") as PackedScene
	assert(scene != null, "Tuk-tuk scene did not load")
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert(not meshes.is_empty(), "Tuk-tuk contains no meshes")
	var bounds := AABB()
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var local_bounds := mesh_node.get_aabb()
		bounds = local_bounds if bounds.size == Vector3.ZERO else bounds.merge(local_bounds)
	print("TUK_TUK meshes=%d local_bounds=%s root=%s" % [meshes.size(), bounds, model.position])
	quit()
