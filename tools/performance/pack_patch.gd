extends SceneTree

func _init() -> void:
	var packer := PCKPacker.new()
	var err := packer.pck_start("builds/pad7_patch.pck")
	if err != OK:
		printerr("Failed to start pck: ", err)
		quit(1)
		return
	var files := [
		"scripts/world/custom_asset_placements.gd",
		"scripts/world/world_generator.gd",
		"data/world/custom_placements.json"
	]
	for f in files:
		packer.add_file("res://" + f, f)
	packer.flush()
	print("SUCCESS: builds/pad7_patch.pck created")
	quit(0)
