class_name LocalActivityBuilder
extends Node3D

## Small, deterministic resident routines near the bus station and real mapped
## shops.  These are deliberately lightweight: pedestrians share one simple
## scene and walk short pavement routes, making the town feel occupied without
## creating a crowd of expensive skinned characters.

const PEDESTRIAN_SCENE := preload("res://scenes/world/pedestrian.tscn")
const MAX_SHOP_VISITORS := 10
const MAX_CROSSING_PAIRS := 3
const SHIRTS := [Color("#2d6b4f"), Color("#354e83"), Color("#a34c35"), Color("#704a2e"), Color("#755491")]
const SKINS := [Color("#7d4733"), Color("#a96b4a"), Color("#c98a64"), Color("#6d3f2d")]
const ACTIVE_SHOP_KINDS := ["bakery", "tea", "general", "wine", "butcher", "dairy", "convenience", "supermarket", "fast_food", "pharmacy", "greengrocer", "car_wash", "fuel"]

var shop_visitor_count := 0
var bus_passenger_count := 0
var crossing_pedestrian_count := 0
var shopkeeper_count := 0
## Each entry is {position: Vector3, name: String}; queried by the player for
## a simple offline shop interaction, rather than putting invisible areas on
## every map POI.
var shop_entries: Array[Dictionary] = []

func build(world: Node, data: MapData, bus_station: BusStationBuilder) -> void:
	name = "LocalActivity"
	_add_bus_passengers(world, bus_station)
	_add_shop_visitors(world, data)
	_add_crossing_pedestrians(world, data)

func _add_bus_passengers(world: Node, bus_station: BusStationBuilder) -> void:
	for index in bus_station.passenger_spots.size():
		var at := bus_station.passenger_spots[index]
		var resident: Variant = _new_resident("BusPassenger_%02d" % (index + 1), index)
		var platform_y: float = at.y + 0.36
		resident.ground_sampler = func(_point: Vector2) -> float: return platform_y
		resident.position = at
		resident.walk_direction = Vector3.FORWARD if index % 2 == 0 else Vector3.RIGHT
		resident.patrol_distance = 1.15
		resident.walk_speed = 0.48
		add_child(resident)
		bus_passenger_count += 1

func _add_shop_visitors(world: Node, data: MapData) -> void:
	var selected := 0
	for poi in data.pois:
		if selected >= MAX_SHOP_VISITORS:
			break
		if str(poi.kind) not in ACTIVE_SHOP_KINDS or poi.position.length() > 1050.0:
			continue
		var road: Dictionary = world.signage._nearest_road(poi.position, 40.0)
		if road.is_empty():
			continue
		var side := 1.0 if (poi.position - road.point).dot(road.normal) >= 0.0 else -1.0
		var pavement: Vector2 = road.point + road.normal * side * (road.half_width + 1.55)
		if not world.buildings.is_clear(pavement, 0.35):
			continue
		var resident: Variant = _new_resident("ShopVisitor_%02d" % (selected + 1), selected + 10)
		resident.ground_sampler = resident.sample_world_surface.bind(world)
		resident.position = GeoProjection.map_to_world(pavement, world.ground_height(pavement))
		resident.walk_direction = Vector3(road.direction.x, 0.0, road.direction.y)
		resident.patrol_distance = 2.6 + float(selected % 3) * 0.7
		resident.walk_speed = 0.60 + float(selected % 2) * 0.08
		add_child(resident)
		var shop_name := str(poi.name).strip_edges()
		if shop_name.is_empty():
			shop_name = str(poi.kind).replace("_", " ").capitalize()
		shop_entries.append({"position": resident.position, "name": shop_name, "kind": str(poi.kind)})
		var keeper: Variant = _new_resident("Shopkeeper_%02d" % (shopkeeper_count + 1), selected + 30)
		keeper.ground_sampler = keeper.sample_world_surface.bind(world)
		keeper.position = resident.position - resident.walk_direction * 0.85
		keeper.walk_direction = -resident.walk_direction
		keeper.idle_mode = true
		add_child(keeper)
		shopkeeper_count += 1
		selected += 1
		shop_visitor_count += 1

func _add_crossing_pedestrians(world: Node, data: MapData) -> void:
	var pairs := 0
	for crossing in data.crossings:
		if pairs >= MAX_CROSSING_PAIRS or crossing.length() > 1100.0:
			continue
		var road: Dictionary = world.signage._nearest_road(crossing, 14.0)
		if road.is_empty():
			continue
		var normal: Vector2 = road.normal
		var distance: float = float(road.half_width) + 1.25
		for side in [-1.0, 1.0]:
			var start_map: Vector2 = road.point + normal * side * distance
			var target_map: Vector2 = road.point - normal * side * distance
			var resident: Variant = _new_resident("CrossingResident_%02d" % (crossing_pedestrian_count + 1), crossing_pedestrian_count + 20)
			resident.ground_sampler = resident.sample_world_surface.bind(world)
			resident.position = GeoProjection.map_to_world(start_map, world.ground_height(start_map))
			resident.crossing_mode = true
			resident.crossing_target = GeoProjection.map_to_world(target_map, world.ground_height(target_map))
			resident.crossing_wait_seconds = 2.8 + float(crossing_pedestrian_count % 2) * 0.8
			resident.walk_speed = 0.9
			resident.traffic_signal = world.signage
			resident.traffic_group = 0
			add_child(resident)
			crossing_pedestrian_count += 1
		pairs += 1

func nearest_shop(world_position: Vector3, radius: float = 3.4) -> Dictionary:
	var nearest: Dictionary = {}
	var best := radius * radius
	for entry in shop_entries:
		var distance: float = world_position.distance_squared_to(entry.position)
		if distance < best:
			best = distance
			nearest = entry
	return nearest

func _new_resident(resident_name: String, palette: int) -> Variant:
	var resident := PEDESTRIAN_SCENE.instantiate()
	resident.name = resident_name
	resident.sway_offset = float(palette) * 0.73
	resident.shirt_color = SHIRTS[palette % SHIRTS.size()]
	resident.skin_color = SKINS[palette % SKINS.size()]
	return resident
