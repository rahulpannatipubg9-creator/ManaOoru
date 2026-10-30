extends SceneTree

## The realistic male rig rests in a T-pose. On foot and unarmed its arms must hang
## beside the body and its elbows must bend forward, never stay horizontal.

var _failures := 0

func _init() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var person: CharacterBody3D = (load("res://scenes/player/person.tscn") as PackedScene).instantiate()
	root.add_child(person)
	for _frame in 20:
		await physics_frame
	var character: Node3D = person.get_node_or_null("TestCharacter")
	# Desktop checkouts also have the test-only lady model; cycle to the male one the tablet ships.
	for _attempt in 3:
		if character == null or character.male_model == null or character.male_model.visible:
			break
		character.toggle_character()
	# process_frame fires before nodes process, so let the pose run twice.
	for _frame in 3:
		await process_frame
	if character == null or character.male_skeleton == null or not character.male_model.visible:
		print("SKIP character arm hang regression: realistic male rig not active")
		quit()
		return
	_check_arms(character, "standing")
	person.set_touch_move_input(Vector2(0.0, -1.0))
	person.set_touch_run_pressed(true)
	for _frame in 45:
		await physics_frame
	_check_arms(character, "running")
	if _failures > 0:
		print("FAIL character arm hang regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS character arm hang regression: unarmed male arms hang (no T-pose) and elbows bend forward, standing and running")
	quit()

func _check_arms(character: Node3D, state: String) -> void:
	var rig: Skeleton3D = character.male_skeleton
	for side in ["L", "R"]:
		var shoulder := _point(character, rig, "CC_Base_%s_Upperarm" % side)
		var elbow := _point(character, rig, "CC_Base_%s_Forearm" % side)
		var wrist := _point(character, rig, "CC_Base_%s_Hand" % side)
		var upper := (elbow - shoulder).normalized()
		var lower := (wrist - elbow).normalized()
		_check(upper.dot(Vector3.DOWN) > 0.7, "%s %s upper arm must point down, not sideways (%s)" % [state, side, upper])
		_check(lower.z > upper.z, "%s %s elbow must bend forward (+Z), upper %s lower %s" % [state, side, upper, lower])

## A bone's head in the character's own space (forward +Z, up +Y).
func _point(character: Node3D, rig: Skeleton3D, bone_name: String) -> Vector3:
	var bone := rig.find_bone(bone_name)
	return character.to_local(rig.to_global(rig.get_bone_global_pose(bone).origin))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
