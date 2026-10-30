extends SceneTree

func _init() -> void:
	var scene := load("res://assets/models/characters/gdk_realistic_male_rigged.glb") as PackedScene
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		print("Male mesh=", mesh.name, " skin_bound=", mesh.skin != null, " skeleton_path=", mesh.skeleton)
	for skeleton: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		print("Male skeleton=", skeleton.name, " bones=", skeleton.get_bone_count())
	quit()
