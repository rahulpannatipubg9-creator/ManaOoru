extends SceneTree
func _init() -> void:
	var data := MapData.load_shared()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapData.OVERTURE_BUILDINGS_PATH))
	assert(data.overture_building_count == raw.features.size() and data.overture_building_count > 0)
	var source_ids := {}
	for feature: Dictionary in raw.features:
		source_ids[feature.properties.id] = feature
	var found := 0
	for building: Dictionary in data.buildings:
		if building.source != "overture":
			continue
		assert(source_ids.has(building.overture_id), "Supplement must retain its actual source ID")
		var feature: Dictionary = source_ids[building.overture_id]
		var coordinates: Array = feature.geometry.coordinates[0]
		var points: PackedVector2Array = building.points
		assert(points.size() == coordinates.size()-1, "Closed source ring should not duplicate its final vertex")
		var center := Vector2.ZERO
		for i in points.size():
			assert(points[i].distance_to(GeoProjection.lon_lat_to_map(coordinates[i][0],coordinates[i][1])) < 0.01,
				"Do not shift or reshape source geometry")
			center += points[i]
		center /= points.size()
		assert(center.distance_to(Vector2(315.6,-334.57)) < 470.0, "Supplement must stay near the target neighborhood")
		assert(building.tags.is_empty(), "Do not fabricate floor counts or shop identities")
		found += 1
	assert(found == data.overture_building_count)
	print("PASS Overture integration: %d source IDs, original geometry, no fabricated attributes" % found)
	quit()
