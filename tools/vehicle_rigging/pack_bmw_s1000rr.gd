extends SceneTree
func _init() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file("res://assets/models/vehicles/bmw_s1000_rr/bmw_s1000rr_rig.glb", state)
	if result != OK:
		printerr("Failed to load bmw_s1000_rr_rig.glb: ", result)
		quit(1)
		return
	var model := document.generate_scene(state)
	var scene := PackedScene.new()
	var err := scene.pack(model)
	if err != OK:
		printerr("Failed to pack scene: ", err)
		model.free()
		quit(1)
		return
	var saved := ResourceSaver.save(scene, "res://assets/models/vehicles/bmw_s1000_rr/bmw_s1000_rr.scn")
	print("PACK_BMW_S1000RR saved with code: ", saved)
	model.free()
	quit(saved)

