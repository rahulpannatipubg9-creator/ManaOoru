class_name TreeBuilder
extends Node3D

## Every real tree in the district, where it really stands and as tall as it really is,
## from the Meta / WRI 1 m canopy-height map (see tools/import_trees.py). Trees are
## instanced in chunks, built nearest-first within a per-frame time budget like the
## buildings: near chunks as four crossed impostor cards that cast shadows, far chunks
## as one camera-facing card showing the matching view, hidden beyond a view distance. Each
## trunk is a thin static collider so cars and people cannot pass through it. Trees that
## would stand on a road, in a building, on water, in a stadium or on a spawn spot are
## left out (the canopy map sometimes reads roofs and road verges as canopy).

const TREES_PATH := "res://data/trees/godavarikhani_trees.bin"
const IMPOSTOR := preload("res://assets/textures/trees/broadleaf_impostor.png")
const CHUNK_SIZE := 96.0
const FRAME_BUDGET_USEC := 3000
## The impostor model: card frame (metres) and the real tree inside it.
const MODEL_FRAME := 24.91
const MODEL_HEIGHT := 19.47
const MODEL_RADIUS := 12.21
## Clearance includes the visible canopy, not only the trunk. Without this,
## canopy cards from roadside trees visually block narrow residential lanes.
const ROAD_CLEARANCE := 10.0
## The source canopy raster can mistake roofs for trees. Match the clearance to
## the visible canopy radius so a tree card cannot cover a mapped house or yard.
const BUILDING_CLEARANCE := 10.0
const SPAWN_CLEARANCE := 6.0
const MINE_CLEARANCE := 14.0
const TRUNK_RADIUS := 0.22
const DESKTOP_VIEW_DISTANCE := 800.0
const MOBILE_VIEW_DISTANCE := 450.0
## Chunks nearer than this (from their centre) draw the crossed cards; farther ones the billboard.
const NEAR_DISTANCE := 170.0
const BLOCKING_AREAS := ["water", "stadium", "pitch", "quarry"]

## Called with no arguments, returns the map point to build around first.
var focus: Callable
var tree_count := 0
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _mesh: ArrayMesh
var _billboard_mesh: ArrayMesh
var _material: ShaderMaterial
var _billboard_material: ShaderMaterial
var _trunk_shape: CylinderShape3D
var _world: Node
var _road_grid: Dictionary = {}
var _blocked_areas: Array[PackedVector2Array] = []
var _keep_clear: Array[Vector3] = []
var _resort_timer := 0.0

func setup(world: Node, data: MapData) -> void:
	name = "Trees"
	_world = world
	_mesh = _impostor_mesh()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/tree_impostor.gdshader")
	_material.set_shader_parameter("impostor", IMPOSTOR)
	_billboard_mesh = _billboard_card()
	_billboard_material = ShaderMaterial.new()
	_billboard_material.shader = preload("res://shaders/tree_billboard.gdshader")
	_billboard_material.set_shader_parameter("impostor", IMPOSTOR)
	_trunk_shape = CylinderShape3D.new()
	_trunk_shape.radius = TRUNK_RADIUS
	_trunk_shape.height = 4.0
	for road in data.roads:
		var half := RoadStyle.width(road) * 0.5 + ROAD_CLEARANCE
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			_index_road_segment(points[index - 1], points[index], half)
	for road in data.topoexport_roads:
		var half := RoadStyle.width(road) * 0.5 + ROAD_CLEARANCE
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			_index_road_segment(points[index - 1], points[index], half)
	for area in data.areas:
		if area.kind in BLOCKING_AREAS:
			_blocked_areas.append(area.points)
	var bytes := FileAccess.get_file_as_bytes(TREES_PATH)
	for offset in range(0, bytes.size(), 16):
		var point := Vector2(bytes.decode_float(offset), bytes.decode_float(offset + 4))
		if not GeoProjection.is_playable(point):
			continue
		var cell := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))
		if not _chunks.has(cell):
			_chunks[cell] = PackedFloat32Array()
		_chunks[cell].append_array(PackedFloat32Array([point.x, point.y, bytes.decode_float(offset + 8), bytes.decode_float(offset + 12)]))
	for tree: Dictionary in data.topoexport_trees:
		var point: Vector2 = tree.point
		var cell := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))
		if not _chunks.has(cell):
			_chunks[cell] = PackedFloat32Array()
		_chunks[cell].append_array(PackedFloat32Array([point.x, point.y,
			float(tree.get("height", 8.0)), float(tree.get("crown_diameter", 6.0))]))
	_pending.assign(_chunks.keys())

## Spots that must stay free of trees (spawns, the coal-gallery portal), in world space with radius in w.
func keep_clear(at: Vector3, radius: float) -> void:
	_keep_clear.append(Vector3(at.x, at.z, radius))

func pending_chunk_count() -> int:
	return _pending.size()

func build_around(center: Vector2, radius: float) -> void:
	for cell in _pending.duplicate():
		if _cell_center(cell).distance_to(center) <= radius:
			_build_chunk(cell)
			_pending.erase(cell)

func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	_resort_timer -= delta
	# Follow the same tracked body as the buildings unless given a focus of our own.
	var source: Callable = focus if focus.is_valid() else _world.buildings.focus
	if _resort_timer <= 0.0 and source.is_valid():
		_resort_timer = 0.5
		var center: Vector2 = source.call()
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _cell_center(a).distance_squared_to(center) < _cell_center(b).distance_squared_to(center))
	var started := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - started < FRAME_BUDGET_USEC:
		_build_chunk(_pending.pop_front())

func _build_chunk(cell: Vector2i) -> void:
	var trees: PackedFloat32Array = _chunks[cell]
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var buildings: BuildingBuilder = _world.buildings
	for index in range(0, trees.size(), 4):
		var point := Vector2(trees[index], trees[index + 1])
		if _blocked(point) or not buildings.is_clear(point, BUILDING_CLEARANCE):
			continue
		var height := trees[index + 2]
		var crown := trees[index + 3]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(roundi(point.x * 10.0), roundi(point.y * 10.0)))
		var up := height / MODEL_HEIGHT
		# Keep crowns at least as broad as the model's own proportions; the map's crowns read narrow.
		var across := maxf(crown / MODEL_RADIUS, up * 0.8) * rng.randf_range(0.9, 1.15)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(across, up, across))
		var ground: float = _world.ground_height(point)
		transforms.append(Transform3D(basis, Vector3(point.x, ground - 0.1, point.y)))
		var shade := rng.randf_range(0.85, 1.08)
		tints.append(Color(shade * rng.randf_range(0.95, 1.05), shade, shade * rng.randf_range(0.88, 1.0)))
	if transforms.is_empty():
		return
	var multimesh := _multimesh(_mesh, transforms, tints)
	var far := _multimesh(_billboard_mesh, transforms, tints)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	for index in transforms.size():
		var foot := transforms[index].origin
		PhysicsServer3D.body_add_shape(body, _trunk_shape.get_rid(), Transform3D(Basis(), foot + Vector3.UP * 2.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees_%d_%d" % [cell.x, cell.y]
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.visibility_range_end = NEAR_DISTANCE
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	instance.set_meta("trunks", body)
	var distant := MultiMeshInstance3D.new()
	distant.name = "FarTrees_%d_%d" % [cell.x, cell.y]
	distant.multimesh = far
	distant.material_override = _billboard_material
	distant.visibility_range_begin = NEAR_DISTANCE
	distant.visibility_range_end = MOBILE_VIEW_DISTANCE if OS.has_feature("mobile") else DESKTOP_VIEW_DISTANCE
	distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(distant)
	tree_count += transforms.size()

static func _multimesh(mesh: Mesh, transforms: Array[Transform3D], tints: Array[Color]) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_custom_data(index, tints[index])
	return multimesh

func _exit_tree() -> void:
	for child in get_children():
		if child.has_meta("trunks"):
			PhysicsServer3D.free_rid(child.get_meta("trunks"))

func _blocked(point: Vector2) -> bool:
	for clear in _keep_clear:
		if point.distance_to(Vector2(clear.x, clear.y)) < clear.z:
			return true
	var center := Vector2i(floori(point.x / 50.0), floori(point.y / 50.0))
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			for segment in _road_grid.get(Vector2i(x, y), []):
				if Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1]).distance_to(point) < segment[2]:
					return true
	for area in _blocked_areas:
		if Geometry2D.is_point_in_polygon(point, area):
			return true
	return false

## A road segment can cross several 50 m lookup cells. Index it in every cell
## touched by its clearance envelope so the tree filter works on long OSM ways.
func _index_road_segment(a: Vector2, b: Vector2, half: float) -> void:
	var low := a.min(b) - Vector2.ONE * half
	var high := a.max(b) + Vector2.ONE * half
	for x in range(floori(low.x / 50.0), floori(high.x / 50.0) + 1):
		for y in range(floori(low.y / 50.0), floori(high.y / 50.0) + 1):
			var cell := Vector2i(x, y)
			if not _road_grid.has(cell):
				_road_grid[cell] = []
			_road_grid[cell].append([a, b, half])

## Four vertical cards through the trunk at 0/45/90/135 degrees, each mapped to its view
## in the atlas. Unit model: the real tree is MODEL_HEIGHT tall, cards are MODEL_FRAME square.
static func _impostor_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for view in 4:
		var angle := deg_to_rad(view * 45.0)
		# Blender's camera for view i sat at (sin a, -cos a, 0) looking at the trunk, which in
		# Godot (Y up, Z = -Blender Y) is the (sin a, 0, cos a) side with its right edge along (cos a, 0, -sin a).
		var across := Vector3(cos(angle), 0.0, -sin(angle)) * MODEL_FRAME * 0.5
		var facing := Vector3(sin(angle), 0.0, cos(angle))
		var u0 := view / 4.0
		var u1 := (view + 1) / 4.0
		var corners := [-across, across, across + Vector3.UP * MODEL_FRAME, -across + Vector3.UP * MODEL_FRAME]
		var corner_uvs := [Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0)]
		for triangle in [[0, 1, 2], [0, 2, 3]]:
			for corner in triangle:
				vertices.append(corners[corner])
				uvs.append(corner_uvs[corner])
				normals.append(facing)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## One card, MODEL_FRAME square, base at the trunk; the billboard shader turns it and picks the view.
static func _billboard_card() -> ArrayMesh:
	var half := MODEL_FRAME * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-half, 0, 0), Vector3(half, 0, 0), Vector3(half, MODEL_FRAME, 0),
		Vector3(-half, 0, 0), Vector3(half, MODEL_FRAME, 0), Vector3(-half, MODEL_FRAME, 0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves the card around the trunk, so give it a bounding box that covers every turn.
	mesh.custom_aabb = AABB(Vector3(-half, 0.0, -half), Vector3(MODEL_FRAME, MODEL_FRAME, MODEL_FRAME))
	return mesh

func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CHUNK_SIZE
