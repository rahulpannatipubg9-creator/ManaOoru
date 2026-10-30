class_name GpsNavigator
extends Node

## Waypoint navigation over the RoadNetwork. Progress is sampled a few times per
## second from the tracked body (person on foot, occupied vehicle while driving),
## not every frame, and only a short window of the route is searched each update.

signal route_changed

const UPDATE_INTERVAL := 0.2
const PROGRESS_SEARCH_WINDOW := 40
const ARRIVAL_RADIUS := {RoadNetwork.Mode.WALK: 10.0, RoadNetwork.Mode.DRIVE: 18.0}
const OFF_ROUTE_DISTANCE := {RoadNetwork.Mode.WALK: 25.0, RoadNetwork.Mode.DRIVE: 35.0}
const OFF_ROUTE_GRACE_SECONDS := 1.5
const REROUTE_COOLDOWN_MSEC := 2000
const ARRIVED_MESSAGE_SECONDS := 4.0

var network: RoadNetwork
## Returns {position: Vector2, mode: RoadNetwork.Mode} for whatever the player controls.
var tracker: Callable
var has_destination := false
var target := Vector2.ZERO
var destination_name := ""
var mode := RoadNetwork.Mode.WALK
var route := PackedVector2Array()
var remaining_route := PackedVector2Array()
var remaining_distance := 0.0
var error_text := ""
var arrived := false
var _cumulative := PackedFloat32Array()
var _progress_index := 0
var _update_timer := 0.0
var _off_route_time := 0.0
var _last_route_msec := 0
var _arrived_timer := 0.0

func setup(road_network: RoadNetwork, tracked: Callable) -> void:
	network = road_network
	tracker = tracked

## Sets a waypoint at any map point. Returns false (with error_text set) when no road route exists.
func set_destination(point: Vector2, label := "") -> bool:
	has_destination = true
	arrived = false
	target = point
	destination_name = label
	var state: Dictionary = tracker.call()
	mode = state.mode
	return _compute_route(state.position)

func clear() -> void:
	has_destination = false
	arrived = false
	destination_name = ""
	error_text = ""
	_set_route(PackedVector2Array())
	route_changed.emit()

## Text for the HUD: distance, arrival, or why no route could be drawn.
func status_text() -> String:
	if arrived:
		return "Destination reached"
	if not has_destination:
		return ""
	if not error_text.is_empty():
		return "GPS: %s" % error_text
	var label := destination_name if not destination_name.is_empty() else "Waypoint"
	return "%s  •  %s  •  %s" % [label, format_distance(remaining_distance), "Drive" if mode == RoadNetwork.Mode.DRIVE else "Walk"]

## Map point the destination marker should use: the end of the road route when one exists.
func marker_point() -> Variant:
	if not has_destination:
		return null
	return route[route.size() - 1] if route.size() >= 2 else target

static func format_distance(meters: float) -> String:
	if meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	return "%d m" % int(roundf(meters / 10.0) * 10.0)

func _process(delta: float) -> void:
	if arrived:
		_arrived_timer -= delta
		if _arrived_timer <= 0.0:
			clear()
		return
	if not has_destination:
		return
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	var elapsed := _update_timer
	_update_timer = 0.0
	var state: Dictionary = tracker.call()
	var position: Vector2 = state.position
	if state.mode != mode:
		mode = state.mode
		_compute_route(position)
		return
	if route.size() < 2:
		if Time.get_ticks_msec() - _last_route_msec > REROUTE_COOLDOWN_MSEC:
			_compute_route(position)
		return
	var deviation := _update_progress(position)
	if route[route.size() - 1].distance_to(position) <= ARRIVAL_RADIUS[mode]:
		arrived = true
		_arrived_timer = ARRIVED_MESSAGE_SECONDS
		_set_route(PackedVector2Array())
		route_changed.emit()
		return
	if deviation > OFF_ROUTE_DISTANCE[mode]:
		_off_route_time += elapsed
		if _off_route_time >= OFF_ROUTE_GRACE_SECONDS and Time.get_ticks_msec() - _last_route_msec > REROUTE_COOLDOWN_MSEC:
			_compute_route(position)
			return
	else:
		_off_route_time = 0.0
	route_changed.emit()

func _compute_route(from: Vector2) -> bool:
	_last_route_msec = Time.get_ticks_msec()
	_off_route_time = 0.0
	var result := network.find_route(from, target, mode)
	error_text = result.error
	_set_route(result.points)
	if result.ok:
		_update_progress(from)
	route_changed.emit()
	return result.ok

func _set_route(points: PackedVector2Array) -> void:
	route = points
	remaining_route = points
	_progress_index = 0
	_cumulative = PackedFloat32Array([0.0])
	for index in range(1, points.size()):
		_cumulative.append(_cumulative[index - 1] + points[index - 1].distance_to(points[index]))
	remaining_distance = _cumulative[_cumulative.size() - 1] if points.size() >= 2 else 0.0

## Moves the progress marker to the closest point on the route ahead and returns
## the distance from the player to the route.
func _update_progress(position: Vector2) -> float:
	var best_index := _progress_index
	var best_point := route[_progress_index]
	var best_distance := INF
	var last_segment := mini(_progress_index + PROGRESS_SEARCH_WINDOW, route.size() - 2)
	for index in range(maxi(_progress_index - 2, 0), last_segment + 1):
		var closest := Geometry2D.get_closest_point_to_segment(position, route[index], route[index + 1])
		var distance := closest.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
			best_point = closest
	_progress_index = best_index
	remaining_distance = _cumulative[_cumulative.size() - 1] - _cumulative[best_index] - route[best_index].distance_to(best_point)
	remaining_route = PackedVector2Array([best_point])
	remaining_route.append_array(route.slice(best_index + 1))
	return best_distance
