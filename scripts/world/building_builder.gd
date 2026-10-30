class_name BuildingBuilder
extends Node3D

## Extrudes every building footprint (OSM + Microsoft) at its real position and
## shape. Buildings are merged per chunk (one mesh, one collision body, one
## water-tank multimesh), built nearest-first within a per-frame time budget so
## start-up stays fast on phones, and hidden beyond a view distance.
##
## Footprints are real. Heights come from Google Open Buildings 2.5D where it covers
## the building (about 96%); otherwise, and for paint and shopfronts, which no open
## data records, values are chosen deterministically from the building's position.
## Each building stands on the terrain, its base sunk to the lowest ground under it.

const CHUNK_SIZE := 160.0
const FLOOR_HEIGHT := 3.0
const PLINTH := 0.3
const PARAPET_HEIGHT := 0.9
const MIN_AREA := 6.0
const MAX_MEASURED_FLOORS := 15
const MAIN_ROAD_DISTANCE := 22.0
const RESIDENTIAL_FRONTAGE_DISTANCE := 13.0
const VIDYA_NAGAR_2_CENTER := Vector2(315.60, -334.57)
const VIDYA_NAGAR_2_RADIUS := 400.0
## House forecourts need parcel/setback data. Keep them off until that source
## exists, so only verified building footprints define the Vidya Nagar 2 layout.
const ENABLE_INFERRED_RESIDENTIAL_FORECOURTS := false
const SYNC_BUILD_RADIUS := 300.0
const FRAME_BUDGET_USEC := 4000
const DESKTOP_VIEW_DISTANCE := 900.0
const MOBILE_VIEW_DISTANCE := 550.0
const PAINTS := [
	Color("#e9dcc0"), Color("#f2e6a6"), Color("#e8b9a8"), Color("#b9d4e0"), Color("#c9dfb7"),
	Color("#f4f1ea"), Color("#d6a77a"), Color("#cdbfe0"), Color("#e6cf9c"), Color("#a9c7c3"),
]
## Detailed house models (from the user's "building House" pack). A real footprint whose
## shape is close to one of these is drawn with the model instead of a plain extrusion,
## aligned to the footprint and facing the nearest road. Front = the model's ±Z side.
## Apartment blocks (from the user's "street-city-buildings-8" pack) go on real buildings
## measured at APARTMENT_MIN_FLOORS or more, stretched to the footprint and the measured height.
const HOUSE_MODELS := [
	{"scene": "res://assets/models/houses/house_1.glb", "width": 12.34, "depth": 10.62, "height": 6.73, "front": 1.0, "storeys": 2, "kind": "house"},
	{"scene": "res://assets/models/houses/house_2.glb", "width": 8.28, "depth": 10.16, "height": 4.79, "front": -1.0, "storeys": 1, "kind": "house"},
	{"scene": "res://assets/models/houses/house_3.glb", "width": 12.90, "depth": 15.40, "height": 5.39, "front": 1.0, "storeys": 1, "kind": "house"},
	{"scene": "res://assets/models/apartments/apartment_long.glb", "width": 35.35, "depth": 15.12, "height": 24.80, "front": 1.0, "storeys": 8, "kind": "apartment"},
	{"scene": "res://assets/models/apartments/apartment_section.glb", "width": 8.60, "depth": 18.28, "height": 22.12, "front": 1.0, "storeys": 7, "kind": "apartment"},
	{"scene": "res://assets/models/apartments/apartment_corner.glb", "width": 27.69, "depth": 13.88, "height": 32.54, "front": 1.0, "storeys": 10, "kind": "apartment"},
]
const APARTMENT_MIN_FLOORS := 4
const APARTMENT_FIT_TOLERANCE := 0.45
const APARTMENT_MIN_RECTANGULARITY := 0.75
## Number of real buildings drawn as apartment blocks.
var apartment_model_count := 0
const HOUSE_FIT_TOLERANCE := 0.18
const HOUSE_MIN_RECTANGULARITY := 0.85
## Share of matching footprints that get a model: the pack's pitched-roof houses are
## mixed in for variety rather than replacing whole flat-roofed colonies.
const HOUSE_SHARE := 0.2
const HOUSE_VIEW_DISTANCE := 450.0
const MOBILE_HOUSE_VIEW_DISTANCE := 260.0
## Decorative asset models approximate rectangular footprints. Keep them disabled
## while reproducing a real district so walls, roofs and collision preserve the
## surveyed OSM/Microsoft footprint exactly.
const USE_DECORATIVE_HOUSE_MODELS := false
const KIND_FACADE := 0.0
const KIND_PLAIN := 1.0
const KIND_ROOF := 2.0
const KIND_LEDGE := 3.0
const KIND_APRON := 4.0
const KIND_SIGN := 5.0
## Real shop, bank, hospital and temple names (OpenStreetMap + Overture Maps), baked onto
## signboard atlas pages by tools/signboards/make_signboards.gd.
const BOARDS_PATH := "res://assets/textures/signboards/boards.json"
const APPEARANCE_REFERENCES_PATH := "res://data/local/building_appearance_references.json"
## A place this far from any footprint is left to the roadside board instead.
const BOARD_REACH := 18.0
const BOARD_BOTTOM := 2.45
const BOARD_MAX_WIDTH := 7.5
const BOARD_ASPECT := 84.0 / 384.0
const BOARD_OFFSET := 0.05
const StorefrontAllocator := preload("res://scripts/world/storefront_allocator.gd")
const FOOTPRINT_CELL := 64.0
## Wall finishes the shader can draw (bits 1-2 of the style code in COLOR.a).
enum Finish { PAINTED, PEELING, BRICK, CONCRETE }
## Chajja sunshades over each storey's windows, and awnings over shops.
const LEDGE_HEIGHT := 2.4
const LEDGE_THICKNESS := 0.09
const LEDGE_DEPTH := 0.45
const AWNING_HEIGHT := 2.36
const AWNING_DEPTH := 0.75
const LEDGE_MIN_WALL := 2.5
## Concrete forecourt shops and houses pour in front of the wall that faces the road.
const APRON_DEPTH := 1.8
const APRON_HEIGHT := 0.45

## Footprints of every building that exists in 3D; the minimap draws exactly these.
var footprints: Array[PackedVector2Array] = []
## Called with no arguments, returns the map point to build around first.
var stream_radius := 650.0
var stream_budget_usec := 2000
var stream_enabled := true
var _stream_nodes: Dictionary = {}
var focus: Callable
## Number of buildings whose height came from measured data.
var measured_height_count := 0
var _terrain: TerrainData
var _heights: BuildingHeights
var _styles: Array[Dictionary] = []
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _built: Dictionary = {}
var _material: ShaderMaterial
var _tank_mesh: CylinderMesh
var _main_road_grid: Dictionary = {}
var _road_grid: Dictionary = {}
var _house_meshes: Array[Mesh] = []
## Number of footprints drawn with a detailed house model.
var house_model_count := 0
var _resort_timer := 0.0
var _boards: Array = []
## Names of real places drawn on a building front, so signage can skip duplicate roadside boards.
var _board_names: Dictionary = {}
## Planned mounts are also used by signage to suppress duplicate pole boards.
var facade_mounts: Array[Dictionary] = []
var unmounted_board_count := 0
var storefront_allocator: RefCounted
var building_metadata: Array[Dictionary] = []
var _sign_road_grid: Dictionary = {}
## Corners of each footprint's bounding box: low at index * 2, high at index * 2 + 1.
var _footprint_bounds := PackedVector2Array()
## Footprints whose bounding box touches each FOOTPRINT_CELL square.
var _footprint_grid: Dictionary = {}
var _board_keys: Dictionary = {}
var _board_keys_for := -1

func setup(data: MapData, is_excluded: Callable) -> void:
	# Rebuilding the same generator must replace its generated state.
	for child in get_children():
		child.free()
	footprints.clear()
	_footprint_bounds.clear()
	_footprint_grid.clear()
	building_metadata.clear()
	_styles.clear()
	_chunks.clear()
	_pending.clear()
	_built.clear()
	_stream_nodes.clear()
	_main_road_grid.clear()
	_road_grid.clear()
	_sign_road_grid.clear()
	measured_height_count = 0
	name = "Buildings"
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/building.gdshader")
	_material.set_shader_parameter("albedo_array", preload("res://assets/textures/facade/facade_albedo.jpg"))
	_material.set_shader_parameter("normal_array", preload("res://assets/textures/facade/facade_normal.jpg"))
	_material.set_shader_parameter("arm_array", preload("res://assets/textures/facade/facade_arm.jpg"))
	_material.set_shader_parameter("signboard_pages", preload("res://assets/textures/signboards/signboards.png"))
	_tank_mesh = CylinderMesh.new()
	_tank_mesh.top_radius = 0.55
	_tank_mesh.bottom_radius = 0.55
	_tank_mesh.height = 1.15
	_tank_mesh.radial_segments = 10
	var tank_material := StandardMaterial3D.new()
	tank_material.albedo_color = Color("#1d1f22")
	tank_material.roughness = 0.6
	_tank_mesh.material = tank_material
	_terrain = data.terrain
	_heights = data.building_heights
	_index_main_roads(data)
	if USE_DECORATIVE_HOUSE_MODELS:
		_load_house_models()
	var appearance_references: Dictionary = {}
	if FileAccess.file_exists(APPEARANCE_REFERENCES_PATH):
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(APPEARANCE_REFERENCES_PATH))
		if document is Dictionary and document.get("buildings") is Dictionary:
			appearance_references = document.buildings
	preload("res://scripts/performance/startup_profile.gd").mark("  setup: head")
	for building in data.buildings:
		var points: PackedVector2Array = building.points
		var area := _signed_area(points)
		if absf(area) < MIN_AREA or building.tags.get("man_made") == "water_tower" or is_excluded.call(points):
			continue
		if area < 0.0:
			points = points.duplicate()
			points.reverse()
		var index := footprints.size()
		footprints.append(points)
		_index_footprint(index, points)
		var style := _style_for(points, absf(area), building.tags)
		var reference_key := "osm/way/%d" % int(building.osm_id) if building.has("osm_id") else ""
		if reference_key == "osm/way/599330373":
			# Frontage interpretation only: no surveyed height is asserted.
			style.floors = 2
			style.wall_height = 6.3
			style.tank = false
			style.theatre_frontage = true
		if appearance_references.has(reference_key):
			style = apply_photo_reference(style, appearance_references[reference_key])
		# Keep source use tags separate from the randomly chosen visual finish.
		var gps := GeoProjection.map_to_lon_lat(_centroid(points))
		var building_id := "osm/way/%s" % str(building.osm_id) if building.has("osm_id") else "%s@%.8f,%.8f" % [str(building.source), gps[0], gps[1]]
		building_metadata.append({"id": building_id,
			"tags": building.tags.duplicate(true), "base": style.base, "floors": style.floors,
			"wall_height": style.get("wall_height", style.floors * FLOOR_HEIGHT + PLINTH),
			"appearance_evidence": style.get("appearance_evidence", {})})
		if USE_DECORATIVE_HOUSE_MODELS:
			_fit_house_model(points, absf(area), style, building.tags)
		_styles.append(style)
		var cell := _cell(_centroid(points))
		if not _chunks.has(cell):
			_chunks[cell] = PackedInt32Array()
		_chunks[cell].append(index)
	_pending.assign(_chunks.keys())
	preload("res://scripts/performance/startup_profile.gd").mark("  setup: styles loop")
	_assign_boards()
	preload("res://scripts/performance/startup_profile.gd").mark("  setup: assign boards")
	preload("res://scripts/world/user_shop_facades.gd").build(self, data)
	preload("res://scripts/performance/startup_profile.gd").mark("  setup: user shop facades")
	_add_historical_shop_reference_panels()
	preload("res://scripts/performance/startup_profile.gd").mark("  setup: historical")

## True when this real place's name is already on its building's shop front.
func has_facade_board(place_name: String) -> bool:
	if _board_keys_for != _board_names.size():
		_board_keys_for = _board_names.size()
		_board_keys.clear()
		for mounted_name: String in _board_names:
			_board_keys[_sign_name_key(mounted_name)] = true
	return _board_keys.has(_sign_name_key(place_name))

## Count of real names drawn on building fronts.
func facade_board_count() -> int:
	return _board_names.size()

## Puts every real named place on the building it stands in (or the nearest one).
func _assign_boards() -> void:
	facade_mounts.clear()
	_board_names.clear()
	_board_keys_for = -1
	unmounted_board_count = 0
	for style in _styles:
		style.erase("boards")
		style.erase("sign_mounts")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOARDS_PATH)) if FileAccess.file_exists(BOARDS_PATH) else null
	if not parsed is Dictionary:
		return
	_boards = parsed.boards
	storefront_allocator = StorefrontAllocator.new()
	storefront_allocator.allocate(footprints, building_metadata, _boards, _direction_to_road, _distance_to_road, _sign_clear_of_roads)
	for mount: Dictionary in storefront_allocator.assignments:
		var style: Dictionary = _styles[mount.building_index]
		if not style.has("boards"):
			style.boards = []
			style.sign_mounts = []
		style.boards.append(mount.board_index)
		style.sign_mounts.append(mount)
		facade_mounts.append(mount)
		_board_names[str(_boards[mount.board_index].name).to_upper()] = true
	unmounted_board_count = storefront_allocator.unplaced.size()
	var reasons := {}
	for record: Dictionary in storefront_allocator.unplaced:
		reasons[record.reason] = int(reasons.get(record.reason, 0)) + 1
	preload("res://scripts/performance/startup_profile.gd").mark("    boards: allocate")
	var report := {"businesses": storefront_allocator.businesses, "storefronts": storefront_allocator.units,
		"assignments": storefront_allocator.assignments, "unplaced": storefront_allocator.unplaced, "reasons": reasons}
	var file := FileAccess.open("user://signage_placement_report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_report_json(report), "  "))
	print("Storefront allocation: %d assigned, %d unplaced; %s" % [facade_mounts.size(), unmounted_board_count, reasons])
	if "--signage-debug" in OS.get_cmdline_user_args():
		_add_signage_debug()

## Test the rendered panel, rather than only its wall anchor. Overlapping source
## footprints must never swallow a sign or leave a thin strip visible at a corner.
func _sign_clear_of_buildings(a: Vector2, b: Vector2, normal: Vector2) -> bool:
	var aa := a + normal * BOARD_OFFSET
	var bb := b + normal * BOARD_OFFSET
	var low := aa.min(bb)
	var high := aa.max(bb)
	for x in range(floori(low.x / FOOTPRINT_CELL), floori(high.x / FOOTPRINT_CELL) + 1):
		for y in range(floori(low.y / FOOTPRINT_CELL), floori(high.y / FOOTPRINT_CELL) + 1):
			for index: int in _footprint_grid.get(Vector2i(x, y), PackedInt32Array()):
				var footprint := footprints[index]
				if Geometry2D.is_point_in_polygon(aa, footprint) or Geometry2D.is_point_in_polygon(bb, footprint):
					return false
				for edge in footprint.size():
					if Geometry2D.segment_intersects_segment(aa, bb, footprint[edge], footprint[(edge + 1) % footprint.size()]) != null:
						return false
	return true

func _index_footprint(index: int, points: PackedVector2Array) -> void:
	var low := points[0]
	var high := low
	for point in points:
		low = low.min(point)
		high = high.max(point)
	_footprint_bounds.append(low)
	_footprint_bounds.append(high)
	for x in range(floori(low.x / FOOTPRINT_CELL), floori(high.x / FOOTPRINT_CELL) + 1):
		for y in range(floori(low.y / FOOTPRINT_CELL), floori(high.y / FOOTPRINT_CELL) + 1):
			var cell := Vector2i(x, y)
			if not _footprint_grid.has(cell):
				_footprint_grid[cell] = PackedInt32Array()
			_footprint_grid[cell].append(index)

func _sign_clear_of_roads(a: Vector2, b: Vector2, normal: Vector2) -> bool:
	if not _sign_clear_of_buildings(a, b, normal):
		return false
	# Validate the complete panel segment, including its wall offset, against
	# source-road corridors; never change building geometry or road widths.
	var middle := (a + b) * 0.5
	var reach := a.distance_to(b) * 0.5 + 25.0
	for x in range(floori((middle.x - reach) / 50.0), floori((middle.x + reach) / 50.0) + 1):
		for y in range(floori((middle.y - reach) / 50.0), floori((middle.y + reach) / 50.0) + 1):
			for road: Dictionary in _sign_road_grid.get(Vector2i(x, y), []):
				var aa := a + normal * BOARD_OFFSET
				var bb := b + normal * BOARD_OFFSET
				if Geometry2D.segment_intersects_segment(aa, bb, road.a, road.b) != null:
					return false
				var distance := minf(aa.distance_to(Geometry2D.get_closest_point_to_segment(aa, road.a, road.b)), bb.distance_to(Geometry2D.get_closest_point_to_segment(bb, road.a, road.b)))
				distance = minf(distance, road.a.distance_to(Geometry2D.get_closest_point_to_segment(road.a, aa, bb)))
				distance = minf(distance, road.b.distance_to(Geometry2D.get_closest_point_to_segment(road.b, aa, bb)))
				if distance < float(road.half_width):
					return false
	return true

static func _report_json(value: Variant) -> Variant:
	if value is Vector2:
		return {"x": value.x, "z": value.y}
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(_report_json(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _report_json(value[key])
		return result
	return value

func _add_signage_debug() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for mount in facade_mounts:
		var middle: Vector2 = (mount.a + mount.b) * 0.5
		mesh.surface_set_color(Color.GREEN)
		mesh.surface_add_vertex(Vector3(middle.x, mount.bottom, middle.y))
		mesh.surface_add_vertex(Vector3(middle.x + mount.normal.x * 2.0, mount.bottom, middle.y + mount.normal.y * 2.0))
	for record: Dictionary in storefront_allocator.unplaced:
		var point: Vector2 = record.position
		var y := _terrain.height_at(point) + 1.5
		mesh.surface_set_color(Color.RED)
		mesh.surface_add_vertex(Vector3(point.x - 0.4, y, point.y))
		mesh.surface_add_vertex(Vector3(point.x + 0.4, y, point.y))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "SignageDebug"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	add_child(instance)

static func _sign_name_key(text: String) -> String:
	return StorefrontAllocator.name_key(text)

static func _distance_to_footprint(point: Vector2, points: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, points):
		return 0.0
	var best := INF
	for index in points.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
		best = minf(best, closest.distance_to(point))
	return best

## Builds every chunk within radius immediately (used at spawn), the rest stream in.
func build_around(center: Vector2, radius: float = SYNC_BUILD_RADIUS) -> void:
	for cell in _pending.duplicate():
		if _cell_center(cell).distance_to(center) <= radius + CHUNK_SIZE:
			_build_chunk(cell)
	_pending = _pending.filter(func(cell: Vector2i) -> bool: return not _built.has(cell))

func build_all() -> void:
	for cell in _pending:
		_build_chunk(cell)
	_pending.clear()

func pending_chunk_count() -> int:
	return _pending.size()

## True when a circle of the given radius touches no building footprint.
func is_clear(point: Vector2, radius: float) -> bool:
	var center := _cell(point)
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			for index: int in _chunks.get(Vector2i(x, y), PackedInt32Array()):
				# Outside the box widened by radius, a footprint can neither hold nor touch the circle.
				var low := _footprint_bounds[index * 2]
				var high := _footprint_bounds[index * 2 + 1]
				if point.x < low.x - radius or point.x > high.x + radius or point.y < low.y - radius or point.y > high.y + radius:
					continue
				var footprint := footprints[index]
				if Geometry2D.is_point_in_polygon(point, footprint):
					return false
				for edge in footprint.size():
					var closest := Geometry2D.get_closest_point_to_segment(point, footprint[edge], footprint[(edge + 1) % footprint.size()])
					if closest.distance_to(point) < radius:
						return false
	return true

func _process(delta: float) -> void:
	_resort_timer -= delta
	if _resort_timer <= 0.0 and focus.is_valid():
		_resort_timer = 0.5
		var center: Vector2 = focus.call()
		if stream_enabled: _refresh_stream(center)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _cell_center(a).distance_squared_to(center) < _cell_center(b).distance_squared_to(center))
	var started := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - started < stream_budget_usec:
		_build_chunk(_pending.pop_front())

func _refresh_stream(center: Vector2) -> void:
	var load_distance := stream_radius + CHUNK_SIZE
	var unload_distance := load_distance + CHUNK_SIZE * 2.0
	_pending = _pending.filter(func(cell: Vector2i) -> bool:
		return not _built.has(cell) and _cell_center(cell).distance_to(center) <= load_distance)
	var origin := _cell(center)
	var count := ceili(load_distance / CHUNK_SIZE) + 1
	for x in range(origin.x - count, origin.x + count + 1):
		for y in range(origin.y - count, origin.y + count + 1):
			var cell := Vector2i(x, y)
			if _chunks.has(cell) and not _built.has(cell) and not _pending.has(cell) and _cell_center(cell).distance_to(center) <= load_distance:
				_pending.append(cell)
	for cell: Vector2i in _stream_nodes.keys():
		if _cell_center(cell).distance_to(center) > unload_distance:
			var chunk: Node = _stream_nodes[cell]
			remove_child(chunk)
			chunk.queue_free()
			_stream_nodes.erase(cell)
			_built.erase(cell)

func apply_view_distance(distance: float) -> void:
	stream_radius = distance
	for chunk: Node in _stream_nodes.values():
		for mesh: GeometryInstance3D in chunk.find_children("*", "GeometryInstance3D", true, false):
			mesh.visibility_range_end = distance
	_resort_timer = 0.0

func _build_chunk(cell: Vector2i) -> void:
	if _built.has(cell):
		return
	_built[cell] = true
	var surface := MeshSurface.new()
	var tanks: Array[Transform3D] = []
	var houses: Array[Array] = []
	for model in HOUSE_MODELS:
		houses.append([])
	for index in _chunks[cell]:
		var style: Dictionary = _styles[index]
		if style.has("house"):
			# The model is drawn instead; keep the footprint's collision so it stays solid.
			var hidden := MeshSurface.new()
			_append_building(hidden, footprints[index], style, tanks)
			surface.collision.append_array(hidden.collision)
			houses[style.house.type].append(style.house.transform)
		else:
			_append_building(surface, footprints[index], style, tanks)
	var chunk := Node3D.new()
	chunk.name = "BuildingChunk_%d_%d" % [cell.x, cell.y]
	add_child(chunk)
	_stream_nodes[cell] = chunk
	for mount: Dictionary in facade_mounts:
		if _cell(_centroid(footprints[mount.building_index])) != cell:
			continue
		if _sign_name_key(str(_boards[mount.board_index].name)) == "new ashok theatre":
			var facade := preload("res://scripts/world/ashok_theatre_facade.gd").build(mount.wall_a,mount.wall_b,mount.normal,building_metadata[mount.building_index].base)
			chunk.add_child(facade)
	for index in _chunks[cell]:
		if str(building_metadata[index].id).trim_suffix(".0") == preload("res://scripts/world/cinema_poster_wall.gd").BUILDING_ID:
			chunk.add_child(preload("res://scripts/world/cinema_poster_wall.gd").build(footprints[index], building_metadata[index].base))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.to_mesh()
	mesh_instance.material_override = _material
	mesh_instance.visibility_range_end = stream_radius
	chunk.add_child(mesh_instance)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(surface.collision)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	chunk.add_child(body)
	if not tanks.is_empty():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _tank_mesh
		multimesh.instance_count = tanks.size()
		for tank_index in tanks.size():
			multimesh.set_instance_transform(tank_index, tanks[tank_index])
		var tank_instance := MultiMeshInstance3D.new()
		tank_instance.multimesh = multimesh
		tank_instance.visibility_range_end = mesh_instance.visibility_range_end * 0.5
		chunk.add_child(tank_instance)
	for type in houses.size():
		if houses[type].is_empty() or _house_meshes[type] == null:
			continue
		var house_multimesh := MultiMesh.new()
		house_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		house_multimesh.mesh = _house_meshes[type]
		house_multimesh.instance_count = houses[type].size()
		for instance in houses[type].size():
			house_multimesh.set_instance_transform(instance, houses[type][instance])
		var house_instance := MultiMeshInstance3D.new()
		house_instance.name = "Houses_%d" % (type + 1)
		house_instance.multimesh = house_multimesh
		house_instance.visibility_range_end = MOBILE_HOUSE_VIEW_DISTANCE if OS.has_feature("mobile") else HOUSE_VIEW_DISTANCE
		chunk.add_child(house_instance)

func _append_building(surface: MeshSurface, points: PackedVector2Array, style: Dictionary, tanks: Array[Transform3D]) -> void:
	var base: float = style.base
	var height: float = base + style.get("wall_height", style.floors * FLOOR_HEIGHT + PLINTH)
	var top := height + PARAPET_HEIGHT
	var paint: Color = style.color
	var count := points.size()
	var along := 0.0
	for edge in count:
		var a := points[edge]
		var b := points[(edge + 1) % count]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var direction := (b - a) / length
		var outward := Vector3(direction.y, 0.0, -direction.x)
		var a0 := Vector3(a.x, base, a.y)
		var b0 := Vector3(b.x, base, b.y)
		var a1 := Vector3(a.x, top, a.y)
		var b1 := Vector3(b.x, top, b.y)
		# Wall UVs are metres above the building's own base so windows line up per floor.
		var uv_a0 := Vector2(along, 0.0)
		var uv_b0 := Vector2(along + length, 0.0)
		var uv_a1 := Vector2(along, top - base)
		var uv_b1 := Vector2(along + length, top - base)
		var info := Vector2(height - base, KIND_PLAIN if style.get("theatre_frontage",false) else KIND_FACADE)
		surface.quad(a0, b0, b1, a1, outward, paint, uv_a0, uv_b0, uv_b1, uv_a1, info, true)
		var to_road := _direction_to_road((a + b) * 0.5)
		var road_facing := Vector2(outward.x, outward.z).dot(to_road) > 0.6
		if style.near_main_road and length >= LEDGE_MIN_WALL and not style.get("theatre_frontage",false):
			_append_ledges(surface, a, b, outward, along, base, height, style, paint)
			if road_facing:
				_append_apron(surface, a, b, outward, base, height, paint)
		elif ENABLE_INFERRED_RESIDENTIAL_FORECOURTS and style.residential_frontage and road_facing and length >= 2.5:
			# Narrow front slab/step for a house beside a Vidya Nagar 2 lane.
			# It leaves the mapped setback visible while giving each home an access edge.
			_append_apron(surface, a, b, outward, base, height, paint, 0.95)
		# Inner face of the parapet, visible from rooftops and the overhead camera.
		var a_roof := Vector3(a.x, height, a.y)
		var b_roof := Vector3(b.x, height, b.y)
		surface.quad(a_roof, b_roof, b1, a1, -outward, paint, uv_a0, uv_b0, uv_b1, uv_a1, Vector2(height - base, KIND_PLAIN), false)
		along += length
	if style.has("boards"):
		_append_boards(surface, points, style, base, height, top)
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		# Self-intersecting footprint: roof it with its convex hull rather than leave it open.
		points = Geometry2D.convex_hull(points)
		points.remove_at(points.size() - 1)
		triangles = Geometry2D.triangulate_polygon(points)
	for corner in range(0, triangles.size(), 3):
		var p0 := points[triangles[corner]]
		var p1 := points[triangles[corner + 1]]
		var p2 := points[triangles[corner + 2]]
		surface.triangle(Vector3(p0.x, height, p0.y), Vector3(p1.x, height, p1.y), Vector3(p2.x, height, p2.y),
			Vector3.UP, paint, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(height, KIND_ROOF), true)
	if style.tank:
		var center := _centroid(points)
		if Geometry2D.is_point_in_polygon(center, points):
			tanks.append(Transform3D(Basis(), Vector3(center.x, height + 0.6, center.y)))

## Thin painted slabs along one wall: an awning over the shops, then a chajja over
## every storey's windows. Visual only, so the chase camera's spring arm ignores them.
func _append_ledges(surface: MeshSurface, a: Vector2, b: Vector2, outward: Vector3, along: float,
		base: float, height: float, style: Dictionary, paint: Color) -> void:
	var shops := paint.a8 % 2 == 0
	for storey in int(style.floors):
		var floor_base: float = base + storey * FLOOR_HEIGHT
		var shop_awning: bool = storey == 0 and shops
		var bottom: float = floor_base + (AWNING_HEIGHT if shop_awning else LEDGE_HEIGHT)
		if bottom + LEDGE_THICKNESS > height - 0.3:
			break
		_append_slab(surface, a, b, outward, along, bottom, AWNING_DEPTH if shop_awning else LEDGE_DEPTH, base, height, paint)

## Signboards for the building's real places on its most road-facing walls, side by
## side above the shops. UVs address the board's cell in the atlas page.
func _append_boards(surface: MeshSurface, points: PackedVector2Array, style: Dictionary, base: float, height: float, top: float) -> void:
	if style.get("theatre_frontage",false):
		return # Custom facade lettering replaces the small storefront panel.
	for mount: Dictionary in style.get("sign_mounts", []):
		_append_board(surface, mount.a, mount.b, mount.bottom, mount.height, _boards[mount.board_index], height - base)

func _append_board(surface: MeshSurface, a: Vector2, b: Vector2, bottom: float, board_height: float, board: Dictionary, roof: float) -> void:
	var direction := (b - a).normalized()
	var outward := Vector3(direction.y, 0.0, -direction.x)
	var a0 := Vector3(a.x, bottom, a.y) + outward * BOARD_OFFSET
	var b0 := Vector3(b.x, bottom, b.y) + outward * BOARD_OFFSET
	var lift := Vector3.UP * board_height
	var rect: Array = board.rect
	# Seen from outside, wall b is on the viewer's left, so the cell's left edge goes there.
	var info := Vector2(float(board.page), KIND_SIGN)
	surface.quad(a0, b0, b0 + lift, a0 + lift, outward, Color.WHITE,
		Vector2(rect[2], rect[3]), Vector2(rect[0], rect[3]), Vector2(rect[0], rect[1]), Vector2(rect[2], rect[1]), info, false)

## Raised concrete forecourt along the road-facing wall, visual only.
func _append_apron(surface: MeshSurface, a: Vector2, b: Vector2, outward: Vector3, base: float, height: float, paint: Color,
		depth := APRON_DEPTH) -> void:
	var out := outward * depth
	var top := Vector3.UP * (base + APRON_HEIGHT)
	var bottom := Vector3.UP * base
	var a_wall := Vector3(a.x, 0.0, a.y)
	var b_wall := Vector3(b.x, 0.0, b.y)
	var info := Vector2(height - base, KIND_APRON)
	surface.quad(a_wall + top, b_wall + top, b_wall + out + top, a_wall + out + top,
		Vector3.UP, paint, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, info, false)
	surface.quad(a_wall + out + bottom, b_wall + out + bottom, b_wall + out + top, a_wall + out + top,
		outward, paint, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, info, false)

func _append_slab(surface: MeshSurface, a: Vector2, b: Vector2, outward: Vector3, along: float,
		bottom: float, depth: float, base: float, height: float, paint: Color) -> void:
	var top := bottom + LEDGE_THICKNESS
	var length := a.distance_to(b)
	var out := outward * depth
	var a_wall := Vector3(a.x, 0.0, a.y)
	var b_wall := Vector3(b.x, 0.0, b.y)
	var info := Vector2(height - base, KIND_LEDGE)
	var u0 := Vector2(along, bottom - base)
	var u1 := Vector2(along + length, bottom - base)
	var u2 := Vector2(along + length, top - base)
	var u3 := Vector2(along, top - base)
	var lift_bottom := Vector3.UP * bottom
	var lift_top := Vector3.UP * top
	# Front edge, top and underside; the short ends are hidden against neighbours or too thin to see.
	surface.quad(a_wall + out + lift_bottom, b_wall + out + lift_bottom, b_wall + out + lift_top, a_wall + out + lift_top,
		outward, paint, u0, u1, u2, u3, info, false)
	var d0 := Vector2(along, 0.0)
	var d1 := Vector2(along + length, 0.0)
	var d2 := Vector2(along + length, depth)
	var d3 := Vector2(along, depth)
	surface.quad(a_wall + lift_top, b_wall + lift_top, b_wall + out + lift_top, a_wall + out + lift_top,
		Vector3.UP, paint, d0, d1, d2, d3, info, false)
	surface.quad(a_wall + lift_bottom, b_wall + lift_bottom, b_wall + out + lift_bottom, a_wall + out + lift_bottom,
		Vector3.DOWN, paint, d0, d1, d2, d3, info, false)

func _style_for(points: PackedVector2Array, area: float, tags: Dictionary) -> Dictionary:
	var center := _centroid(points)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(center.x * 10.0), roundi(center.y * 10.0)))
	var near_main_road := _is_near_main_road(center)
	var kind := str(tags.get("building", "yes"))
	var floors := 1
	var measured := _heights.height_for(points) if _heights else 0.0
	if tags.has("building:levels"):
		floors = clampi(int(str(tags["building:levels"]).to_int()), 1, 12)
	elif measured > 0.0:
		floors = clampi(roundi((measured - PLINTH) / FLOOR_HEIGHT), 1, MAX_MEASURED_FLOORS)
		measured_height_count += 1
	elif kind in ["school", "college", "hospital", "commercial", "retail", "office"]:
		floors = rng.randi_range(2, 3)
	elif area < 25.0:
		floors = 1
	elif near_main_road:
		floors = [2, 2, 3, 3, 3, 4, 4][rng.randi_range(0, 6)]
	else:
		floors = [1, 1, 1, 2, 2, 2, 2, 3, 3][rng.randi_range(0, 8)]
	if area > 800.0 and measured <= 0.0:
		floors = clampi(floors, 1, 3)
	var commercial := kind in ["commercial", "retail"] or tags.has("shop") or (near_main_road and rng.randf() < 0.75)
	# Explicit residential use must not acquire random storefront shutters.
	if kind in StorefrontAllocator.RESIDENTIAL and not tags.has("shop"):
		commercial = false
	var color: Color = PAINTS[rng.randi_range(0, PAINTS.size() - 1)]
	# Small deterministic pigment variation retains a coherent town palette.
	# Derive it independently so existing floor/use/finish/tank choices do not shift.
	var pigment_seed := absi(hash(Vector2i(roundi(center.x), roundi(center.y))))
	var pigment := 0.90 + float(pigment_seed % 101) / 1000.0
	color = Color(color.r * pigment, color.g * pigment, color.b * pigment, color.a)
	# Most Godavarikhani buildings are painted; back-lane ones are often bare brick or concrete.
	var finish_roll := rng.randf()
	var finish := Finish.PAINTED
	if near_main_road:
		finish = Finish.PEELING if finish_roll < 0.12 else Finish.PAINTED
	elif finish_roll < 0.1:
		finish = Finish.PEELING
	elif finish_roll < 0.22:
		finish = Finish.BRICK
	elif finish_roll < 0.3:
		finish = Finish.CONCRETE
	color.a8 = (0 if commercial else 1) | (finish << 1) | (rng.randi_range(0, 31) << 3)
	# Sink the base slightly below the lowest ground under the footprint so no wall floats on slopes.
	var base := (_terrain.lowest_under(points) if _terrain else 0.0) - 0.3
	var residential_frontage := not near_main_road and kind == "yes" and area <= 260.0 \
		and center.distance_to(VIDYA_NAGAR_2_CENTER) <= VIDYA_NAGAR_2_RADIUS \
		and _distance_to_road(center) <= RESIDENTIAL_FRONTAGE_DISTANCE
	var style := {"floors": floors, "color": color, "base": base, "tank": area > 30.0 and rng.randf() < 0.55,
		"near_main_road": near_main_road, "residential_frontage": residential_frontage,
		"measured": measured > 0.0, "pick": rng.randf()}
	return apply_source_appearance(style, tags)

## Only explicit source attributes override procedural appearance. An image GPS
## point is never treated as a building ID or permission to guess its facade.
static func apply_source_appearance(style: Dictionary, tags: Dictionary) -> Dictionary:
	var evidence := {}
	var paint_text := str(tags.get("building:colour", tags.get("building:color", ""))).strip_edges()
	if not paint_text.is_empty() and Color.html_is_valid(paint_text):
		var paint := Color.html(paint_text)
		# Alpha encodes facade use, finish and variation; retain those shader bits.
		paint.a = (style.color as Color).a
		style.color = paint
		evidence["paint"] = "building:colour/color"
	var height_text := str(tags.get("height", "")).strip_edges().trim_suffix(" m").trim_suffix("m").strip_edges()
	if height_text.is_valid_float():
		var height := height_text.to_float()
		if is_finite(height) and height >= 2.5 and height <= 150.0:
			style.wall_height = height
			if not tags.has("building:levels"):
				style.floors = clampi(floori(height / FLOOR_HEIGHT), 1, MAX_MEASURED_FLOORS)
			evidence["height"] = "height"
	if tags.has("building:levels"):
		evidence["floors"] = "building:levels"
	style.appearance_evidence = evidence
	return style

static func apply_photo_reference(style: Dictionary, reference: Dictionary) -> Dictionary:
	# A building-bound record must carry provenance. Unbound observations never
	# enter this path, and original map tags/coordinates are never overwritten.
	if str(reference.get("reference_url", "")).is_empty() or str(reference.get("capture_date", "")).is_empty() or reference.get("image_ids", []).is_empty():
		return style
	var levels := str(reference.get("building:levels", ""))
	if levels.is_valid_int() and levels.to_int() >= 1 and levels.to_int() <= MAX_MEASURED_FLOORS:
		style.floors = levels.to_int()
		# Retain measured metric height when present; storeys alone do not measure metres.
	var prior: Dictionary = style.get("appearance_evidence", {}).duplicate(true)
	style = apply_source_appearance(style, reference)
	style.appearance_evidence.merge(prior)
	style.appearance_evidence["photo_reference"] = reference.duplicate(true)
	return style

func _load_house_models() -> void:
	for model in HOUSE_MODELS:
		var mesh: Mesh = null
		if ResourceLoader.exists(model.scene):
			var scene: Node = (load(model.scene) as PackedScene).instantiate()
			var found := scene.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				mesh = (found[0] as MeshInstance3D).mesh
			scene.free()
		_house_meshes.append(mesh)

## Swaps a plain extrusion for a house model when the real footprint is a near-rectangle
## of matching size in a residential street (not on a main road, not a named place).
func _fit_house_model(points: PackedVector2Array, area: float, style: Dictionary, tags: Dictionary) -> void:
	if tags.has("name") or tags.has("amenity") or tags.has("shop") or points.size() > 12:
		return
	var apartment: bool = style.measured and style.floors >= APARTMENT_MIN_FLOORS
	if not apartment and (style.near_main_road or style.pick >= HOUSE_SHARE or points.size() > 10):
		return
	var box := _oriented_box(points)
	var min_rectangularity := APARTMENT_MIN_RECTANGULARITY if apartment else HOUSE_MIN_RECTANGULARITY
	if box.is_empty() or area / (box.width * box.depth) < min_rectangularity:
		return
	var best := -1
	var best_error := APARTMENT_FIT_TOLERANCE if apartment else HOUSE_FIT_TOLERANCE
	var swap := false
	for type in HOUSE_MODELS.size():
		var model: Dictionary = HOUSE_MODELS[type]
		if _house_meshes[type] == null or (model.kind == "apartment") != apartment:
			continue
		# Measured two-storey buildings only get the two-storey house, and vice versa.
		if not apartment and style.measured and (style.floors >= 2) != (model.storeys >= 2):
			continue
		for swapped in [false, true]:
			var width: float = box.depth if swapped else box.width
			var depth: float = box.width if swapped else box.depth
			var error := maxf(absf(width / model.width - 1.0), absf(depth / model.depth - 1.0))
			if error < best_error:
				best_error = error
				best = type
				swap = swapped
	if best == -1:
		return
	var model: Dictionary = HOUSE_MODELS[best]
	var along: Vector2 = box.axis.orthogonal() if swap else box.axis
	var width_dir := Vector3(along.x, 0.0, along.y)
	var depth_dir := width_dir.cross(Vector3.UP)
	var center: Vector2 = box.center
	var to_road := _direction_to_road(center)
	if to_road != Vector2.ZERO and Vector2(depth_dir.x, depth_dir.z).dot(to_road) * model.front < 0.0:
		width_dir = -width_dir
		depth_dir = -depth_dir
	var width: float = box.depth if swap else box.width
	var depth: float = box.width if swap else box.depth
	# Apartment blocks also stretch to the measured height; houses keep their own.
	var height_scale := 1.0
	if apartment:
		height_scale = clampf((style.floors * FLOOR_HEIGHT + PLINTH) / model.height, 0.5, 1.6)
	var basis := Basis(width_dir * (width / model.width), Vector3.UP * height_scale, depth_dir * (depth / model.depth))
	style.house = {"type": best, "transform": Transform3D(basis, Vector3(center.x, style.base + 0.3, center.y))}
	style.floors = maxi(1, roundi((model.height * height_scale - PLINTH - PARAPET_HEIGHT) / FLOOR_HEIGHT))
	style.tank = false
	if apartment:
		apartment_model_count += 1
	else:
		house_model_count += 1

## Minimum-area rectangle around a footprint: {center, axis (unit), width (along axis), depth}.
static func _oriented_box(points: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(points)
	var best := {}
	var best_area := INF
	for index in range(hull.size() - 1):
		var edge := hull[index + 1] - hull[index]
		if edge.length_squared() < 0.0001:
			continue
		var axis := edge.normalized()
		var normal := axis.orthogonal()
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point in hull:
			var local := Vector2(point.dot(axis), point.dot(normal))
			low = low.min(local)
			high = high.max(local)
		var size := high - low
		if size.x * size.y < best_area:
			best_area = size.x * size.y
			var middle := (low + high) * 0.5
			best = {"center": axis * middle.x + normal * middle.y, "axis": axis, "width": size.x, "depth": size.y}
	return best

func _direction_to_road(point: Vector2) -> Vector2:
	var center := Vector2i(floori(point.x / 50.0), floori(point.y / 50.0))
	var best := Vector2.ZERO
	var best_distance := INF
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			var segments: PackedVector2Array = _road_grid.get(Vector2i(x, y), PackedVector2Array())
			for index in range(0, segments.size(), 2):
				var closest := Geometry2D.get_closest_point_to_segment(point, segments[index], segments[index + 1])
				if closest.distance_to(point) < best_distance:
					best_distance = closest.distance_to(point)
					best = (closest - point).normalized()
	return best

func _distance_to_road(point: Vector2) -> float:
	var center := Vector2i(floori(point.x / 50.0), floori(point.y / 50.0))
	var best_distance := INF
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			var segments: PackedVector2Array = _road_grid.get(Vector2i(x, y), PackedVector2Array())
			for index in range(0, segments.size(), 2):
				best_distance = minf(best_distance, Geometry2D.get_closest_point_to_segment(point, segments[index], segments[index + 1]).distance_to(point))
	return best_distance

func _index_main_roads(data: MapData) -> void:
	for road in data.roads:
		if not RoadStyle.is_path(road.kind):
			var road_points: PackedVector2Array = road.points
			for index in range(1, road_points.size()):
				var a := road_points[index - 1]
				var b := road_points[index]
				for x in range(floori(minf(a.x, b.x) / 50.0), floori(maxf(a.x, b.x) / 50.0) + 1):
					for y in range(floori(minf(a.y, b.y) / 50.0), floori(maxf(a.y, b.y) / 50.0) + 1):
						var sign_cell := Vector2i(x, y)
						if not _sign_road_grid.has(sign_cell):
							_sign_road_grid[sign_cell] = []
						_sign_road_grid[sign_cell].append({"a": a, "b": b, "half_width": RoadStyle.width(road) * 0.5})
				var road_cell := Vector2i(floori(road_points[index].x / 50.0), floori(road_points[index].y / 50.0))
				if not _road_grid.has(road_cell):
					_road_grid[road_cell] = PackedVector2Array()
				_road_grid[road_cell].append_array(PackedVector2Array([road_points[index - 1], road_points[index]]))
		if not (RoadStyle.is_major(road.kind) or road.kind == "tertiary"):
			continue
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			var cell := Vector2i(floori(points[index].x / 50.0), floori(points[index].y / 50.0))
			if not _main_road_grid.has(cell):
				_main_road_grid[cell] = PackedVector2Array()
			_main_road_grid[cell].append_array(PackedVector2Array([points[index - 1], points[index]]))

func _is_near_main_road(point: Vector2) -> bool:
	var center := Vector2i(floori(point.x / 50.0), floori(point.y / 50.0))
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			var segments: PackedVector2Array = _main_road_grid.get(Vector2i(x, y), PackedVector2Array())
			for index in range(0, segments.size(), 2):
				if Geometry2D.get_closest_point_to_segment(point, segments[index], segments[index + 1]).distance_to(point) < MAIN_ROAD_DISTANCE:
					return true
	return false

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))

func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CHUNK_SIZE

static func _signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

static func _centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())

## Historical names belong to a matched block, not verified individual units.
## Keep them on one explicit research panel rather than claiming storefront pins.
func _add_historical_shop_reference_panels() -> void:
	var path := "res://data/local/historical_shop_observations.json"
	if not FileAccess.file_exists(path):
		return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary:
		return
	for block: Dictionary in document.get("blocks", []):
		var key := "osm/way/%d" % int(block.osm_way_id)
		for index in building_metadata.size():
			if str(building_metadata[index].id) != key:
				continue
			var points := footprints[index]
			var best := 0
			var best_score := -INF
			for edge in points.size():
				var a := points[edge]
				var b := points[(edge + 1) % points.size()]
				var middle := (a + b) * 0.5
				var normal := Vector2((b - a).normalized().y, -(b - a).normalized().x)
				var score: float = normal.dot(_direction_to_road(middle)) * 100.0 + minf(a.distance_to(b), 50.0)
				if score > best_score:
					best_score = score
					best = edge
			var a := points[best]
			var b := points[(best + 1) % points.size()]
			var middle := (a + b) * 0.5
			var direction := (b - a).normalized()
			var normal := Vector2(direction.y, -direction.x)
			var location := middle + normal * 0.3
			var panel := Label3D.new()
			panel.name = "HistoricalShopReference_%d" % int(block.osm_way_id)
			panel.text = "%s — HISTORICAL SHOP REFERENCES\nSeen June 2020; current occupancy unverified\n%s\nMatched block only; individual shop bays unverified\nMapillary / geomannar" % [str(block.building_name), " | ".join(PackedStringArray(block.names))]
			panel.font_size = 32
			panel.pixel_size = 0.012
			panel.outline_size = 8
			panel.modulate = Color("#fff0b0")
			panel.visibility_range_end = 100.0
			panel.position = Vector3(location.x, float(_styles[index].base) + 4.8, location.y)
			panel.rotation.y = atan2(normal.x, normal.y)
			panel.set_meta("source", document.reference_url)
			panel.set_meta("capture_date", document.capture_date)
			panel.set_meta("placement_status", block.placement_status)
			add_child(panel)
			# Unlocated observations remain explicit research notes, never destinations.
			for note: Dictionary in document.get("unlocated_observations", []):
				panel.text += "\nOther junction observation: %s (building unverified)" % str(note.name)
			break
