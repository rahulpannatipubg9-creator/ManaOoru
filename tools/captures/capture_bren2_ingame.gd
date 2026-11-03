extends SceneTree

const OUT := "res://outputs/character_previews/bren2_ingame/"
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
	person.set_weapon_model(Weapons.BREN2)
	person.set_weapon_equipped(true)
	await shot(person, "bren2_low_ready_front", Vector3(1.4, 1.35, 2.6), 1.15, spot)
	await shot(person, "bren2_low_ready_side", Vector3(-2.8, 1.3, 0.4), 1.1, spot)
	quit()

func frames(n: int) -> void:
	for _i in n:
		GameplayControls.blocked = false
		await process_frame

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
