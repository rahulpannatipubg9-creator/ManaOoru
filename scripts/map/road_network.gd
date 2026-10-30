class_name RoadNetwork
extends RefCounted

## Routable graph built from the OSM road pieces in MapData.
## Graph nodes are OSM nodes, so shared nodes form junctions and bridges/flyovers
## without a shared node correctly do not connect to the roads beneath them.

enum Mode { WALK, DRIVE }

const FLAG_WALK := 1
const FLAG_DRIVE_FORWARD := 2
const FLAG_DRIVE_BACKWARD := 4
const GRID_CELL_SIZE := 50.0
const MAX_SNAP_DISTANCE := 250.0
const NOT_WALKABLE := ["motorway", "motorway_link"]
## Relative cost per metre while driving; lower values make the router prefer bigger roads.
const DRIVE_COST := {
	"motorway": 0.75, "motorway_link": 0.8, "trunk": 0.8, "trunk_link": 0.85,
	"primary": 0.85, "primary_link": 0.9, "secondary": 0.9, "secondary_link": 0.95,
	"tertiary": 1.0, "tertiary_link": 1.0, "unclassified": 1.15, "residential": 1.15,
	"road": 1.2, "living_street": 1.4, "service": 1.4, "track": 2.0,
}
const MIN_DRIVE_COST := 0.75

var node_positions := PackedVector2Array()
var edge_a := PackedInt32Array()
var edge_b := PackedInt32Array()
var edge_length := PackedFloat32Array()
var edge_drive_cost := PackedFloat32Array()
var edge_flags := PackedByteArray()
var _node_index: Dictionary = {}
var _node_edges: Array[PackedInt32Array] = []
var _grid: Dictionary = {}
var _component := {Mode.WALK: PackedInt32Array(), Mode.DRIVE: PackedInt32Array()}
var _main_component := {Mode.WALK: -1, Mode.DRIVE: -1}
var _search_cost := PackedFloat32Array()
var _search_parent := PackedInt32Array()
var _search_goal := Vector2.ZERO
var _search_heuristic_scale := 1.0

func _init(data: MapData) -> void:
	for road in data.roads:
		_add_road(road)
	for mode in [Mode.WALK, Mode.DRIVE]:
		_label_components(mode)

func node_count() -> int:
	return node_positions.size()

func edge_count() -> int:
	return edge_a.size()

func main_component_size(mode: int) -> int:
	var labels: PackedInt32Array = _component[mode]
	var count := 0
	for label in labels:
		if label == _main_component[mode]:
			count += 1
	return count

## Closest point on a usable road of the main connected network.
## Returns {} when nothing usable lies within max_distance.
func snap(point: Vector2, mode: int, max_distance := MAX_SNAP_DISTANCE) -> Dictionary:
	var best := {}
	var best_distance := max_distance
	var center := _cell(point)
	var max_ring := ceili(max_distance / GRID_CELL_SIZE)
	for ring in max_ring + 1:
		if not best.is_empty() and float(ring - 1) * GRID_CELL_SIZE > best_distance:
			break
		for x in range(center.x - ring, center.x + ring + 1):
			for y in range(center.y - ring, center.y + ring + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != ring:
					continue
				for edge in _grid.get(Vector2i(x, y), PackedInt32Array()):
					if not _is_edge_usable(edge, mode):
						continue
					var a := node_positions[edge_a[edge]]
					var b := node_positions[edge_b[edge]]
					var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
					var distance := closest.distance_to(point)
					if distance < best_distance:
						best_distance = distance
						var t := 0.0 if a.is_equal_approx(b) else a.distance_to(closest) / a.distance_to(b)
						best = {"edge": edge, "t": t, "point": closest, "distance": distance}
	return best

## A* search over the road graph between two arbitrary map points.
## Returns {ok, points, length, error}. Never fabricates a straight-line route.
func find_route(from: Vector2, to: Vector2, mode: int) -> Dictionary:
	var road_word := "drivable" if mode == Mode.DRIVE else "walkable"
	var start := snap(from, mode)
	if start.is_empty():
		return _failure("You are more than %d m from a %s road." % [int(MAX_SNAP_DISTANCE), road_word])
	var goal := snap(to, mode)
	if goal.is_empty():
		return _failure("No %s road within %d m of that point." % [road_word, int(MAX_SNAP_DISTANCE)])
	var count := node_positions.size()
	var start_node := count
	var goal_node := count + 1
	_search_cost.resize(count + 2)
	_search_cost.fill(INF)
	_search_parent.resize(count + 2)
	_search_parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count + 2)
	var heap := _MinHeap.new()
	_search_goal = goal.point
	_search_heuristic_scale = MIN_DRIVE_COST if mode == Mode.DRIVE else 1.0
	var start_edge: int = start.edge
	var goal_edge: int = goal.edge
	var start_t: float = start.t
	var goal_t: float = goal.t
	if start_edge == goal_edge and _can_traverse(start_edge, goal_t >= start_t, mode):
		_relax(heap, goal_node, start_node, absf(goal_t - start_t) * _edge_cost(start_edge, mode))
	if _can_traverse(start_edge, false, mode):
		_relax(heap, edge_a[start_edge], start_node, start_t * _edge_cost(start_edge, mode))
	if _can_traverse(start_edge, true, mode):
		_relax(heap, edge_b[start_edge], start_node, (1.0 - start_t) * _edge_cost(start_edge, mode))
	while not heap.is_empty():
		var node := heap.pop()
		if node == goal_node:
			break
		if closed[node] == 1:
			continue
		closed[node] = 1
		var base := _search_cost[node]
		for edge in _node_edges[node]:
			var forward := edge_a[edge] == node
			if _can_traverse(edge, forward, mode):
				_relax(heap, edge_b[edge] if forward else edge_a[edge], node, base + _edge_cost(edge, mode))
		if node == edge_a[goal_edge] and _can_traverse(goal_edge, true, mode):
			_relax(heap, goal_node, node, base + goal_t * _edge_cost(goal_edge, mode))
		if node == edge_b[goal_edge] and _can_traverse(goal_edge, false, mode):
			_relax(heap, goal_node, node, base + (1.0 - goal_t) * _edge_cost(goal_edge, mode))
	if _search_parent[goal_node] == -1:
		return _failure("No %s route connects these places in the map data." % road_word)
	var reversed := PackedVector2Array([_search_goal])
	var node := _search_parent[goal_node]
	while node != start_node:
		reversed.append(node_positions[node])
		node = _search_parent[node]
	reversed.append(start.point)
	reversed.reverse()
	var length := 0.0
	for index in range(1, reversed.size()):
		length += reversed[index - 1].distance_to(reversed[index])
	return {"ok": true, "points": reversed, "length": length, "error": ""}

func _relax(heap: _MinHeap, node: int, parent: int, value: float) -> void:
	if value >= _search_cost[node]:
		return
	_search_cost[node] = value
	_search_parent[node] = parent
	var estimate := 0.0
	if node < node_positions.size():
		estimate = node_positions[node].distance_to(_search_goal) * _search_heuristic_scale
	heap.push(value + estimate, node)

func _failure(message: String) -> Dictionary:
	return {"ok": false, "points": PackedVector2Array(), "length": 0.0, "error": message}

func _add_road(road: Dictionary) -> void:
	var kind: String = road.kind
	var flags := 0
	if not kind in NOT_WALKABLE:
		flags |= FLAG_WALK
	if DRIVE_COST.has(kind):
		if road.oneway >= 0:
			flags |= FLAG_DRIVE_FORWARD
		if road.oneway <= 0:
			flags |= FLAG_DRIVE_BACKWARD
	if flags == 0:
		return
	var ids: PackedInt64Array = road.node_ids
	var points: PackedVector2Array = road.points
	var previous := _node_for(ids[0], points[0])
	for index in range(1, ids.size()):
		var current := _node_for(ids[index], points[index])
		var length := points[index - 1].distance_to(points[index])
		if current != previous and length > 0.01:
			_add_edge(previous, current, length, DRIVE_COST.get(kind, 1.0), flags)
		previous = current

func _node_for(osm_id: int, point: Vector2) -> int:
	if _node_index.has(osm_id):
		return _node_index[osm_id]
	var index := node_positions.size()
	_node_index[osm_id] = index
	node_positions.append(point)
	_node_edges.append(PackedInt32Array())
	return index

func _add_edge(a: int, b: int, length: float, drive_cost: float, flags: int) -> void:
	var edge := edge_a.size()
	edge_a.append(a)
	edge_b.append(b)
	edge_length.append(length)
	edge_drive_cost.append(drive_cost)
	edge_flags.append(flags)
	_node_edges[a].append(edge)
	_node_edges[b].append(edge)
	var from_cell := _cell(node_positions[a].min(node_positions[b]))
	var to_cell := _cell(node_positions[a].max(node_positions[b]))
	for x in range(from_cell.x, to_cell.x + 1):
		for y in range(from_cell.y, to_cell.y + 1):
			var key := Vector2i(x, y)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			_grid[key].append(edge)

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / GRID_CELL_SIZE), floori(point.y / GRID_CELL_SIZE))

func _edge_cost(edge: int, mode: int) -> float:
	return edge_length[edge] * (edge_drive_cost[edge] if mode == Mode.DRIVE else 1.0)

func _can_traverse(edge: int, forward: bool, mode: int) -> bool:
	if mode == Mode.WALK:
		return (edge_flags[edge] & FLAG_WALK) != 0
	return (edge_flags[edge] & (FLAG_DRIVE_FORWARD if forward else FLAG_DRIVE_BACKWARD)) != 0

func _is_edge_usable(edge: int, mode: int) -> bool:
	var mask := FLAG_WALK if mode == Mode.WALK else FLAG_DRIVE_FORWARD | FLAG_DRIVE_BACKWARD
	if (edge_flags[edge] & mask) == 0:
		return false
	var labels: PackedInt32Array = _component[mode]
	return labels[edge_a[edge]] == _main_component[mode]

## Labels connected components (ignoring one-way direction) so snapping never
## lands on a small island of road that cannot reach the rest of the town.
func _label_components(mode: int) -> void:
	var mask := FLAG_WALK if mode == Mode.WALK else FLAG_DRIVE_FORWARD | FLAG_DRIVE_BACKWARD
	var labels := PackedInt32Array()
	labels.resize(node_positions.size())
	labels.fill(-1)
	var sizes := PackedInt32Array()
	for origin in node_positions.size():
		if labels[origin] != -1:
			continue
		var label := sizes.size()
		var size := 0
		var stack := PackedInt32Array([origin])
		labels[origin] = label
		while not stack.is_empty():
			var node := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			for edge in _node_edges[node]:
				if (edge_flags[edge] & mask) == 0:
					continue
				var other := edge_b[edge] if edge_a[edge] == node else edge_a[edge]
				if labels[other] == -1:
					labels[other] = label
					stack.append(other)
		sizes.append(size)
	var best := -1
	for label in sizes.size():
		if best == -1 or sizes[label] > sizes[best]:
			best = label
	_component[mode] = labels
	_main_component[mode] = best

class _MinHeap:
	var _keys := PackedFloat32Array()
	var _values := PackedInt32Array()

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, value: int) -> void:
		_keys.append(key)
		_values.append(value)
		var index := _keys.size() - 1
		while index > 0:
			var parent := (index - 1) >> 1
			if _keys[parent] <= _keys[index]:
				break
			_swap(index, parent)
			index = parent

	func pop() -> int:
		var top := _values[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.resize(last)
		_values.resize(last)
		var index := 0
		while true:
			var left := index * 2 + 1
			if left >= last:
				break
			var smallest := left
			if left + 1 < last and _keys[left + 1] < _keys[left]:
				smallest = left + 1
			if _keys[index] <= _keys[smallest]:
				break
			_swap(index, smallest)
			index = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var value := _values[a]
		_values[a] = _values[b]
		_values[b] = value
