extends SceneTree

func _init() -> void:
	var data := MapData.load_shared()
	assert(data.topoexport_roads.size() == 273, "TopoExport road export must retain all 273 road features")
	assert(data.topoexport_trees.size() == 3786, "TopoExport tree export must retain all 3786 tree points")
	for road in data.topoexport_roads:
		assert(float(road.width) > 0.0, "TopoExport roads must retain a positive width")
		assert(road.points.size() >= 2, "TopoExport roads must retain line geometry")
	for tree in data.topoexport_trees:
		assert(float(tree.height) > 0.0 and float(tree.crown_diameter) > 0.0,
			"TopoExport trees must retain height and crown diameter")
	assert(data.topoexport_roads[0].points[0] is Vector2, "TopoExport roads must be converted to game coordinates")
	assert(data.topoexport_trees[0].point is Vector2, "TopoExport trees must be converted to game coordinates")
	print("PASS TopoExport regression: %d supplemental roads and %d measured trees loaded" %
		[data.topoexport_roads.size(), data.topoexport_trees.size()])
	quit()
