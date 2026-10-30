extends SceneTree
## Offline evidence inventory, not a claim of field-survey accuracy.
func _init() -> void:
	var data := MapData.load_shared()
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.setup(data, func(_ring: PackedVector2Array) -> bool: return false)
	var end := GeoProjection.lon_lat_to_map(79.51507258, 18.7542867)
	var records := []
	var sourced_paint := 0
	var sourced_height := 0
	var photo_count := 0
	for i in builder.footprints.size():
		var center := BuildingBuilder._centroid(builder.footprints[i])
		var meta: Dictionary = builder.building_metadata[i]
		var evidence: Dictionary = meta.appearance_evidence
		var photo_bound := evidence.has("photo_reference")
		# A narrow study envelope between the two known pins, not a road survey.
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center, Vector2.ZERO, end)) > 50.0 and not photo_bound:
			continue
		photo_count += int(photo_bound)
		sourced_paint += int(evidence.has("paint"))
		sourced_height += int(evidence.has("height") or evidence.has("floors"))
		var gps := GeoProjection.map_to_lon_lat(center)
		var names := []
		for mount: Dictionary in builder.facade_mounts:
			if mount.building_index == i:
				names.append(builder._boards[mount.board_index].name)
		records.append({"building_id":meta.id,"longitude":gps[0],"latitude":gps[1],
			"source_tags":meta.tags,"assigned_signs":names,"appearance_evidence":evidence,
			"photo_binding":"historical_visual_pilot" if photo_bound else "unverified","needs_photo_review":not photo_bound})
	var report := {"study":"Chowrasta to New Ashok Theatre; 50m around straight pin-to-pin study axis, not surveyed road boundary",
		"building_count":records.size(),"historical_photo_pilots":photo_count,"explicit_paint_count":sourced_paint,
		"explicit_height_or_floor_count":sourced_height,"records":records,
		"limitations":"Includes dated photo pilot buildings adjoining the envelope. Visual matches are interpretations, not surveys/current-condition confirmation. Do not derive building position from camera GPS. Other fallback paint/heights remain illustrative."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/facade_review"))
	var file := FileAccess.open("res://outputs/facade_review/chowrasta_inventory.json",FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("FACADE REVIEW: ",records.size()," buildings; ",sourced_paint," source paint; ",sourced_height," source height/floors")
	quit()
