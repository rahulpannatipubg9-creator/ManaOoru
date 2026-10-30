extends SceneTree

## Proves a start-up optimisation left the world unchanged. Boots the real main scene,
## forces every streamed chunk to build, and writes one line per fact to the path after
## "--": counts, spawn spots, and a hash of every mesh, collider, multimesh and label.
##   run_godot.sh 400 --headless --path . --script tests/world_fingerprint.gd -- out.txt
## Compare two runs with diff. Nothing may change between a baseline and an optimised build.

var lines: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func fact(key: String, value: Variant) -> void:
	lines.append("%s = %s" % [key, str(value)])

func _run() -> void:
	var started := Time.get_ticks_msec()
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	print("main scene ready after %d ms" % (Time.get_ticks_msec() - started))
	game.city_life.save_enabled = false
	game.set_process(false)
	var world: Node3D = game.get_node("World")
	_record_data(world)
	_record_placement(game, world)
	world.buildings.stream_enabled = false
	world.buildings.build_all()
	world.trees.build_around(Vector2.ZERO, INF)
	var counts := {}
	var digests := {}
	_walk(world, counts, digests)
	var kinds: Array = counts.keys()
	kinds.sort()
	for kind: String in kinds:
		fact("nodes." + kind, counts[kind])
	var groups: Array = digests.keys()
	groups.sort()
	for group: String in groups:
		fact("digest." + group, (digests[group] as PackedStringArray).size())
		var joined := "\n".join(_sorted(digests[group]))
		fact("digest." + group + ".md5", joined.md5_text())
	fact("tree_count", world.trees.tree_count)
	var path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://world_fingerprint.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("fingerprint: %d facts written to %s" % [lines.size(), path])
	quit(0)

func _sorted(items: PackedStringArray) -> PackedStringArray:
	var result := items.duplicate()
	result.sort()
	return result

func _record_data(world: Node3D) -> void:
	var data: MapData = world.map_data
	fact("roads", data.roads.size())
	fact("roads.md5", str(data.roads).md5_text())
	fact("topoexport_roads", data.topoexport_roads.size())
	fact("topoexport_roads.md5", str(data.topoexport_roads).md5_text())
	fact("topoexport_trees", data.topoexport_trees.size())
	fact("topoexport_trees.md5", str(data.topoexport_trees).md5_text())
	fact("buildings", data.buildings.size())
	fact("buildings.md5", str(data.buildings).md5_text())
	fact("buildings.by_source", [data.osm_building_count, data.microsoft_building_count, data.overture_building_count])
	fact("landmarks", data.landmarks.size())
	fact("landmarks.md5", str(data.landmarks).md5_text())
	fact("pois", data.pois.size())
	fact("pois.md5", str(data.pois).md5_text())
	fact("places.md5", str(data.places).md5_text())
	fact("areas.md5", str(data.areas).md5_text())
	fact("barriers.md5", str(data.barriers).md5_text())
	fact("railways.md5", str(data.railways).md5_text())
	fact("crossings.md5", str(data.crossings).md5_text())
	fact("level_crossings.md5", str(data.level_crossings).md5_text())
	fact("traffic_signals.md5", str(data.traffic_signals).md5_text())
	fact("source_road_way_count", data.source_road_way_count)
	fact("pin_count", data.chowrasta_reference_pin_count)
	fact("user_shop_import_stats", data.user_shop_import_stats)
	fact("attribution", data.attribution)
	fact("rendered_footprints", world.rendered_building_footprints.size())
	fact("footprints.md5", str(world.rendered_building_footprints).md5_text())
	fact("building_metadata.md5", str(world.buildings.building_metadata).md5_text())
	fact("facade_mounts", world.buildings.facade_mounts.size())
	fact("facade_mounts.md5", str(world.buildings.facade_mounts).md5_text())
	fact("unmounted_boards", world.buildings.unmounted_board_count)
	fact("roads.rendered", [world.roads.source_rendered_way_count, world.roads.topoexport_rendered_count, world.roads.topoexport_duplicate_count])
	fact("signage", [world.signage.board_count, world.signage.signal_count, world.signage.street_plate_count, world.signage.junction_board_count, world.signage.dustbin_count()])

func _record_placement(game: Node3D, world: Node3D) -> void:
	fact("player_spawn", world.player_spawn)
	fact("vehicle_spawns", world.vehicle_spawns)
	fact("helicopter_spawn", world.helicopter_spawn)
	var bodies: PackedStringArray = []
	for vehicle: Node3D in game.vehicles:
		bodies.append("%s %s" % [vehicle.name, vehicle.global_transform])
	bodies.sort()
	fact("vehicles.md5", "\n".join(bodies).md5_text())

## One digest line per node: its transform plus whatever it draws or collides with.
func _walk(node: Node, counts: Dictionary, digests: Dictionary) -> void:
	var kind := node.get_class()
	counts[kind] = int(counts.get(kind, 0)) + 1
	var group := _group_of(node)
	var line := ""
	if node is MeshInstance3D and node.mesh != null:
		line = "%s %s %s" % [node.global_transform, _mesh_digest(node.mesh), node.visibility_range_end]
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var multimesh: MultiMesh = node.multimesh
		line = "%s %d %s %s" % [node.global_transform, multimesh.instance_count, multimesh.buffer.to_byte_array().size(), multimesh.buffer.to_byte_array().compress().hex_encode().md5_text()]
	elif node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		line = "%s %s" % [node.global_transform, node.shape.get_faces().to_byte_array().compress().hex_encode().md5_text()]
	elif node is CollisionShape3D and node.shape != null:
		line = "%s %s" % [node.global_transform, node.shape.get_class()]
	elif node is Label3D:
		line = "%s %s" % [node.global_transform, node.text]
	if not line.is_empty():
		if not digests.has(group):
			digests[group] = PackedStringArray()
		digests[group].append(line)
	for child in node.get_children():
		_walk(child, counts, digests)

func _group_of(node: Node) -> String:
	var path := String(node.get_path())
	var parts := path.split("/")
	var at := parts.find("World")
	if at < 0 or at + 1 >= parts.size():
		return "world"
	return parts[at + 1].get_slice("_", 0).rstrip("0123456789@")

func _mesh_digest(mesh: Mesh) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_MD5)
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
			var values: Variant = arrays[slot]
			if values != null:
				digest.update(values.to_byte_array())
	return digest.finish().hex_encode()
