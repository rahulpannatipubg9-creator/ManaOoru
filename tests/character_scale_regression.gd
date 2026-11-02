extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/player/person.tscn") as PackedScene
	var person := scene.instantiate() as CharacterBody3D
	root.add_child(person)
	await process_frame
	var visual := person.get_node("TestCharacter")
	var active_model: Node3D = visual.mixamo_model if (visual.mixamo_model and visual.mixamo_model.visible) else visual.male_model
	assert(visual.is_active() and active_model != null and active_model.visible and (visual.model == null or not visual.model.visible),
		"Character must be the default visual")
	var char_bounds: AABB = active_model.global_transform * visual._skinned_model_bounds(active_model)
	print("Character rendered bounds=", char_bounds)
	assert(char_bounds.size.y > 1.5 and char_bounds.size.y < 1.9,
		"Default character must be upright and match player height")
	if visual.mixamo_model != null and visual.mixamo_model.visible:
		assert(absf(char_bounds.size.y - visual.DEFAULT_MIXAMO_HEIGHT) < 0.03,
			"Default Mixamo character must match the configured 1.73m height")
		assert(absf(person.stand_height - visual.DEFAULT_MIXAMO_HEIGHT) < 0.001,
			"Standing collision height must match the default character")
	var sole := char_bounds.position.y - person.global_position.y
	print("Character soles above the person origin=", sole)
	assert(sole > -0.05 and sole < 0.05,
		"Default character must stand on the person's floor: not sunk below it, not floating above it")
	if active_model == visual.mixamo_model:
		for clip in ["Arm_Stretching", "Start_Walking", "Jogging", "Sitting"]:
			visual.set_process(false)
			visual.mixamo_anim_player.play(clip)
			for sample in [0.0, 0.3, 0.8]:
				visual.mixamo_anim_player.seek(sample, true)
				var animated: AABB = active_model.global_transform * visual._skinned_model_bounds(active_model)
				assert(animated.size.length() < 3.5, "Animated Soldier must remain human sized: " + clip)
				assert(active_model.scale.x < 1.1, "Skin units must not be multiplied twice")
				print(clip, " at ", sample, " skinned bounds=", animated.size)
	var next_char: String = visual.toggle_character()
	if next_char == "Rahul":
		assert(visual.toggle_character() == "Legacy Avatar", "Legacy avatar must remain selectable")
	else:
		assert(next_char == "Legacy Avatar", "Legacy avatar must remain selectable")
	if visual.model == null:
		assert(visual.toggle_character() == "Rahul", "Without the test-only lady, AVATAR returns to Rahul")
		print("PASS character scale: Rahul default, legacy selectable (no test-only lady in this checkout)")
		quit()
		return
	assert(visual.toggle_character() == "Lady Character", "The test-only lady stays selectable on desktop")
	var model: Node3D = visual.model
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	print("Character visual scale=", model.scale, " rendered height=", bounds.size.y)
	assert(bounds.size.y <= 1.75, "Default character must remain at player height")
	quit()
