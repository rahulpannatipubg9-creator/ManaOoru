extends SceneTree

class Fixture extends Node3D:
	var player_spawn: Dictionary = {"position": Vector3.ZERO}
	var signage: SignageBuilder
	func ground_height(_point: Vector2) -> float:
		return 0.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--city" in OS.get_cmdline_user_args():
		await _city()
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/traffic_profiles.json"))
	var total := 0
	for profile: Dictionary in config.profiles:
		total += int(profile.spawn_weight)
	assert(total == 100, "Spawn weights must total 100")
	var world := Fixture.new()
	root.add_child(world)
	var manager := TrafficManager.new()
	world.add_child(manager)
	manager.set("_world", world)
	manager.profiles = config.profiles
	manager.districts = config.districts
	manager.set_physics_process(false)
	var focus := Node3D.new()
	root.add_child(focus)
	manager.focus_override = focus
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3(0,0,-300))
	lane.curve.add_point(Vector3(0,0,300))
	lane.set_meta("next", [])
	lane.set_meta("heading", Vector3.FORWARD)
	lane.set_meta("district", "city")
	root.add_child(lane)
	for i in 50:
		manager.get("_candidate_lanes").append(lane)
		var offsets: PackedFloat32Array = manager.get("_candidate_offsets")
		offsets.append(float(i) * 12.0)
		manager.set("_candidate_offsets", offsets)
	var parked := Node3D.new()
	parked.position = Vector3(0,0,60)
	root.add_child(parked)
	parked.add_to_group("enterable_vehicle")
	manager._cache_drivable_vehicles()
	for i in 100:
		manager._physics_process(0.31)
		for vehicle in manager.fleet:
			vehicle.set_physics_process(false)
			if vehicle.active:
				var distance := vehicle.position.distance_to(focus.position)
				assert(distance >= 40.0 and distance <= 90.0, "Spawn outside annulus")
				assert(vehicle.position.distance_to(parked.position) >= 8.0, "Spawn too close to parked vehicle")
		assert(manager.vehicle_count <= 25 and manager.fleet.size() <= 25, "Pool exceeded cap")
	assert(manager.vehicle_count > 0, "No traffic spawned")
	for a in manager.fleet:
		for b in manager.fleet:
			if a != b and a.active and b.active:
				assert(a.position.distance_to(b.position) >= 8.0, "Overlap spawn")
	focus.position.z = 200.0
	manager._physics_process(0.31)
	for vehicle in manager.fleet:
		if vehicle.active:
			assert(vehicle.position.distance_to(focus.position) <= 110.0, "Distant traffic retained")
	focus.position = Vector3.ZERO
	for i in 50:
		manager._physics_process(0.31)
	assert(manager.vehicle_count > 0, "Traffic failed to respawn after return")
	parked.free()
	world.free()
	focus.free()
	lane.free()
	print("PASS manager: weights, annulus, clearance, cap, despawn and return")
	quit()

func _city() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	var manager := game.get_node("World").get("traffic") as TrafficManager
	assert(manager.junction != null, "Mapped four-way junction missing")
	var stop_count := 0
	for child in manager.junction.get_children():
		if child is TrafficStopPoint and child.controller != null:
			stop_count += 1
	assert(stop_count >= 4, "Four inbound stop points required")
	for frame in 600:
		await physics_frame
	print("City candidates: %d, pooled: %d, active: %d" % [manager.get("_candidate_lanes").size(), manager.fleet.size(), manager.vehicle_count])
	assert(manager.vehicle_count > 0, "City traffic did not spawn")
	assert(manager.vehicle_count <= 25, "Active cap exceeded")
	for vehicle in manager.fleet:
		if vehicle.active:
			assert(vehicle.global_position.distance_to(manager.focus_position()) <= 111.0, "City traffic outside despawn radius")
	var previous: Dictionary = {}
	for vehicle in manager.fleet:
		if vehicle.active:
			previous[vehicle] = vehicle.global_position
	for frame in 120:
		await physics_frame
	var moved := false
	for vehicle: TrafficVehicle in previous:
		if vehicle.active and vehicle.global_position.distance_to(previous[vehicle]) > 2.0:
			moved = true
	assert(moved, "City vehicles spawned but did not drive")
	var test_focus := Node3D.new()
	game.add_child(test_focus)
	test_focus.global_position = manager.focus_position() + Vector3(150,0,0)
	manager.focus_override = test_focus
	for frame in 240:
		await physics_frame
	for vehicle in manager.fleet:
		if vehicle.active:
			assert(vehicle.global_position.distance_to(test_focus.global_position) <= 111.0, "City despawn failed after 150m travel")
	manager.focus_override = null
	for frame in 240:
		await physics_frame
	assert(manager.vehicle_count > 0, "City traffic failed to return")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_traffic_v1.png")
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.global_position = manager.focus_position() + Vector3(0,110,0)
		camera.rotation.x = -PI * 0.5
		camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_traffic_overview.png")
	print("PASS city traffic: %d active, %d pooled, %d lanes, %d stops, center %s" % [manager.vehicle_count, manager.fleet.size(), manager.lanes.size(), stop_count, manager.junction_center])
	root.remove_child(game)
	game.free()
	await process_frame
	quit()
