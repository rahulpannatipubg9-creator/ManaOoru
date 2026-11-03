extends RefCounted

## Uniform grid over road segments, so "what is near this point?" stops walking every
## road. Each segment sits in every cell its bounding box touches. near() returns segment
## indexes in insertion order, so a nearest-road search keeps the winner a full scan picks.

const CELL := 50.0

var starts := PackedVector2Array()
var ends := PackedVector2Array()
var half_widths := PackedFloat64Array()
## Index of the road each segment belongs to, as given to add().
var owners := PackedInt32Array()
## Widest half_width added, for callers that test against each segment's own width.
var widest_half := 0.0
var _cells: Dictionary = {}

func add(a: Vector2, b: Vector2, half_width: float, owner: int) -> void:
	var index := starts.size()
	starts.append(a)
	ends.append(b)
	half_widths.append(half_width)
	owners.append(owner)
	widest_half = maxf(widest_half, half_width)
	for x in range(floori(minf(a.x, b.x) / CELL), floori(maxf(a.x, b.x) / CELL) + 1):
		for y in range(floori(minf(a.y, b.y) / CELL), floori(maxf(a.y, b.y) / CELL) + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_cells[cell] = PackedInt32Array()
			_cells[cell].append(index)

## Every segment that could lie within reach of point, ascending, without repeats.
## It can hold farther segments too: callers still measure the real distance.
func near(point: Vector2, reach: float) -> PackedInt32Array:
	var padded := maxf(reach, 0.0) + 0.01
	var found := PackedInt32Array()
	for x in range(floori((point.x - padded) / CELL), floori((point.x + padded) / CELL) + 1):
		for y in range(floori((point.y - padded) / CELL), floori((point.y + padded) / CELL) + 1):
			var cell: Variant = _cells.get(Vector2i(x, y))
			if cell != null:
				found.append_array(cell)
	found.sort()
	var kept := 0
	for index in found.size():
		if index == 0 or found[index] != found[index - 1]:
			found[kept] = found[index]
			kept += 1
	found.resize(kept)
	return found

## Stops at the first hit, for yes/no questions where order cannot matter.
func any_within(point: Vector2, margin: float) -> bool:
	var padded := maxf(widest_half + margin, 0.0) + 0.01
	for x in range(floori((point.x - padded) / CELL), floori((point.x + padded) / CELL) + 1):
		for y in range(floori((point.y - padded) / CELL), floori((point.y + padded) / CELL) + 1):
			var cell: Variant = _cells.get(Vector2i(x, y))
			if cell == null:
				continue
			for index: int in cell:
				if Geometry2D.get_closest_point_to_segment(point, starts[index], ends[index]).distance_to(point) < half_widths[index] + margin:
					return true
	return false
