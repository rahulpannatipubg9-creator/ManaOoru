extends SceneTree

const OUT_BRAIN := "/Users/rahulpannati/.gemini/antigravity/brain/69a10935-63a8-4da8-9804-5e66387edc38/screenshots/"
const OUT_LOCAL := "res://outputs/captures/asset_integration/"
const GameplayControls := preload("res://scripts/player/gameplay_controls.gd")

var game: Node
var cam: Camera3D

func _init() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_BRAIN)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_LOCAL))
	root.size = Vector2i(1280, 720)

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	game = main_scene.instantiate()
	root.add_child(game)

	# Allow world generation to complete
	for _i in 40:
		GameplayControls.blocked = false
		await process_frame

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	var game_cam := root.get_viewport().get_camera_3d()
	if game_cam and game_cam != cam:
		cam.environment = game_cam.environment
		cam.attributes = game_cam.attributes
		cam.far = 1200.0
	root.add_child(cam)

	var captures := [
		{
			"label": "01_vidya_nagar_suv",
			"target": "ParkedSUV4x4",
			"cam_offset": Vector3(4.0, 1.8, 4.0),
			"look_offset": Vector3(0.0, 0.7, 0.0)
		},
		{
			"label": "02_vidya_nagar_banana_tree",
			"target": "BananaTree_1",
			"cam_offset": Vector3(3.2, 1.9, 3.6),
			"look_offset": Vector3(0.0, 1.3, 0.0)
		},
		{
			"label": "03_hotel_sai_leela_luxury_pool",
			"target": "CourtyardSwimmingPool",
			"cam_offset": Vector3(4.0, 7.0, 7.0),
			"look_offset": Vector3(-4.0, -0.6, -4.0)
		},
		{
			"label": "04_godavari_bridge_crash_barriers",
			"target": "BridgeSpeedLimitSign",
			"cam_offset": Vector3(-5.5, 2.0, 7.5),
			"look_offset": Vector3(2.5, 1.0, -4.0)
		},
		{
			"label": "05_coal_mine_incline_pylon_and_signs",
			"target": "InclinePowerPylon",
			"cam_offset": Vector3(12.0, 6.0, 14.0),
			"look_offset": Vector3(-3.0, 4.0, 0.0)
		}
	]

	for item in captures:
		var target_node := game.find_child(str(item.target), true, false) as Node3D
		if not target_node:
			print("Missing: ", item.target)
			continue

		var pos: Vector3 = target_node.global_position
		cam.global_position = pos + (item.cam_offset as Vector3)
		cam.look_at(pos + (item.look_offset as Vector3), Vector3.UP)

		for _f in 20:
			GameplayControls.blocked = false
			await process_frame

		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		if img and not img.is_empty():
			var p1: String = OUT_BRAIN + str(item.label) + ".png"
			var p2: String = ProjectSettings.globalize_path(OUT_LOCAL + str(item.label) + ".png")
			img.save_png(p1)
			img.save_png(p2)
			print("CAPTURED: ", str(item.label), " -> ", p1)

	print("ALL CAPTURES COMPLETED")
	quit()
