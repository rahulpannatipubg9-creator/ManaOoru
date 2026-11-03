class_name TrafficManager
extends Node3D

const VEHICLE_SCENE := preload("res://scenes/traffic/traffic_vehicle.tscn")
@export var max_active_vehicles: int = 25
@export var spawn_min_distance: float = 40.0
@export var spawn_max_distance: float = 90.0
@export var despawn_distance: float = 110.0
@export var spawn_interval: float = 0.3
@export var spawn_clearance: float = 8.0
var vehicle_count: int = 0
var municipal_vehicle_count: int = 0
var bus_vehicle_count: int = 0
var tuk_tuk_count: int = 0
const TrafficLightController := preload("res://scripts/world/traffic_light_controller.gd")
const TrafficVehicle := preload("res://scripts/world/traffic_vehicle.gd")
const TrafficLaneBuilder := preload("res://scripts/world/traffic_lane_builder.gd")
const TrafficStopPoint := preload("res://scripts/world/traffic_stop_point.gd")

var tuk_tuk_near_spawn: bool = false
var profiles: Array = []
var districts: Dictionary = {}
var lanes: Array[Path3D] = []
var fleet: Array[TrafficVehicle] = []
var focus_override: Node3D
var junction: TrafficLightController
var _drivable_vehicles: Array[Node3D] = []
var _game: Node
var _world: Node3D
var _elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_query := PhysicsShapeQueryParameters3D.new()
var _spawn_grid: Dictionary = {}
var junction_center := Vector2.INF
var _candidate_lanes: Array[Path3D] = []
var _candidate_offsets: PackedFloat32Array = PackedFloat32Array()

func setup(world: Node3D, data: MapData) -> void:
	name = "Traffic"
	_world = world
	_game = world.get_parent()
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		max_active_vehicles = 12
		spawn_interval = 0.5
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/traffic_profiles.json"))
	profiles = config.profiles
	districts = config.districts
	_rng.randomize()
	var paths := Node3D.new()
	paths.name = "Lanes"
	paths.visible = false # Organizational nodes must not block pedestrian crossing checks.
	add_child(paths)
	lanes = TrafficLaneBuilder.build(world, data, paths)
	for lane in lanes:
		lane.set_meta("speed_scale", float(districts[lane.get_meta("district")].speed_scale))
		if not bool(lane.get_meta("loop", false)):
			continue
		var length := lane.curve.get_baked_length()
		for i in range(ceili(length / 12.0)):
			_candidate_lanes.append(lane)
			_candidate_offsets.append(minf(length - 0.1, float(i) * 12.0 + 1.0))
	for index in _candidate_lanes.size():
		var point := _candidate_lanes[index].curve.sample_baked(_candidate_offsets[index])
		var cell := Vector2i(floori(point.x / 64.0), floori(point.z / 64.0))
		if not _spawn_grid.has(cell):
			_spawn_grid[cell] = PackedInt32Array()
		_spawn_grid[cell].append(index)
	_create_junction(data)
	call_deferred("_cache_drivable_vehicles")

func focus_position() -> Vector3:
	if is_instance_valid(focus_override):
		return focus_override.global_position
	if _game != null and _game.has_method("tracked_body"):
		var body := _game.tracked_body() as Node3D
		if is_instance_valid(body):
			return body.global_position
	return _world.player_spawn.get("position", Vector3.ZERO)

func _physics_process(delta: float) -> void:
	if _world == null:
		return
	var focus := focus_position()
	for vehicle in fleet:
		if vehicle.active and vehicle.global_position.distance_squared_to(focus) > despawn_distance * despawn_distance:
			vehicle.set_active(false)
	_elapsed += delta
	if _elapsed >= spawn_interval:
		_elapsed = 0.0
		_recount()
		if vehicle_count < max_active_vehicles:
			_try_spawn(focus)
		_recount()

func _recount() -> void:
	vehicle_count = 0
	bus_vehicle_count = 0
	tuk_tuk_count = 0
	for vehicle in fleet:
		if vehicle.active:
			vehicle_count += 1
			if vehicle.vehicle_kind == "bus":
				bus_vehicle_count += 1
			if vehicle.vehicle_kind == "auto":
				tuk_tuk_count += 1

func _try_spawn(focus: Vector3) -> void:
	if _candidate_lanes.is_empty():
		return
	var max_attempts := 15 if (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")) else 80
	for attempt in max_attempts:
		var index := _rng.randi_range(0, _candidate_lanes.size() - 1)
		if not _spawn_grid.is_empty():
			var cell := Vector2i(floori(focus.x / 64.0), floori(focus.z / 64.0)) + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
			if not _spawn_grid.has(cell):
				continue
			var choices: PackedInt32Array = _spawn_grid[cell]
			index = choices[_rng.randi_range(0, choices.size() - 1)]
		var path := _candidate_lanes[index]
		var offset := _candidate_offsets[index]
		var point := path.to_global(path.curve.sample_baked(offset))
		var distance := point.distance_to(focus)
		if distance < spawn_min_distance or distance > spawn_max_distance or Vector2(point.x, point.z).distance_to(junction_center) < 22.0:
			continue
		if path.has_meta("stop") and absf(offset - (path.get_meta("stop") as TrafficStopPoint).progress) < 20.0:
			continue
		var profile := _choose_profile(str(path.get_meta("district")))
		var clear := true
		for other in fleet:
			if other.active and other.global_position.distance_to(point) < maxf(spawn_clearance, (other.vehicle_length + float(profile.length)) * 0.5 + 2.0):
				clear = false
		for obstacle in _drivable_vehicles:
			if is_instance_valid(obstacle) and obstacle.global_position.distance_to(point) < spawn_clearance:
				clear = false
		if not clear:
			continue
		var vehicle: TrafficVehicle
		for pooled in fleet:
			if not pooled.active:
				vehicle = pooled
				break
		if vehicle == null:
			if fleet.size() >= max_active_vehicles:
				return
			vehicle = VEHICLE_SCENE.instantiate() as TrafficVehicle
			vehicle.name = "AmbientTraffic_%02d" % fleet.size()
			vehicle.vehicle_kind = profile.kind
			vehicle.speed = float(profile.max_speed)
			vehicle.acceleration = float(profile.acceleration)
			vehicle.vehicle_length = float(profile.length)
			vehicle.manager = self
			add_child(vehicle)
			vehicle.route_finished.connect(_release)
			fleet.append(vehicle)
		vehicle.configure(profile)
		# Validate the actual body bounds against world and vehicles before activation.
		var query := _spawn_query
		query.shape = vehicle.get_node("CollisionShape3D").shape
		var heading: Vector3 = path.get_meta("heading")
		query.transform = Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.z)), point + Vector3.UP * 0.8)
		query.collision_mask = 9
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		vehicle.activate(path, offset)
		return

func _choose_profile(district: String) -> Dictionary:
	var weights: Dictionary = districts[district].weights
	var total := 0.0
	for profile: Dictionary in profiles:
		total += float(profile.spawn_weight) * float(weights.get(profile.kind, 1.0))
	var choice := _rng.randf() * total
	for profile: Dictionary in profiles:
		choice -= float(profile.spawn_weight) * float(weights.get(profile.kind, 1.0))
		if choice <= 0.0:
			return profile
	return profiles.back()

func _release(vehicle: TrafficVehicle) -> void:
	vehicle.set_active(false)

func free_distance(vehicle: TrafficVehicle, heading: Vector3) -> float:
	var result := INF
	for other in fleet:
		if other == vehicle or not other.active:
			continue
		var offset := other.global_position - vehicle.global_position
		if absf(offset.y) > 3.0:
			continue
		var ahead := offset.dot(heading)
		if ahead > 0.0 and absf(offset.cross(heading).y) < 1.7:
			result = minf(result, maxf(0.0, ahead - (vehicle.vehicle_length + other.vehicle_length) * 0.5 - vehicle.safe_gap))
	return result

func following_limit(vehicle: TrafficVehicle, heading: Vector3, delta: float) -> float:
	var gap := free_distance(vehicle, heading)
	return minf(sqrt(2.0 * vehicle.braking * gap), gap / maxf(delta, 0.001))

func _create_junction(data: MapData) -> void:
	var best_center := Vector2.INF
	var best_distance := INF
	for cluster in SignageBuilder.signal_junctions(data):
		var approaches: Array = _world.signage._approaches(cluster[0])
		if approaches.size() != 4 or approaches.any(func(arm: Dictionary) -> bool: return not bool(arm.inbound)):
			continue
		if cluster[0].length_squared() < best_distance:
			best_distance = cluster[0].length_squared()
			best_center = cluster[0]
	if best_center == Vector2.INF:
		push_error("Traffic: no mapped four-way junction found")
		return
	junction_center = best_center
	var container := Node3D.new()
	container.name = "Junctions"
	container.visible = false
	add_child(container)
	junction = preload("res://scenes/traffic/traffic_junction.tscn").instantiate() as TrafficLightController
	container.add_child(junction)
	# Signal MultiMeshes share phase materials across town. Group 0 is N/S,
	# group 1 E/W, consistently with the signage builder.
	_world.signage.traffic_controller = junction
	for lane in lanes:
		if (lane.get_meta("junction_point") as Vector2).distance_to(best_center) > 3.0:
			continue
		var heading: Vector3 = lane.get_meta("heading")
		var group := 0 if absf(heading.z) >= absf(heading.x) else 1
		var title := "StopNorth" if heading.z > 0.7 else "StopSouth" if heading.z < -0.7 else "StopEast" if heading.x < 0.0 else "StopWest"
		var stop := junction.get_node(title) as TrafficStopPoint
		if stop.controller != null:
			stop = TrafficStopPoint.new()
			stop.name = "LaneStop_%s" % lane.name
			junction.add_child(stop)
		stop.phase_group = group
		stop.controller = junction
		stop.progress = lane.curve.get_baked_length() - 12.0
		stop.global_position = lane.to_global(lane.curve.sample_baked(stop.progress))
		lane.set_meta("stop", stop)

	# Propagate approach stop lines upstream across short source-map sections.
	# Negative progress moves the physical stop onto a preceding section.
	for pass_index in 12:
		var changed := false
		for lane in lanes:
			if lane.has_meta("stop"):
				continue
			var next: Array = lane.get_meta("next")
			if next.is_empty() or not (next[0] as Path3D).has_meta("stop"):
				continue
			var target := next[0] as Path3D
			var downstream := target.get_meta("stop") as TrafficStopPoint
			var target_offset := float(target.get_meta("stop_offset", downstream.progress))
			if target_offset > 18.0:
				continue
			lane.set_meta("stop", downstream)
			lane.set_meta("stop_offset", lane.curve.get_baked_length() + target_offset)
			changed = true
		if not changed:
			break

func _cache_drivable_vehicles() -> void:
	_drivable_vehicles.clear()
	for vehicle in get_tree().get_nodes_in_group("enterable_vehicle"):
		if vehicle is Node3D:
			_drivable_vehicles.append(vehicle)
