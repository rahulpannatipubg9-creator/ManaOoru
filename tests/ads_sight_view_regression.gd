extends SceneTree

## BGMI/PUBG aiming: scoping from third person looks down the sight in first person
## without moving the aim point, and releasing returns to third person. A player who
## chose first person stays there after aiming.

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
	for _frame in 10:
		await physics_frame
	var pivot: Node3D = person.get_node("CameraPivot")
	var camera: Camera3D = pivot.get_node("SpringArm3D/Camera3D")
	person.combat_mode = true
	person.set_weapon_equipped(true)
	for _frame in 10:
		await process_frame
	_check(not pivot.is_first_person(), "Third person must be the starting view")
	var look_before := -camera.global_basis.z
	var fov_before := camera.fov
	pivot.touch_aim = true
	for _frame in 30:
		await process_frame
	_check(pivot.is_aiming, "Scope must aim with an equipped rifle in action mode")
	_check(pivot.is_first_person() and pivot.is_sight_view(), "Scoping from TPP must look down the sight in first person")
	var look_aiming := -camera.global_basis.z
	_check(look_before.angle_to(look_aiming) < 0.05, "Scoping must keep the aim direction (%.3f rad drift)" % look_before.angle_to(look_aiming))
	_check(camera.fov < fov_before - 10.0, "Scoping must zoom (%.1f -> %.1f)" % [fov_before, camera.fov])
	pivot.touch_aim = false
	for _frame in 30:
		await process_frame
	_check(not pivot.is_first_person() and not pivot.is_sight_view(), "Releasing scope must return to third person")
	_check(look_aiming.angle_to(-camera.global_basis.z) < 0.05, "Leaving the sight must keep the aim direction")
	pivot.set_view_mode(pivot.ViewMode.FIRST_PERSON)
	pivot.touch_aim = true
	for _frame in 20:
		await process_frame
	pivot.touch_aim = false
	for _frame in 20:
		await process_frame
	_check(pivot.is_first_person(), "A player who chose FPP must stay in FPP after aiming")
	if _failures > 0:
		print("FAIL ADS sight view regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS ADS sight view regression: TPP scope enters the sight view with the aim held, zooms, returns to TPP; chosen FPP is kept")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
