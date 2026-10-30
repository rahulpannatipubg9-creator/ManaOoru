class_name CityCommunity
extends Node3D
## Small, bounded routines and hometown identity details. New props are game
## scenery, positioned outside the existing carriageways and source footprints.
const Resident := preload("res://scenes/world/pedestrian.tscn")
var talking_residents := 0
var shop_routines := 0
var identity_markers: Array[Dictionary] = []
var _world: Node
var _elapsed := 0.0
var _waiting: Array[Node3D] = []

func setup(world: Node) -> void:
	_world = world
	var spots: Array[Dictionary] = world.roadside_spots(Vector2.ZERO, 12, 3.4, 24.0, ["residential", "unclassified", "tertiary", "secondary"])
	for i in mini(6, spots.size()):
		var spot: Dictionary = spots[i]
		var direction := Vector3(spot.direction.x, 0.0, spot.direction.y)
		for side: float in [-1.0, 1.0]:
			var p: Vector2 = spot.position + spot.direction * side * 0.75
			if not world.buildings.is_clear(p, 2.1) or world._is_on_any_road(p, 0.35):
				continue
			var person: Node3D = Resident.instantiate()
			person.name = "TalkingResident_%02d" % talking_residents
			person.position = GeoProjection.map_to_world(p, ground_y(p) - 0.07)
			person.walk_direction = direction * -side
			person.idle_mode = true
			person.talking_mode = true
			person.sway_offset = float(i) * 1.7 + side
			person.shirt_color = [Color("#9d693e"), Color("#386f76"), Color("#795588")][i % 3]
			add_child(person)
			talking_residents += 1
	# Existing visitors keep their counts and identities; a few now approach the
	# shop threshold, briefly disappear inside, and return along the same safe path.
	for person: Node in world.local_activity.get_children():
		if not person is Node3D or not person.name.begins_with("ShopVisitor"):
			continue
		var a: Vector3 = person.position
		var tangent: Vector3 = person.walk_direction
		var b := a + tangent * 1.6
		if _safe_path(a, b):
			person.activity_route = PackedVector3Array([a, b])
			person.activity_wait_seconds = 8.0 + shop_routines * 0.8
			person.hide_at_destination = true
			shop_routines += 1
	# Short doorstep routines use actual allocated frontage anchors rather than
	# disappearing at an arbitrary point along the pavement.
	var doorway_visitors := 0
	for unit: Dictionary in world.buildings.storefront_allocator.units:
		if doorway_visitors >= 6 or str(unit.business_id).is_empty() or Vector2(unit.entrance).length() > 1300.0:
			continue
		var normal: Vector2 = unit.normal
		var front: Vector2 = unit.entrance + normal * 1.5
		var door: Vector2 = unit.entrance + normal * 0.65
		var a := GeoProjection.map_to_world(front, ground_y(front) - 0.07)
		var b := GeoProjection.map_to_world(door, ground_y(door) - 0.07)
		if not _safe_path(a, b):
			continue
		var visitor: Node3D = Resident.instantiate()
		visitor.name = "DoorstepVisitor_%02d" % doorway_visitors
		visitor.position = a
		visitor.activity_route = PackedVector3Array([a, b])
		visitor.activity_wait_seconds = 7.0 + doorway_visitors
		visitor.hide_at_destination = true
		visitor.shirt_color = Color("#8b5940")
		add_child(visitor)
		doorway_visitors += 1
		shop_routines += 1
	for person: Node in world.local_activity.get_children():
		if person.name.begins_with("BusPassenger"):
			person.idle_mode = true
			person.talking_mode = true
			_waiting.append(person)
	for person: Node in world.find_children("*", "Node3D", true, false):
		if person.get_script() == preload("res://scripts/world/pedestrian.gd"):
			person.ground_sampler = ground_y
			if person.crossing_mode:
				person.crossing_guard = crossing_clear
	for child in get_children():
		if child.get_script() == preload("res://scripts/world/pedestrian.gd"):
			child.ground_sampler = ground_y
	_build_identity()

func ground_y(point: Vector2) -> float:
	var height: float = _world.ground_height(point) - 0.2
	var road: Dictionary = _world.signage._nearest_road(point, 12.0)
	if not road.is_empty() and point.distance_to(road.point) <= float(road.half_width) + 1.0:
		height = _world.ground_height(point) + (0.04 if point.distance_to(road.point) <= float(road.half_width) else 0.005)
	for unit: Dictionary in _world.buildings.storefront_allocator.units:
		var delta: Vector2 = point - unit.entrance
		var normal: Vector2 = unit.normal
		var out := delta.dot(normal)
		if out >= 0.0 and out <= BuildingBuilder.APRON_DEPTH and absf(delta.dot(normal.orthogonal())) < float(unit.width) * 0.5:
			var meta: Dictionary = _world.buildings.building_metadata[unit.building_index]
			height = maxf(height, float(meta.base) + BuildingBuilder.APRON_HEIGHT)
	return height

func _safe_path(a: Vector3, b: Vector3) -> bool:
	for i in 8:
		var p := Vector2(lerpf(a.x, b.x, float(i) / 7.0), lerpf(a.z, b.z, float(i) / 7.0))
		if not _world.buildings.is_clear(p, 0.5) or _world._is_on_any_road(p, 0.3):
			return false
	return true

func crossing_clear(a: Vector3, b: Vector3) -> bool:
	for vehicle: Node3D in _world.traffic.get_children():
		if not vehicle.visible:
			continue
		if _distance_to_path(vehicle.position, a, b) < 13.0:
			return false
	var game := _world.get_parent()
	if game.get("vehicles") != null:
		for vehicle: Node3D in game.vehicles:
			if vehicle is RigidBody3D and vehicle.linear_velocity.length() > 1.0 and _distance_to_path(vehicle.position, a, b) < 13.0:
				return false
	return true

func _distance_to_path(point: Vector3, a: Vector3, b: Vector3) -> float:
	return Vector2(point.x, point.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z)))

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0.0
	for i in _waiting.size():
		var person: Node3D = _waiting[i]
		# Short boarding/return beats occur only when a service bus is nearby.
		var bus_near := false
		for vehicle: Node in _world.traffic.get_children():
			if vehicle is TrafficVehicle and vehicle.vehicle_kind == "bus" and vehicle.position.distance_to(person.position) < 18.0:
				bus_near = true
		if bus_near and person.activity_route.is_empty():
			var start: Vector3 = person.position
			var end: Vector3 = start + person.walk_direction * 1.0
			if _safe_path(start, end):
				person.activity_route = PackedVector3Array([start, end])
				person.activity_wait_seconds = 18.0 + i * 1.5
				person.hide_at_destination = true
				person.idle_mode = false

func _build_identity() -> void:
	var center: Vector2 = _world.player_spawn.position.x * Vector2.RIGHT + _world.player_spawn.position.z * Vector2.DOWN if not _world.player_spawn.is_empty() else Vector2.ZERO
	_add_plaque(center + Vector2(18, 5), "CHOWRASTHA\nGODAVARIKHANI", "Chowrastha streets", Color("#b46d32"))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(StreetLifeBuilder.DATA_PATH))
	if parsed is Dictionary:
		for market: Dictionary in parsed.get("markets", []):
			var p := GeoProjection.lon_lat_to_map(float(market.lon), float(market.lat))
			_add_plaque(p, str(market.name).to_upper() + "\nLOCAL MARKET", str(market.name), Color("#865e37"))
		for gate: Dictionary in parsed.get("entrances", []):
			var p := GeoProjection.lon_lat_to_map(float(gate.lon), float(gate.lat))
			if identity_markers.size() < 10:
				_add_plaque(p, str(gate.get("name", gate.get("colony", "COLONY"))).to_upper() + "\nWELCOME HOME", str(gate.get("name", gate.get("colony", "Colony entrance"))), Color("#497c69"))
	if _world.coal_mine:
		_add_plaque(Vector2(_world.coal_mine.position.x, _world.coal_mine.position.z) + Vector2(12, 0), "SINGARENI COAL BELT\nMINERS OF GODAVARIKHANI", "Coal-town heritage", Color("#b3893d"))

func _add_plaque(near: Vector2, text: String, title: String, color: Color) -> void:
	var spots: Array[Dictionary] = _world.roadside_spots(near, 1, 4.3, 1.0, ["secondary", "tertiary", "residential", "unclassified"])
	if spots.is_empty() or Vector2(spots[0].position).distance_to(near) > 180.0:
		return
	var point: Vector2 = spots[0].position
	for existing: Dictionary in identity_markers:
		if point.distance_to(Vector2(existing.position.x, existing.position.z)) < 15.0:
			return
	var position := GeoProjection.map_to_world(point, _world.ground_height(point))
	var plaque := Node3D.new()
	plaque.position = position
	plaque.rotation.y = atan2(spots[0].direction.x, spots[0].direction.y)
	add_child(plaque)
	_box(plaque, Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 0.65), Color("#67645c"))
	_box(plaque, Vector3(0, 1.55, 0), Vector3(2.0, 1.6, 0.18), color)
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.007
	label.position = Vector3(0, 1.65, 0.11)
	label.modulate = Color("#fff0ce")
	label.outline_size = 6
	label.no_depth_test = false
	plaque.add_child(label)
	# Decorative festival bunting above the plaque, away from travel space.
	for i in 5:
		_box(plaque, Vector3((i - 2) * 0.37, 2.7 - absf(i - 2) * 0.06, 0), Vector3(0.23, 0.32, 0.035), [Color("#ce7038"), Color("#d7ba62"), Color("#538876")][i % 3])
	identity_markers.append({"position": position, "name": title, "source": "representative_game_detail"})

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
