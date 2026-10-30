extends SceneTree

const OUT := "/Users/rahulpannati/.gemini/antigravity/brain/69a10935-63a8-4da8-9804-5e66387edc38/screenshots/03_hotel_sai_leela_luxury_pool.png"
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

	var pool := game.find_child("CourtyardSwimmingPool", true, false) as Node3D
	if not pool:
		print("POOL NOT FOUND")
		quit()
		return

	print("POOL FOUND AT ", pool.global_position)
	var cam := Camera3D.new()
	cam.current = true
	root.add_child(cam)
	cam.global_position = pool.global_position + Vector3(0.0, 7.0, 7.0)
	cam.look_at(pool.global_position + Vector3(0.0, -0.5, 0.0), Vector3.UP)

	for _f in 20:
		GameplayControls.blocked = false
		await process_frame

	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT)
	print("SAVED TO ", OUT)
	quit()
