extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var traffic_root := Node3D.new()
	world.add_child(traffic_root)
	var scooter := TrafficVehicle.new()
	scooter.vehicle_kind = "scooter"
	scooter.route = PackedVector3Array([Vector3.ZERO,Vector3(0,0,30)])
	scooter.ground_sampler = func(_p: Vector2) -> float: return 0.0
	traffic_root.add_child(scooter)
	await process_frame
	assert(scooter.has_node("Driver") and scooter.has_node("Passenger"),"Scooter requires two seated riders")
	scooter._process(.2)
	assert(scooter.position.z > 0 and is_zero_approx(scooter.position.y),"Scooter must advance grounded")
	var blocker := TrafficVehicle.new()
	blocker.position = scooter.position + Vector3(0,0,2)
	traffic_root.add_child(blocker)
	var before := scooter.position
	scooter._process(.2)
	assert(scooter.position == before,"Scooter must wait for traffic ahead")
	blocker.position.x = 10
	scooter._process(.2)
	assert(scooter.position.z > before.z,"Scooter must resume when clear")
	print("PASS scooter: two riders, grounded travel, obstacle stop and resume")
	quit()
