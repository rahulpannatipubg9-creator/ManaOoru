extends SceneTree

func _init() -> void:
	var original := {"floors": 2, "color": Color(0.7, 0.6, 0.5, 17.0 / 255.0)}
	var explicit := BuildingBuilder.apply_source_appearance(original.duplicate(), {"building:colour": "#e4cba8", "height": "8.4 m"})
	assert(is_equal_approx(explicit.wall_height, 8.4), "Source height must not be rounded to storeys")
	assert(is_equal_approx(explicit.color.r, Color.html("#e4cba8").r))
	assert(explicit.color.a8 == original.color.a8, "Paint overrides must retain shader encoding")
	var invalid := BuildingBuilder.apply_source_appearance(original.duplicate(), {"building:colour": "unknown", "height": "20 feet"})
	assert(invalid.color == original.color and not invalid.has("wall_height"), "Do not guess invalid source attributes")
	var empty := BuildingBuilder.apply_source_appearance(original.duplicate(), {})
	assert(empty.color == original.color and empty.floors == original.floors)
	var unbound := BuildingBuilder.apply_photo_reference(original.duplicate(), {"building:levels":"4"})
	assert(unbound.floors == original.floors, "Unbound photographs must not override a building")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BuildingBuilder.APPEARANCE_REFERENCES_PATH)).buildings["osm/way/599199178"]
	var observed := BuildingBuilder.apply_photo_reference(original.duplicate(), reference)
	assert(observed.floors == 2 and observed.appearance_evidence.photo_reference.capture_date == "2020-06-11")
	assert(observed.color.a8 == original.color.a8 and not observed.has("wall_height"), "Visual storeys do not establish metric height")
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	var ring := PackedVector2Array([Vector2(0,0),Vector2(12,0),Vector2(12,12),Vector2(0,12)])
	# Force the frontage condition which previously randomized residential shops.
	builder._main_road_grid[Vector2i.ZERO] = PackedVector2Array([Vector2(-20,0),Vector2(30,0)])
	var home := builder._style_for(ring,144.0,{"building":"house"})
	assert((home.color.a8 & 1) == 1, "Explicit homes must retain residential facades")
	print("PASS building appearance: explicit metric height, paint, shader flags, invalid evidence rejection, residential facade")
	quit()
