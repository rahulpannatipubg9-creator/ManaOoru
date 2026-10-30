extends SceneTree

## Rahul's AK-47 stance (tools/rahul_character, 15_rifle.py) layered over his locomotion in
## scripts/player/test_character.gd: with a rifle out the clips set the body, the arms still reach the
## game's own rifle, the feet stay on the ground, and a standing peek leans the upper body to the same side
## as the camera's peek instead of tipping the whole model.

const GameplayControls := preload("res://scripts/player/gameplay_controls.gd")
const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
## Wrist to grip target, metres: the arm solve reaches it whenever the target is within the arm's length.
const MAX_GRIP_GAP := 0.03

var _failures := 0
var person: CharacterBody3D
var visual: Node3D

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	person = (load("res://scenes/player/person.tscn") as PackedScene).instantiate()
	root.add_child(person)
	await frames(5)
	visual = person.get_node("TestCharacter")
	# Combat mode: the body turns to the camera's aim, so the camera sits behind it as in a match.
	person.combat_mode = true
	_check(visual._rifle_clips.size() == visual.RIFLE_CLIPS.size(), "The AK-47 stance clips are loaded")

	# Unarmed standing peek tips the whole model toward the side of the peek: Q ("< PEEK", -1) is left, and
	# +x is the character's left.
	await frames(30)
	var head_rest := person.to_local(_head_world())
	person.touch_peek_input = -1.0
	await frames(40)
	var unarmed_head: float = person.to_local(_head_world()).x - head_rest.x
	_check(visual.male_model.rotation.z < -0.2 and unarmed_head > 0.15,
		"Unarmed Q peek tips the whole model to the character's left (%.2f rad, head %.2f m)" % [visual.male_model.rotation.z, unarmed_head])
	person.touch_peek_input = 0.0
	await frames(30)

	person.set_weapon_equipped(true)
	await frames(40)
	_check(visual._armed > 0.95, "Drawing the rifle blends the stance in (%.2f)" % visual._armed)
	_check(visual._rifle_body > 0.9, "Standing armed: the rifle clips set the chest (%.2f)" % visual._rifle_body)
	_grips("standing at the low ready")
	_feet_on_ground("standing at the low ready")

	# Armed: the camera is behind the shoulder; measure along its screen-right axis.
	var camera := person.get_viewport().get_camera_3d()
	var screen_right := camera.global_basis.x
	var camera_rest := camera.global_position
	var armed_rest := _head_world()
	person.touch_peek_input = -1.0
	await frames(40)
	var camera_side := (camera.global_position - camera_rest).dot(screen_right)
	var armed_head := (_head_world() - armed_rest).dot(screen_right)
	_check(absf(visual.male_model.rotation.z) < 0.03, "Armed standing peek keeps the feet planted, not the model tipped (%.3f rad)" % visual.male_model.rotation.z)
	_check(armed_head < -0.08, "Armed Q peek leans the upper body to the screen's left (head %.2f m)" % armed_head)
	_check(camera_side < -0.3, "Q peek slides the camera to the screen's left (%.2f m)" % camera_side)
	_check(camera.global_basis.x.y > 0.1, "Q peek rolls the view to the left (screen-right axis up %.2f)" % camera.global_basis.x.y)
	_grips("peeking")
	_feet_on_ground("peeking")
	person.touch_peek_input = 0.0
	await frames(30)

	person.set_touch_move_input(Vector2(0.0, -1.0))
	await frames(60)
	_check(visual._rifle_body > 0.8, "Jogging armed: the rifle jog sets the chest (%.2f)" % visual._rifle_body)
	_grips("jogging")
	person.set_touch_run_pressed(true)
	await frames(60)
	_check(visual._rifle_body > 0.8, "Sprinting armed: the rifle sprint sets the chest (%.2f)" % visual._rifle_body)
	_grips("sprinting")
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)
	await frames(40)

	# Exploration mode with the rifle out: the body does not turn to the aim, the hands must still reach.
	person.combat_mode = false
	await frames(40)
	_grips("exploration mode, standing")
	person.combat_mode = true

	person.set_weapon_equipped(false)
	await frames(60)
	_check(visual._armed < 0.05, "Holstering fades the rifle stance out (%.2f)" % visual._armed)

	# A remote player aiming (stance bit 4) takes the scoped stance with the hands on its rifle.
	var puppet: CharacterBody3D = NetworkPlayerScript.new()
	root.add_child(puppet)
	await frames(2)
	var remote: Node3D = puppet.get_node_or_null("TestCharacter")
	_check(remote != null and not remote._rifle_clips.is_empty(), "A remote player is Rahul with the rifle clips")
	if remote != null:
		for _i in 40:
			puppet.update_network_state(Vector3.ZERO, 0.0, 0.0, 4 | (Weapons.AK47 << 3), 0.0, true, false)
			await process_frame
		_check(remote._aim > 0.95 and remote._rifle_body > 0.9, "Remote aim blends the scoped stance in (aim %.2f, body %.2f)" % [remote._aim, remote._rifle_body])
		visual = remote
		_grips("remote player aiming")
	puppet.queue_free()

	if _failures > 0:
		print("FAIL rahul rifle stance regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS rahul rifle stance regression: rifle clips set the stance standing, jogging, sprinting and peeking; hands reach the rifle (local, exploration, remote aiming); feet planted")
	quit()

func frames(n: int) -> void:
	for _i in n:
		GameplayControls.blocked = false
		await physics_frame
	await process_frame

func _head_world() -> Vector3:
	var skeleton: Skeleton3D = visual.male_skeleton
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("CC_Base_Head")).origin)

func _grips(label: String) -> void:
	var skeleton: Skeleton3D = visual.male_skeleton
	for side in ["L", "R"]:
		var hand := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("CC_Base_%s_Hand" % side)).origin)
		var target: Vector3 = visual.to_global(visual.left_grip_target if side == "L" else visual.right_grip_target)
		var gap := hand.distance_to(target)
		_check(gap < MAX_GRIP_GAP, "%s: %s hand on the rifle (%.3f m from its grip)" % [label, side, gap])

func _feet_on_ground(label: String) -> void:
	var skeleton: Skeleton3D = visual.male_skeleton
	for side in ["L", "R"]:
		var toe := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("CC_Base_%s_ToeBase" % side)).origin)
		var height := toe.y - person.global_position.y
		_check(height > -0.03 and height < 0.08, "%s: %s foot on the ground (toe joint %.3f m up)" % [label, side, height])

func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
