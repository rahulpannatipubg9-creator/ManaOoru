extends SceneTree

func _init() -> void:
	var path := "res://assets/models/characters/player_character_rigged.glb"
	if not ResourceLoader.exists(path):
		print("FAIL: Model does not exist")
		quit(1)
		return
	var scene := load(path) as PackedScene
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var found_mesh := false
	var found_skeleton := false
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		print("Player mesh=", mesh.name, " skin_bound=", mesh.skin != null, " skeleton_path=", mesh.skeleton)
		found_mesh = true
	for skeleton: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		print("Player skeleton=", skeleton.name, " bones=", skeleton.get_bone_count())
		found_skeleton = true
	if found_mesh and found_skeleton:
		print("PASS: Player character is fully rigged and skin-bound in Godot!")
	else:
		print("FAIL: Missing mesh or skeleton")
	quit(0)
