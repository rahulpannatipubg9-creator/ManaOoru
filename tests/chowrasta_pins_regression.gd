extends SceneTree

## Validates that source-backed business coordinates become real game-map pins.
func _init() -> void:
	var data := MapData.load_shared()
	assert(data.chowrasta_reference_pin_count > 0, "Chowrasta source-backed pins missing")
	var hdfc_pin: Dictionary = {}
	for landmark in data.landmarks:
		if landmark.name == "HDFC Bank" and landmark.position.length() < 1000.0:
			hdfc_pin = landmark
			break
	assert(not hdfc_pin.is_empty(), "Mapped HDFC Bank Chowrasta pin missing")
	assert(hdfc_pin.position.length() < 15.0, "HDFC Bank must remain at its exact source coordinate")
	for exact_name in ["NEW ASHOK THEATRE", "ARJUN SWEET HOUSE"]:
		var found := false
		for landmark in data.landmarks:
			if landmark.name == exact_name:
				found = true
				assert(landmark.position.length() <= 1000.0, "%s must be in the Chowrasta zone" % exact_name)
				break
		assert(found, "Exact Chowrasta pin missing: %s" % exact_name)
	for landmark in data.landmarks:
		if landmark.category == "Shop":
			assert(GeoProjection.is_playable(landmark.position),
				"Shop pins must remain inside the playable zone")
	assert(not data.user_shop_import_stats.is_empty(), "User Overpass export must load")
	var imported: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapData.USER_SHOPS_PATH))
	var expected := 0
	for element: Dictionary in imported.elements:
		var coordinate: Dictionary = element if element.get("type") == "node" else element.get("center", {})
		var tags: Dictionary = element.get("tags", {})
		if not coordinate.has("lat") or not coordinate.has("lon") or MapData.poi_kind(tags).is_empty():
			continue
		var point := GeoProjection.lon_lat_to_map(float(coordinate.lon), float(coordinate.lat))
		if not GeoProjection.is_playable(point):
			continue
		var found := false
		for poi in data.pois:
			if poi.position.distance_to(point) < 40.0 and poi.name.to_lower() == str(tags.get("name", "")).strip_edges().to_lower() and poi.kind == MapData.poi_kind(tags):
				found = true
				break
		assert(found, "User place missing: %s" % str(tags.get("name", element.id)))
		expected += 1
	print("PASS user shop import: %d eligible places, %s" % [expected, data.user_shop_import_stats])
	print("PASS Chowrasta pins regression: %d source-backed pins in the 1 km zone" % data.chowrasta_reference_pin_count)
	quit()
