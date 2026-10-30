class_name MapCanvas
extends Control

## Draws the playable world top-down from the same map-plane data the 3D world
## and router use. Roads are bucketed into a coarse grid once, so each redraw
## only touches the cells inside the view; all buildings share one cached mesh.

const CELL_SIZE := 250.0
## Below this zoom, landmark names overlap too much to read, so only dots are drawn.
const LABEL_MIN_ZOOM := 0.4
const BACKGROUND := Color("#1d2b26")
const BUILDING_COLOR := Color("#3c4d47")
const ROUTE_COLOR := Color("#c05cff")
const DESTINATION_COLOR := Color("#ffd24a")
const PLAYER_COLOR := Color("#ffffff")
const VEHICLE_COLOR := Color("#5fb8ff")
const LANDMARK_COLORS := {
	"Road": Color("#f2c14e"), "Bus station": Color("#4fd18b"), "Hospital": Color("#ff6b6b"),
	"Police": Color("#6aa8ff"), "Temple": Color("#ff9f43"), "College": Color("#c7a6ff"),
	"School": Color("#c7a6ff"), "Theatre": Color("#ff7ad9"), "Fuel": Color("#9be15d"),
	"Worship": Color("#ff9f43"), "Bank": Color("#6ad0ff"), "Post office": Color("#ff5c5c"),
	"Monument": Color("#e0c068"), "Health centre": Color("#ff8f8f"), "Stadium": Color("#7fe07f"),
	"Area": Color("#d0d0d0"), "Shop": Color("#ffd166"),
}
## Drawing order matters: smaller roads first so major roads sit on top.
const ROAD_STYLES := ["path", "minor", "major"]
const ROAD_COLORS := {"path": Color("#7d8a83"), "minor": Color("#c9cfc8"), "major": Color("#f2c14e")}
const ROAD_WIDTHS_PX := {"path": 1.0, "minor": 2.2, "major": 3.6}
const MAJOR_KINDS := ["motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
	"secondary", "secondary_link"]
const PATH_KINDS := ["footway", "path", "pedestrian", "steps", "cycleway", "bridleway", "track"]

static var _shared_cache: Dictionary = {}

var view_center := Vector2.ZERO
var pixels_per_meter := 1.0
## Rotation applied to the map plane; 0 means north-up.
var view_rotation := 0.0
var road_width_scale := 1.0
var show_labels := false
var clamp_destination_to_edge := false
var player_position := Vector2.ZERO
var player_heading := Vector2(0.0, -1.0)
## Each entry: {position: Vector2, heading: Vector2}
var vehicles: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var route := PackedVector2Array()
var destination: Variant = null
var _cache: Dictionary

func setup(data: MapData, building_footprints: Array[PackedVector2Array], landmark_list: Array[Dictionary]) -> void:
	landmarks = landmark_list
	var key := data.get_instance_id()
	if not _shared_cache.has(key):
		_shared_cache[key] = _build_cache(data, building_footprints)
	_cache = _shared_cache[key]
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

## Forward direction of a body on the map plane. Person and car both face local +Z.
static func heading_of(body: Node3D) -> Vector2:
	var forward: Vector3 = body.forward_direction() if body.has_method("forward_direction") else body.global_transform.basis.z
	var heading := Vector2(forward.x, forward.z)
	return heading.normalized() if heading.length_squared() > 0.0001 else Vector2(0.0, -1.0)

func map_transform() -> Transform2D:
	return Transform2D(view_rotation, Vector2(pixels_per_meter, pixels_per_meter), 0.0, size * 0.5) \
		* Transform2D(0.0, -view_center)

func screen_to_map(screen_point: Vector2) -> Vector2:
	return map_transform().affine_inverse() * screen_point

func map_to_screen(map_point: Vector2) -> Vector2:
	return map_transform() * map_point

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _cache.is_empty():
		return
	var transform := map_transform()
	draw_set_transform_matrix(transform)
	draw_mesh(_cache.buildings, null, Transform2D.IDENTITY, BUILDING_COLOR)
	var cells := _visible_cells(transform)
	for style in ROAD_STYLES:
		var width: float = ROAD_WIDTHS_PX[style] * road_width_scale / pixels_per_meter
		for cell in cells:
			var segments: PackedVector2Array = _cache.roads.get(cell, {}).get(style, PackedVector2Array())
			if not segments.is_empty():
				draw_multiline(segments, ROAD_COLORS[style], width)
	if route.size() >= 2:
		draw_polyline(route, ROUTE_COLOR, 4.5 * road_width_scale / pixels_per_meter)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_landmarks(transform)
	for vehicle in vehicles:
		_draw_vehicle(transform * vehicle.position, transform.basis_xform(vehicle.heading))
	if destination != null:
		_draw_destination(transform * (destination as Vector2))
	_draw_player(transform * player_position, transform.basis_xform(player_heading))

func _visible_cells(transform: Transform2D) -> Array[Vector2i]:
	var inverse := transform.affine_inverse()
	var corners := [inverse * Vector2.ZERO, inverse * Vector2(size.x, 0.0), inverse * size, inverse * Vector2(0.0, size.y)]
	var low: Vector2 = corners[0]
	var high: Vector2 = corners[0]
	for corner in corners:
		low = low.min(corner)
		high = high.max(corner)
	var result: Array[Vector2i] = []
	# Segments are bucketed by midpoint, so pad by one cell to catch segments that cross into view.
	for x in range(floori(low.x / CELL_SIZE) - 1, floori(high.x / CELL_SIZE) + 2):
		for y in range(floori(low.y / CELL_SIZE) - 1, floori(high.y / CELL_SIZE) + 2):
			var cell := Vector2i(x, y)
			if _cache.roads.has(cell):
				result.append(cell)
	return result

func _draw_landmarks(transform: Transform2D) -> void:
	var font := ThemeDB.fallback_font
	var bounds := Rect2(Vector2.ZERO, size)
	for landmark in landmarks:
		var screen: Vector2 = transform * (landmark.position as Vector2)
		if not bounds.has_point(screen):
			continue
		var color: Color = LANDMARK_COLORS.get(landmark.category, Color.WHITE)
		draw_circle(screen, 4.0, Color(0, 0, 0, 0.6))
		draw_circle(screen, 3.0, color)
		if show_labels and pixels_per_meter >= LABEL_MIN_ZOOM:
			draw_string_outline(font, screen + Vector2(6.0, 4.0), landmark.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
			draw_string(font, screen + Vector2(6.0, 4.0), landmark.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _draw_vehicle(screen: Vector2, direction: Vector2) -> void:
	var forward := direction.normalized() if direction.length_squared() > 0.0 else Vector2.UP
	var side := Vector2(-forward.y, forward.x)
	var points := PackedVector2Array([
		screen + forward * 6.0 + side * 3.5, screen + forward * 6.0 - side * 3.5,
		screen - forward * 6.0 - side * 3.5, screen - forward * 6.0 + side * 3.5,
	])
	draw_colored_polygon(points, VEHICLE_COLOR)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.7), 1.0)

func _draw_destination(screen: Vector2) -> void:
	var inner := Rect2(Vector2(10.0, 10.0), size - Vector2(20.0, 20.0))
	if clamp_destination_to_edge and not inner.has_point(screen):
		var center := size * 0.5
		var offset := screen - center
		var scale := minf(absf(inner.size.x * 0.5 / maxf(absf(offset.x), 0.001)), absf(inner.size.y * 0.5 / maxf(absf(offset.y), 0.001)))
		screen = center + offset * scale
	draw_circle(screen, 8.0, Color(0, 0, 0, 0.7))
	draw_circle(screen, 6.0, DESTINATION_COLOR)
	draw_circle(screen, 2.5, Color(0, 0, 0, 0.8))

func _draw_player(screen: Vector2, direction: Vector2) -> void:
	var forward := direction.normalized() if direction.length_squared() > 0.0 else Vector2.UP
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array([
		screen + forward * 10.0, screen - forward * 7.0 + side * 7.0,
		screen - forward * 3.0, screen - forward * 7.0 - side * 7.0,
	])
	draw_colored_polygon(arrow, PLAYER_COLOR)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.85), 1.5)

static func _build_cache(data: MapData, building_footprints: Array[PackedVector2Array]) -> Dictionary:
	var vertices := PackedVector2Array()
	for footprint in building_footprints:
		var triangles := Geometry2D.triangulate_polygon(footprint)
		for index in triangles:
			vertices.append(footprint[index])
	var buildings := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		buildings.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var roads: Dictionary = {}
	for road in data.roads:
		var style := "minor"
		if road.kind in MAJOR_KINDS:
			style = "major"
		elif road.kind in PATH_KINDS:
			style = "path"
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			var a := points[index - 1]
			var b := points[index]
			var cell := Vector2i(floori((a.x + b.x) * 0.5 / CELL_SIZE), floori((a.y + b.y) * 0.5 / CELL_SIZE))
			if not roads.has(cell):
				roads[cell] = {}
			if not roads[cell].has(style):
				roads[cell][style] = PackedVector2Array()
			roads[cell][style].append(a)
			roads[cell][style].append(b)
	return {"buildings": buildings, "roads": roads}
