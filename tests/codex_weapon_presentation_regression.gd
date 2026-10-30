extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var person = load("res://scenes/player/person.tscn").instantiate()
	root.add_child(person)
	person.set_physics_process(false)
	var camera := person.camera_pivot.get_node("SpringArm3D/Camera3D") as Camera3D
	camera.current = true
	person.combat_mode = true
	person.set_weapon_equipped(true)
	person._update_weapon_presentation(0.5)
	assert(person.muzzle != null, "Equipped rifle has a muzzle marker")
	assert(person.weapon.global_basis.z.dot(-camera.global_basis.z) > 0.99, "Rifle +Z barrel faces camera target direction")
	assert(person.weapon_muzzle_position().distance_to(person.weapon.global_position) > 0.4, "Muzzle sits at barrel end")
	person.camera_pivot.set_view_mode(1)
	person._update_weapon_presentation(0.1)
	var character = person.get_node_or_null("TestCharacter")
	if character: assert(not character.visible, "FPP hides third-person head/body")
	person.camera_pivot.set_view_mode(0)
	person._update_weapon_presentation(0.1)
	if character: assert(character.visible, "TPP restores the avatar")
	person.set_weapon_equipped(false)
	assert(not person.is_weapon_equipped(), "Unequip hides rifle")
	person.queue_free()
	await process_frame
	print("PASS weapon presentation: barrel direction, muzzle position, FPP/TPP visibility, unequip")
	quit(0)
