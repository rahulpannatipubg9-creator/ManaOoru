class_name SignageBuilder
extends Node3D

## Street-level signage placed from real map data:
## - name boards for every mapped shop, hospital, school, temple, bank, office…
##   at the roadside in front of its real position;
## - colony/locality name boards for mapped place names;
## - street-name plates along every named street (OpenStreetMap names, plus names
##   backed by real business addresses; see tools/fetch_places.py);
## - a name board at every named junction centre (Ramesh Nagar Centre, Swatantra Chowk…);
## - statues for mapped monuments;
## - pedestrian-crossing signs at mapped zebra crossings, railway level-crossing signs;
## - traffic signals at mapped (or locally listed) signal junctions, cycling red/amber/green.
## Municipal dustbins are ambience: placed beside commercial boards, not mapped positions.

const BOARD_HEIGHT := 0.8
const CHARACTER_WIDTH := 0.3
const MAX_BOARD_WIDTH := 7.5
const BOARD_BOTTOM := 2.3
const LABEL_VIEW_DISTANCE := 140.0
const SIGNAL_CYCLE := [["green", 12.0], ["amber", 3.0], ["red", 15.0]]
const SIGNAL_ROAD_KINDS := ["trunk", "primary", "secondary", "tertiary"]
const SIGNAL_CLUSTER_DISTANCE := 30.0
const STREETS_PATH := "res://data/places/godavarikhani_streets.json"
## A plate near each end of every named road piece, and one every spacing along it.
const STREET_PLATE_SPACING := 160.0
const STREET_PLATE_END_OFFSET := 10.0
## No two plates of the same street closer than this.
const STREET_PLATE_GAP := 90.0
const STREET_PLATE_HEIGHT := 0.42
const STREET_PLATE_BOTTOM := 2.3
const JUNCTION_BOARD_HEIGHT := 0.6
const JUNCTION_BOARD_BOTTOM := 2.4
const HEALTH := ["hospital", "clinic", "pharmacy", "dentist", "doctors", "blood_bank", "health_post", "doctor"]
const EDUCATION := ["school", "college", "educational_institution", "university", "kindergarten"]
const NON_COMMERCIAL := ["place_of_worship", "police", "government", "office", "information", "artwork",
	"community_centre", "post_office", "educational_institution"]
const KIND_LABELS := {
	"bakery": "BAKERY", "tea": "TEA STALL", "general": "GENERAL STORE", "wine": "WINE SHOP",
	"bar": "BAR", "butcher": "MEAT SHOP", "dairy": "MILK DAIRY", "convenience": "KIRANA STORE",
	"supermarket": "SUPERMARKET", "photo": "PHOTO STUDIO", "fast_food": "TIFFIN CENTRE",
	"atm": "ATM", "car_wash": "CAR WASH", "fuel": "PETROL BUNK", "school": "SCHOOL",
	"pharmacy": "MEDICAL STORE", "greengrocer": "VEGETABLES", "place_of_worship": "TEMPLE",
}

var board_count := 0
var terrain: TerrainData
var signal_count := 0
var street_plate_count := 0
var junction_board_count := 0
var _road_grid: Dictionary = {}
var _boards := MeshSurface.new()
var _poles := MeshSurface.new()
var _bins: Array[Transform3D] = []
var _signal_lights: Dictionary = {}
## "group_colour" → lamp transforms; all lamps of one phase share one MultiMesh.
var _lamps: Dictionary = {}
var _signal_time := 0.0

func build(data: MapData, buildings: BuildingBuilder) -> void:
	name = "Signage"
	terrain = data.terrain
	_index_roads(data)
	for poi in data.pois:
		if poi.kind == "monument":
			_add_statue(poi)
		else:
			_add_poi_board(poi, buildings)
	for place in data.places:
		_add_roadside_board(place.position, place.name.to_upper(), Color("#1f6b3a"), Color.WHITE, 30.0)
	for landmark in data.landmarks:
		if landmark.category == "Stadium":
			_add_roadside_board(landmark.position, landmark.name.to_upper(), Color("#7a1f1f"), Color("#ffe9a8"), 200.0)
	_add_street_plates()
	_add_junction_boards()
	_add_point_signs(_cluster(data.crossings, 25.0), "PEDESTRIAN\nCROSSING", Color("#1d4f9c"), Color.WHITE)
	_add_point_signs(data.level_crossings, "RAILWAY\nCROSSING", Color("#f4f1ea"), Color("#b3261e"))
	for junction in signal_junctions(data):
		_add_traffic_signal(junction)
	_commit()

func _process(delta: float) -> void:
	if _signal_lights.is_empty():
		return
	_signal_time = fmod(_signal_time + delta, _cycle_length() * 2.0)
	for group: int in _signal_lights:
		var phase := _phase_at(fmod(_signal_time + group * _cycle_length(), _cycle_length() * 2.0))
		for colour in ["red", "amber", "green"]:
			var material: StandardMaterial3D = _signal_lights[group][colour]
			material.emission_energy_multiplier = 3.0 if colour == phase else 0.0
			material.albedo_color = material.emission.darkened(0.0 if colour == phase else 0.75)

func _cycle_length() -> float:
	var total := 0.0
	for step in SIGNAL_CYCLE:
		total += step[1]
	return total

## Group 0 runs green→amber→red; group 1 is red while group 0 moves, then vice versa.
func _phase_at(time: float) -> String:
	if time >= _cycle_length():
		return "red"
	var elapsed := 0.0
	for step in SIGNAL_CYCLE:
		elapsed += step[1]
		if time < elapsed:
			return step[0]
	return "red"

## Used by lightweight ambient road traffic.  Opposite approaches use the
## complementary group, matching the two alternating lamp phases above.
func traffic_phase_for_group(group: int) -> String:
	return _phase_at(fmod(_signal_time + (group % 2) * _cycle_length(), _cycle_length() * 2.0))

func _add_poi_board(poi: Dictionary, buildings: BuildingBuilder) -> void:
	# A facade-mounted business sign must not also become a pole sign at the
	# kerb. Only places without a safe facade mount use freestanding boards.
	if buildings.has_facade_board(poi.name):
		return
	# An unassigned business remains a map record, not an invented pole sign.
	# Area, junction, bus stop and traffic signs have separate builders below.
	if not str(poi.name).is_empty():
		return
	var kind: String = poi.kind
	var text: String = poi.name.to_upper() if not poi.name.is_empty() else str(KIND_LABELS.get(kind, kind.capitalize().to_upper()))
	var background := _board_color(kind, text)
	var foreground := Color.WHITE
	if kind in HEALTH:
		background = Color("#f7f7f2")
		foreground = Color("#c62828")
		text = "+ " + text
	elif kind == "place_of_worship":
		foreground = Color("#7a1010")
	var board := _add_roadside_board(poi.position, text, background, foreground, 60.0)
	if board.is_empty() or kind in HEALTH + EDUCATION + NON_COMMERCIAL:
		return
	var bin_point: Vector2 = board.position + board.along * 2.2
	if buildings.is_clear(bin_point, 0.5):
		_bins.append(Transform3D(Basis(Vector3.UP, board.angle), Vector3(bin_point.x, 0.0, bin_point.y)))

func _board_color(kind: String, text: String) -> Color:
	if kind in EDUCATION:
		return Color("#1d4f9c")
	if kind in ["bank", "atm", "post_office"]:
		return Color("#0b4f8a")
	if kind == "police":
		return Color("#123a7a")
	if kind == "place_of_worship":
		return Color("#f39c12")
	if kind in ["government", "office", "educational_institution"]:
		return Color("#2e5e3a")
	var palette := [Color("#c0392b"), Color("#d35400"), Color("#16a085"), Color("#8e44ad"), Color("#b7950b"), Color("#1e8449")]
	return palette[absi(hash(text)) % palette.size()]

## Places a name board at the edge of the nearest road, facing traffic.
## Returns {position, along, angle} or {} when no road is within reach.
func _add_roadside_board(target: Vector2, text: String, background: Color, foreground: Color, reach: float) -> Dictionary:
	var road := _nearest_road(target, reach)
	if road.is_empty():
		return {}
	var toward_target: Vector2 = target - road.point
	var outward: Vector2 = road.normal if toward_target.dot(road.normal) >= 0.0 else -road.normal
	var position: Vector2 = road.point + outward * (road.half_width + 1.4)
	var width := clampf(text.length() * CHARACTER_WIDTH, 2.2, MAX_BOARD_WIDTH)
	var lines := ceili(text.length() * 72.0 * 0.006 * 0.60 / (width * 0.92))
	var height := BOARD_HEIGHT * lines
	var along: Vector2 = outward.orthogonal()
	var angle := atan2(-outward.x, -outward.y)
	_add_panel(position, along, -outward, width, height, BOARD_BOTTOM, background)
	_add_label(position - outward * 0.07, angle, text, width, BOARD_BOTTOM + height * 0.5, foreground)
	board_count += 1
	return {"position": position, "along": along, "angle": angle}

func _add_street_plates() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STREETS_PATH)) if FileAccess.file_exists(STREETS_PATH) else null
	if not parsed is Dictionary:
		return
	for street: Dictionary in parsed.streets:
		var text := str(street.name).to_upper()
		var placed := PackedVector2Array()
		for line: Array in street.lines:
			var points := PackedVector2Array()
			for lon_lat: Array in line:
				points.append(GeoProjection.lon_lat_to_map(float(lon_lat[0]), float(lon_lat[1])))
			for point in _plate_points(points):
				if not GeoProjection.is_playable(point):
					continue
				var too_close := false
				for other in placed:
					too_close = too_close or other.distance_to(point) < STREET_PLATE_GAP
				if too_close:
					continue
				var road := _nearest_road(point, 12.0)
				if road.is_empty():
					continue
				placed.append(point)
				_add_street_plate(road, text)

func _add_junction_boards() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STREETS_PATH)) if FileAccess.file_exists(STREETS_PATH) else null
	if not parsed is Dictionary:
		return
	for junction: Dictionary in parsed.get("junctions", []):
		var point := GeoProjection.lon_lat_to_map(float(junction.lon), float(junction.lat))
		var road := _nearest_road(point, 40.0)
		if road.is_empty() or not GeoProjection.is_playable(point):
			continue
		# On the corner, clear of the carriageway, readable from both directions.
		var facing: Vector2 = -road.direction
		var text := str(junction.name).to_upper()
		var width := clampf(text.length() * 0.24, 2.2, 5.5)
		var position: Vector2 = road.point + road.normal * (road.half_width + width * 0.5 + 0.6)
		_add_panel(position, road.normal, facing, width, JUNCTION_BOARD_HEIGHT, JUNCTION_BOARD_BOTTOM, Color("#0d5c63"))
		var middle := JUNCTION_BOARD_BOTTOM + JUNCTION_BOARD_HEIGHT * 0.5
		_add_label(position + facing * 0.03, atan2(facing.x, facing.y), text, width, middle, Color.WHITE, 40)
		_add_label(position - facing * 0.03, atan2(-facing.x, -facing.y), text, width, middle, Color.WHITE, 40)
		junction_board_count += 1
		board_count += 1

## Points along a road piece: near each end and every STREET_PLATE_SPACING in between.
static func _plate_points(points: PackedVector2Array) -> PackedVector2Array:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	var wanted: Array[float] = [minf(STREET_PLATE_END_OFFSET, length * 0.5)]
	var distance := STREET_PLATE_SPACING
	while distance < length - STREET_PLATE_END_OFFSET:
		wanted.append(distance)
		distance += STREET_PLATE_SPACING
	if length > STREET_PLATE_END_OFFSET * 2.0:
		wanted.append(length - STREET_PLATE_END_OFFSET)
	var result := PackedVector2Array()
	var walked := 0.0
	var next := 0
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var piece := a.distance_to(b)
		while next < wanted.size() and wanted[next] <= walked + piece:
			result.append(a.lerp(b, (wanted[next] - walked) / maxf(piece, 0.001)))
			next += 1
		walked += piece
	return result

## Blue municipal street-name plate on posts at the kerb, readable from both directions.
func _add_street_plate(road: Dictionary, text: String) -> void:
	var facing: Vector2 = -road.direction
	var width := clampf(text.length() * 0.2, 1.6, 5.0)
	# The plate spans away from the road, so keep its near end clear of the carriageway.
	var position: Vector2 = road.point + road.normal * (road.half_width + width * 0.5 + 0.4)
	_add_panel(position, road.normal, facing, width, STREET_PLATE_HEIGHT, STREET_PLATE_BOTTOM, Color("#0b4f8a"))
	var middle := STREET_PLATE_BOTTOM + STREET_PLATE_HEIGHT * 0.5
	_add_label(position + facing * 0.03, atan2(facing.x, facing.y), text, width, middle, Color.WHITE, 30)
	_add_label(position - facing * 0.03, atan2(-facing.x, -facing.y), text, width, middle, Color.WHITE, 30)
	street_plate_count += 1
	board_count += 1

func _add_point_signs(points: PackedVector2Array, text: String, background: Color, foreground: Color) -> void:
	for point in points:
		var road := _nearest_road(point, 15.0)
		if road.is_empty():
			continue
		# Faces traffic travelling along +direction, a few metres before the crossing.
		var facing: Vector2 = -road.direction
		var position: Vector2 = road.point + road.normal * (road.half_width + 1.0) - road.direction * 4.0
		_add_panel(position, road.normal, facing, 1.2, 1.2, 1.9, background)
		_add_label(position + facing * 0.07, atan2(facing.x, facing.y), text, 1.2, 2.5, foreground, 26)
		board_count += 1

func _add_statue(poi: Dictionary) -> void:
	var at: Vector2 = poi.position
	var stone := Color("#bdb6a6")
	var bronze := Color("#6d5a3a")
	_box(_boards, at, Vector2(2.6, 2.6), 0.0, 1.6, stone)
	_box(_boards, at, Vector2(0.9, 0.7), 1.6, 3.4, bronze)
	_box(_boards, at, Vector2(0.5, 0.5), 3.4, 3.9, bronze)
	_add_label(at + Vector2(0.0, 1.32), 0.0, poi.name.to_upper(), 2.5, 1.0, Color("#3a2f1f"), 36)
	board_count += 1

## Every junction where a main road (trunk/primary/secondary/tertiary) meets at least two
## other arms gets signals, plus any signal mapped in OSM or listed locally. Roundabouts
## are left unsignalled. Junction nodes closer than SIGNAL_CLUSTER_DISTANCE (the two
## carriageways of a divided road) count as one junction. Each entry is the list of
## node positions making up that junction.
static func signal_junctions(data: MapData) -> Array[PackedVector2Array]:
	var arms: Dictionary = {}
	var positions: Dictionary = {}
	var major: Dictionary = {}
	var roundabout: Dictionary = {}
	for road in data.roads:
		if RoadStyle.is_path(road.kind):
			continue
		var ids: PackedInt64Array = road.node_ids
		var points: PackedVector2Array = road.points
		for index in ids.size():
			var id := ids[index]
			arms[id] = int(arms.get(id, 0)) + (1 if index == 0 or index == ids.size() - 1 else 2)
			positions[id] = points[index]
			if road.kind in SIGNAL_ROAD_KINDS:
				major[id] = true
			if road.junction == "roundabout":
				roundabout[id] = true
	var candidates := PackedVector2Array()
	for id in arms:
		if arms[id] >= 3 and major.has(id) and not roundabout.has(id):
			candidates.append(positions[id])
	for mapped in data.traffic_signals:
		candidates.append(mapped.position)
	var clusters: Array[PackedVector2Array] = []
	for point in candidates:
		var joined := false
		for cluster in clusters:
			if cluster[0].distance_to(point) < SIGNAL_CLUSTER_DISTANCE:
				cluster.append(point)
				joined = true
				break
		if not joined:
			clusters.append(PackedVector2Array([point]))
	return clusters

func _add_traffic_signal(nodes: PackedVector2Array) -> void:
	var approaches: Array[Dictionary] = []
	for node in nodes:
		for approach in _approaches(node):
			var duplicate := false
			for existing in approaches:
				if existing.direction.dot(approach.direction) > 0.95 and existing.at.distance_to(approach.at) < SIGNAL_CLUSTER_DISTANCE:
					duplicate = true
			if not duplicate:
				approaches.append(approach)
	if approaches.size() < 3:
		return
	# Phase groups per junction: arms roughly in line with the first arm share a phase.
	var reference: Vector2 = approaches[0].direction
	var placed := false
	for approach in approaches:
		if not approach.inbound:
			continue
		var direction: Vector2 = approach.direction
		var normal := direction.orthogonal()
		# Vehicles drive on the left in India, so the signal stands on the approach's left kerb.
		var junction: Vector2 = approach.at
		var pole: Vector2 = junction + direction * (approach.half_width + 3.0) - normal * (approach.half_width + 0.8)
		# Never stand a pole on a carriageway (e.g. the other half of a divided road).
		if _on_carriageway(pole):
			continue
		placed = true
		_box(_poles, pole, Vector2(0.18, 0.18), 0.0, 4.2, Color("#2a2d30"))
		var head: Vector2 = pole + normal * 0.0
		_box(_poles, head, Vector2(0.45, 0.35), 4.2, 5.6, Color("#1b1c1e"))
		var group := 0 if absf(direction.dot(reference)) > 0.7 else 1
		for slot in 3:
			var colour: String = ["red", "amber", "green"][slot]
			# Lamps on the face that looks back down the approach, towards oncoming drivers.
			var lamp_at := Vector3(head.x, 5.35 - slot * 0.42 + _ground(head), head.y) + Vector3(direction.x, 0.0, direction.y) * 0.2
			_lamp_transforms(group, colour).append(Transform3D(Basis(), lamp_at))
	if placed:
		signal_count += 1

func _approaches(junction: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var center := _cell(junction)
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			for segment in _road_grid.get(Vector2i(x, y), []):
				for end in [0, 1]:
					var at: Vector2 = segment.a if end == 0 else segment.b
					var other: Vector2 = segment.b if end == 0 else segment.a
					if at.distance_to(junction) < 3.0 and other.distance_to(at) > 1.0:
						var direction: Vector2 = (other - at).normalized()
						var duplicate := false
						for existing in result:
							if existing.direction.dot(direction) > 0.95:
								duplicate = true
						# One-way arms leaving the junction carry no approaching traffic.
						var inbound: bool = segment.oneway == 0 or (segment.oneway > 0) == (end == 1)
						if not duplicate:
							result.append({"direction": direction, "half_width": segment.half_width, "at": at, "inbound": inbound})
	return result

func _on_carriageway(point: Vector2) -> bool:
	var road := _nearest_road(point, 15.0)
	return not road.is_empty() and (road.point as Vector2).distance_to(point) < road.half_width + 0.3

func _lamp_transforms(group: int, colour: String) -> Array:
	var key := "%d_%s" % [group, colour]
	if not _lamps.has(key):
		_lamps[key] = []
	return _lamps[key]

func _signal_material(group: int, colour: String) -> StandardMaterial3D:
	if not _signal_lights.has(group):
		_signal_lights[group] = {}
	if not _signal_lights[group].has(colour):
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.emission = {"red": Color("#ff2a1a"), "amber": Color("#ffb300"), "green": Color("#2bff6a")}[colour]
		material.albedo_color = material.emission.darkened(0.75)
		_signal_lights[group][colour] = material
	return _signal_lights[group][colour]

func _add_panel(center: Vector2, along: Vector2, facing: Vector2, width: float, height: float, bottom: float, color: Color) -> void:
	var half := along * width * 0.5
	var front := Vector3(facing.x, 0.0, facing.y)
	_boards.quad(_v(center - half, bottom), _v(center + half, bottom), _v(center + half, bottom + height),
		_v(center - half, bottom + height), front, color, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	_boards.quad(_v(center - half, bottom), _v(center + half, bottom), _v(center + half, bottom + height),
		_v(center - half, bottom + height), -front, color.darkened(0.3), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	for post in [-0.42, 0.42]:
		_box(_poles, center + along * width * post, Vector2(0.09, 0.09), 0.0, bottom + height * 0.5, Color("#5d6166"))

func _add_label(at: Vector2, angle: float, text: String, width: float, height: float, color: Color, font_size := 72) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.006
	label.width = width / label.pixel_size * 0.92
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(at.x, height + _ground(at), at.y)
	label.rotation.y = angle
	label.visibility_range_end = LABEL_VIEW_DISTANCE
	add_child(label)

func _box(surface: MeshSurface, center: Vector2, size: Vector2, bottom: float, top: float, color: Color) -> void:
	var hx := Vector2(size.x * 0.5, 0.0)
	var hz := Vector2(0.0, size.y * 0.5)
	var corners := [center - hx - hz, center + hx - hz, center + hx + hz, center - hx + hz]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var mid := (a + b) * 0.5 - center
		surface.quad(_v(a, bottom), _v(b, bottom), _v(b, top), _v(a, top), Vector3(mid.x, 0.0, mid.y).normalized(), color,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
	surface.quad(_v(corners[0], top), _v(corners[1], top), _v(corners[2], top), _v(corners[3], top), Vector3.UP,
		color.lightened(0.1), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)

func _commit() -> void:
	for surface in [_boards, _poles]:
		if surface.vertices.is_empty():
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = surface.to_mesh()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 0.8
		instance.material_override = material
		add_child(instance)
		if not surface.collision.is_empty():
			var body := StaticBody3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(surface.collision)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			instance.add_child(body)
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.13
	lamp_mesh.height = 0.26
	lamp_mesh.radial_segments = 10
	lamp_mesh.rings = 5
	for key: String in _lamps:
		var parts := key.split("_")
		var lamps: Array = _lamps[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = lamp_mesh
		multimesh.instance_count = lamps.size()
		for index in lamps.size():
			multimesh.set_instance_transform(index, lamps[index])
		var lamp_instance := MultiMeshInstance3D.new()
		lamp_instance.name = "SignalLamps_" + key
		lamp_instance.multimesh = multimesh
		lamp_instance.material_override = _signal_material(int(parts[0]), parts[1])
		add_child(lamp_instance)
	if not _bins.is_empty():
		var bin := CylinderMesh.new()
		bin.top_radius = 0.42
		bin.bottom_radius = 0.36
		bin.height = 1.0
		bin.radial_segments = 10
		var bin_material := StandardMaterial3D.new()
		bin_material.albedo_color = Color("#2e7d32")
		bin.material = bin_material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = bin
		multimesh.instance_count = _bins.size()
		for index in _bins.size():
			var bin_at := _bins[index].origin
			multimesh.set_instance_transform(index, _bins[index].translated(Vector3(0.0, 0.5 + _ground(Vector2(bin_at.x, bin_at.z)), 0.0)))
		var bins := MultiMeshInstance3D.new()
		bins.name = "Dustbins"
		bins.multimesh = multimesh
		add_child(bins)

func dustbin_count() -> int:
	return _bins.size()

func _cluster(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	var kept := PackedVector2Array()
	for point in points:
		var near := false
		for existing in kept:
			if existing.distance_to(point) < radius:
				near = true
		if not near:
			kept.append(point)
	return kept

func _index_roads(data: MapData) -> void:
	for road in data.roads:
		if RoadStyle.is_path(road.kind):
			continue
		var half := RoadStyle.width(road) * 0.5
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			var segment := {"a": points[index - 1], "b": points[index], "half_width": half, "oneway": int(road.oneway)}
			var cell := _cell(points[index - 1].lerp(points[index], 0.5))
			if not _road_grid.has(cell):
				_road_grid[cell] = []
			_road_grid[cell].append(segment)

func _nearest_road(point: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_distance := reach
	var center := _cell(point)
	var rings := ceili(reach / 50.0) + 1
	for x in range(center.x - rings, center.x + rings + 1):
		for y in range(center.y - rings, center.y + rings + 1):
			for segment in _road_grid.get(Vector2i(x, y), []):
				if segment.a.distance_to(segment.b) < 0.01:
					continue
				var closest := Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
				var distance := closest.distance_to(point)
				if distance < best_distance:
					best_distance = distance
					var direction: Vector2 = (segment.b - segment.a).normalized()
					best = {"point": closest, "direction": direction, "normal": direction.orthogonal(), "half_width": segment.half_width}
	return best

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 50.0), floori(point.y / 50.0))

func _ground(point: Vector2) -> float:
	return terrain.height_at(point) if terrain else 0.0

## Vertex at a height above the terrain surface.
func _v(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y + _ground(point), point.y)
