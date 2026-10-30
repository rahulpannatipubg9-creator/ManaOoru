extends SceneTree

## Windowed capture of Rahul (tools/rahul_character) in the real game scene, unarmed and with the AK-47:
##   caffeinate -d -i godot --path . --script tests/capture_rahul_ingame.gd
## Writes outputs/character_previews/rahul_ingame/*.png. The pictures are taken through a SubViewport that
## shares the game's world, so the game camera stays current and the rifle keeps its camera-relative hold
## (docs/lessons/TESTING_AND_TOOLS.md).

const OUT := "res://outputs/character_previews/rahul_ingame/"
const GameplayControls := preload("res://scripts/player/gameplay_controls.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

var game: Node
var view: SubViewport
var cam: Camera3D

func _init() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(40)
	var person: CharacterBody3D = game.person
	var character = person.get_node_or_null("TestCharacter")
	print("CAPTURE model ", character.male_model.scene_file_path if character and character.male_model else "none")
	# an open stretch of road (as tests/codex_combat_capture.gd), away from the spawn's tuk tuk and NPCs
	person.global_position = Vector3(116.0, 1.2, -105.0)
	person.combat_mode = true
	await frames(30)
	view = SubViewport.new()
	view.size = Vector2i(960, 720)
	view.world_3d = root.get_viewport().world_3d
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	cam = Camera3D.new()
	cam.fov = 40.0
	var game_cam := root.get_viewport().get_camera_3d()
	if game_cam:
		cam.environment = game_cam.environment
		cam.attributes = game_cam.attributes
		cam.far = game_cam.far
	view.add_child(cam)

	var spot := person.global_position
	await shot(person, "unarmed_standing", Vector3(1.6, 1.3, 3.0), 1.0, spot)
	person.set_touch_move_input(Vector2(0.0, -1.0))
	await shot(person, "unarmed_jog_side", Vector3(-3.4, 1.1, 0.0), 0.9, spot)
	person.set_touch_run_pressed(true)
	await shot(person, "unarmed_sprint_side", Vector3(-3.6, 1.1, 0.0), 0.9, spot)
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)

	person.set_weapon_model(Weapons.AK47)
	person.set_weapon_equipped(true)
	await shot(person, "ak_low_ready_front", Vector3(1.4, 1.35, 2.6), 1.15, spot)
	await shot(person, "ak_low_ready_side", Vector3(-2.8, 1.3, 0.4), 1.1, spot)
	await shot(person, "ak_low_ready_back", Vector3(-0.9, 1.7, -2.6), 1.3, spot)
	person.touch_peek_input = -1.0
	await shot(person, "ak_peek_left_back", Vector3(0.0, 1.6, -3.0), 1.2, spot)
	await shot(person, "ak_peek_left_front", Vector3(0.0, 1.4, 3.0), 1.2, spot)
	person.touch_peek_input = 1.0
	await shot(person, "ak_peek_right_back", Vector3(0.0, 1.6, -3.0), 1.2, spot)
	person.touch_peek_input = 0.0
	person.set_touch_move_input(Vector2(0.0, -1.0))
	await shot(person, "ak_jog_side", Vector3(-3.4, 1.15, 0.0), 1.0, spot)
	person.set_touch_run_pressed(true)
	await shot(person, "ak_sprint_side", Vector3(-3.6, 1.15, 0.0), 1.0, spot)
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)
	person.crouching = true
	await shot(person, "ak_crouch_front", Vector3(1.4, 1.0, 2.6), 0.7, spot)
	quit()

func frames(n: int) -> void:
	for _i in n:
		GameplayControls.blocked = false
		await process_frame

## Camera placed in the person's own frame (+z ahead of the character, +x its left), looking at a height on it.
## Moving shots put the person back on `spot` each frame, so a run never carries them into a building.
func shot(person: Node3D, label: String, offset: Vector3, look_height: float, spot: Vector3) -> void:
	for _i in 50:
		GameplayControls.blocked = false
		person.global_position = Vector3(spot.x, person.global_position.y, spot.z)
		var basis := person.global_basis
		cam.global_position = person.global_position + basis * offset
		cam.look_at(person.global_position + Vector3.UP * look_height, Vector3.UP)
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + label + ".png")
	view.get_texture().get_image().save_png(path)
	print("CAPTURE saved ", path)
