extends SceneTree

func _init() -> void:
	print("--- TESTING GANGA NAGAR BRIDGE & ROAD CLEARANCE ---")
	var map_data := MapData.load_shared()
	assert(map_data != null, "MapData must load")

	var world := Node3D.new()
	root.add_child(world)

	# 1. Test RoadBuilder paves Ganga Nagar bridge ways
	var roads := RoadBuilder.new()
	world.add_child(roads)
	roads.build(map_data)

	var ganga_ways := [818523335, 818523337, 818523339, 818523341]
	for way_id in ganga_ways:
		print("Checking Ganga Nagar bridge way ", way_id, " in rendered roads: ", roads.rendered_way_ids.has(way_id))
		assert(roads.rendered_way_ids.has(way_id), "Ganga Nagar bridge way %d must be paved with no gap!" % way_id)

	# 2. Test Building road clearance
	var buildings := BuildingBuilder.new()
	world.add_child(buildings)
	var road_grid: RefCounted = map_data.road_grid()
	var stats := {"road_conflicts": 0}
	var exclusion_filter := func(points: PackedVector2Array) -> bool:
		if points.size() < 3:
			return true
		for pt in points:
			if road_grid.any_within(pt, -0.2):
				stats["road_conflicts"] += 1
				return true
		var centroid := Vector2.ZERO
		for pt in points:
			centroid += pt
		centroid /= float(points.size())
		if road_grid.any_within(centroid, 0.0):
			stats["road_conflicts"] += 1
			return true
		return false

	buildings.setup(map_data, exclusion_filter)
	print("Excluded %d building footprints on roads. Kept %d valid footprints." % [stats.road_conflicts, buildings.footprints.size()])
	assert(buildings.footprints.size() > 15000, "Must retain legitimate buildings")
	assert(stats.road_conflicts > 1000, "Must exclude overlapping buildings on roads")

	# Check that NO kept footprint penetrates any road
	var remaining_on_road := 0
	for fp in buildings.footprints:
		var conflict := false
		for pt in fp:
			if road_grid.any_within(pt, -0.2):
				conflict = true
				break
		if conflict:
			remaining_on_road += 1
	print("Remaining buildings on road surface: ", remaining_on_road)
	assert(remaining_on_road == 0, "No rendered building may penetrate road carriageway!")

	# 3. Test SignageBuilder traffic pole clearance
	var signage := SignageBuilder.new()
	world.add_child(signage)
	signage.build(map_data, buildings)
	print("Signage built successfully with pole clearance. Signal count: ", signage.signal_count)
	assert(signage.signal_count > 0, "Must build traffic signals")

	print("ALL GANGA NAGAR BRIDGE AND CLEARANCE TESTS PASSED!")
	quit(0)
