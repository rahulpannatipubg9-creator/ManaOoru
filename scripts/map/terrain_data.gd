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

## Triangle soup for the whole ground, one entry per chunk of cells:
## {row, col, vertices, normals}. Pure data, so it runs on the worker threads.
func build_chunks(chunk_cells: int) -> Array[Dictionary]:
	var cells := size - 1
	var chunks: Array[Dictionary] = []
	for row in range(0, cells, chunk_cells):
		for col in range(0, cells, chunk_cells):
			chunks.append({"row": row, "col": col, "cells": chunk_cells})
	var task := WorkerThreadPool.add_group_task(_fill_chunk.bind(chunks), chunks.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	return chunks

## Each cell is two triangles on the same diagonal as height_at, wound and lit from above.
func _fill_chunk(index: int, chunks: Array[Dictionary]) -> void:
	var chunk: Dictionary = chunks[index]
	var first_row: int = chunk.row
	var first_col: int = chunk.col
	var last_row := mini(first_row + int(chunk.cells), size - 1)
	var last_col := mini(first_col + int(chunk.cells), size - 1)
	var count := (last_row - first_row) * (last_col - first_col) * 6
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(count)
	normals.resize(count)
	var at := 0
	for row in range(first_row, last_row):
		for col in range(first_col, last_col):
			var v00 := vertex(row, col)
			var v10 := vertex(row, col + 1)
			var v01 := vertex(row + 1, col)
			var v11 := vertex(row + 1, col + 1)
			var first := (v10 - v00).cross(v01 - v00).normalized()
			if first.y < 0.0:
				first = -first
			var second := (v01 - v11).cross(v10 - v11).normalized()
			if second.y < 0.0:
				second = -second
			vertices[at] = v00
			vertices[at + 1] = v10
			vertices[at + 2] = v01
			vertices[at + 3] = v11
			vertices[at + 4] = v01
			vertices[at + 5] = v10
			normals[at] = first
			normals[at + 1] = first
			normals[at + 2] = first
			normals[at + 3] = second
			normals[at + 4] = second
			normals[at + 5] = second
			at += 6
	chunk.vertices = vertices
	chunk.normals = normals
