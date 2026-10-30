extends SceneTree

func _init() -> void:
	var model_scene := load("res://assets/models/helicopter/gdk_chowrasta_helicopter.glb") as PackedScene
	var model := model_scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		print("Helicopter mesh local dimensions=", mesh.get_aabb().size, " transform=", mesh.transform)
	quit()
