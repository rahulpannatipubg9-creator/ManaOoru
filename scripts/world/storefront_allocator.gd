extends RefCounted
## Generation-time ownership. Source positions are never moved or used to fill
## a nearby building. A footprint must contain the business pin. Untagged
## footprints can host a single verified occupant, never inferred multi-tenancy.
const CELL := 64.0
const MIN_UNIT_WIDTH := 3.2
const EDGE_MARGIN := 0.25
const SIGN_BOTTOM := 2.45
const GROUND_BAND_TOP := 3.15
const ASPECT := 84.0 / 384.0
## Numerical/boundary tolerance only (ten centimetres), not a search radius.
const BOUNDARY_TOLERANCE := 0.10
const RESIDENTIAL := ["house", "residential", "apartments", "detached", "semidetached_house", "terrace", "dormitory", "bungalow", "hut"]

var businesses: Array[Dictionary] = []
var units: Array[Dictionary] = []
var assignments: Array[Dictionary] = []
var unplaced: Array[Dictionary] = []
var _grid: Dictionary = {}

static func name_key(text: String) -> String:
	var key := text.to_lower().replace(", godavarikhani", "").strip_edges()
	return "new ashok theatre" if key in ["new ashoka talkies", "new ashok theatre"] else key

static func record_id(record: Dictionary) -> String:
	var source_features: Array = record.get("source_features", [])
	if not source_features.is_empty():
		return "osm/%s/%s" % [str(source_features[0].get("type", "feature")), str(source_features[0].get("id"))]
	return str(record.get("business_id", "%s@%.8f,%.8f" % [str(record.name), float(record.lon), float(record.lat)]))

func allocate(footprints: Array[PackedVector2Array], metadata: Array[Dictionary], boards: Array,
		road_direction: Callable, road_distance: Callable, road_clear := Callable()) -> void:
	businesses.clear()
	units.clear()
	assignments.clear()
	unplaced.clear()
	_grid.clear()
	for index in footprints.size():
		var low := footprints[index][0]
		var high := low
		for p in footprints[index]:
			low = low.min(p)
			high = high.max(p)
		for x in range(floori(low.x / CELL), floori(high.x / CELL) + 1):
			for y in range(floori(low.y / CELL), floori(high.y / CELL) + 1):
				var cell := Vector2i(x, y)
				if not _grid.has(cell):
					_grid[cell] = []
				_grid[cell].append(index)
	var groups: Dictionary = {}
	for board_index in boards.size():
		var board: Dictionary = boards[board_index]
		var point := GeoProjection.lon_lat_to_map(float(board.lon), float(board.lat))
		if not GeoProjection.is_playable(point):
			continue
		var alias := false
		for business in businesses:
			if business.id == record_id(board) or (name_key(business.name) == name_key(str(board.name)) and business.point.distance_to(point) < 25.0):
				business.source_records.append(board.duplicate(true))
				alias = true
				break
		if alias:
			continue
		var business := {"id": record_id(board), "name": str(board.name), "point": point,
			"board_index": board_index, "source_records": [board.duplicate(true)]}
		businesses.append(business)
		var candidates: Array[int] = []
		var cell := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
		var nearby: Dictionary = {}
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for index: int in _grid.get(cell + Vector2i(dx, dy), []):
					nearby[index] = true
		for index: int in nearby:
			if _contains_pin(point, footprints[index]):
				candidates.append(index)
		if candidates.size() != 1:
			_reject(business, "no_containing_building" if candidates.is_empty() else "ambiguous_overlapping_footprints")
			continue
		var index: int = candidates[0]
		var tags: Dictionary = metadata[index].get("tags", {})
		if str(tags.get("building", "")) in RESIDENTIAL:
			_reject(business, "residential_building", index)
			continue
		if not groups.has(index):
			groups[index] = []
		groups[index].append(business)
	for index: int in groups:
		_allocate_building(index, footprints[index], metadata[index], groups[index], road_direction, road_distance, road_clear)

static func _contains_pin(point: Vector2, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return true
	for edge in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()])) <= BOUNDARY_TOLERANCE:
			return true
	return false

func _allocate_building(index: int, points: PackedVector2Array, meta: Dictionary, occupants: Array,
		road_direction: Callable, road_distance: Callable, road_clear: Callable) -> void:
	var tags: Dictionary = meta.get("tags", {})
	var building_id := str(meta.id)
	var kind := str(tags.get("building", "yes"))
	# Multiple shops require actual retail/commercial/mixed-use source tags.
	# Random visual facade colours and proximity to roads are not evidence.
	var multi := kind in ["retail", "commercial", "mixed_use"] and not tags.has("shop") and not tags.has("amenity")
	if occupants.size() > 1 and not multi:
		var named: Array = occupants.filter(func(b: Dictionary) -> bool: return name_key(b.name) == name_key(str(tags.get("name", ""))))
		if named.size() == 1:
			for b: Dictionary in occupants:
				if b != named[0]:
					_reject(b, "not_named_building_occupant", index)
			occupants = named
		else:
			for b: Dictionary in occupants:
				_reject(b, "multiple_businesses_without_verified_units", index)
			return
	var walls: Array[Dictionary] = []
	for edge in points.size():
		var a := points[edge]
		var b := points[(edge + 1) % points.size()]
		var length := a.distance_to(b)
		var direction := (b - a).normalized()
		var normal := Vector2(direction.y, -direction.x)
		var middle := (a + b) * 0.5
		var facing: float = normal.dot(road_direction.call(middle))
		if length >= MIN_UNIT_WIDTH + EDGE_MARGIN * 2.0 and facing >= 0.5:
			walls.append({"a": a, "b": b, "normal": normal, "length": length,
				"edge": edge, "score": facing * 100.0 - float(road_distance.call(middle))})
	if walls.is_empty():
		for b: Dictionary in occupants:
			_reject(b, "no_valid_road_facing_frontage", index)
		return
	walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var wall: Dictionary = walls[0]
	var usable: float = wall.length - EDGE_MARGIN * 2.0
	var capacity := maxi(1, floori(usable / MIN_UNIT_WIDTH)) if multi else 1
	var span := usable / capacity
	var direction: Vector2 = (wall.b - wall.a).normalized()
	var building_units: Array[Dictionary] = []
	for slot in capacity:
		var middle: Vector2 = wall.a + direction * (EDGE_MARGIN + span * (slot + 0.5))
		var unit := {"id": "%s/front-%d/unit-%d" % [building_id, wall.edge, slot], "building_id": building_id,
			"building_index": index, "width": span, "center": middle, "entrance": middle,
			"entrance_evidence": "inferred_frontage" if multi else "single_contained_business",
			"business_id": "", "wall_a": wall.a, "wall_b": wall.b, "normal": wall.normal}
		units.append(unit)
		building_units.append(unit)
	occupants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var demand: Dictionary = {}
	for business: Dictionary in occupants:
		var projection: float = (business.point - wall.a).dot(direction) - EDGE_MARGIN
		var slot := clampi(floori(projection / span), 0, capacity - 1)
		demand[slot] = int(demand.get(slot, 0)) + 1
	for business: Dictionary in occupants:
		# Select the unit at the business's own frontage projection. If occupied,
		# never relocate that business into another empty unit just to fit it.
		var projection: float = (business.point - wall.a).dot(direction) - EDGE_MARGIN
		var slot := clampi(floori(projection / span), 0, capacity - 1)
		var unit: Dictionary = building_units[slot]
		if int(demand[slot]) > 1:
			_reject(business, "ambiguous_businesses_at_same_storefront", index)
			continue
		if not str(unit.business_id).is_empty():
			_reject(business, "frontage_unit_already_occupied", index)
			continue
		var width := minf(span - 0.16, 7.5)
		# The sign fits wholly inside the ground-floor lintel band; never borrow
		# upper-floor wall space or squash its text aspect ratio.
		width = minf(width, (GROUND_BAND_TOP - SIGN_BOTTOM) / ASPECT)
		var wall_height := float(meta.get("wall_height", float(meta.floors) * 3.0 + 0.3))
		width = minf(width, (wall_height - 0.15 - SIGN_BOTTOM) / ASPECT)
		if width < 2.4:
			_reject(business, "insufficient_ground_floor_sign_band", index)
			continue
		if road_clear.is_valid() and not road_clear.call(unit.center - direction * width * 0.5, unit.center + direction * width * 0.5, wall.normal):
			_reject(business, "sign_intersects_road_or_building", index)
			continue
		unit.business_id = business.id
		assignments.append({"business_id": business.id, "storefront_id": unit.id,
			"building_id": building_id, "building_index": index, "board_index": business.board_index,
			"a": unit.center - direction * width * 0.5, "b": unit.center + direction * width * 0.5,
			"height": width * ASPECT, "bottom": float(meta.base) + SIGN_BOTTOM,
			"normal": wall.normal, "wall_a": wall.a, "wall_b": wall.b, "mounting": "facade",
			"roof": float(meta.base) + minf(wall_height, GROUND_BAND_TOP + 0.15)})

func _reject(business: Dictionary, reason: String, index := -1) -> void:
	unplaced.append({"business_id": business.id, "name": business.name, "board_index": business.board_index,
		"position": business.point, "building_index": index, "reason": reason,
		"source_records": business.source_records})
