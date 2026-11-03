extends SceneTree

const RamagundamFlyoverClass := preload("res://scripts/world/ramagundam_flyover_builder.gd")
const TrafficVehicleClass := preload("res://scripts/world/traffic_vehicle.gd")

class WorldMock extends Node3D:
	var terrain: TerrainData
	var flyover: Node3D
	
	func ground_height(point: Vector2) -> float:
		return terrain.height_at(point)
	
	func flyover_height_at(point: Vector2, fallback: float) -> float:
		if flyover and flyover.has_method("deck_height_at"):
			var dh: float = flyover.deck_height_at(point)
			if dh != -INF:
				return dh
		return fallback

func _init() -> void:
	run.call_deferred()

func run() -> void:
	print("--- TESTING TRAFFIC LANE HEIGHTS & VEHICLES ---")
	var map_data := MapData.load_shared()
	assert(map_data != null, "MapData must load")

	var world_mock := WorldMock.new()
	world_mock.terrain = map_data.terrain
	root.add_child(world_mock)

	var flyover := RamagundamFlyoverClass.new()
	world_mock.flyover = flyover
	world_mock.add_child(flyover)
	flyover.build(world_mock, map_data)

	var lanes_parent := Node3D.new()
	root.add_child(lanes_parent)
	var lanes := TrafficLaneBuilder.build(world_mock, map_data, lanes_parent)
	print("Total traffic lanes built: ", lanes.size())
	assert(lanes.size() > 50, "Expected >50 traffic lanes")

	# 1. Verify Ground Roads vs Bridge Roads
	var elevated_bridge_lanes := 0
	var illegal_flying_lanes := 0

	for lane in lanes:
		var curve := lane.curve
		var road_name := str(lane.get_meta("road_name", ""))
		for i in range(curve.point_count):
			var pt := curve.get_point_position(i)
			# Only check in flyover corridor
			if pt.x >= -250.0 and pt.x <= 450.0 and pt.z >= -2700.0 and pt.z <= -2000.0:
				var gh := world_mock.ground_height(Vector2(pt.x, pt.z))
				var elev := pt.y - gh
				if elev > 3.0:
					# Check if this road was a bridge road
					var is_bridge_name := "flyover" in road_name.to_lower()
					if is_bridge_name:
						elevated_bridge_lanes += 1
					else:
						illegal_flying_lanes += 1
						printerr("FAIL: Ground road lane flying in sky: ", lane.name, " road=", road_name, " elev=", elev, " pos=", pt)

	print("Elevated flyover lanes found: ", elevated_bridge_lanes)
	print("Illegal flying ground lanes: ", illegal_flying_lanes)
	assert(illegal_flying_lanes == 0, "No ground roads should be flying in the air!")
	assert(elevated_bridge_lanes > 0, "Flyover bridge roads must be elevated")

	# 2. Verify Bike Traffic Vehicle Setup
	var bike := TrafficVehicleClass.new()
	bike.vehicle_kind = "bike"
	root.add_child(bike)
	bike._ready()

	assert(bike.has_node("BikeRider"), "Bike must have a BikeRider attached")
	var rider := bike.get_node("BikeRider")
	assert(rider.has_node("Torso"), "BikeRider must have Torso")
	assert(rider.has_node("Helmet"), "BikeRider must have Helmet")

	var bullet := bike.get_node_or_null("BulletModel")
	assert(bullet != null, "Bike must have BulletModel")
	var fp := bullet.get_node_or_null("FrontWheelPivot")
	var rp := bullet.get_node_or_null("RearWheelPivot")
	assert(fp != null, "Bike must have FrontWheelPivot")
	assert(rp != null, "Bike must have RearWheelPivot")
	assert(absf(fp.rotation.z - PI * 0.5) < 0.01, "FrontWheelPivot must have rot.z = PI/2")
	assert(absf(rp.rotation.z - PI * 0.5) < 0.01, "RearWheelPivot must have rot.z = PI/2")

	# Verify wheel rolling in physics process
	var dummy_lane := Path3D.new()
	dummy_lane.curve = Curve3D.new()
	dummy_lane.curve.bake_interval = 1.0
	dummy_lane.curve.add_point(Vector3(0, 0, 0))
	dummy_lane.curve.add_point(Vector3(0, 0, 100))
	dummy_lane.set_meta("next", [dummy_lane])
	dummy_lane.set_meta("speed_scale", 1.0)
	root.add_child(dummy_lane)

	bike.activate(dummy_lane, 0.0)
	var prev_fp_rot: Vector3 = fp.rotation
	bike.current_speed = 5.0
	bike._physics_process(0.1)
	assert(fp.rotation != prev_fp_rot, "Wheel must roll during movement")

	# 3. Verify Auto-Rickshaw Traffic Vehicle Setup
	var auto := TrafficVehicleClass.new()
	auto.vehicle_kind = "auto"
	root.add_child(auto)
	auto._ready()

	var tuk_tuk := auto.get_node_or_null("TukTukModel")
	assert(tuk_tuk != null, "Auto must have TukTukModel")
	assert(tuk_tuk.position.y <= 0.05, "Auto-rickshaw must not be lifted in the air! position.y must be <= 0.05m")
	var auto_driver := tuk_tuk.get_node_or_null("AutoDriver")
	assert(auto_driver != null, "Auto must have AutoDriver")
	assert(auto_driver.position.y > 0.0, "Driver must be seated inside the auto, not hanging below!")

	# Cleanup
	auto.queue_free()
	bike.queue_free()
	dummy_lane.queue_free()
	lanes_parent.queue_free()
	world_mock.queue_free()

	print("PASS Traffic lane heights, auto ground adherence, and bike rider/wheel rotation")
	quit()
