class_name RoadsideDrainageBuilder
extends Node3D
## Representative game scenery. No surveyed drainage/GIS is imported here.
## Shallow channels fit above the visual terrain (-0.2 m). Terrain collision is
## deliberately retained: this first version adds no obstacles or fall hazards.

const CHUNK_SIZE := 160.0
const GRID_SIZE := 32.0
const SECTION_LENGTH := 4.0
const WIDTH := 0.64
const HALF := WIDTH * 0.5
const EDGE_GAP := 1.35
## Existing shopfront aprons project 1.8 m beyond source footprints. Reserve
## that full depth plus clearance, including for chunks not yet rendered.
const BUILDING_MARGIN := BuildingBuilder.APRON_DEPTH + 0.55
const ROAD_MARGIN := 1.08
const BED_Y := -0.14
const WATER_Y := -0.085
const RIM_Y := 0.018
const FRAME_BUDGET_USEC := 3000
const ELIGIBLE := ["primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service", "road"]
const RESIDENTIAL := ["residential", "living_street", "service", "unclassified", "road"]
const CONCRETE := Color("#96988b")
const ConcreteShader := preload("res://shaders/roadside_drainage.gdshader")
const WaterShader := preload("res://shaders/roadside_drainage_water.gdshader")

var segments: Array[Dictionary] = []
var covered_count := 0
var open_count := 0
var rejected_count := 0
var candidate_count := 0
var budget_limited := false
var generation_complete := false
var enabled := true:
	set(value):
		enabled = value
		visible = value
var water_enabled := true:
	set(value):
		water_enabled = value
		for child in get_children():
			if child.name.begins_with("Water_"):
				child.visible = value
var focus: Callable
var _data: MapData
var _roads: Dictionary = {}
var _polygons: Dictionary = {}
var _barriers: Dictionary = {}
var _placed: Dictionary = {}
var _keep_clear: Array[Vector3] = []
var _entrances: Array[Vector2] = []
var _jobs: Dictionary = {}
var _pending: Array[Vector2i] = []
var _current_cell := Vector2i.ZERO
var _current_jobs: Array = []
var _job_index := 0
var _surface: MeshSurface
var _water: MeshSurface
var _concrete_material: ShaderMaterial
var _water_material: ShaderMaterial
var _limit := 12000
var _view_distance := 300.0
var _debug := false

func setup(world: Node, data: MapData) -> void:
	for child in get_children():
		child.free()
	segments.clear()
	covered_count = 0
	open_count = 0
	rejected_count = 0
	candidate_count = 0
	budget_limited = false
	generation_complete = false
	_roads.clear()
	_polygons.clear()
	_barriers.clear()
	_placed.clear()
	_keep_clear.clear()
	_entrances.clear()
	_jobs.clear()
	_pending.clear()
	_current_jobs.clear()
	_job_index = 0
	_surface = null
	_water = null
	_data = data
	name = "RepresentativeDrainage"
	_limit = 6000 if OS.has_feature("mobile") else 12000
	_view_distance = 180.0 if OS.has_feature("mobile") else 300.0
	_debug = "--drainage-debug" in OS.get_cmdline_user_args()
	_concrete_material = ShaderMaterial.new()
	_concrete_material.shader = ConcreteShader
	_water_material = ShaderMaterial.new()
	_water_material.shader = WaterShader
	for road: Dictionary in data.roads:
		var points: PackedVector2Array = road.points
		var half := RoadStyle.width(road) * 0.5
		for i in range(1, points.size()):
			_index_segment(_roads, {"a": points[i - 1], "b": points[i], "radius": half + ROAD_MARGIN}, half + ROAD_MARGIN)
	for polygon: PackedVector2Array in world.buildings.footprints:
		_index_polygon(polygon)
	for area: Dictionary in data.areas:
		if area.kind in ["water", "stadium", "pitch", "quarry"]:
			_index_polygon(area.points)
	for barrier: Dictionary in data.barriers:
		_add_barrier(barrier.points, 0.8)
	for rail: PackedVector2Array in data.railways:
		_add_barrier(rail, 2.0)
	for entry: Vector3 in world.street_life.occupied():
		_keep_clear.append(entry)
	for spawn: Dictionary in world.vehicle_spawns:
		_protect(spawn.position, 5.0)
	if not world.player_spawn.is_empty():
		_protect(world.player_spawn.position, 5.0)
	if not world.helicopter_spawn.is_empty():
		_protect(world.helicopter_spawn.position, 16.0)
	for entry: Dictionary in world.bus_station.terminal_entries:
		_protect(entry.position, 14.0)
	for entry: Dictionary in world.local_activity.shop_entries:
		_protect(entry.position, 4.0)
	# Unknown doors are treated conservatively: open sections need a generous
	# footprint setback; known/inferred storefronts get an additional cover zone.
	for unit: Dictionary in world.buildings.storefront_allocator.units:
		_entrances.append(unit.entrance)
	# Select complete source runs across the city, rather than exhausting all
	# geometry near spawn and leaving distant districts permanently empty.
	var candidates: Array[Dictionary] = data.roads.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _road_priority(a) < _road_priority(b))
	for road: Dictionary in candidates:
		_queue_road(road)
	_pending.assign(_jobs.keys())
	_sort_pending(Vector2.ZERO)
	set_process(true)

func _protect(point: Vector3, radius: float) -> void:
	_keep_clear.append(Vector3(point.x, point.z, radius))

func _road_priority(road: Dictionary) -> int:
	for p: Vector2 in road.points:
		if p.length() < 160.0:
			return -1000000000 + int(road.way_id) % 1000000
	return posmod(int(road.way_id) * 2654435761, 1000000000)

func _queue_road(road: Dictionary) -> void:
	if not road.kind in ELIGIBLE or str(road.get("junction", "")) == "roundabout":
		return
	var points: PackedVector2Array = road.points
	var half := RoadStyle.width(road) * 0.5
	var along := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var direction := (b - a) / length
		var count := maxi(1, ceili(length / SECTION_LENGTH))
		for side: float in [-1.0, 1.0]:
			var normal := direction.orthogonal() * side
			var offset := normal * (half + EDGE_GAP + HALF)
			for step in count:
				if candidate_count >= _limit:
					budget_limited = true
					return
				candidate_count += 1
				var start := a.lerp(b, float(step) / count) + offset
				var end := a.lerp(b, float(step + 1) / count) + offset
				var cell := Vector2i(floori((start.x + end.x) * 0.5 / CHUNK_SIZE), floori((start.y + end.y) * 0.5 / CHUNK_SIZE))
				if not _jobs.has(cell):
					_jobs[cell] = []
				_jobs[cell].append({"a": start, "b": end, "normal": normal, "road_id": road.way_id,
					"kind": road.kind, "side": side, "along": along + length * step / count})
		along += length

func _process(_delta: float) -> void:
	if not enabled:
		return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < FRAME_BUDGET_USEC and not generation_complete:
		_step()

func build_all() -> void:
	while not generation_complete:
		_step()

func _step() -> void:
	if _job_index >= _current_jobs.size():
		_commit_chunk()
		if _pending.is_empty() or segments.size() >= _limit:
			budget_limited = budget_limited or not _pending.is_empty()
			_jobs.clear()
			_pending.clear()
			_current_jobs.clear()
			generation_complete = true
			set_process(false)
			print("Representative drainage: %d covered, %d open sections; %d rejected; budget limited: %s" % [covered_count, open_count, rejected_count, budget_limited])
			return
		if focus.is_valid():
			_sort_pending(focus.call())
		_current_cell = _pending.pop_front()
		_current_jobs = _jobs[_current_cell]
		_jobs.erase(_current_cell)
		_job_index = 0
		_surface = MeshSurface.new()
		_water = MeshSurface.new()
	var job: Dictionary = _current_jobs[_job_index]
	_job_index += 1
	if segments.size() >= _limit:
		budget_limited = true
		_job_index = _current_jobs.size()
		return
	if not placement_clear(job.a, job.b):
		rejected_count += 1
		return
	var covered := not _open_allowed(job)
	job["covered"] = covered
	job["provenance"] = "representative_procedural"
	segments.append(job)
	_index_segment(_placed, {"a": job.a, "b": job.b, "radius": WIDTH + 0.08}, WIDTH + 0.08)
	if covered:
		covered_count += 1
	else:
		open_count += 1
	_append_section(job)

func placement_clear(a: Vector2, b: Vector2, building_margin := BUILDING_MARGIN) -> bool:
	for endpoint: Vector2 in [a, b]:
		if endpoint.length() + HALF > GeoProjection.PLAYABLE_RADIUS_METERS:
			return false
	for entry: Dictionary in _nearby(_roads, a, b, HALF):
		if _segment_distance(a, b, entry.a, entry.b) < float(entry.radius) + HALF:
			return false
	if not _buildings_clear(a, b, HALF + building_margin):
		return false
	for entry: Dictionary in _nearby(_barriers, a, b, HALF):
		if _segment_distance(a, b, entry.a, entry.b) < float(entry.radius) + HALF:
			return false
	for entry: Dictionary in _nearby(_placed, a, b, WIDTH):
		# Consecutive sections may share an end, but parallel duplicates must not.
		if a.distance_to(entry.b) < 0.01 or b.distance_to(entry.a) < 0.01:
			continue
		if _segment_distance(a, b, entry.a, entry.b) < WIDTH + 0.06:
			return false
	for spot: Vector3 in _keep_clear:
		if _point_distance(Vector2(spot.x, spot.y), a, b) < spot.z + HALF:
			return false
	# Draped visuals must stay above the unchanged visible ground between vertices.
	var ha := _height(a)
	var hb := _height(b)
	if absf(ha - hb) > a.distance_to(b) * 0.18:
		return false
	for i in range(1, 8):
		var t := float(i) / 8.0
		for side: float in [-HALF, 0.0, HALF]:
			var n := (b - a).normalized().orthogonal() * side
			var p := a.lerp(b, t) + n
			var interpolated := lerpf(_height(a + n), _height(b + n), t)
			if absf(_height(p) - interpolated) > 0.035:
				return false
	return true

func _open_allowed(job: Dictionary) -> bool:
	if not job.kind in RESIDENTIAL or not _buildings_clear(job.a, job.b, 2.8):
		return false
	for entrance: Vector2 in _entrances:
		if _point_distance(entrance, job.a, job.b) < 9.0:
			return false
	return true

func _buildings_clear(a: Vector2, b: Vector2, margin: float) -> bool:
	for record: Dictionary in _nearby(_polygons, a, b, margin):
		var polygon: PackedVector2Array = record.points
		if Geometry2D.is_point_in_polygon(a, polygon) or Geometry2D.is_point_in_polygon(b, polygon):
			return false
		for i in polygon.size():
			if _segment_distance(a, b, polygon[i], polygon[(i + 1) % polygon.size()]) < margin:
				return false
	return true

func _add_barrier(points: PackedVector2Array, radius: float) -> void:
	for i in range(1, points.size()):
		_index_segment(_barriers, {"a": points[i - 1], "b": points[i], "radius": radius}, radius)

func _index_polygon(points: PackedVector2Array) -> void:
	if points.is_empty():
		return
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	_index_rect(_polygons, rect.grow(3.0), {"points": points})

func _index_segment(store: Dictionary, entry: Dictionary, margin: float) -> void:
	_index_rect(store, Rect2(entry.a, Vector2.ZERO).expand(entry.b).grow(margin), entry)

func _index_rect(store: Dictionary, rect: Rect2, entry: Dictionary) -> void:
	for x in range(floori(rect.position.x / GRID_SIZE), floori(rect.end.x / GRID_SIZE) + 1):
		for y in range(floori(rect.position.y / GRID_SIZE), floori(rect.end.y / GRID_SIZE) + 1):
			var cell := Vector2i(x, y)
			if not store.has(cell):
				store[cell] = []
			store[cell].append(entry)

func _nearby(store: Dictionary, a: Vector2, b: Vector2, margin: float) -> Array:
	var rect := Rect2(a, Vector2.ZERO).expand(b).grow(margin)
	var entries: Array = []
	for x in range(floori(rect.position.x / GRID_SIZE), floori(rect.end.x / GRID_SIZE) + 1):
		for y in range(floori(rect.position.y / GRID_SIZE), floori(rect.end.y / GRID_SIZE) + 1):
			entries.append_array(store.get(Vector2i(x, y), []))
	return entries

static func _point_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))

static func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_point_distance(a, c, d), _point_distance(b, c, d)), minf(_point_distance(c, a, b), _point_distance(d, a, b)))

func _height(p: Vector2) -> float:
	return _data.terrain.height_at(p)

func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, _height(p) + y, p.y)

func _append_section(job: Dictionary) -> void:
	var a: Vector2 = job.a
	var b: Vector2 = job.b
	var n: Vector2 = job.normal
	var al := a - n * HALF
	var ar := a + n * HALF
	var bl := b - n * HALF
	var br := b + n * HALF
	var u: float = job.along
	var end := u + a.distance_to(b)
	var paint := CONCRETE * (0.95 + float(posmod(int(job.road_id), 7)) * 0.012)
	paint.a = 1.0
	if job.covered:
		_quad(_surface, al, bl, br, ar, RIM_Y, paint, u, end, 1.0)
	else:
		_quad(_surface, al, bl, br, ar, BED_Y, paint.darkened(0.40), u, end, 3.0)
		var inner := HALF - 0.075
		_quad(_surface, al, bl, b - n * inner, a - n * inner, RIM_Y, paint, u, end)
		_quad(_surface, a + n * inner, b + n * inner, br, ar, RIM_Y, paint, u, end)
		_vertical(a - n * inner, b - n * inner, BED_Y, RIM_Y, Vector3(n.x, 0, n.y), paint)
		_vertical(b + n * inner, a + n * inner, BED_Y, RIM_Y, Vector3(-n.x, 0, -n.y), paint)
		_quad(_water, a - n * inner, b - n * inner, b + n * inner, a + n * inner, WATER_Y, Color.WHITE, u, end)
	_vertical(bl, al, BED_Y, RIM_Y, Vector3(-n.x, 0, -n.y), paint)
	_vertical(ar, br, BED_Y, RIM_Y, Vector3(n.x, 0, n.y), paint)
	# No transverse walls at tessellation points: open sections remain visually
	# connected rather than becoming a sequence of four-metre concrete dams.

func _quad(surface: MeshSurface, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, color: Color, u: float, end: float, kind := 0.0) -> void:
	surface.quad(_v(a, y), _v(b, y), _v(c, y), _v(d, y), Vector3.UP, color,
		Vector2(u, 0), Vector2(end, 0), Vector2(end, 1), Vector2(u, 1), Vector2(kind, 0), false)

func _vertical(a: Vector2, b: Vector2, low: float, high: float, normal: Vector3, color: Color) -> void:
	_surface.quad(_v(a, low), _v(b, low), _v(b, high), _v(a, high), normal, color,
		Vector2(0, 0), Vector2(a.distance_to(b), 0), Vector2(a.distance_to(b), 1), Vector2(0, 1), Vector2(2, 0), false)

func _commit_chunk() -> void:
	if _surface == null or _surface.vertices.is_empty():
		return
	_add_mesh(_surface, _concrete_material, "Concrete_", true)
	if not _water.vertices.is_empty():
		_add_mesh(_water, _water_material, "Water_", water_enabled)
	_surface = null
	_water = null

func _add_mesh(surface: MeshSurface, material: Material, prefix: String, show: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "%s%d_%d" % [prefix, _current_cell.x, _current_cell.y]
	mesh.mesh = surface.to_mesh()
	mesh.material_override = material
	mesh.visible = show
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = _view_distance
	add_child(mesh)
	if _debug and prefix == "Concrete_":
		var debug_material := StandardMaterial3D.new()
		debug_material.albedo_color = Color("#d97f31")
		debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = debug_material

func _sort_pending(center: Vector2) -> void:
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return ((Vector2(a) + Vector2.ONE * 0.5) * CHUNK_SIZE).distance_squared_to(center) < ((Vector2(b) + Vector2.ONE * 0.5) * CHUNK_SIZE).distance_squared_to(center))
