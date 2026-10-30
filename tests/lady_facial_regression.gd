extends SceneTree

func _init() -> void:
	var person_scene := load("res://scenes/player/person.tscn") as PackedScene
	assert(person_scene != null, "Person scene must load")
	var person := person_scene.instantiate() as CharacterBody3D
	root.add_child(person)
	await process_frame
	var character := person.get_node_or_null("TestCharacter")
	assert(character != null and character.skeleton != null, "Lady character skeleton missing")
	for bone_name in ["head", "DEF-jaw", "DEF-eye.L", "DEF-eye.R"]:
		assert(character.skeleton.find_bone(bone_name) >= 0, "Lady face bone missing: %s" % bone_name)
	var eye: int = character.skeleton.find_bone("DEF-eye.L")
	var before: Quaternion = character.skeleton.get_bone_pose_rotation(eye)
	character._face_time += 1.0
	character._pose_lady_face(0.0)
	var after: Quaternion = character.skeleton.get_bone_pose_rotation(eye)
	assert(not before.is_equal_approx(after), "Lady eye performance remained static")
	print("PASS lady facial regression: eye, head and jaw performance controls")
	quit()
