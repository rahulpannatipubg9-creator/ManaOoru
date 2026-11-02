extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller := TrafficLightController.new()
	root.add_child(controller)
	controller.set_physics_process(false)
	controller.elapsed = 16.0
	assert(controller.phase_for_group(0) == "red" and controller.phase_for_group(1) == "green")
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3.ZERO)
	lane.curve.add_point(Vector3(0, 0, 100))
	lane.set_meta("next", [])
	root.add_child(lane)
	var stop := TrafficStopPoint.new()
	stop.controller = controller
	stop.progress = 30.0
	root.add_child(stop)
	lane.set_meta("stop", stop)
	var vehicle := TrafficVehicle.new()
	root.add_child(vehicle)
	vehicle.activate(lane, 10.0)
	vehicle.speed = 10.0
	for frame in 360:
		await physics_frame
	assert(vehicle.position.z + vehicle.vehicle_length * 0.5 < 30.0, "Red stop line crossed")
	assert(vehicle.current_speed < 0.1, "Red light failed to stop")
	controller.elapsed = 12.5
	assert(controller.phase_for_group(0) == "amber")
	var before := vehicle.position.z
	for frame in 30:
		await physics_frame
	assert(vehicle.position.z < before + 0.05, "Yellow released waiting traffic")
	controller.elapsed = 0.0
	for frame in 180:
		await physics_frame
	assert(vehicle.position.z > 35.0, "Green failed to release traffic")
	controller.elapsed = 16.0
	before = vehicle.position.z
	for frame in 60:
		await physics_frame
	assert(vehicle.position.z > before + 2.0, "Vehicle stopped inside junction")
	vehicle.free()
	stop.free()
	lane.free()
	controller.free()
	print("PASS traffic signals: phases, red/yellow stop, green release, committed clearance")
	quit()
