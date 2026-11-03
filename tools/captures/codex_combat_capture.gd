extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(30): await process_frame
	var character = game.person.get_node_or_null("TestCharacter")
	if character and character.male_model:
		character.male_model.visible = true
		if character.model: character.model.visible = false
	game.gameplay.action_mode = true
	game.person.combat_mode = true
	game.person.set_weapon_equipped(true)
	game.person.global_position = Vector3(116.0, 1.2, -105.0)
	game.gameplay.ammo = 30
	game.person.camera_pivot._yaw = game.person.rotation.y + PI
	game.person.camera_pivot._pitch = -0.08
	for i in range(20): await process_frame
	await capture("tpp-holding")
	game.person.camera_pivot.touch_aim = true
	for i in range(20): await process_frame
	game.gameplay.attack()
	await capture("tpp-firing")
	game.person.camera_pivot.set_view_mode(1)
	for i in range(20): await process_frame
	await capture("fpp-aiming")
	quit()
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/Users/rahulpannati/Documents/Codex/2026-10-27/wha/outputs/combat-review/" + label + ".png")
