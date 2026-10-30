extends SceneTree

## Windowed capture of player v2 in the real game scene (run with: caffeinate -d -i godot --path . --script
## tests/capture_player_v2.gd). Writes outputs/character_previews/v2_ingame/*.png.

const OUT := "res://outputs/character_previews/v2_ingame/"
const GameplayControls := preload("res://scripts/player/gameplay_controls.gd")

var game: Node
var cam: Camera3D

func _init() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(40)
	var person: CharacterBody3D = game.person
	var character = person.get_node_or_null("TestCharacter")
	print("CAPTURE model ", character.male_model.scene_file_path if character and character.male_model else "none")
	# an open stretch of road (as tests/codex_combat_capture.gd), away from the spawn's tuk tuk and NPCs
	person.global_position = Vector3(116.0, 1.2, -105.0)
	await frames(30)
	var game_cam := root.get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = 40.0
	if game_cam:
		cam.environment = game_cam.environment
		cam.attributes = game_cam.attributes
		cam.far = game_cam.far
	root.add_child(cam)
	for layer: CanvasLayer in root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await shot(person, "standing_front", Vector3(0.0, 1.45, -3.2), 1.0)
	await shot(person, "standing_threequarter", Vector3(2.0, 1.35, -2.4), 1.0)
	await shot(person, "standing_back", Vector3(0.0, 1.5, 3.2), 1.0)
	await shot(person, "face_closeup", Vector3(0.35, 1.62, -1.0), 1.55)
	await shot(person, "feet_closeup", Vector3(0.9, 0.45, -1.1), 0.15)
	person.set_touch_move_input(Vector2(0.0, -1.0))
	await shot(person, "walking_side", Vector3(-3.2, 1.1, 0.0), 0.9)
	person.set_touch_run_pressed(true)
	await shot(person, "running_side", Vector3(-3.4, 1.1, 0.0), 0.9)
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)
	person.set_weapon_equipped(true)
	await shot(person, "rifle_threequarter", Vector3(2.2, 1.45, -2.6), 1.1)
	person.crouching = true
	await shot(person, "crouch_threequarter", Vector3(2.2, 1.1, -2.6), 0.7)
	quit()

func frames(n: int) -> void:
	for _i in n:
		GameplayControls.blocked = false
		await process_frame

## Camera placed in the person's own frame (x right, -z ahead of the character), looking at a height on it.
func shot(person: Node3D, label: String, offset: Vector3, look_height: float) -> void:
	for _i in 45:
		GameplayControls.blocked = false
		var basis := person.global_basis
		cam.global_position = person.global_position + basis * offset
		cam.look_at(person.global_position + Vector3.UP * look_height, Vector3.UP)
		cam.current = true
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + label + ".png")
	root.get_texture().get_image().save_png(path)
	print("CAPTURE saved ", path)
