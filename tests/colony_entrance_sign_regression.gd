extends SceneTree

var _failures := 0

func _init() -> void:
	var world := (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var street_life: StreetLifeBuilder = world.street_life
	for expected_name in ["VIDYA NAGAR 2", "SURYA NAGAR"]:
		var found := false
		for placement: Dictionary in street_life.gate_placements:
			if str(placement.name).to_upper() != expected_name:
				continue
			found = true
			_check(placement.offset_from_entrance >= 7.0 and placement.offset_from_entrance <= 39.0,
				"%s sign must be placed down the colony lane, away from the junction" % expected_name)
			_check(placement.road_type in ["residential", "living_street", "unclassified", "service", "road"],
				"%s sign must use a local access lane, not a through-road" % expected_name)
			_check(placement.post_clearance >= 0.5,
				"%s sign supports must clear the mapped road edge" % expected_name)
			var matching_road := false
			for road: Dictionary in world.map_data.roads:
				if road.way_id != placement.road_way_id:
					continue
				var points: PackedVector2Array = road.points
				for index in range(1, points.size()):
					if Geometry2D.get_closest_point_to_segment(placement.center, points[index - 1], points[index]).distance_to(placement.center) < 0.1:
						matching_road = true
			_check(matching_road, "%s sign must align to its source road geometry" % expected_name)
		_check(found, "%s sign placement must be generated" % expected_name)
	world.queue_free()
	await process_frame
	if _failures > 0:
		push_error("FAIL colony entrance sign regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS colony entrance sign regression: Vidya Nagar 2 and Surya Nagar boards sit down their mapped access lanes with clear roadside supports")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
