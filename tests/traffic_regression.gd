extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var manager := TrafficManager.new()
	root.add_child(manager)
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3.ZERO)
	lane.curve.add_point(Vector3(0, 0, 120))
	lane.set_meta("next", [])
	root.add_child(lane)
	var front := TrafficVehicle.new()
	var rear := TrafficVehicle.new()
	for vehicle in [front, rear]:
		vehicle.manager = manager
		manager.add_child(vehicle)
		manager.fleet.append(vehicle)
	front.activate(lane, 30.0)
	rear.activate(lane, 10.0)
	front.speed = 0.0
	rear.speed = 12.0
	for frame in 360:
		await physics_frame
		assert(front.position.z - rear.position.z >= 7.0, "Rear traffic pushed/overlapped leader")
	assert(rear.position.z > 12.0, "Rear traffic never accelerated")
	assert(rear.current_speed < 0.2, "Rear traffic did not brake")
	assert(absf(rear.position.x) < 0.01 and absf(rear.position.y) < 0.01, "Traffic left lane")
	front.speed = 8.0
	var before := rear.position.z
	for frame in 120:
		await physics_frame
	assert(rear.position.z > before + 1.0, "Rear did not resume")
	manager.free()
	lane.free()
	print("PASS traffic: acceleration, safe gap, braking, release, lane stability")
	quit()
