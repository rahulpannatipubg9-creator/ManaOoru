extends SceneTree

## Remote players in a match are the real character, not capsules: same rig, gait clips, rifle hold, armband and
## protection glow as the local player (scripts/network/network_player.gd).
## Run: godot --headless --path . --script tests/tdm_remote_character_regression.gd

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

func run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 1.0, 300.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var puppet: CharacterBody3D = NetworkPlayerScript.new()
	puppet.peer_id = 7
	puppet.nickname = "Kiran"
	root.add_child(puppet)
	for _i in 5:
		await physics_frame
	check(puppet.has_character(), "the remote player uses the character rig")
	var character: Node3D = puppet.get_node_or_null("TestCharacter")
	check(character != null and character.male_skeleton != null and character.male_model.visible, "the realistic character is visible")
	check(character != null and character.skeleton == null, "the desktop-only test model is not loaded for remote players")
	check(not puppet.get_node("VisualRoot").visible, "the placeholder capsules are hidden")
	check(puppet.weapon != null and puppet.weapon.visible, "the rifle is shown while armed")
	if puppet.weapon != null:
		check(not puppet.weapon.find_child("M416_part_2", true, false).visible, "the loose rifle parts are hidden")
		check(puppet.weapon.is_ancestor_of(puppet._muzzle_flash), "the muzzle flash sits on the rifle")
	check(puppet.is_weapon_equipped() and puppet.puppet_on_floor(), "it reports the same state queries as the local person")

	# Walk forwards at the game's walk speed: the body moves, the gait clips run, the legs swing.
	var left_foot: int = character.male_skeleton.find_bone("CC_Base_L_Foot")
	var low := 9.0
	var high := -9.0
	var position := Vector3.ZERO
	for _i in 120:
		position += puppet.global_basis.z * 4.2 / 60.0
		puppet.update_network_state(position, puppet.rotation.y, -0.1, 0, 0.0, true, false)
		await physics_frame
		var foot_local: Vector3 = puppet.to_local(character.male_skeleton.to_global(character.male_skeleton.get_bone_global_pose(left_foot).origin))
		low = minf(low, foot_local.z)
		high = maxf(high, foot_local.z)
	var speed := Vector2(puppet.velocity.x, puppet.velocity.z).length()
	check(speed > 3.0 and speed < 5.5, "the speed is read from the synced movement (%.2f m/s)" % speed)
	check(high - low > 0.5, "the legs swing while it walks (foot travel %.2f m)" % (high - low))
	check(character._clip_weight > 0.9, "the gait clips drive the pose")

	# Team armband and protection glow.
	puppet.set_tdm_team(1, true)
	var attachment: Node = character.male_skeleton.get_node_or_null("ArmbandAttachment")
	check(attachment != null and attachment.get_child_count() == 1, "a team armband is attached to the left arm bone")
	puppet.set_tdm_alive(true, true)
	var glowing := false
	for mesh_node in character.find_children("*", "MeshInstance3D", true, false):
		glowing = glowing or (mesh_node as MeshInstance3D).material_overlay != null
	check(glowing, "spawn protection puts a glow on the character")
	puppet.set_tdm_alive(true, false)
	var still_glowing := false
	for mesh_node in character.find_children("*", "MeshInstance3D", true, false):
		still_glowing = still_glowing or (mesh_node as MeshInstance3D).material_overlay != null
	check(not still_glowing, "the glow ends with the protection")
	puppet.set_tdm_alive(false, false)
	await physics_frame
	check(puppet.visible and puppet._collision.disabled, "a dead player falls and can no longer be hit")
	for _i in int(puppet.BODY_SECONDS * 60.0) + 20:
		await physics_frame
	check(not puppet.visible, "the body disappears after a moment")
	puppet.set_tdm_alive(true, false)
	puppet.update_network_state(position, puppet.rotation.y, 0.0, 1, 0.0, true, false)
	await physics_frame
	check(puppet.crouching and not puppet.prone, "a crouching stance is passed to the animation")
	check(puppet.is_head_hit(puppet.global_position.y + puppet._capsule.height - 0.1), "head hits are still recognised")
	print("TDM remote character regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
