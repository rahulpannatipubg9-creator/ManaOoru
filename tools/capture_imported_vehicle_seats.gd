extends SceneTree
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(700, 500)
	Engine.time_scale = 4.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .14, .17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	root.add_child(sun)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	collision.position.y = -.5
	ground.add_child(collision)
	root.add_child(ground)
	var person := load("res://scenes/player/person.tscn").instantiate() as CharacterBody3D
	root.add_child(person)
	person.set_movement_enabled(false)
	person.set_collision_enabled(false)
	var weapon := person.get_node_or_null("Weapon") as Node3D
	if weapon:
		weapon.visible = false
	var entry: Node = load("res://scripts/vehicle/vehicle_entry.gd").new()
	root.add_child(entry)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 45
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/imported_vehicle_profiles.json"))
	DirAccess.make_dir_recursive_absolute("res://outputs/vehicle_rigs/seats")
	catalog["royal_enfield_bullet"] = {"actual_dimensions": [0.785, 1.225, 2.11]}
	for id: String in catalog:
		var path := "res://scenes/vehicles/royal_enfield_bullet.tscn" if id == "royal_enfield_bullet" else "res://scenes/vehicles/imported/%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var car := load(path).instantiate() as RigidVehicle
		car.set_driving_enabled(false)
		car.set_input_authority(false)
		root.add_child(car)
		car.freeze = true
		person.global_position = Vector3(3, 0, 0)
		entry.begin_enter(person, car)
		for frame in 240:
			await physics_frame
			if entry.is_seated() and person.get_node("TestCharacter")._seat > .99:
				break
		var dimensions: Array = catalog[id].actual_dimensions
		var length := float(dimensions[2])
		var height := float(dimensions[1])
		camera.position = Vector3(length*.85, height+.8, length*.9)
		camera.look_at(Vector3(0, height*.52, 0))
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://outputs/vehicle_rigs/seats/%s.png" % id)
		print("SEAT_CAPTURE ", id, " seated=", entry.is_seated())
		for side in [-1.0, 1.0]:
			camera.position = Vector3(length * side, height * .65, 0)
			camera.look_at(Vector3(0, height * .55, 0))
			await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://outputs/vehicle_rigs/seats/%s_side_%s.png" % [id, "left" if side < 0 else "right"])
		entry.cancel()
		car.queue_free()
		await process_frame
	quit()
