class_name TrafficBuilder
extends Node3D

const TrafficVehicleScene := preload("res://scripts/world/traffic_vehicle.gd")
const MAX_TRAFFIC := 10
const TRAFFIC_RADIUS := 1000.0
const COLORS := [Color("#c13d32"), Color("#ece7d9"), Color("#315b91"), Color("#555b5f"), Color("#e0a52e"), Color("#447447")]

var vehicle_count := 0
var municipal_vehicle_count := 0
var bus_vehicle_count := 0
var tuk_tuk_count := 0
var tuk_tuk_near_spawn := false

func build(world: Node, data: MapData) -> void:
	name = "Traffic"
	var candidates: Array[Dictionary] = []
	for road in data.roads:
		if not RoadStyle.is_major(road.kind) and road.kind != "tertiary":
			continue
		if road.points.size() < 2 or road.points[0].length() > TRAFFIC_RADIUS:
			continue
		var length := 0.0
		for index in range(1, road.points.size()):
			length += road.points[index - 1].distance_to(road.points[index])
		if length >= 65.0:
			candidates.append({"road": road, "length": length})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.length > b.length)
	var ordered: Array[Dictionary] = []
	var bus_candidate := _bus_station_candidate(data, candidates)
	var spawn_map := GeoProjection.world_to_map(world.player_spawn.position) if not world.player_spawn.is_empty() else Vector2.ZERO
	var tuk_tuk_candidate := _nearest_candidate(spawn_map, candidates)
	if not bus_candidate.is_empty():
		ordered.append(bus_candidate)
	if not tuk_tuk_candidate.is_empty() and tuk_tuk_candidate != bus_candidate:
		ordered.append(tuk_tuk_candidate)
	for candidate in candidates:
		if candidate != bus_candidate and candidate != tuk_tuk_candidate:
			ordered.append(candidate)
	for index in mini(MAX_TRAFFIC, ordered.size()):
		var road: Dictionary = ordered[index].road
		var route := _left_lane_route(world, road)
		if route.size() < 2:
			continue
		var vehicle := TrafficVehicleScene.new() as TrafficVehicle
		vehicle.name = "AmbientTraffic_%02d" % (index + 1)
		vehicle.route = route
		var surface_height := RoadStyle.surface_height(str(road.kind))
		vehicle.ground_sampler = func(point: Vector2) -> float: return world.ground_height(point) + surface_height
		vehicle.speed = 5.5 + float(index % 4) * 1.0
		# The detailed Tuk Tuk is player-drivable. Ambient vehicles are not, so
		# don't show a second Tuk Tuk that looks usable but cannot be entered.
		vehicle.vehicle_kind = "bus" if index == 0 else ("municipal" if index == 4 else ("auto" if index % 3 == 0 else "car"))
		if index == 2:
			vehicle.vehicle_kind = "scooter"
			vehicle.speed = 3.5
			vehicle.name = "TwoRiderScooter"
		vehicle.body_color = COLORS[index % COLORS.size()]
		vehicle.signal_group = index % 2
		vehicle.signal_controller = world.signage
		for signal_data in data.traffic_signals:
			vehicle.signal_positions.append(GeoProjection.map_to_world(signal_data.position, world.ground_height(signal_data.position)))
		add_child(vehicle)
		vehicle_count += 1
		if vehicle.vehicle_kind == "municipal":
			municipal_vehicle_count += 1
		if vehicle.vehicle_kind == "bus":
			bus_vehicle_count += 1
		if vehicle.vehicle_kind == "tuk_tuk":
			tuk_tuk_count += 1
			tuk_tuk_near_spawn = vehicle.route[0].distance_to(world.player_spawn.position) < 250.0

## Put the one ambient bus on the real road closest to the mapped TGSRTC POI,
## so the people waiting at that terminal are part of a visible service route.
func _bus_station_candidate(data: MapData, candidates: Array[Dictionary]) -> Dictionary:
	var station := Vector2.INF
	for poi in data.pois:
		if str(poi.kind) == "bus_station":
			station = poi.position
			break
	if station == Vector2.INF:
		return {}
	var selected: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var road: Dictionary = candidate.road
		for point: Vector2 in road.points:
			var distance := point.distance_squared_to(station)
			if distance < best_distance:
				best_distance = distance
				selected = candidate
	return selected

func _nearest_candidate(point: Vector2, candidates: Array[Dictionary]) -> Dictionary:
	var selected: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var road: Dictionary = candidate.road
		for sample: Vector2 in road.points:
			var distance := sample.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				selected = candidate
	return selected

func _left_lane_route(world: Node, road: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	var points: PackedVector2Array = road.points
	for index in points.size():
		var direction := (points[min(index + 1, points.size() - 1)] - points[max(index - 1, 0)]).normalized()
		if direction.length_squared() < 0.001:
			continue
		# India drives left: keep each ambient vehicle on the left half of its source road.
		var lane := points[index] - direction.orthogonal() * maxf(1.2, RoadStyle.width(road) * 0.22)
		result.append(GeoProjection.map_to_world(lane, world.ground_height(lane) + RoadStyle.surface_height(str(road.kind))))
	return result
