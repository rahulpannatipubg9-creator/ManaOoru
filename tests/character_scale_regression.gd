extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/player/person.tscn") as PackedScene
	var person := scene.instantiate() as CharacterBody3D
	root.add_child(person)
	await process_frame
	var visual := person.get_node("TestCharacter")
	assert(visual.is_active() and visual.male_model.visible and (visual.model == null or not visual.model.visible),
		"Rahul (the player's likeness) must be the default visual")
	assert(visual.male_skeleton != null and visual._male_bones.size() >= 8,
		"Realistic male must provide a locomotion-capable arm and leg rig")
	var male_bounds := AABB()
	var male_first := true
	for mesh: MeshInstance3D in visual.male_model.find_children("*", "MeshInstance3D", true, false):
		var male_box: AABB = mesh.global_transform * mesh.get_aabb()
		male_bounds = male_box if male_first else male_bounds.merge(male_box)
		male_first = false
	print("Male rendered bounds=", male_bounds)
	assert(male_bounds.size.y > 1.5 and male_bounds.size.y < 1.9,
		"Realistic male must be upright and match the lady character height")
	# Relative to the person: there is no floor here, so the body is already falling in world space.
	var sole := male_bounds.position.y - person.global_position.y
	print("Male soles above the person origin=", sole)
	assert(sole > -0.05 and sole < 0.05,
		"Realistic male must stand on the person's floor: not sunk below it, not floating above it")
	assert(visual.toggle_character() == "Legacy Avatar", "Legacy avatar must remain selectable")
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
