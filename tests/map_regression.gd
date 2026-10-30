extends SceneTree

const MAP_DATA_PATH := "res://data/osm/godavarikhani_core.json"

func _init() -> void:
	var file := FileAccess.open(MAP_DATA_PATH, FileAccess.READ)
	assert(file != null, "Map data must load")
	assert(JSON.parse_string(file.get_as_text()) is Dictionary, "Map data must be valid JSON")

	var data := MapData.load_shared()
	assert(data.chowrasta_reference_pin_count > 0, "Chowrasta source-backed shop pins missing")
	var hdfc_pin: Dictionary = {}
	for landmark in data.landmarks:
		if landmark.name == "HDFC Bank" and landmark.position.length() < 1000.0:
			hdfc_pin = landmark
			break
	assert(not hdfc_pin.is_empty(), "Mapped HDFC Bank Chowrasta pin missing")
	assert(hdfc_pin.position.length() < 15.0, "HDFC Bank pin must remain at its exact source coordinate")
	var expected_ids := {}
	for road in data.roads:
		# Bridge decks are paved by the Godavari bridge model, not by RoadBuilder.
		if road.get("structure", "") != "bridge":
			expected_ids[road.way_id] = true

	var world_scene := load("res://scenes/world/world.tscn") as PackedScene
	assert(world_scene != null, "World scene must load")
	var world := world_scene.instantiate()
	root.add_child(world)
	await process_frame

	var rendered_road_ids: Dictionary = world.roads.rendered_way_ids
	var missing := 0
	for road_id in expected_ids:
		if not rendered_road_ids.has(road_id):
			missing += 1
			push_error("Missing rendered highway way: %s" % road_id)
	if missing > 0:
		print("FAIL map regression: %d highway ways inside the playable radius were not rendered" % missing)
		quit(1)
		return
	assert(world.street_life.pole_count > 100, "Main roads must have visible street lamps")
	assert(world.street_life.utility_pole_count > 20, "Main roads must have GDK utility poles and wiring")
	print("PASS map regression: %d/%d highway ways with geometry inside the playable radius rendered (%d source ways)" %
		[rendered_road_ids.size(), expected_ids.size(), data.source_road_way_count])
	quit()
