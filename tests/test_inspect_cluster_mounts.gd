extends SceneTree

func _init() -> void:
	var data := MapData.load_shared()
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.setup(data, func(_p): return false)

	var mounts := {}
	for child in builder.get_children():
		if child.has_meta("shop_id"):
			mounts[str(child.get_meta("shop_id"))] = child

	print("Total mounts indexed: ", mounts.size())

	# Inspect GDK-C100-168 and GDK-C100-176
	for check_id in ["GDK-C100-165", "GDK-C100-166", "GDK-C100-167", "GDK-C100-168", "GDK-C100-173", "GDK-C100-174", "GDK-C100-175", "GDK-C100-176"]:
		if mounts.has(check_id):
			var m: Node3D = mounts[check_id]
			print("%s: pos=%s, normal=%s, basis_z=%s" % [check_id, m.global_position, m.global_basis.z, m.basis.z])
		else:
			print("%s: NOT FOUND IN MOUNTS!" % check_id)

	quit(0)
