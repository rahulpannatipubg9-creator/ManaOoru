extends SceneTree

## Crouch and prone poses, hit and death reactions, movement speed by direction, and the synced aim pose of
## remote players (docs/ANIMATION_OVERHAUL_PLAN.md, stages 3 to 6).
## Run: godot --headless --path . --script tests/character_stance_reactions_regression.gd

const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")

var failures := 0
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func bone_height(character: Node, bone: String) -> float:
	var rig: Skeleton3D = character.male_skeleton
	return rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin).y - character.get_parent().global_position.y

func run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var person: CharacterBody3D = (load("res://scenes/player/person.tscn") as PackedScene).instantiate()
	root.add_child(person)
	await frames(20)
	var character: Node3D = person.get_node("TestCharacter")
	for _attempt in 3:
		if character.male_model.visible:
			break
		character.toggle_character()
	await frames(20)
	check(character._crouch_walk != null and character._crouch_idle != null, "the crouch clips are loaded")
	var standing_hip := bone_height(character, "CC_Base_Hip")

	# Crouch: hips well down, and the crouch walk moves the feet.
	person._update_stance(true, false)
	await frames(40)
	var crouched_hip := bone_height(character, "CC_Base_Hip")
	check(standing_hip - crouched_hip > 0.2, "crouching lowers the hips (%.2f m)" % (standing_hip - crouched_hip))
	person.set_touch_move_input(Vector2(0.0, -1.0))
	var rig: Skeleton3D = character.male_skeleton
	var foot := rig.find_bone("CC_Base_L_Foot")
	var low := 9.0
	var high := -9.0
	for _i in 60:
		await physics_frame
		var z: float = person.to_local(rig.to_global(rig.get_bone_global_pose(foot).origin)).z
		low = minf(low, z)
		high = maxf(high, z)
	check(high - low > 0.3, "the crouch walk steps (foot travel %.2f m)" % (high - low))
	person.set_touch_move_input(Vector2.ZERO)

	# Prone: lying down, head lifted, a crawl when moving.
	person._update_stance(false, true)
	await frames(60)
	check(character.male_model.rotation.x > 1.0, "prone lays the body down (%.2f rad)" % character.male_model.rotation.x)
	var thigh := rig.find_bone("CC_Base_L_Thigh")
	var still := rig.get_bone_pose_rotation(thigh)
	person.set_touch_move_input(Vector2(0.0, -1.0))
	var moved := 0.0
	for _i in 60:
		await physics_frame
		moved = maxf(moved, rig.get_bone_pose_rotation(thigh).angle_to(still))
	check(moved > 0.3, "the legs crawl while moving prone (%.2f rad)" % moved)
	person.set_touch_move_input(Vector2.ZERO)
	person._update_stance(false, false)
	await frames(40)

	# Hit: the chest jolts; death: the body falls over and stands back up on reset.
	var chest := rig.find_bone("CC_Base_Spine02")
	await frames(2)
	var before := rig.get_bone_pose_rotation(chest)
	character.play_hit(person.global_position + person.global_basis.z * 10.0)
	await process_frame
	await process_frame
	check(rig.get_bone_pose_rotation(chest).angle_to(before) > 0.05, "a hit jolts the chest")
	character.play_death(person.global_position + person.global_basis.z * 10.0)
	await frames(60)
	check(absf(character.male_model.rotation.x) > 1.2 and character.is_dead(), "a death drops the body over")
	character.reset_death()
	await frames(5)
	check(absf(character.male_model.rotation.x) < 0.3 and not character.is_dead(), "reset stands the body back up")

	# Speed by direction with a rifle out.
	person.combat_mode = true
	person.set_weapon_equipped(true)
	await frames(10)
	var speeds := {}
	for case in [["forward", Vector2(0.0, -1.0)], ["sideways", Vector2(1.0, 0.0)], ["backward", Vector2(0.0, 1.0)]]:
		person.set_touch_move_input(case[1])
		await frames(50)
		speeds[case[0]] = Vector2(person.velocity.x, person.velocity.z).length()
		person.set_touch_move_input(Vector2.ZERO)
		await frames(30)
	check(absf(speeds.forward - person.walk_speed) < 0.2, "forward runs at full speed (%.2f)" % speeds.forward)
	check(absf(speeds.sideways - person.walk_speed * person.strafe_speed_scale) < 0.3, "sideways is slower (%.2f)" % speeds.sideways)
	check(absf(speeds.backward - person.walk_speed * person.backward_speed_scale) < 0.3, "backwards is slower still (%.2f)" % speeds.backward)

	# A remote player who is aiming holds the rifle at the shoulder; a hit makes it flinch; a death drops it.
	var puppet: CharacterBody3D = NetworkPlayerScript.new()
	root.add_child(puppet)
	await frames(5)
	puppet.update_network_state(Vector3(5, 0, 0), 0.0, 0.0, 0, 0.0, true, false)
	await frames(30)
	var hip_rifle: float = puppet.weapon.global_position.y
	puppet.update_network_state(Vector3(5, 0, 0), 0.0, 0.0, 4, 0.0, true, false)
	await frames(30)
	check(puppet.aiming and puppet.stance == 0, "the aim flag is read from the stance code")
	check(puppet.weapon.global_position.y - hip_rifle > 0.2, "an aiming remote player shoulders the rifle (%.2f m higher)" % (puppet.weapon.global_position.y - hip_rifle))
	puppet.notify_hit(Vector3(5, 1, 10))
	puppet.set_tdm_alive(false, false)
	await frames(30)
	check(puppet.visible and puppet.get_node("TestCharacter").is_dead(), "a killed remote player falls and stays briefly")
	puppet.set_tdm_alive(true, false)
	await frames(3)
	check(puppet.visible and not puppet.get_node("TestCharacter").is_dead(), "a respawned remote player stands again")
	print("Character stance and reactions regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
