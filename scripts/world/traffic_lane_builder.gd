class_name TrafficLaneBuilder
extends RefCounted

## Directed lane sections share graph nodes, never proximity-connect overpasses.
static func build(world: Node3D, data: MapData, parent: Node3D) -> Array[Path3D]:
	var lanes: Array[Path3D] = []
	var starts: Dictionary = {}
	for road: Dictionary in data.roads:
		if RoadStyle.is_path(str(road.kind)) or road.points.size() < 2:
			continue
		if not str(road.kind) in RoadNetwork.DRIVE_COST:
			continue
		for direction: int in [1, -1]:
			if int(road.oneway) != 0 and int(road.oneway) != direction:
				continue
			for i in range(road.points.size() - 1):
				var ai := i if direction == 1 else i + 1
				var bi := i + 1 if direction == 1 else i
				var a: Vector2 = road.points[ai]
				var b: Vector2 = road.points[bi]
				if a.distance_to(b) < 1.0:
					continue
				var forward := (b - a).normalized()
				var left := -forward.orthogonal() * maxf(1.0, RoadStyle.width(road) * 0.22)
				var lane := Path3D.new()
				lane.name = "Lane_%d" % lanes.size()
				lane.curve = Curve3D.new()
				lane.curve.bake_interval = 1.0
				var samples := maxi(1, ceili(a.distance_to(b) / 4.0))
				for j in range(samples + 1):
					var point := a.lerp(b, float(j) / samples) + left
					var height: float = world.ground_height(point)
					if world.has_method("flyover_height_at"):
						height = world.flyover_height_at(point, height)
					lane.curve.add_point(GeoProjection.map_to_world(point, height + RoadStyle.surface_height(str(road.kind))))
				lane.set_meta("junction_point", b)
				lane.set_meta("start", road.node_ids[ai])
				lane.set_meta("end", road.node_ids[bi])
				lane.set_meta("heading", Vector3(forward.x, 0.0, forward.y))
				lane.set_meta("road_name", str(road.name))
				lane.set_meta("kind", str(road.kind))
				var district := "city"
				if a.distance_to(Vector2(1543, 1388)) < 850.0:
					district = "mine"
				if "rajeev" in str(road.name).to_lower() or "rajiv" in str(road.name).to_lower() or str(road.kind) in ["trunk", "motorway"]:
					district = "highway"
				lane.set_meta("district", district)
				parent.add_child(lane)
				lanes.append(lane)
				var id: int = road.node_ids[ai]
				if not starts.has(id):
					starts[id] = []
				starts[id].append(lane)
	# Keep every legal outgoing option while finding roads that reach cycles.
	var incoming: Dictionary = {}
	var degree: Dictionary = {}
	for lane in lanes:
		var choices: Array[Path3D] = []
		var heading: Vector3 = lane.get_meta("heading")
		for candidate: Path3D in starts.get(lane.get_meta("end"), []):
			if candidate.get_meta("end") == lane.get_meta("start") or heading.dot(candidate.get_meta("heading")) < -0.8:
				continue
			choices.append(candidate)
			if not incoming.has(candidate):
				incoming[candidate] = []
			incoming[candidate].append(lane)
		lane.set_meta("options", choices)
		degree[lane] = choices.size()
	var queue: Array[Path3D] = []
	for lane in lanes:
		if int(degree[lane]) == 0:
			queue.append(lane)
	var cursor := 0
	while cursor < queue.size():
		var terminal := queue[cursor]
		cursor += 1
		for predecessor: Path3D in incoming.get(terminal, []):
			degree[predecessor] = int(degree[predecessor]) - 1
			if int(degree[predecessor]) == 0:
				queue.append(predecessor)
	for lane in lanes:
		var next: Array[Path3D] = []
		var best: Path3D
		var score := -2.0
		var heading: Vector3 = lane.get_meta("heading")
		for candidate: Path3D in lane.get_meta("options"):
			if int(degree[candidate]) == 0:
				continue
			var dot := heading.dot(candidate.get_meta("heading"))
			if dot > score:
				score = dot
				best = candidate
		if best != null:
			var endpoint := best.curve.get_point_position(0)
			var last := lane.curve.get_point_position(lane.curve.point_count - 1)
			if last.distance_to(endpoint) > 0.01:
				lane.curve.add_point(endpoint)
			next.append(best)
		lane.set_meta("next", next)
		lane.set_meta("loop", best != null)
		lane.remove_meta("options")
	return lanes
