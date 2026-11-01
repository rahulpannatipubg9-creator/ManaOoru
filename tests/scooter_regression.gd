extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3.ZERO)
	lane.curve.add_point(Vector3(0,0,50))
	lane.set_meta("next", [])
	root.add_child(lane)
	var scooter := TrafficVehicle.new()
	scooter.vehicle_kind = "scooter"
	root.add_child(scooter)
	assert(scooter.has_node("Driver") and scooter.has_node("Passenger"), "Scooter needs seated occupants")
	scooter.activate(lane, 0.0)
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 2)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(0,1,15)
	root.add_child(blocker)
	for frame in 300:
		await physics_frame
	assert(scooter.position.z > 1.0 and scooter.position.z < 10.0, "Scooter must approach and stop at obstacle")
	assert(scooter.current_speed < 0.1, "Scooter did not stop")
	blocker.position.x = 20.0
	var before := scooter.position.z
	for frame in 120:
		await physics_frame
	assert(scooter.position.z > before + 1.0, "Scooter did not resume")
	scooter.free()
	blocker.free()
	lane.free()
	print("PASS scooter: occupants, obstacle stop and resume")
	quit()
