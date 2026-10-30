extends SceneTree

func _init() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	collision.shape = shape
	collision.position.y = -0.5
	ground.add_child(collision)
	root.add_child(ground)
	var scene := load("res://scenes/player/person.tscn") as PackedScene
	var person := scene.instantiate() as CharacterBody3D
	root.add_child(person)
	await process_frame
	var visual := person.get_node("TestCharacter")
	assert(visual.male_model.visible, "Rahul must be the default character")
	var skeleton: Skeleton3D = visual.male_skeleton
	assert(skeleton != null, "Male walk/run rig missing")
	person.set_touch_move_input(Vector2(0.0, -1.0))
	person.set_touch_run_pressed(true)
	for _frame in 45:
		await physics_frame
		await process_frame
	for bone_name in ["CC_Base_L_Upperarm", "CC_Base_R_Upperarm", "CC_Base_L_Thigh", "CC_Base_R_Thigh"]:
		var index := skeleton.find_bone(bone_name)
		assert(index >= 0, "Required locomotion bone missing: %s" % bone_name)
		var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var pose := skeleton.get_bone_pose_rotation(index)
		assert(rest.angle_to(pose) > 0.02, "%s must animate while running" % bone_name)
	visual.seated = true
	await process_frame
	var seated_arm := skeleton.find_bone("CC_Base_L_Upperarm")
	var seated_rest := skeleton.get_bone_rest(seated_arm).basis.get_rotation_quaternion()
	assert(seated_rest.angle_to(skeleton.get_bone_pose_rotation(seated_arm)) > 0.3,
		"Male arm must reach the steering wheel while seated")
	print("PASS male locomotion regression: arm and leg cycles animate during running")
	quit()
