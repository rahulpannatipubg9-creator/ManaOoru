extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var data := MapData.load_shared()
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.setup(data, func(_p): return false)

	var mounted_names: Array[String] = []
	var user_facade_count := 0
	for child in builder.get_children():
		if child.has_meta("shop_name"):
			user_facade_count += 1
			mounted_names.append(str(child.get_meta("shop_name")))

	print("Total mounted user facade signs found: ", user_facade_count)

	# Read all shops from survey_batch_030_135.tsv
	var file := FileAccess.open("res://data/survey/survey_batch_030_135.tsv", FileAccess.READ)
	assert(file != null, "survey_batch_030_135.tsv must exist")

	var header := file.get_line().split("\t")
	var target_names: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var cols := line.split("\t")
		if cols.size() > 1:
			target_names.append(cols[1].strip_edges())

	print("Batch 030-135 targets count: ", target_names.size())

	var found_count := 0
	var missing: Array[String] = []
	for target in target_names:
		var found := false
		if builder.has_facade_board(target):
			found = true
		else:
			for mname in mounted_names:
				if mname.to_lower() == target.to_lower() or target.to_lower() in mname.to_lower() or mname.to_lower() in target.to_lower():
					found = true
					break
		if found:
			found_count += 1
		else:
			missing.append(target)

	print("Mounted Batch 030-135 shops: %d / %d (%.1f%%)" % [found_count, target_names.size(), (float(found_count) / float(target_names.size())) * 100.0])
	if not missing.is_empty():
		print("Missing shops count: ", missing.size())
		print("Sample missing (up to 10): ", missing.slice(0, 10))

	assert(found_count == target_names.size(), "All 106/106 batch shops must be mounted on facades")
	print("PASS 100% of Batch 030-135 storefront facade signs mounted in Godavarikhani world!")
	builder.queue_free()
	await process_frame
	quit()
