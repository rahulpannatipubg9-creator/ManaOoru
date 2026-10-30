extends SceneTree

const OUT := "/Users/rahulpannati/.gemini/antigravity/brain/69a10935-63a8-4da8-9804-5e66387edc38/screenshots/"
const GameplayControls := preload("res://scripts/player/gameplay_controls.gd")

func _init() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var game := main_scene.instantiate()
	root.add_child(game)

	for _i in 35:
		GameplayControls.blocked = false
		await process_frame

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 55.0
	root.add_child(cam)

	var list := [
		{
			"label": "vidya_nagar_suv",
			"target": "ParkedSUV4x4",
			"cam_offset": Vector3(-1.2, 1.6, 4.2),
			"look_offset": Vector3(0.0, 0.8, 0.0)
		},
		{
			"label": "vidya_nagar_banana_tree",
			"target": "BananaTree_1",
			"cam_offset": Vector3(3.2, 1.8, 3.2),
			"look_offset": Vector3(0.0, 1.2, 0.0)
		},
		{
			"label": "godavari_bridge_crash_barriers",
			"target": "BridgeSpeedLimitSign",
			"cam_offset": Vector3(-5.5, 2.0, 7.5),
			"look_offset": Vector3(2.5, 1.0, -4.0)
		},
		{
			"label": "coal_mine_power_pylon",
			"target": "InclinePowerPylon",
			"cam_offset": Vector3(12.0, 6.0, 14.0),
			"look_offset": Vector3(-3.0, 4.0, 0.0)
		},
		{
			"label": "hotel_sai_leela_luxury_pool",
			"target": "CourtyardSwimmingPool",
			"cam_offset": Vector3(8.0, 6.5, 9.0),
			"look_offset": Vector3(0.0, 0.0, 0.0)
		},
		{
			"label": "hotel_sai_leela_lobby_sofas",
			"target": "LobbySofaSet",
			"cam_offset": Vector3(-1.8, 1.2, 2.2),
			"look_offset": Vector3(0.0, 0.4, 0.0)
		}
	]

	for item in list:
		var node := game.find_child(str(item.target), true, false) as Node3D
		if not node:
			print("MISSING ", item.target)
			continue
		var pos: Vector3 = node.global_position
		cam.global_position = pos + (item.cam_offset as Vector3)
		cam.look_at(pos + (item.look_offset as Vector3), Vector3.UP)
		for _f in 20:
			GameplayControls.blocked = false
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var path := OUT + str(item.label) + ".png"
		img.save_png(path)
		print("SAVED: ", str(item.label), " -> ", path)

	print("FINISHED ALL")
	quit()
