extends SceneTree

func _init() -> void:
	var signal_controller := SignageBuilder.new()
	var vehicle := TrafficVehicle.new()
	vehicle.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -12.0)])
	vehicle.speed = 6.0
	vehicle.signal_controller = signal_controller
	vehicle.signal_group = 0
	vehicle.signal_positions = PackedVector3Array([Vector3(0.0, 0.0, -4.0)])
	root.add_child(vehicle)
	await process_frame
	signal_controller.set("_signal_time", 20.0) # Group 0 has red here.
	vehicle._process(1.0)
	assert(vehicle.position.distance_to(Vector3.ZERO) < 0.01, "Traffic ignored red signal")
	signal_controller.set("_signal_time", 0.0) # Group 0 is green here.
	vehicle._process(1.0)
	assert(vehicle.position.z < -5.0, "Traffic did not release on green signal")
	print("PASS traffic-signal regression: red stop and green release")
	quit()
