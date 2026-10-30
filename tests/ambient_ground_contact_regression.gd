extends SceneTree

class SurfaceFixture extends Node3D:
	var signage := SignageBuilder.new()
	var buildings := {"storefront_allocator": {"units": []}}
	func ground_height(_point: Vector2) -> float:
		return 2.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var vehicle := TrafficVehicle.new()
	vehicle.route = PackedVector3Array([Vector3.ZERO, Vector3(10,0,0)])
	vehicle.speed = 5.0
	# Route vertices have equal height, but the intervening road rises by a metre.
	vehicle.ground_sampler = func(point: Vector2) -> float: return sin(point.x * PI / 10.0)
	root.add_child(vehicle)
	vehicle.set_process(false)
	vehicle._process(1.0)
	assert(absf(vehicle.position.x - 5.0) < 0.001, "Grounding must not change route progress")
	assert(absf(vehicle.position.y - 1.0) < 0.001, "Traffic must follow intervening road relief instead of floating along endpoint interpolation")
	var resident = load("res://scenes/world/pedestrian.tscn").instantiate()
	resident.idle_mode = true
	resident.ground_sampler = func(_point: Vector2) -> float: return 3.0
	root.add_child(resident)
	resident.set_process(false)
	resident._process(0.0)
	assert(absf(resident.position.y - 2.93) < 0.001, "Neutral capsule soles must meet the supplied surface")
	resident.left_leg.rotation.x = 0.45
	resident.right_leg.rotation.x = -0.45
	resident._update_ground_contact(0.0)
	assert(resident.position.y < 2.91, "Animated sole lift must lower the root rather than leave both feet hovering")
	assert(absf(resident.position.x) < 0.001 and absf(resident.position.z) < 0.001, "Contact correction must not move residents horizontally")
	var fixture := SurfaceFixture.new()
	root.add_child(fixture)
	var road := StaticBody3D.new()
	road.collision_layer = RoadBuilder.ROAD_LAYER
	road.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4,0.1,4)
	collision.shape = shape
	road.position.y = 2.01
	road.add_child(collision)
	fixture.add_child(road)
	for frame in range(2):
		await physics_frame
	assert(absf(resident.sample_world_surface(Vector2.ZERO, fixture) - 2.06) < 0.001, "Residents must use the visible road surface")
	assert(absf(resident.sample_world_surface(Vector2(10,10), fixture) - 1.8) < 0.001, "Residents off-road must use visible terrain rather than its raised collision surface")
	fixture.signage.free()
	fixture.free()
	print("PASS ambient contact: nonlinear terrain, unchanged route progress, neutral and animated foot support")
	vehicle.free()
	resident.free()
	quit()
