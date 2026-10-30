class_name RoadBuilder
extends Node3D

## Builds the ground-level map: road carriageways from the real OSM centrelines
## at class/lane-based widths, gravel shoulders, lane markings, zebra crossings at
## mapped crossings, jersey-barrier medians, walls, railway tracks and parks/water/
## pitches. Everything is merged into a few meshes per chunk. Surfaces are drawn by
## shaders/road.gdshader with real asphalt and ground textures; UV2.x carries the
## surface kind (road.gdshader KIND_*) and UV.x the position across the road.
## Road surfaces also get collision on layer 2 (not hit by cars or the person)
## so tests and gameplay can ask "is this point on a road?".

const CHUNK_SIZE := 250.0
const ROAD_LAYER := 2
const JOINT_SEGMENTS := 8
## Matches half the terrain cell so draped geometry follows the ground closely.
const DRAPE_STEP := 7.5
const DASH_LENGTH := 3.0
const DASH_GAP := 5.0
const LINE_WIDTH := 0.14
const MARKINGS_VIEW_DISTANCE := 260.0
const ASPHALT := {"major": Color("#2f3235"), "minor": Color("#3e4144"), "path": Color("#9c8f78"), "track": Color("#8a7458")}
const MARKING_WHITE := Color("#e9e9e2")
## Kinds understood by shaders/road.gdshader.
const KIND_MAJOR := 1.0
const KIND_MINOR := 2.0
const KIND_DIRT := 3.0
const KIND_SHOULDER := 4.0
const AREA_KINDS := {"park": 10.0, "grass": 10.0, "pitch": 11.0, "stadium": 10.0, "water": 13.0, "quarry": 14.0}
## Gravel shoulder beside every carriageway: kept inside the 1.4 m where cars park at the
## roadside, and drawn just above the ground but under every road surface.
const SHOULDER_WIDTH := 1.0
const SHOULDER_HEIGHT := 0.005
## Residential streets in Godavarikhani commonly have open, concrete-lined side
## drains. OpenStreetMap does not map each channel, so these are inferred only
## for local lanes; mapped drain geometry can replace this later.
const DRAIN_WIDTH := 0.55
const DRAIN_DEPTH := 0.36
const DRAIN_OFFSET := 0.14
const DRAIN_END_CLEARANCE := 2.2
const DRAIN_COLOR := Color("#8d918c")
## Vidya Nagar 2's mapped entrance. Drainage is deliberately scoped to this
## first reconstruction district; neighbouring colonies will get their own
## reviewed bounds rather than receiving a blanket procedural treatment.
const VIDYA_NAGAR_2_CENTER := Vector2(315.60, -334.57)
const VIDYA_NAGAR_2_RADIUS := 400.0
## Until a surveyed drainage layer is available, preserve the source road layout
## rather than adding inferred channels that can misrepresent a neighbourhood.
const ENABLE_INFERRED_DRAINS := false
const AREA_COLORS := {
	"park": Color("#5b8a46"), "grass": Color("#7b9655"), "pitch": Color("#4d8a3a"),
	"stadium": Color("#86955f"), "water": Color("#3d6c86"), "quarry": Color("#4a4440"),
}
## Heights above the terrain collision surface. The visible terrain sits 0.2 m lower,
## so areas and roads never z-fight with it at a distance.
const AREA_HEIGHTS := {"quarry": -0.15, "park": -0.12, "grass": -0.12, "stadium": -0.1, "pitch": -0.08, "water": -0.06}

## OSM way ids that produced carriageway geometry, for coverage checks.
var rendered_way_ids: Dictionary = {}
var source_rendered_way_count := 0
var drain_segment_count := 0
var topoexport_rendered_count := 0
var topoexport_duplicate_count := 0
var _surfaces: Dictionary = {}
var _markings: Dictionary = {}
var _solids: Dictionary = {}
var terrain: TerrainData
var _surface_material: StandardMaterial3D
var _marking_material: StandardMaterial3D
var _road_material: ShaderMaterial

func build(data: MapData) -> void:
	name = "Roads"
	terrain = data.terrain
	_surface_material = _vertex_color_material(0.95)
	_marking_material = _vertex_color_material(0.7)
	_road_material = _make_road_material()
	for area in data.areas:
		# The Godavari (GodavariBridgeBuilder) is built at river level, not draped on the ground.
		if not area.has("structure"):
			_add_area(area)
	for road in data.roads:
		# Bridge decks are paved by the bridge model itself.
		if road.get("structure", "") != "bridge":
			_add_road(road)
	source_rendered_way_count = rendered_way_ids.size()
	preload("res://scripts/performance/startup_profile.gd").mark("  road: osm geometry")
	for road in data.topoexport_roads:
		if _matches_existing_road(road, data.roads, data.osm_road_grid()):
			topoexport_duplicate_count += 1
		else:
			_add_road(road)
			topoexport_rendered_count += 1
	preload("res://scripts/performance/startup_profile.gd").mark("  road: topo")
	for crossing in data.crossings:
		_add_zebra(crossing, data)
	for barrier in data.barriers:
		var tall: bool = barrier.kind != "jersey_barrier"
		_add_wall(barrier.points, 0.3 if tall else 0.6, 2.0 if tall else 0.8,
			Color("#c9bfae") if tall else Color("#b7b4ac"))
	for railway in data.railways:
		_add_railway(railway)
	for area in data.areas:
		if area.kind == "stadium":
			_add_compound_wall(area.points, data)
	preload("res://scripts/performance/startup_profile.gd").mark("  road: zebra walls rail")
	_commit()
	preload("res://scripts/performance/startup_profile.gd").mark("  road: commit")

## Compound wall around a mapped stadium, with a gate gap facing the nearest road.
func _add_compound_wall(ring: PackedVector2Array, data: MapData) -> void:
	var gate := ring[0]
	var best := INF
	for point in ring:
		for road in data.roads:
			for road_point in road.points:
				var distance: float = point.distance_to(road_point)
				if distance < best:
					best = distance
					gate = point
	var closed := ring.duplicate()
	closed.append(ring[0])
	var piece := PackedVector2Array()
	for index in closed.size():
		if closed[index].distance_to(gate) < 6.0:
			if piece.size() >= 2:
				_add_wall(piece, 0.3, 2.2, Color("#d8cfb8"))
			piece = PackedVector2Array()
			continue
		piece.append(closed[index])
	if piece.size() >= 2:
		_add_wall(piece, 0.3, 2.2, Color("#d8cfb8"))

static func road_style_color(kind: String) -> Color:
	if RoadStyle.is_major(kind):
		return ASPHALT.major
	if RoadStyle.is_path(kind):
		return ASPHALT.path
	if kind == "track":
		return ASPHALT.track
	return ASPHALT.minor

func _add_road(road: Dictionary) -> void:
	var corners: PackedVector2Array = road.points
	# Short pieces so the carriageway follows the terrain between OSM nodes.
	var points := densify(corners, DRAPE_STEP)
	var half := RoadStyle.width(road) * 0.5
	var y := RoadStyle.surface_height(road.kind)
	var color := road_style_color(road.kind)
	var unpaved: bool = RoadStyle.is_path(road.kind) or road.kind == "track"
	var kind := KIND_DIRT if unpaved else (KIND_MAJOR if RoadStyle.is_major(road.kind) else KIND_MINOR)
	var info := Vector2(kind, 0.0)
	if road.has("way_id"):
		rendered_way_ids[road.way_id] = true
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		if a.distance_to(b) < 0.01:
			continue
		var across := (b - a).normalized().orthogonal()
		var side := across * half
		var surface := _surface_for(a.lerp(b, 0.5))
		surface.quad(_v(a + side, y), _v(b + side, y), _v(b - side, y), _v(a - side, y),
			Vector3.UP, color, Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(-1.0, 0.0), info, true)
		if not unpaved:
			for edge in [1.0, -1.0]:
				var inner: Vector2 = across * edge * half
				var outer: Vector2 = across * edge * (half + SHOULDER_WIDTH)
				surface.quad(_v(a + inner, SHOULDER_HEIGHT), _v(b + inner, SHOULDER_HEIGHT), _v(b + outer, SHOULDER_HEIGHT),
					_v(a + outer, SHOULDER_HEIGHT), Vector3.UP, color, Vector2(0.0, 0.0), Vector2(0.0, 0.0),
					Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(KIND_SHOULDER, 0.0), false)
	for point in corners:
		_add_disc(_surface_for(point), point, half, y, color, info)
	if ENABLE_INFERRED_DRAINS and _has_residential_drain(road):
		_add_side_drains(points, half)
	if unpaved:
		return
	var two_way_centre: bool = int(road.oneway) == 0 and half * 2.0 >= 5.5
	var lane_divider: bool = int(road.oneway) != 0 and (int(road.lanes) >= 2 or RoadStyle.is_major(road.kind))
	if two_way_centre or lane_divider:
		_add_dashes(points, 0.0, y + 0.012)
	if RoadStyle.is_major(road.kind):
		for edge in [-1.0, 1.0]:
			_add_line(points, edge * (half - 0.35), y + 0.012)

## TopoExport and OSM commonly describe the same centreline.  Keep the OSM
## version when a supplemental line follows it, while retaining genuinely
## missing service lanes and footways from the export.
func _matches_existing_road(candidate: Dictionary, existing: Array[Dictionary], grid: RefCounted) -> bool:
	var candidate_points: PackedVector2Array = candidate.points
	if candidate_points.size() < 2:
		return true
	var samples: Array[Vector2] = [candidate_points[0], candidate_points[candidate_points.size() - 1]]
	for index in range(1, candidate_points.size() - 1, 2):
		samples.append(candidate_points[index])
	# Only a road passing within 7 m of the first sample can match, so test just those.
	var tried: Dictionary = {}
	for segment in grid.near(samples[0], 7.0):
		var owner: int = grid.owners[segment]
		if tried.has(owner):
			continue
		tried[owner] = true
		var road_points: PackedVector2Array = existing[owner].points
		var all_close := true
		for sample in samples:
			var closest_distance := INF
			for index in range(1, road_points.size()):
				closest_distance = minf(closest_distance,
					sample.distance_to(Geometry2D.get_closest_point_to_segment(sample, road_points[index - 1], road_points[index])))
			if closest_distance > 7.0:
				all_close = false
				break
		if all_close:
			return true
	return false

func _add_disc(surface: MeshSurface, center: Vector2, radius: float, y: float, color: Color, info := Vector2.ZERO) -> void:
	for step in JOINT_SEGMENTS:
		var a := center + Vector2.RIGHT.rotated(TAU * step / JOINT_SEGMENTS) * radius
		var b := center + Vector2.RIGHT.rotated(TAU * (step + 1) / JOINT_SEGMENTS) * radius
		surface.triangle(_v(center, y), _v(a, y), _v(b, y), Vector3.UP, color,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, info, true)

## Open U-shaped drains along both sides of an ordinary neighbourhood road. They
## stop short of road joins so junctions stay open for pedestrians and vehicles.
func _add_side_drains(points: PackedVector2Array, road_half_width: float) -> void:
	for index in range(1, points.size()):
		var start := points[index - 1]
		var end := points[index]
		var length := start.distance_to(end)
		if length <= DRAIN_END_CLEARANCE * 2.0 + 0.1:
			continue
		var direction := (end - start) / length
		start += direction * DRAIN_END_CLEARANCE
		end -= direction * DRAIN_END_CLEARANCE
		var across := direction.orthogonal()
		for sign in [-1.0, 1.0]:
			var outward: Vector2 = across * sign
			var inner_a: Vector2 = start + outward * (road_half_width + SHOULDER_WIDTH + DRAIN_OFFSET)
			var inner_b: Vector2 = end + outward * (road_half_width + SHOULDER_WIDTH + DRAIN_OFFSET)
			var outer_a: Vector2 = inner_a + outward * DRAIN_WIDTH
			var outer_b: Vector2 = inner_b + outward * DRAIN_WIDTH
			var surface := _solid_for(start.lerp(end, 0.5))
			# Channel floor and its two concrete walls. The upper rim is slightly
			# raised so the channel reads clearly without becoming a road obstacle.
			surface.quad(_v(inner_a, -DRAIN_DEPTH), _v(inner_b, -DRAIN_DEPTH), _v(outer_b, -DRAIN_DEPTH), _v(outer_a, -DRAIN_DEPTH),
				Vector3.UP, DRAIN_COLOR.darkened(0.16), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
			surface.quad(_v(inner_a, 0.04), _v(inner_b, 0.04), _v(inner_b, -DRAIN_DEPTH), _v(inner_a, -DRAIN_DEPTH),
				Vector3(-outward.x, 0.0, -outward.y), DRAIN_COLOR, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
			surface.quad(_v(outer_b, 0.04), _v(outer_a, 0.04), _v(outer_a, -DRAIN_DEPTH), _v(outer_b, -DRAIN_DEPTH),
				Vector3(outward.x, 0.0, outward.y), DRAIN_COLOR, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
			drain_segment_count += 1

func _has_residential_drain(road: Dictionary) -> bool:
	if not str(road.kind) in ["residential", "unclassified", "living_street", "service"]:
		return false
	for point: Vector2 in road.points:
		if point.distance_to(VIDYA_NAGAR_2_CENTER) <= VIDYA_NAGAR_2_RADIUS:
			return true
	return false

func _add_dashes(points: PackedVector2Array, offset: float, y: float) -> void:
	var cursor := 0.0
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var direction := (b - a) / length
		var side := direction.orthogonal()
		var travelled := 0.0
		while travelled < length:
			var period := fmod(cursor + travelled, DASH_LENGTH + DASH_GAP)
			if period < DASH_LENGTH:
				var dash := minf(DASH_LENGTH - period, length - travelled)
				var start := a + direction * travelled + side * offset
				_marking_quad(start, start + direction * dash, side, LINE_WIDTH, y)
				travelled += dash
			else:
				travelled += DASH_LENGTH + DASH_GAP - period
		cursor += length

func _add_line(points: PackedVector2Array, offset: float, y: float) -> void:
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		if a.distance_to(b) < 0.01:
			continue
		var side := (b - a).normalized().orthogonal()
		_marking_quad(a + side * offset, b + side * offset, side, LINE_WIDTH, y)

func _marking_quad(a: Vector2, b: Vector2, side: Vector2, width: float, y: float) -> void:
	var half := side * width * 0.5
	_marking_for(a.lerp(b, 0.5)).quad(_v(a + half, y), _v(b + half, y), _v(b - half, y), _v(a - half, y),
		Vector3.UP, MARKING_WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

## Zebra stripes across the nearest mapped road at an OSM crossing node.
func _add_zebra(point: Vector2, data: MapData) -> void:
	var best_distance := 8.0
	var best_road: Dictionary = {}
	var best_direction := Vector2.ZERO
	var best_point := point
	var grid: RefCounted = data.osm_road_grid()
	for segment in grid.near(point, best_distance):
		var road: Dictionary = data.roads[grid.owners[segment]]
		if RoadStyle.is_path(road.kind):
			continue
		var a: Vector2 = grid.starts[segment]
		var b: Vector2 = grid.ends[segment]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := closest.distance_to(point)
		if distance < best_distance and a.distance_to(b) > 0.01:
			best_distance = distance
			best_road = road
			best_point = closest
			best_direction = (b - a).normalized()
	if best_road.is_empty():
		return
	var half := RoadStyle.width(best_road) * 0.5
	var y := RoadStyle.surface_height(best_road.kind) + 0.012
	var across := best_direction.orthogonal()
	var stripe := -half + 0.45
	while stripe < half - 0.3:
		var center := best_point + across * stripe
		_marking_quad(center - best_direction * 1.5, center + best_direction * 1.5, across, 0.45, y)
		stripe += 0.9

func _add_wall(line: PackedVector2Array, thickness: float, height: float, color: Color) -> void:
	var points := densify(line, DRAPE_STEP)
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		if a.distance_to(b) < 0.01:
			continue
		var direction := (b - a).normalized()
		var side := direction.orthogonal() * thickness * 0.5
		var surface := _solid_for(a.lerp(b, 0.5))
		for facing in [-1.0, 1.0]:
			var offset: Vector2 = side * facing
			var normal := Vector3(offset.x, 0.0, offset.y).normalized()
			surface.quad(_v(a + offset, 0.0), _v(b + offset, 0.0), _v(b + offset, height), _v(a + offset, height),
				normal, color, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
		surface.quad(_v(a + side, height), _v(b + side, height), _v(b - side, height), _v(a - side, height),
			Vector3.UP, color.lightened(0.1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
		for end in [a, b]:
			var outward := (-direction if end == a else direction)
			surface.quad(_v(end + side, 0.0), _v(end - side, 0.0), _v(end - side, height), _v(end + side, height),
				Vector3(outward.x, 0.0, outward.y), color, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)

func _add_railway(line: PackedVector2Array) -> void:
	var points := densify(line, DRAPE_STEP)
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		if a.distance_to(b) < 0.01:
			continue
		var side := (b - a).normalized().orthogonal()
		var ballast := side * 1.6
		_surface_for(a.lerp(b, 0.5)).quad(_v(a + ballast, 0.08), _v(b + ballast, 0.08), _v(b - ballast, 0.08), _v(a - ballast, 0.08),
			Vector3.UP, Color("#6d655c"), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		for rail in [-0.72, 0.72]:
			var offset: Vector2 = side * rail
			_marking_for(a.lerp(b, 0.5)).quad(_v(a + offset + side * 0.04, 0.16), _v(b + offset + side * 0.04, 0.16),
				_v(b + offset - side * 0.04, 0.16), _v(a + offset - side * 0.04, 0.16),
				Vector3.UP, Color("#8d8f93"), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

func _add_area(area: Dictionary) -> void:
	var points: PackedVector2Array = area.points
	var triangles := Geometry2D.triangulate_polygon(points)
	var color: Color = AREA_COLORS.get(area.kind, AREA_COLORS.grass)
	var y: float = AREA_HEIGHTS.get(area.kind, -0.12)
	var info := Vector2(AREA_KINDS.get(area.kind, AREA_KINDS.grass), 0.0)
	for corner in range(0, triangles.size(), 3):
		_add_draped_triangle(points[triangles[corner]], points[triangles[corner + 1]], points[triangles[corner + 2]], y, color, info)

## Splits large area triangles until they are small enough to follow the terrain.
func _add_draped_triangle(a: Vector2, b: Vector2, c: Vector2, y: float, color: Color, info: Vector2) -> void:
	if maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) > DRAPE_STEP * 2.0:
		var ab := a.lerp(b, 0.5)
		var bc := b.lerp(c, 0.5)
		var ca := c.lerp(a, 0.5)
		for triangle in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			_add_draped_triangle(triangle[0], triangle[1], triangle[2], y, color, info)
		return
	_surface_for(a).triangle(_v(a, y), _v(b, y), _v(c, y), Vector3.UP, color,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, info, false)

## Inserts points so no segment is longer than max_step.
static func densify(points: PackedVector2Array, max_step: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in points.size():
		if index > 0:
			var a := points[index - 1]
			var b := points[index]
			var pieces := ceili(a.distance_to(b) / max_step)
			for piece in range(1, pieces):
				result.append(a.lerp(b, float(piece) / pieces))
		result.append(points[index])
	return result

func _commit() -> void:
	for cell in _surfaces:
		var surface: MeshSurface = _surfaces[cell]
		var chunk := Node3D.new()
		chunk.name = "RoadChunk_%d_%d" % [cell.x, cell.y]
		add_child(chunk)
		chunk.add_child(_mesh_instance(surface, _road_material, 0.0))
		if not surface.collision.is_empty():
			var body := StaticBody3D.new()
			body.collision_layer = 1 << (ROAD_LAYER - 1)
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(surface.collision)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			chunk.add_child(body)
	for cell in _markings:
		var markings := _mesh_instance(_markings[cell], _marking_material, MARKINGS_VIEW_DISTANCE)
		markings.name = "Markings_%d_%d" % [cell.x, cell.y]
		add_child(markings)
	for cell in _solids:
		var solid: MeshSurface = _solids[cell]
		var walls := _mesh_instance(solid, _surface_material, 0.0)
		walls.name = "Walls_%d_%d" % [cell.x, cell.y]
		add_child(walls)
		var body := StaticBody3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(solid.collision)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		walls.add_child(body)
	_surfaces.clear()
	_markings.clear()
	_solids.clear()

func _mesh_instance(surface: MeshSurface, material: Material, view_distance: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = surface.to_mesh()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = view_distance
	return instance

func _surface_for(point: Vector2) -> MeshSurface:
	return _bucket(_surfaces, point)

func _marking_for(point: Vector2) -> MeshSurface:
	return _bucket(_markings, point)

func _solid_for(point: Vector2) -> MeshSurface:
	return _bucket(_solids, point)

func _bucket(store: Dictionary, point: Vector2) -> MeshSurface:
	var cell := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))
	if not store.has(cell):
		store[cell] = MeshSurface.new()
	return store[cell]

static func _make_road_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/road.gdshader")
	material.set_shader_parameter("road_albedo", preload("res://assets/textures/ground/road_albedo.jpg"))
	material.set_shader_parameter("road_normal", preload("res://assets/textures/ground/road_normal.jpg"))
	material.set_shader_parameter("road_arm", preload("res://assets/textures/ground/road_arm.jpg"))
	material.set_shader_parameter("ground_albedo", preload("res://assets/textures/ground/ground_albedo.jpg"))
	material.set_shader_parameter("ground_normal", preload("res://assets/textures/ground/ground_normal.jpg"))
	material.set_shader_parameter("ground_arm", preload("res://assets/textures/ground/ground_arm.jpg"))
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.normalize = true
	var generator := FastNoiseLite.new()
	generator.frequency = 0.02
	noise.noise = generator
	material.set_shader_parameter("noise", noise)
	return material

static func _vertex_color_material(roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	return material

## Vertex at a height above the terrain surface.
func _v(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y + (terrain.height_at(point) if terrain else 0.0), point.y)
