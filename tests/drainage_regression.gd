extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var demo := load("res://scenes/tests/drainage_demo.tscn").instantiate() as Node3D
	root.add_child(demo)
	for i in range(3):
		await physics_frame
	var space := demo.get_world_3d().direct_space_state
	var open_query := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 10), Vector3(0, -5, 10))
	var open_hit := space.intersect_ray(open_query)
	assert(not open_hit.is_empty(), "Open channel must have a solid bed")
	assert(absf(open_hit.position.y + 1.425) < 0.01, "Water must not behave as a solid cover")
	var road_query := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0))
	var road_hit := space.intersect_ray(road_query)
	assert(not road_hit.is_empty() and absf(road_hit.position.y - 0.37) < 0.01, "Road must span the covered channel")
	var cover_query := PhysicsRayQueryParameters3D.create(Vector3(-9, 5, 15), Vector3(-9, -5, 15))
	var cover_hit := space.intersect_ray(cover_query)
	assert(not cover_hit.is_empty() and absf(cover_hit.position.y - 1.125) < 0.01, "Covered drain must have a solid lid")
	print("PASS: open bed, non-solid water, road crossing, covered-drain lid")
	demo.queue_free()
	await process_frame
	quit()
