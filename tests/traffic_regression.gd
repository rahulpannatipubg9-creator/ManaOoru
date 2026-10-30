extends SceneTree

func _init() -> void:
	var traffic := TrafficVehicle.new()
	traffic.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, -8.0)])
	traffic.speed = 4.0
	root.add_child(traffic)
	await process_frame
	var start := traffic.position
	for step in 10:
		traffic._process(0.1)
	assert(traffic.position.distance_to(start) > 2.0, "Ambient traffic did not advance")
	for step in 30:
		traffic._process(0.1)
	assert(traffic.position.z <= 0.01 and traffic.position.z >= -8.01, "Traffic left its mapped road route")
	assert(traffic._route_direction == -1 or traffic.position.z > -7.9, "Traffic teleported instead of turning at road end")
	print("PASS traffic regression: mapped route movement and end-of-road turnaround")
	quit()
