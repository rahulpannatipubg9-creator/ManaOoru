extends SceneTree

func _initialize() -> void:
	call_deferred("capture_all")

func capture_all() -> void:
	root.size = Vector2i(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DirAccess.make_dir_recursive_absolute("outputs/chowrasta_sketch_city")

	var city = load("res://scenes/world/chowrasta_city.tscn").instantiate()
	root.add_child(city)

	for i in range(5):
		await process_frame

	city.hud.visible = false

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true

	var shots := [
		{
			"name": "01_top_down_sketch_reference.png",
			"pos": Vector3(0.0, 95.0, 0.0),
			"look": Vector3(0.0, 0.0, 0.0)
		},
		{
			"name": "02_chowrasta_aerial_perspective.png",
			"pos": Vector3(38.0, 36.0, 42.0),
			"look": Vector3(0.0, 2.0, 0.0)
		},
		{
			"name": "03_petrol_station_and_shop.png",
			"pos": Vector3(-6.0, 5.0, 2.0),
			"look": Vector3(-24.0, 3.5, -18.0)
		},
		{
			"name": "04_four_shops_and_hotel.png",
			"pos": Vector3(6.0, 5.0, 8.0),
			"look": Vector3(26.0, 4.0, -12.0)
		},
		{
			"name": "05_bus_stop_and_commercial.png",
			"pos": Vector3(8.0, 5.0, -6.0),
			"look": Vector3(28.0, 3.5, 14.0)
		},
		{
			"name": "06_residential_houses.png",
			"pos": Vector3(2.0, 8.0, 4.0),
			"look": Vector3(-24.0, 3.0, 24.0)
		}
	]

	for shot in shots:
		camera.position = shot["pos"]
		var up_vec: Vector3 = Vector3(0, 0, -1) if shot["pos"].x == 0.0 and shot["pos"].z == 0.0 else Vector3.UP
		camera.look_at(shot["look"], up_vec)
		for f in range(2):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "outputs/chowrasta_sketch_city/" + shot["name"]
		root.get_texture().get_image().save_png(path)
		print("Saved screenshot: ", path)

	print("ALL CAPTURES COMPLETED!")
	quit(0)
