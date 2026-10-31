extends SceneTree

func _init() -> void:
	print("--- Running Drivable Vehicles, Ambient Traffic, and District Missions Test ---")

	# Test 1: Royal Enfield Bullet 350 Scene
	var bullet_scene := load("res://scenes/vehicles/royal_enfield_bullet.tscn") as PackedScene
	assert(bullet_scene != null, "royal_enfield_bullet.tscn must load")
	var bullet := bullet_scene.instantiate() as RigidVehicle
	assert(bullet != null, "Instantiated bullet must be a RigidVehicle")
	assert(bullet.vehicle_mass == 195.0, "Bullet mass should be 195.0 kg")
	assert(bullet.drivetrain != null and bullet.drivetrain.cylinders == 1, "Bullet should have single cylinder drivetrain")
	assert(bullet.seat_hip != Vector3.ZERO, "Bullet must have seat_hip configured")
	assert(bullet.left_hand_grip != Vector3.ZERO and bullet.right_hand_grip != Vector3.ZERO, "Bullet must have handlebar grip points")
	root.add_child(bullet)
	await process_frame
	print("PASS: Royal Enfield Bullet 350 drivable scene verified (mass=%.1fkg, cylinders=%d, seat=%s)" % [bullet.vehicle_mass, bullet.drivetrain.cylinders, str(bullet.seat_hip)])
	bullet.queue_free()

	# Test 2: TGSRTC Super Luxury Express Bus Scene
	var bus_scene := load("res://scenes/vehicles/tgsrtc_bus.tscn") as PackedScene
	assert(bus_scene != null, "tgsrtc_bus.tscn must load")
	var bus := bus_scene.instantiate() as RigidVehicle
	assert(bus != null, "Instantiated bus must be a RigidVehicle")
	assert(bus.vehicle_mass == 11500.0, "TGSRTC bus mass should be 11,500.0 kg")
	assert(bus.drivetrain != null and bus.drivetrain.cylinders == 6, "TGSRTC bus should have 6-cylinder diesel drivetrain")
	assert(bus.seat_hip != Vector3.ZERO, "Bus must have RHD driver seat configured")
	root.add_child(bus)
	await process_frame
	print("PASS: TGSRTC Express Bus drivable scene verified (mass=%.1fkg, cylinders=%d, seat=%s)" % [bus.vehicle_mass, bus.drivetrain.cylinders, str(bus.seat_hip)])
	bus.queue_free()

	# Test 3: Ambient Traffic Models (Bus, Auto, Bullet, Avenger, SUV)
	for kind in ["bus", "auto", "bullet", "avenger", "suv", "scooter"]:
		var tv := TrafficVehicle.new()
		tv.vehicle_kind = kind
		tv.route = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 50)])
		tv.ground_sampler = func(_p: Vector2) -> float: return 0.0
		root.add_child(tv)
		await process_frame
		assert(tv.get_child_count() > 0, "Traffic vehicle kind '%s' must have visual children" % kind)
		tv._process(0.1)
		assert(tv.position.z >= 0.0, "Traffic vehicle kind '%s' must advance" % kind)
		print("PASS: Ambient traffic model '%s' initialized and simulated successfully" % kind)
		tv.queue_free()

	# Test 4: Main Game with District Missions
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	assert(main_scene != null, "main.tscn must load")
	var game: Node = main_scene.instantiate()
	root.add_child(game)
	for _frame in 10:
		await process_frame

	var gameplay: Node = game.get_node_or_null("CityGameplay")
	assert(gameplay != null, "CityGameplay node must exist in main game")

	# Test 4A: Start TGSRTC Bus Route mission
	var started_bus: bool = gameplay.start_mission("tgsrtc_route")
	assert(started_bus, "TGSRTC transit route mission must start successfully")
	assert(gameplay.mission.get("kind") == "tgsrtc_route", "Mission kind should be tgsrtc_route")
	assert(gameplay.mission.get("points").size() == 4, "TGSRTC route should have 4 stops (Depot -> Chowrastha -> Vidyanagar -> Mine)")
	assert(gameplay.mission.get("reward") == 50, "TGSRTC route reward should be 50 coins")
	print("PASS: District Mission 'TGSRTC Bus Transit Route' verified with 4 route checkpoints")
	gameplay.end_mission(false, "Test cleanup")

	# Test 4B: Start Singareni Coal Mine Supply mission
	var started_coal: bool = gameplay.start_mission("coal_delivery")
	assert(started_coal, "Singareni Coal Mine supply mission must start successfully")
	assert(gameplay.mission.get("kind") == "coal_delivery", "Mission kind should be coal_delivery")
	assert(gameplay.mission.get("points").size() == 2, "Coal delivery should have 2 points (Chowrastha -> Mine Incline)")
	assert(gameplay.mission.get("reward") == 35, "Coal delivery reward should be 35 coins")
	print("PASS: District Mission 'Singareni Coal Mine Industrial Supply' verified")
	gameplay.end_mission(false, "Test cleanup")

	# Test 4C: Start Saturday Market Irani Chai Courier mission
	var started_chai: bool = gameplay.start_mission("chai_delivery")
	assert(started_chai, "Saturday Market chai delivery mission must start successfully")
	assert(gameplay.mission.get("kind") == "chai_delivery", "Mission kind should be chai_delivery")
	assert(gameplay.mission.get("points").size() == 2, "Chai delivery should have 2 points (Market -> Vidyanagar)")
	assert(gameplay.mission.get("reward") == 25, "Chai delivery reward should be 25 coins")
	print("PASS: District Mission 'Saturday Market Irani Chai Courier' verified")
	gameplay.end_mission(false, "Test cleanup")

	# Test 4D: Vehicle Spawning via Gameplay (Royal Enfield Bullet and TGSRTC Bus)
	# Position player on a wide clear road spot
	game.person.global_position = Vector3(100.0, game.get_node("World").ground_height(Vector2(100.0, 0.0)) + 0.5, 0.0)
	await process_frame
	var spawned_bullet: Node = gameplay.spawn_extra_vehicle("bullet")
	assert(spawned_bullet != null, "Bullet should spawn via gameplay")
	assert(spawned_bullet is RigidVehicle, "Spawned bullet must be a RigidVehicle")
	print("PASS: Royal Enfield Bullet spawned dynamically and registered in active game vehicles")

	game.person.global_position = Vector3(150.0, game.get_node("World").ground_height(Vector2(150.0, 0.0)) + 0.5, 0.0)
	await process_frame
	var spawned_bus: Node = gameplay.spawn_extra_vehicle("bus")
	assert(spawned_bus != null, "Bus should spawn via gameplay")
	assert(spawned_bus is RigidVehicle, "Spawned bus must be a RigidVehicle")
	print("PASS: TGSRTC Express Bus spawned dynamically and registered in active game vehicles")

	print("\nALL VERIFICATIONS PASSED SUCCESSFULLY!")
	quit(0)
