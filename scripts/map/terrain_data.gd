class_name TerrainData
extends RefCounted

## Ground heights from the Copernicus GLO-30 DEM (built by tools/import_terrain.py),
## in metres relative to Chowrastha. height_at() interpolates on the same two
## triangles per cell that the terrain mesh and collision use, so anything placed
## with it sits exactly on the visible, collidable ground.

const DATA_PATH := "res://data/terrain/godavarikhani_terrain.bin"
const META_PATH := "res://data/terrain/godavarikhani_terrain.json"

var size := 0
var cell_size := 1.0
var origin := Vector2.ZERO
var min_height := 0.0
var max_height := 0.0
var heights := PackedFloat32Array()
var is_valid := false

func _init() -> void:
	if not FileAccess.file_exists(META_PATH) or not FileAccess.file_exists(DATA_PATH):
		push_warning("Terrain data missing; using flat ground")
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	size = int(meta.size)
	cell_size = float(meta.cell_size)
	origin = Vector2(float(meta.origin_x), float(meta.origin_z))
	min_height = float(meta.min_height)
	max_height = float(meta.max_height)
	heights = FileAccess.get_file_as_bytes(DATA_PATH).to_float32_array()
	is_valid = heights.size() == size * size

## Ground height at a map point (x east, z south); 0 outside the data.
func height_at(point: Vector2) -> float:
	if not is_valid:
		return 0.0
	var fx := clampf((point.x - origin.x) / cell_size, 0.0, size - 1.001)
	var fz := clampf((point.y - origin.y) / cell_size, 0.0, size - 1.001)
	var col := floori(fx)
	var row := floori(fz)
	var tx := fx - col
	var tz := fz - row
	var h00 := heights[row * size + col]
	var h10 := heights[row * size + col + 1]
	var h01 := heights[(row + 1) * size + col]
	var h11 := heights[(row + 1) * size + col + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

## Lowest ground height under a set of points.
func lowest_under(points: PackedVector2Array) -> float:
	var lowest := INF
	for point in points:
		lowest = minf(lowest, height_at(point))
	return 0.0 if lowest == INF else lowest

func vertex(row: int, col: int) -> Vector3:
	return Vector3(origin.x + col * cell_size, heights[row * size + col], origin.y + row * cell_size)
