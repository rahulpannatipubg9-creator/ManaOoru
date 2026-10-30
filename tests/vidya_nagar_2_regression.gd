extends SceneTree

## Vidya Nagar 2 must contain source-backed homes and be ready when the game opens.
const CENTER := Vector2(315.60, -334.57)
const RADIUS := 400.0

func _init() -> void:
	var data := MapData.load_shared()
	var mapped_homes := 0
	for building in data.buildings:
		var points: PackedVector2Array = building.points
		var center := Vector2.ZERO
		for point in points:
			center += point
		if not points.is_empty() and (center / points.size()).distance_to(CENTER) <= RADIUS:
			mapped_homes += 1
	assert(mapped_homes >= 500, "Vidya Nagar 2 must retain its source-backed building footprint density")
	var world_scene := load("res://scenes/world/world.tscn") as PackedScene
	var world := world_scene.instantiate()
	root.add_child(world)
	await process_frame
	var entrance := world.get_node_or_null("VidyaNagar2PhotoEntrance")
	assert(entrance != null and entrance.get_child_count()>0,"Vidyanagar 2 photo entrance must be built, not silently omitted")
	assert(float(entrance.get_meta("clearance")) >= 5.0,"Entrance frame must clear vehicles")
	var street := world.get_node_or_null("VidyaNagar2Street")
	assert(street != null and street.get_child_count() > 0, "Vidya Nagar 2 street replica models must be generated and added")
	assert(street.wall_count > 0, "Compound walls must be generated along the street")
	assert(street.gate_count > 0, "Gates must be generated along the street")
	assert(street.porch_count > 0, "Corrugated porches must be generated")
	assert(street.tree_count > 0, "Setback trees must be generated")
	var built: Dictionary = world.buildings.get("_built")
	var target_chunks := 0
	for cell: Vector2i in built:
		var chunk_center := (Vector2(cell) + Vector2(0.5, 0.5)) * BuildingBuilder.CHUNK_SIZE
		if chunk_center.distance_to(CENTER) <= RADIUS + BuildingBuilder.CHUNK_SIZE:
			target_chunks += 1
	assert(target_chunks > 0, "Vidya Nagar 2 building chunks must preload")
	print("PASS Vidya Nagar 2 regression: %d source-backed homes, district chunks preloaded" % mapped_homes)
	quit()
