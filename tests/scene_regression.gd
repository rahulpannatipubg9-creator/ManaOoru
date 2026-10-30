extends SceneTree

func _init() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	assert(player_scene != null, "Player scene must load")
	var player := player_scene.instantiate()
	root.add_child(player)
	await process_frame
	var spring_arm := player.get_node("CameraPivot/SpringArm3D") as SpringArm3D
	assert(spring_arm.spring_length >= 6.0, "Camera distance must not be too close")
	assert(spring_arm.collision_mask == 1, "Camera must retain world collision")
	assert(spring_arm.margin >= 0.4, "Camera must keep an obstruction margin")
	var camera_script := load("res://scripts/camera/camera_controller.gd")
	assert(camera_script.clamp_pitch_value(10.0, -0.75, 0.55) == 0.55, "Pitch upper bound failed")
	assert(camera_script.clamp_pitch_value(-10.0, -0.75, 0.55) == -0.75, "Pitch lower bound failed")
	assert(player.get_node_or_null("Chassis/FrontIndicator") != null, "Player facing indicator missing")
	var world_scene := load("res://scenes/world/world.tscn") as PackedScene
	var world := world_scene.instantiate()
	root.add_child(world)
	await process_frame
	assert(world.buildings.facade_board_count() > 0, "Building shopfront signs must be assigned")
	var atlas: Variant = JSON.parse_string(FileAccess.get_file_as_string(BuildingBuilder.BOARDS_PATH))
	for poi in world.map_data.pois:
		if str(poi.name).is_empty():
			continue
		var found := false
		for board: Dictionary in atlas.boards:
			if str(board.name).to_lower() == str(poi.name).to_lower() and GeoProjection.lon_lat_to_map(float(board.lon), float(board.lat)).distance_to(poi.position) < 40.0:
				found = true
				break
		assert(found, "Shopfront texture missing for named map place: %s" % poi.name)
	assert(world.birds != null and world.birds.bird_count() == 36, "Ambient bird flocks missing")
	assert(world.water_infrastructure.tower_count >= 3, "Mapped water towers missing")
	assert(world.water_infrastructure.get_node_or_null("MappedIndianWaterTower") != null, "User water-tank model missing")
	assert(world.bus_station.terminal_count == 1, "Mapped TGSRTC bus station missing")
	assert(world.bus_station.terminal_entries.size() == 1, "TGSRTC interaction point missing")
	assert(world.billboards.billboard_count == 1, "Chowrastha advertising billboard missing")
	assert(world.cctv != null and world.cctv.camera_count >= 4, "Junction CCTV coverage missing")
	assert(world.cctv.bus_station_camera_count == 1, "Bus station CCTV missing")
	assert(world.traffic != null and world.traffic.vehicle_count >= 6, "Ambient mapped-road traffic missing")
	assert(world.traffic.municipal_vehicle_count >= 1, "Moving municipal vehicle missing")
	assert(world.traffic.bus_vehicle_count == 1, "Mapped TGSRTC service bus missing")
	assert(world.local_activity != null and world.local_activity.bus_passenger_count >= 4, "Bus station passengers missing")
	assert(world.local_activity.shop_visitor_count >= 4, "Mapped shop visitors missing")
	assert(world.local_activity.shop_entries.size() >= 4, "Mapped shop interaction points missing")
	assert(world.local_activity.crossing_pedestrian_count >= 2, "Mapped zebra-crossing pedestrians missing")
	assert(world.local_activity.shopkeeper_count >= 4, "Offline shopkeepers missing")
	print("PASS scene regression: camera collision, safe distance, pitch bounds, facing indicator")
	quit()
