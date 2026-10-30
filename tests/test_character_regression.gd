extends SceneTree

const TestCharacter := preload("res://scripts/player/test_character.gd")
var _failures := 0

func _init() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 10:
		await physics_frame
	var person := game.get_node("Player") as CharacterBody3D
	var stand_in := person.get_node("TestCharacter")
	if not ResourceLoader.exists(TestCharacter.MODEL_PATH):
		_check(not stand_in.is_active() and (person.get_node("Body") as MeshInstance3D).mesh != null,
			"Without the local test model the block figure must stay")
		_finish("SKIP test character regression: no local test model; block figure kept")
		return
	_check(stand_in.is_active(), "Local test model must load onto the person")
	for mesh_name in ["Body", "Head", "Legs"]:
		_check((person.get_node(mesh_name) as MeshInstance3D).mesh == null, "Block figure %s must be hidden" % mesh_name)
	var model: Node3D = stand_in.model
	var height := _height(model)
	_check(absf(height - TestCharacter.TARGET_HEIGHT) < 0.15, "Test model must be person-sized (%.2f m)" % height)
	var skeleton: Skeleton3D = stand_in.skeleton
	var thigh := skeleton.find_bone("DEF-thigh.L")
	var idle_pose := skeleton.get_bone_pose_rotation(thigh)
	person.set_touch_move_input(Vector2(0.0, -1.0))
	var swing := 0.0
	for _frame in 60:
		await physics_frame
		swing = maxf(swing, skeleton.get_bone_pose_rotation(thigh).angle_to(idle_pose))
	_check(swing > 0.3, "Legs must swing while walking (%.2f rad)" % swing)
	var feet_ok := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		feet_ok = feet_ok and mesh.visible
	_check(feet_ok, "Every part of the test model must stay visible")
	_finish("PASS test character regression: local model loads, block figure hidden, person-sized, walk cycle animates")

func _height(model: Node3D) -> float:
	var top := -INF
	var bottom := INF
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	return top - bottom

func _finish(message: String) -> void:
	if _failures > 0:
		print("FAIL test character regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print(message)
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
