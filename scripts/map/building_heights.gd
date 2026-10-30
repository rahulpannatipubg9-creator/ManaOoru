class_name BuildingHeights
extends RefCounted

## Building heights from Google Open Buildings 2.5D (2023), rasterised onto the
## game's map grid by tools/import_building_heights.py.

const DATA_PATH := "res://data/buildings/godavarikhani_building_heights.bin.gz"
const META_PATH := "res://data/buildings/godavarikhani_building_heights.json"
const MAX_SAMPLES := 48
## Fraction of a footprint that must have height data before it is trusted.
const MIN_COVERAGE := 0.3
const PERCENTILE := 0.8

var size := 0
var cell_size := 1.0
var origin := Vector2.ZERO
var units_per_meter := 1.0
var _raster := PackedByteArray()
var is_valid := false

func _init() -> void:
	if not FileAccess.file_exists(META_PATH) or not FileAccess.file_exists(DATA_PATH):
		push_warning("Building height data missing; using generated floor counts")
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	size = int(meta.size)
	cell_size = float(meta.cell_size)
	origin = Vector2(float(meta.origin_x), float(meta.origin_z))
	units_per_meter = float(meta.units_per_meter)
	_raster = FileAccess.get_file_as_bytes(DATA_PATH).decompress(size * size, FileAccess.COMPRESSION_GZIP)
	is_valid = _raster.size() == size * size

func height_at(point: Vector2) -> float:
	var col := floori((point.x - origin.x) / cell_size)
	var row := floori((point.y - origin.y) / cell_size)
	if not is_valid or col < 0 or row < 0 or col >= size or row >= size:
		return 0.0
	return _raster[row * size + col] / units_per_meter

## Measured height of a building in metres, or 0 when the data does not cover it well.
func height_for(footprint: PackedVector2Array) -> float:
	if not is_valid:
		return 0.0
	var bounds := Rect2(footprint[0], Vector2.ZERO)
	for point in footprint:
		bounds = bounds.expand(point)
	var step := maxf(cell_size, sqrt(bounds.get_area() / MAX_SAMPLES))
	var samples := PackedFloat32Array()
	var inside := 0
	var y := bounds.position.y + step * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + step * 0.5
		while x < bounds.end.x:
			var point := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, footprint):
				inside += 1
				var value := height_at(point)
				if value > 0.0:
					samples.append(value)
			x += step
		y += step
	if inside == 0 or float(samples.size()) / inside < MIN_COVERAGE:
		return 0.0
	samples.sort()
	return samples[mini(samples.size() - 1, floori(samples.size() * PERCENTILE))]
