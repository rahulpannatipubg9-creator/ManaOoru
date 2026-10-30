class_name StreetLifeBuilder
extends Node3D

## The everyday street furniture of Godavarikhani:
## - the real Saturday market (OpenStreetMap): rows of raised concrete slabs where
##   vendors heap vegetables and fruit, under tarps and umbrellas;
## - shelters at the real bus stops (Overture Maps) with the stop's name;
## - arched gates at the mapped colony entrances (Surya Nagar, Vidya Nagar 2…);
## - roadside stalls along the busy main roads: coconut heaps, fruit carts, chappal
##   (slipper) stalls and fast-food carts. These are ambience: real stalls move daily
##   and none are mapped, so they are placed where shops line the main roads;
## - street-light poles along the main roads (none are mapped either).
## Everything is merged into one vertex-coloured mesh per chunk, with thin static
## colliders (PhysicsServer shapes, no nodes) so cars and people cannot pass through.

const DATA_PATH := "res://data/places/godavarikhani_street_life.json"
const UTILITY_POLE_SCENE := preload("res://assets/models/utility_pole/gdk_utility_pole.glb")
const PANIPURI_CART_SCENE := preload("res://assets/models/panipuri_cart/gdk_panipuri_cart_mobile.glb")
const BHELPURI_STALL_SCENE := preload("res://assets/models/bhelpuri_stall/gdk_bhelpuri_stall.glb")
const CHUNK_SIZE := 250.0
const VIEW_DISTANCE := 450.0
## Busy-street stalls only within this distance of Chowrastha, where the shops are.
const STALL_RADIUS := 1800.0
const STALL_SPACING := Vector2(28.0, 70.0)
## Stalls and poles stand beyond the strip where cars park (road edge + 0.45..2.35 m).
const STALL_OFFSET := 3.4
const POLE_OFFSET := 2.7
const POLE_SPACING := 32.0
const UTILITY_POLE_SPACING := 96.0
const UTILITY_POLE_OFFSET := 3.1
const WIRE_HEIGHT := 6.45
const WIRE_SAG := 0.55
const WIRE_THICKNESS := 0.028
const POLE_HEIGHT := 8.5
const POLE_COLOR := Color("#72787b")
const LAMP_HOUSING_COLOR := Color("#34383a")
const LAMP_LENS_COLOR := Color("#fff0bd")
const MARKET_SLAB := Vector3(3.0, 0.55, 1.4)
const MARKET_ROWS := 4
const MARKET_SLABS_PER_ROW := 6
const MARKET_AISLE := 2.6
const PRODUCE := [Color("#c0392b"), Color("#e67e22"), Color("#7d3c98"), Color("#2e7d32"), Color("#8d6e63"),
	Color("#f4d03f"), Color("#d35400"), Color("#558b2f"), Color("#ede7d9")]
const TARPS := [Color("#1f5fa8"), Color("#2e7d32"), Color("#c0392b"), Color("#f1c40f"), Color("#ef6c00")]

var stall_count := 0
var pole_count := 0
var lamp_positions := PackedVector3Array()
var road_obstacle_positions := PackedVector2Array()
var utility_pole_count := 0
var bus_stop_count := 0
var market_slab_count := 0
var gate_count := 0
var gate_placements: Array[Dictionary] = []
var _world: Node
var _surfaces: Dictionary = {}
var _street_lamp_surfaces: Dictionary = {}
var _collecting_street_lamp := false
var _body: RID
var _keep_clear: Array[Vector3] = []

func build(world: Node, data: MapData) -> void:
	name = "StreetLife"
	_world = world
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if parsed is Dictionary:
		for market: Dictionary in parsed.markets:
			_add_market(_map_point(market), str(market.name))
		for stop: Dictionary in parsed.bus_stops:
			_add_bus_stop(_map_point(stop), str(stop.name))
		for gate: Dictionary in parsed.entrances:
			_add_gate(_map_point(gate), str(gate.name))
	for road in data.roads:
		if RoadStyle.is_major(road.kind) or road.kind == "tertiary":
			_add_road_furniture(road)
	_commit()

## Spots trees must avoid, as (x, z, radius).
func occupied() -> Array[Vector3]:
	return _keep_clear

func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)

static func _map_point(entry: Dictionary) -> Vector2:
	return GeoProjection.lon_lat_to_map(float(entry.lon), float(entry.lat))

# --- Market ---------------------------------------------------------------------

## Rows of raised slabs on the open ground nearest the mapped market point.
func _add_market(point: Vector2, market_name: String) -> void:
	var road := _nearest_road(point, 80.0)
	var along := Vector2.RIGHT
	if not road.is_empty():
		along = road.direction
	var across := along.orthogonal()
	var center := _clear_spot(point, 18.0)
	if center == Vector2.INF:
		return
	var rng := _rng(center)
	var market_yaw := atan2(along.x, along.y)
	for row in MARKET_ROWS:
		for slot in MARKET_SLABS_PER_ROW:
			var offset: Vector2 = along * ((slot - (MARKET_SLABS_PER_ROW - 1) * 0.5) * (MARKET_SLAB.x + 0.4)) \
				+ across * ((row - (MARKET_ROWS - 1) * 0.5) * (MARKET_SLAB.z + MARKET_AISLE))
			var spot := center + offset
			if not _world.buildings.is_clear(spot, 1.6):
				continue
			var base := _ground(spot)
			_box(spot, base, MARKET_SLAB, market_yaw, Color("#9e9a90"))
			_collide_box(spot, base, MARKET_SLAB, market_yaw)
			var top := base + MARKET_SLAB.y
			# Two or three heaps of produce per slab.
			for heap in rng.randi_range(2, 3):
				var heap_center := spot + along * rng.randf_range(-1.0, 1.0)
				_heap(heap_center, top, 0.45, PRODUCE[rng.randi_range(0, PRODUCE.size() - 1)], rng)
			if rng.randf() < 0.5:
				_tarp(spot, top + 1.6, Vector2(MARKET_SLAB.x + 0.6, MARKET_SLAB.z + 1.0), market_yaw, TARPS[rng.randi_range(0, TARPS.size() - 1)])
			market_slab_count += 1
	_label_board(center + across * ((MARKET_ROWS * 0.5) * (MARKET_SLAB.z + MARKET_AISLE) + 1.5), across, market_name.to_upper(),
		Color("#1f6b3a"), Color.WHITE)
	# User-supplied snack stalls belong at the real mapped Saturday Market, not
	# as arbitrary clutter elsewhere in the town.
	_add_vendor_model(PANIPURI_CART_SCENE, center - along * 9.5 - across * 5.0, market_yaw)
	_add_vendor_model(BHELPURI_STALL_SCENE, center + along * 9.0 + across * 5.0, market_yaw + PI)
	_keep_clear.append(Vector3(center.x, center.y, 16.0))

# --- Bus stops --------------------------------------------------------------------

func _add_bus_stop(point: Vector2, stop_name: String) -> void:
	var road := _nearest_road(point, 40.0)
	if road.is_empty() or not GeoProjection.is_playable(point):
		return
	var toward: Vector2 = point - road.point
	var normal: Vector2 = road.normal if toward.dot(road.normal) >= 0.0 else -road.normal
	var spot: Vector2 = road.point + normal * (road.half_width + 3.2)
	if not _world.buildings.is_clear(spot, 2.0):
		return
	var along: Vector2 = road.direction
	var yaw := atan2(along.x, along.y)
	var base := _ground(spot)
	_box(spot, base, Vector3(5.0, 0.25, 2.4), yaw, Color("#a8a39a"))
	var back := spot + normal * 0.9
	for side: float in [-2.2, 2.2]:
		_cylinder(spot + along * side - normal * 0.9, base, 0.06, 2.7, Color("#4a4f55"))
		_cylinder(back + along * side, base, 0.06, 2.7, Color("#4a4f55"))
		_collide_post(back + along * side, base, 2.7)
	_box(spot, base + 2.7, Vector3(5.4, 0.14, 2.8), yaw, Color("#1f5fa8"))
	_box(back, base + 0.25, Vector3(4.6, 1.8, 0.06), yaw, Color("#c9d1d6"))
	_box(back - normal * 0.35, base + 0.25 + 0.42, Vector3(4.2, 0.08, 0.45), yaw, Color("#8d6e63"))
	_label_board(spot - normal * 1.0 + Vector2(0, 0), -normal, stop_name.to_upper(), Color("#1f5fa8"), Color.WHITE, base + 3.05)
	_keep_clear.append(Vector3(spot.x, spot.y, 5.0))
	bus_stop_count += 1

# --- Colony gates -----------------------------------------------------------------

## Entrance board placed down the mapped colony lane, matching the dedicated
## Vidya Nagar 1 sign. Never put an arch at the junction itself when a safe
## frontage is available farther inside the colony.
func _add_gate(point: Vector2, colony: String) -> void:
	var road := _entrance_road(point)
	if road.is_empty():
		_add_roadside_entrance_sign(point, colony)
		return
	var center := Vector2.ZERO
	var selected_road: Dictionary = {}
	var safe := false
	var inward: Vector2 = road.inward_direction
	for distance: float in [7.0, 11.0, 15.0, 19.0, 23.0, 27.0, 31.0, 35.0, 39.0]:
		var candidate: Vector2 = road.point + inward * distance
		var local_road := _entrance_road(candidate)
		if local_road.is_empty() or local_road.way_id != road.way_id:
			continue
		if candidate.distance_to(local_road.point) > 3.0:
			continue
		candidate = local_road.point
		var half_width: float = local_road.half_width + 0.55
		var clear := true
		for sample_index in 13:
			var at: Vector2 = candidate + local_road.normal * lerpf(-half_width, half_width, float(sample_index) / 12.0)
			if not _world.buildings.is_clear(at, 0.3):
				clear = false
				break
		if clear:
			center = candidate
			selected_road = local_road
			safe = true
			break
	if not safe:
		_add_roadside_entrance_sign(point, colony)
		return
	road = selected_road
	var across: Vector2 = road.normal
	var half: float = road.half_width + 0.55
	var base := _ground(center)
	var yaw := atan2(road.direction.x, road.direction.y)
	var steel := Color("#49423b")
	var faded_panel := Color("#a69b87")
	for side: float in [-1.0, 1.0]:
		var foot: Vector2 = center + across * side * half
		var footing := _ground(foot)
		_box(foot, footing, Vector3(0.14, 5.95, 0.14), yaw, steel)
		_collide_box(foot, footing, Vector3(0.14, 5.95, 0.14), yaw)
		_box(foot, footing, Vector3(0.38, 0.38, 0.38), yaw, Color("#898176"))
	# The readable board sits on the lintel; its slim supports remain beyond
	# the lane edge, matching the established Vidya Nagar 1 entrance treatment.
	var board_width := maxf(2.0, half * 2.0 - 0.65)
	_box(center, base + 5.45, Vector3(board_width, 0.65, 0.07), yaw, faded_panel)
	for frame_y: float in [5.12, 5.98]:
		_box(center, base + frame_y, Vector3(board_width + 0.14, 0.045, 0.08), yaw, steel)
	_label(center - road.direction * 0.05, yaw + PI, colony.to_upper(), board_width * 0.92, base + 5.67, Color("#38342d"), 54)
	_label(center + road.direction * 0.05, yaw, colony.to_upper(), board_width * 0.92, base + 5.67, Color("#38342d"), 54)
	_keep_clear.append(Vector3(center.x, center.y, half + 2.0))
	gate_placements.append({"name": colony, "source_position": point, "center": center,
		"offset_from_entrance": center.distance_to(point), "road_type": road.kind,
		"road_way_id": road.way_id, "road_half_width": road.half_width,
		"post_clearance": half - road.half_width})
	gate_count += 1

## Returns the closest actual access street around a mapped colony entrance.
## Major roads are intentionally excluded: they receive a roadside sign if no
## residential/service branch is mapped close enough.
func _entrance_road(point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 45.0
	for road: Dictionary in _world.map_data.roads:
		var kind := str(road.kind)
		if kind not in ["residential", "living_street", "unclassified", "service", "road"]:
			continue
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			var a := points[index - 1]
			var b := points[index]
			if a.distance_squared_to(b) < 0.01:
				continue
			var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
			var distance := closest.distance_to(point)
			if distance < best_distance:
				var direction := (b - a).normalized()
				# Entrance nodes usually sit near a way endpoint. Choose the
				# segment direction leading away from the entrance, not the main road.
				if point.distance_squared_to(a) < point.distance_squared_to(b):
					direction = (b - closest).normalized()
				else:
					direction = (a - closest).normalized()
				best_distance = distance
				best = {"point": closest, "direction": direction, "inward_direction": direction,
					"normal": direction.orthogonal(), "half_width": RoadStyle.width(road) * 0.5,
					"kind": kind, "way_id": road.way_id}
	return best

## Fallback for an entrance whose local branch has not been captured in OSM:
## make a normal roadside entry board instead of obstructing the through-road.
func _add_roadside_entrance_sign(point: Vector2, colony: String) -> void:
	var road := _nearest_road(point, 55.0)
	if road.is_empty():
		return
	var side := 1.0 if (point - road.point).dot(road.normal) >= 0.0 else -1.0
	var spot: Vector2 = road.point + road.normal * side * (road.half_width + 2.0)
	_label_board(spot, -road.normal * side, colony.to_upper() + "\nENTRANCE", Color("#c0392b"), Color("#fff3c4"))
	_keep_clear.append(Vector3(spot.x, spot.y, 2.0))
	gate_count += 1

# --- Main-road stalls and street lights --------------------------------------------

func _add_road_furniture(road: Dictionary) -> void:
	var points: PackedVector2Array = road.points
	var half := RoadStyle.width(road) * 0.5
	var rng := _rng(points[0])
	var next_stall := rng.randf_range(STALL_SPACING.x, STALL_SPACING.y)
	var next_pole := POLE_SPACING * 0.5
	var next_utility := UTILITY_POLE_SPACING * 0.5
	var previous_utility := Vector2.INF
	var walked := 0.0
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var direction := (b - a) / length
		var normal := direction.orthogonal()
		while next_pole <= walked + length:
			var at := a + direction * (next_pole - walked)
			var side := 1.0 if int(next_pole / POLE_SPACING) % 2 == 0 else -1.0
			_add_pole(at + normal * side * (half + POLE_OFFSET), -normal * side)
			next_pole += POLE_SPACING
		while next_utility <= walked + length:
			var at := a + direction * (next_utility - walked)
			var utility_spot := at + normal * (half + UTILITY_POLE_OFFSET)
			if _add_utility_pole(utility_spot, direction):
				if previous_utility != Vector2.INF:
					_add_wire_span(previous_utility, utility_spot, direction)
				previous_utility = utility_spot
			next_utility += UTILITY_POLE_SPACING
		while next_stall <= walked + length:
			var at := a + direction * (next_stall - walked)
			if at.length() < STALL_RADIUS:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				_add_stall(at + normal * side * (half + STALL_OFFSET), -normal * side, direction, rng)
			next_stall += rng.randf_range(STALL_SPACING.x, STALL_SPACING.y)
		walked += length

func _add_pole(spot: Vector2, toward_road: Vector2) -> void:
	if not GeoProjection.is_playable(spot) or not _world.buildings.is_clear(spot, 0.6) or _on_other_road(spot, 0.5):
		return
	var base := _ground(spot)
	# Municipal main-road lamp: a concrete footing, galvanised pole, short
	# roadside arm and enclosed warm-white LED head. Keep this geometry out of
	# the shadow-casting street-furniture mesh: thin poles shimmer in the sun's
	# shadow map as the camera moves quickly in a vehicle.
	_collecting_street_lamp = true
	_cylinder(spot, base, 0.28, 0.16, Color("#a9aaa5"))
	_cylinder(spot, base + 0.16, 0.105, POLE_HEIGHT - 0.16, POLE_COLOR)
	var arm_end := spot + toward_road * 1.6
	var yaw := atan2(toward_road.x, toward_road.y)
	_box((spot + arm_end) * 0.5, base + POLE_HEIGHT - 0.1, Vector3(0.08, 0.08, 1.7), yaw, POLE_COLOR)
	_box(arm_end, base + POLE_HEIGHT - 0.30, Vector3(0.38, 0.16, 0.70), yaw, LAMP_HOUSING_COLOR)
	_box(arm_end + toward_road * 0.03, base + POLE_HEIGHT - 0.43, Vector3(0.30, 0.025, 0.48), yaw, LAMP_LENS_COLOR)
	_collecting_street_lamp = false
	_collide_post(spot, base, POLE_HEIGHT)
	_keep_clear.append(Vector3(spot.x, spot.y, 1.5))
	road_obstacle_positions.append(spot)
	lamp_positions.append(Vector3(arm_end.x, base + POLE_HEIGHT - 0.45, arm_end.y))
	pole_count += 1

## User-supplied GDK-style electrical pole, converted from the downloaded model.
## Wires are generated from the real road run so they stay aligned with streets.
func _add_utility_pole(spot: Vector2, direction: Vector2) -> bool:
	if not GeoProjection.is_playable(spot) or not _world.buildings.is_clear(spot, 1.2) or _on_other_road(spot, 0.8):
		return false
	var pole := UTILITY_POLE_SCENE.instantiate() as Node3D
	pole.name = "GdkUtilityPole"
	pole.position = Vector3(spot.x, _ground(spot), spot.y)
	pole.rotation.y = atan2(direction.x, direction.y)
	add_child(pole)
	_keep_clear.append(Vector3(spot.x, spot.y, 1.8))
	road_obstacle_positions.append(spot)
	utility_pole_count += 1
	return true

func _add_vendor_model(scene: PackedScene, spot: Vector2, yaw: float) -> void:
	if not _world.buildings.is_clear(spot, 2.5):
		return
	var vendor := scene.instantiate() as Node3D
	vendor.name = "SaturdayMarketVendor"
	vendor.position = Vector3(spot.x, _ground(spot), spot.y)
	vendor.rotation.y = yaw
	# User-provided USDZ/cart sources use centimetres; Godot's world uses metres.
	vendor.scale = Vector3.ONE * 0.01
	add_child(vendor)

## Three sagging overhead conductors between consecutive utility poles. This is
## visual only: it follows road geometry but has no collision.
func _add_wire_span(a: Vector2, b: Vector2, direction: Vector2) -> void:
	var across := direction.orthogonal()
	for offset in [-0.22, 0.0, 0.22]:
		var previous: Vector2 = a + across * offset
		var pieces := maxi(2, ceili(a.distance_to(b) / 12.0))
		for step in range(1, pieces + 1):
			var t := float(step) / pieces
			var current: Vector2 = a.lerp(b, t) + across * offset
			var sag := sin(PI * t) * WIRE_SAG
			_append_wire_segment(previous, current, WIRE_HEIGHT - sag)
			previous = current

func _append_wire_segment(a: Vector2, b: Vector2, height: float) -> void:
	var direction := (b - a).normalized()
	var side := direction.orthogonal() * WIRE_THICKNESS
	var surface := _surface_for(a.lerp(b, 0.5))
	surface.quad(Vector3(a.x + side.x, _ground(a) + height, a.y + side.y),
		Vector3(b.x + side.x, _ground(b) + height, b.y + side.y),
		Vector3(b.x - side.x, _ground(b) + height, b.y - side.y),
		Vector3(a.x - side.x, _ground(a) + height, a.y - side.y),
		Vector3.UP, Color("#242424"), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

## Busy spots only: a stall needs shops within reach and open ground under it.
func _add_stall(spot: Vector2, toward_road: Vector2, along: Vector2, rng: RandomNumberGenerator) -> void:
	if not GeoProjection.is_playable(spot) or not _world.buildings.is_clear(spot, 1.8) or _on_other_road(spot, 1.5):
		return
	if _world.buildings.is_clear(spot, 22.0):
		return
	var base := _ground(spot)
	var yaw := atan2(along.x, along.y)
	var kind := rng.randf()
	if kind < 0.3:
		_coconut_stall(spot, base, yaw, toward_road, rng)
	elif kind < 0.6:
		_fruit_cart(spot, base, yaw, rng)
	elif kind < 0.85:
		_fast_food_cart(spot, base, yaw, rng)
	else:
		_chappal_stall(spot, base, yaw, rng)
	_collide_box(spot, base, Vector3(2.0, 1.2, 1.2), yaw)
	_keep_clear.append(Vector3(spot.x, spot.y, 3.0))
	stall_count += 1

func _coconut_stall(spot: Vector2, base: float, yaw: float, toward_road: Vector2, rng: RandomNumberGenerator) -> void:
	# A heap of tender green coconuts on a jute mat, a chopping stump and a big umbrella.
	_box(spot, base, Vector3(2.2, 0.03, 1.6), yaw, Color("#a1887f"))
	for coconut in rng.randi_range(16, 26):
		var offset := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.5)).rotated(-yaw)
		var height := rng.randf_range(0.0, 0.35) * (1.0 - offset.length())
		_sphere(Vector3(spot.x + offset.x, base + 0.14 + maxf(height, 0.0), spot.y + offset.y), 0.14, Color("#4c8a2e").lerp(Color("#7cb342"), rng.randf()))
	_cylinder(spot + toward_road * 0.9, base, 0.18, 0.45, Color("#6d4c41"))
	_umbrella(spot - toward_road * 0.3, base, 2.4, TARPS[rng.randi_range(0, TARPS.size() - 1)])

func _fruit_cart(spot: Vector2, base: float, yaw: float, rng: RandomNumberGenerator) -> void:
	# Wooden push cart on two wheels, fruit stacked in pyramids, umbrella over it.
	var along := Vector2(sin(yaw), cos(yaw))
	_box(spot, base + 0.75, Vector3(0.95, 0.08, 1.9), yaw, Color("#8d6e63"))
	for wheel: float in [-0.55, 0.55]:
		var at := spot + along.orthogonal() * wheel
		_cylinder(at, base, 0.32, 0.12, Color("#3e2723"))
	for leg: Vector2 in [Vector2(0.4, 0.85), Vector2(-0.4, 0.85)]:
		_cylinder(spot + along * leg.y + along.orthogonal() * leg.x, base, 0.03, 0.75, Color("#5d4037"))
	var fruit: Color = PRODUCE[rng.randi_range(0, PRODUCE.size() - 1)]
	for row in 3:
		for item in 10 - row * 3:
			var offset := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.8, 0.8))
			var world_offset := along.orthogonal() * offset.x + along * offset.y
			_sphere(Vector3(spot.x + world_offset.x, base + 0.88 + row * 0.11, spot.y + world_offset.y), 0.07, fruit.lerp(Color.WHITE, rng.randf() * 0.15))
	_umbrella(spot, base, 2.5, TARPS[rng.randi_range(0, TARPS.size() - 1)])

func _fast_food_cart(spot: Vector2, base: float, yaw: float, rng: RandomNumberGenerator) -> void:
	# Steel cart with a glass display, tin canopy on posts and a board across the top.
	_box(spot, base, Vector3(1.9, 0.95, 0.9), yaw, Color("#b0bec5"))
	_box(spot, base + 0.95, Vector3(1.8, 0.5, 0.06), yaw, Color("#90caf9"))
	var along := Vector2(sin(yaw), cos(yaw))
	for corner: Vector2 in [Vector2(-0.85, -0.4), Vector2(0.85, -0.4), Vector2(-0.85, 0.4), Vector2(0.85, 0.4)]:
		_cylinder(spot + along.orthogonal() * corner.x + along * corner.y, base + 0.95, 0.025, 1.3, Color("#78909c"))
	_box(spot, base + 2.25, Vector3(2.2, 0.05, 1.3), yaw, TARPS[rng.randi_range(0, TARPS.size() - 1)])
	_box(spot, base + 2.3, Vector3(2.0, 0.35, 0.04), yaw, Color("#c62828"))
	_label(spot + along * 0.03, yaw, "FAST FOOD", 2.0, base + 2.47, Color("#fff176"), 40)

func _chappal_stall(spot: Vector2, base: float, yaw: float, rng: RandomNumberGenerator) -> void:
	# Low tiered rack of slippers in pairs under a tarp on bamboo poles.
	for tier in 3:
		_box(spot, base + 0.2 + tier * 0.25, Vector3(2.0, 0.04, 0.45 - tier * 0.1), yaw, Color("#795548"))
		var along := Vector2(sin(yaw), cos(yaw)).orthogonal()
		for pair in 9:
			var at := spot + along * ((pair - 4) * 0.21)
			var color := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.35, 0.9))
			_box(at, base + 0.24 + tier * 0.25, Vector3(0.08, 0.04, 0.24), yaw, color)
	_tarp(spot, base + 2.0, Vector2(2.4, 1.6), yaw, TARPS[rng.randi_range(0, TARPS.size() - 1)])

# --- Geometry helpers -------------------------------------------------------------

func _umbrella(spot: Vector2, base: float, height: float, color: Color) -> void:
	_cylinder(spot, base, 0.03, height, Color("#d7ccc8"))
	var top := Vector3(spot.x, base + height + 0.35, spot.y)
	var segments := 8
	for step in segments:
		var a := Vector3(cos(TAU * step / segments), 0.0, sin(TAU * step / segments)) * 1.4
		var b := Vector3(cos(TAU * (step + 1) / segments), 0.0, sin(TAU * (step + 1) / segments)) * 1.4
		var rim := Vector3(spot.x, base + height - 0.05, spot.y)
		var stripe := color if step % 2 == 0 else Color("#f5f5f5")
		_surface_for(spot).triangle(top, rim + a, rim + b, Vector3.UP, stripe, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		_surface_for(spot).triangle(top, rim + b, rim + a, Vector3.DOWN, stripe.darkened(0.3), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

func _tarp(spot: Vector2, height: float, size: Vector2, yaw: float, color: Color) -> void:
	var along := Vector2(sin(yaw), cos(yaw))
	var across := along.orthogonal()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var foot := spot + across * corner.x * size.x * 0.5 + along * corner.y * size.y * 0.5
		_cylinder(foot, _ground(foot), 0.03, height - _ground(foot), Color("#c8b48a"))
	_box(spot, height, Vector3(size.x, 0.03, size.y), yaw, color)

func _heap(center: Vector2, top: float, radius: float, color: Color, rng: RandomNumberGenerator) -> void:
	for item in 9:
		var offset := Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius)) * 0.8
		var lift := (1.0 - offset.length() / radius) * 0.18
		_sphere(Vector3(center.x + offset.x, top + 0.07 + maxf(lift, 0.0), center.y + offset.y), 0.09, color.lerp(Color.BLACK, rng.randf() * 0.15))

func _box(spot: Vector2, bottom: float, size: Vector3, yaw: float, color: Color) -> void:
	var surface := _surface_for(spot)
	var basis := Basis(Vector3.UP, yaw)
	var center := Vector3(spot.x, bottom + size.y * 0.5, spot.y)
	var h := size * 0.5
	for axis in 3:
		for sign: float in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			v[(axis + 2) % 3] = 1.0
			var c := center + basis * (normal * h)
			var du := basis * (u * h)
			var dv := basis * (v * h)
			surface.quad(c - du - dv, c + du - dv, c + du + dv, c - du + dv, basis * normal, color.darkened(0.12 if axis != 1 else 0.0),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

func _cylinder(spot: Vector2, bottom: float, radius: float, height: float, color: Color) -> void:
	var surface := _surface_for(spot)
	var segments := 6
	for step in segments:
		var a := Vector2.RIGHT.rotated(TAU * step / segments) * radius
		var b := Vector2.RIGHT.rotated(TAU * (step + 1) / segments) * radius
		var mid := (a + b).normalized()
		surface.quad(Vector3(spot.x + a.x, bottom, spot.y + a.y), Vector3(spot.x + b.x, bottom, spot.y + b.y),
			Vector3(spot.x + b.x, bottom + height, spot.y + b.y), Vector3(spot.x + a.x, bottom + height, spot.y + a.y),
			Vector3(mid.x, 0.0, mid.y), color, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

func _sphere(center: Vector3, radius: float, color: Color) -> void:
	var surface := _surface_for(Vector2(center.x, center.z))
	var rings := 3
	var segments := 6
	for ring in rings:
		var t0 := PI * ring / rings
		var t1 := PI * (ring + 1) / rings
		for step in segments:
			var p0 := TAU * step / segments
			var p1 := TAU * (step + 1) / segments
			var a := Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0))
			var b := Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1))
			var c := Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))
			var d := Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))
			var normal := (a + b + c + d).normalized()
			surface.quad(center + a * radius, center + b * radius, center + c * radius, center + d * radius, normal, color,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)

## A board on two posts, readable from both sides.
func _label_board(spot: Vector2, facing: Vector2, text: String, background: Color, foreground: Color, bottom := NAN) -> void:
	var base := _ground(spot)
	var low := base + 2.2 if is_nan(bottom) else bottom
	var width := clampf(text.length() * 0.22, 2.0, 6.0)
	var yaw := atan2(facing.x, facing.y)
	_box(spot, low, Vector3(width, 0.55, 0.06), yaw, background)
	if is_nan(bottom):
		for side: float in [-0.45, 0.45]:
			_cylinder(spot + facing.orthogonal() * width * side, base, 0.05, 2.2, Color("#5d6166"))
	_label(spot + facing * 0.04, yaw, text, width, low + 0.28, foreground, 40)
	_label(spot - facing * 0.04, yaw + PI, text, width, low + 0.28, foreground, 40)

func _label(spot: Vector2, yaw: float, text: String, width: float, height: float, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.006
	label.width = width / label.pixel_size * 0.92
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.position = Vector3(spot.x, height, spot.y)
	label.rotation.y = yaw
	label.visibility_range_end = 160.0
	add_child(label)

func _collide_box(spot: Vector2, bottom: float, size: Vector3, yaw: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	PhysicsServer3D.body_add_shape(_body, shape.get_rid(), Transform3D(Basis(Vector3.UP, yaw), Vector3(spot.x, bottom + size.y * 0.5, spot.y)))
	set_meta("shape_%d" % PhysicsServer3D.body_get_shape_count(_body), shape)

func _collide_post(spot: Vector2, bottom: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = height
	PhysicsServer3D.body_add_shape(_body, shape.get_rid(), Transform3D(Basis(), Vector3(spot.x, bottom + height * 0.5, spot.y)))
	set_meta("shape_%d" % PhysicsServer3D.body_get_shape_count(_body), shape)

# --- Placement helpers ------------------------------------------------------------

func _clear_spot(point: Vector2, radius: float) -> Vector2:
	for ring in 8:
		for step in maxi(1, ring * 6):
			var spot := point + Vector2.RIGHT.rotated(TAU * step / maxi(1, ring * 6)) * ring * 6.0
			if _world.buildings.is_clear(spot, radius) and not _on_other_road(spot, radius * 0.6):
				return spot
	return Vector2.INF

func _nearest_road(point: Vector2, reach: float) -> Dictionary:
	return _world.signage._nearest_road(point, reach)

func _on_other_road(point: Vector2, margin: float) -> bool:
	# Junctions can have a different road closer than the road currently being
	# dressed. Check every carriageway so poles, lamps and stalls never become
	# gameplay obstacles in an adjacent lane.
	return _world._is_on_any_road(point, margin)

func _ground(point: Vector2) -> float:
	return _world.ground_height(point)

static func _rng(point: Vector2) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(point.x * 10.0), roundi(point.y * 10.0)))
	return rng

func _surface_for(point: Vector2) -> MeshSurface:
	var cell := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))
	var target := _street_lamp_surfaces if _collecting_street_lamp else _surfaces
	if not target.has(cell):
		target[cell] = MeshSurface.new()
	return target[cell]

func _commit() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.8
	# Wires are thin horizontal ribbons. The player usually views them from
	# below, so they must render on both faces instead of only casting a shadow.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for cell in _surfaces:
		var instance := MeshInstance3D.new()
		instance.name = "StreetLife_%d_%d" % [cell.x, cell.y]
		instance.mesh = (_surfaces[cell] as MeshSurface).to_mesh()
		instance.material_override = material
		instance.visibility_range_end = VIEW_DISTANCE
		add_child(instance)
	_surfaces.clear()
	for cell in _street_lamp_surfaces:
		var instance := MeshInstance3D.new()
		instance.name = "StreetLights_%d_%d" % [cell.x, cell.y]
		instance.mesh = (_street_lamp_surfaces[cell] as MeshSurface).to_mesh()
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = VIEW_DISTANCE
		add_child(instance)
	_street_lamp_surfaces.clear()
