extends SceneTree

const EPSILON := 0.01

func _init() -> void:
	_test_projection()
	var data := MapData.load_shared()
	_check(data.is_valid, "Bundled OSM extract must load offline")
	var network := RoadNetwork.new(data)
	_test_routing(network)
	await _test_world_alignment(data)
	await _test_game_flow()
	if _failures > 0:
		print("FAIL navigation regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS navigation regression: projection, alignment, A* routing, one-way, minimap, full map, touch, GPS progress/reroute/arrival, walk/drive handover")
	quit()

func _test_projection() -> void:
	var origin := GeoProjection.lon_lat_to_map(GeoProjection.ORIGIN_LON, GeoProjection.ORIGIN_LAT)
	_check(origin.length() < EPSILON, "Projection origin must map to world (0, 0)")
	var north := GeoProjection.lon_lat_to_map(GeoProjection.ORIGIN_LON, GeoProjection.ORIGIN_LAT + 0.001)
	_check(absf(north.y + 111.0) < 0.1 and absf(north.x) < EPSILON, "0.001° north must be 111 m toward -Z")
	var east := GeoProjection.lon_lat_to_map(GeoProjection.ORIGIN_LON + 0.001, GeoProjection.ORIGIN_LAT)
	_check(east.x > 104.0 and east.x < 106.0 and absf(east.y) < EPSILON, "0.001° east must be ~105 m toward +X")
	var point := Vector2(-532.0, -910.0)
	var lon_lat := GeoProjection.map_to_lon_lat(point)
	var round_trip := GeoProjection.lon_lat_to_map(lon_lat[0], lon_lat[1])
	_check(round_trip.distance_to(point) < EPSILON, "Projection must round-trip")

func _test_routing(network: RoadNetwork) -> void:
	_check(network.main_component_size(RoadNetwork.Mode.DRIVE) > 5000, "Drivable network must be connected")
	var bus_station := Vector2(-532.0, -910.0)
	var started := Time.get_ticks_usec()
	var drive := network.find_route(Vector2(116.0, -105.0), bus_station, RoadNetwork.Mode.DRIVE)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	_check(drive.ok, "Drive route to the bus station must exist: %s" % drive.error)
	_check(elapsed_ms < 50.0, "A* must stay well inside a frame budget (took %.1f ms)" % elapsed_ms)
	var straight := Vector2(116.0, -105.0).distance_to(bus_station)
	_check(drive.length >= straight * 0.9, "Road route cannot be shorter than the straight line")
	for index in range(1, drive.points.size() - 2):
		_check(_is_graph_edge(network, drive.points[index], drive.points[index + 1]),
			"Route interior must follow road graph edges only")
	var failure := network.find_route(Vector2.ZERO, Vector2(2950.0, 0.0), RoadNetwork.Mode.DRIVE)
	_check(not failure.ok and failure.points.is_empty() and not failure.error.is_empty(),
		"Unroutable destination must report an error, not a fake straight line")
	var oneway_edge := -1
	for edge in network.edge_count():
		var flags := network.edge_flags[edge]
		if flags & RoadNetwork.FLAG_DRIVE_FORWARD and not flags & RoadNetwork.FLAG_DRIVE_BACKWARD \
				and network.edge_length[edge] > 30.0:
			oneway_edge = edge
			break
	_check(oneway_edge != -1, "Extract must contain a one-way road to test")
	var a := network.node_positions[network.edge_a[oneway_edge]]
	var b := network.node_positions[network.edge_b[oneway_edge]]
	var against_from := a.lerp(b, 0.8)
	var against_to := a.lerp(b, 0.2)
	var walk_against := network.find_route(against_from, against_to, RoadNetwork.Mode.WALK)
	var drive_against := network.find_route(against_from, against_to, RoadNetwork.Mode.DRIVE)
	var drive_with := network.find_route(against_to, against_from, RoadNetwork.Mode.DRIVE)
	_check(walk_against.ok and absf(walk_against.length - against_from.distance_to(against_to)) < 1.0,
		"Walking may use a one-way road in either direction")
	_check(drive_with.ok and absf(drive_with.length - against_from.distance_to(against_to)) < 1.0,
		"Driving with the one-way direction must use the road directly")
	_check(not drive_against.ok or drive_against.length > walk_against.length + 5.0,
		"Driving must not go against a one-way road")

func _is_graph_edge(network: RoadNetwork, from: Vector2, to: Vector2) -> bool:
	var snapped := network.snap((from + to) * 0.5, RoadNetwork.Mode.DRIVE, 1.0)
	if snapped.is_empty():
		return false
	var a := network.node_positions[network.edge_a[snapped.edge]]
	var b := network.node_positions[network.edge_b[snapped.edge]]
	return (a.is_equal_approx(from) and b.is_equal_approx(to)) or (a.is_equal_approx(to) and b.is_equal_approx(from))

## The 3D world must match the map: every road centreline and both carriageway
## edges have road surface under them, and buildings stand on their footprints.
func _test_world_alignment(data: MapData) -> void:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	world.buildings.build_all()
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var samples := 0
	var misses := 0
	for road in data.roads:
		var points: PackedVector2Array = road.points
		var half := RoadStyle.width(road) * 0.5
		for index in range(1, points.size()):
			if points[index - 1].distance_to(points[index]) < 1.0:
				continue
			# Off the exact midpoint: that lies on a quad diagonal, where ray tests are unreliable.
			var middle := points[index - 1].lerp(points[index], 0.37)
			var side := (points[index] - points[index - 1]).normalized().orthogonal()
			for offset in [0.0, half * 0.9, -half * 0.9]:
				samples += 1
				if not _ray_hits(space, middle + side * offset, RoadBuilder.ROAD_LAYER):
					misses += 1
	_check(samples > 5000 and misses == 0, "Road surface must cover every centreline and both edges (%d/%d missing)" % [misses, samples])
	var building_samples := 0
	var building_hits := 0
	for index in range(0, world.rendered_building_footprints.size(), 25):
		var footprint: PackedVector2Array = world.rendered_building_footprints[index]
		var center := Vector2.ZERO
		for point in footprint:
			center += point
		# Nudge off the centroid: on rectangles it lies exactly on the roof's triangle diagonal.
		center = center / footprint.size() + Vector2(0.137, 0.091)
		if not Geometry2D.is_point_in_polygon(center, footprint):
			continue
		building_samples += 1
		var ground_y := data.terrain.height_at(center)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(center.x, ground_y + 80.0, center.y), Vector3(center.x, ground_y - 5.0, center.y), 1))
		if not hit.is_empty() and hit.position.y > ground_y + 1.8 and String(hit.collider.get_parent().name).begins_with("BuildingChunk"):
			building_hits += 1

	_check(building_samples > 300 and building_hits == building_samples,
		"Buildings must stand on their mapped footprints (%d/%d)" % [building_hits, building_samples])
	_check(world.rendered_building_footprints.size() > 15000, "OSM and Microsoft buildings must both be built")
	_check(world.roads.rendered_way_ids.size() >= data.source_road_way_count - 10, "Every mapped road must be rendered")
	_check(world.signage.board_count > 100, "Mapped places must get name boards")
	var names := []
	for landmark in data.landmarks:
		names.append(landmark.name.to_lower())
	for expected in ["jawaharlal nehru stadium", "sccl school", "tgsrtc  bus station , godavarikhani", "ram mandir"]:
		_check(expected in names, "Landmark missing from map data: %s" % expected)
	# Signals stand at every main-road junction, never at the Chowrastha roundabout.
	var junctions := SignageBuilder.signal_junctions(data)
	_check(junctions.size() > 200 and world.signage.signal_count > 200, "Main-road junctions must get traffic signals (%d)" % world.signage.signal_count)
	for junction in junctions:
		_check(junction[0].length() > 15.0, "The Chowrastha roundabout must not be signalised")
	# Traffic signals mapped in OSM or listed locally are added too; check with one injected junction.
	var junction: Vector2 = data.roads[0].points[0]
	for road in data.roads:
		if road.kind == "secondary":
			junction = road.points[road.points.size() - 1]
			break
	data.traffic_signals.append({"position": junction, "source": "test"})
	var signage := SignageBuilder.new()
	root.add_child(signage)
	signage.build(data, world.buildings)
	data.traffic_signals.pop_back()
	_check(signage.signal_count >= 1, "A mapped signal junction must get signal poles on its approaches")
	signage._process(1.0)
	var lit := 0
	for group in signage._signal_lights.values():
		for material: StandardMaterial3D in group.values():
			if material.emission_energy_multiplier > 0.0:
				lit += 1
	_check(lit == signage._signal_lights.size(), "Exactly one lamp per signal group must be lit")
	signage.queue_free()
	# Terrain: real relief, and the collision surface matches TerrainData everywhere in the district.
	_check(data.terrain.is_valid and data.terrain.max_height - data.terrain.min_height > 20.0, "Terrain relief must be loaded")
	var terrain_misses := 0
	for step in 200:
		var probe := Vector2(randf_range(-2900.0, 2900.0), randf_range(-2900.0, 2900.0))
		var expected := data.terrain.height_at(probe)
		var query := PhysicsRayQueryParameters3D.create(Vector3(probe.x, expected + 200.0, probe.y), Vector3(probe.x, expected - 50.0, probe.y), 1)
		query.exclude = []
		var hits := 0
		var found := false
		while hits < 6:
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			if hit.collider.get_parent() != null and String(hit.collider.name).begins_with("Terrain_"):
				found = absf(hit.position.y - expected) < 0.05
				break
			query.exclude = query.exclude + [hit.rid]
			hits += 1
		if not found:
			terrain_misses += 1
	_check(terrain_misses == 0, "Terrain collision must match terrain heights (%d/200 off)" % terrain_misses)
	_check(data.building_heights.is_valid and world.buildings.measured_height_count > 15000, "Measured building heights must be used")
	world.queue_free()
	await process_frame

func _ray_hits(space: PhysicsDirectSpaceState3D, point: Vector2, layer: int) -> bool:
	var ground_y := MapData.load_shared().terrain.height_at(point)
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, ground_y + 5.0, point.y), Vector3(point.x, ground_y - 2.0, point.y), 1 << (layer - 1))
	return not space.intersect_ray(query).is_empty()

func _test_game_flow() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	# Cars are live rigid bodies: let them settle onto their springs and fall asleep first.
	for _frame in 60:
		await physics_frame
	var person := game.get_node("Player") as CharacterBody3D
	var car := game.get_node("Vehicle") as PhysicsBody3D
	var minimap: Minimap = game.hud.minimap
	var navigator: GpsNavigator = game.navigator
	var parked: Dictionary = {}
	var world_buildings: BuildingBuilder = game.get_node("World").buildings
	for vehicle in game.vehicles:
		parked[vehicle] = vehicle.global_position
		_check(world_buildings.is_clear(GeoProjection.world_to_map(vehicle.global_position), 1.5),
			"Parked cars must be on open roadside, not inside buildings")
	_check(world_buildings.is_clear(GeoProjection.world_to_map(person.global_position), 0.8), "Player must spawn in the open")

	# Minimap follows the person: player marker sits exactly at the minimap centre.
	minimap.refresh()
	var canvas := minimap.canvas
	_check(canvas.map_to_screen(GeoProjection.world_to_map(person.global_position)).distance_to(canvas.size * 0.5) < 0.5,
		"Minimap must be centred on the person on foot")
	_check(canvas.vehicles.size() == game.vehicles.size(), "All cars must show as minimap icons while walking")
	minimap.toggle_orientation()
	person.rotation.y = 1.0
	minimap.refresh()
	var arrow := canvas.map_transform().basis_xform(canvas.player_heading).normalized()
	_check(arrow.distance_to(Vector2.UP) < 0.01, "Heading-up minimap must point the arrow up")
	minimap.toggle_orientation()
	person.rotation.y = 0.0

	# Waypoint, route, progress and arrival on foot.
	_check(navigator.set_destination(Vector2(-532.0, -910.0), "Bus station"), "Walking route must be found")
	var full_length := navigator.remaining_distance
	_check(full_length > 1000.0, "Route length must be reported")
	var midpoint := navigator.route[navigator.route.size() / 2]
	person.global_position = GeoProjection.map_to_world(midpoint, 1.2)
	await _wait_gps()
	_check(navigator.remaining_distance < full_length - 200.0, "Remaining distance must shrink as the person progresses")
	_check(navigator.error_text.is_empty(), "Progress along the route must not trigger an error")

	# Deviation triggers a reroute from the new position.
	var route_before := navigator.route
	person.global_position = GeoProjection.map_to_world(_point_away_from(navigator.route, midpoint, 80.0), 1.2)
	for _attempt in 15:
		await _wait_gps()
	_check(navigator.route != route_before, "Leaving the route must trigger recalculation")

	# Arrival.
	person.global_position = GeoProjection.map_to_world(navigator.route[navigator.route.size() - 1], 1.2)
	await _wait_gps()
	_check(navigator.arrived and navigator.status_text() == "Destination reached", "Arrival must be announced")
	navigator.clear()

	# Driving: GPS switches to the vehicle and drive mode; parked cars stay put.
	person.global_position = car.global_position + car.global_transform.basis.x * -1.6
	await process_frame
	game.enter_vehicle(car)
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	_check(game.tracked_body() == car, "Minimap/GPS must track the occupied vehicle")
	_check(navigator.set_destination(Vector2(6.0, -6.0), "Chowrastha"), "Drive route to Chowrastha must be found")
	_check(navigator.mode == RoadNetwork.Mode.DRIVE, "Route must use drive mode while driving")
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 60:
		await physics_frame
	car.set_touch_move_input(Vector2.ZERO)
	minimap.refresh()
	_check(canvas.view_center.distance_to(GeoProjection.world_to_map(car.global_position)) < 0.5,
		"Minimap must follow the vehicle while driving")
	_check(canvas.vehicles.size() == game.vehicles.size() - 1, "The occupied car is the player arrow, not an icon")
	for vehicle in game.vehicles:
		if vehicle != car:
			_check(vehicle.global_position.distance_to(parked[vehicle]) < 0.01, "Parked cars must not move while driving with GPS")

	# Full map pauses gameplay and resumes it unchanged.
	game.set_map_open(true)
	_check(paused and game.hud.full_map.visible and not minimap.visible, "M must open the full map and pause gameplay")
	var frozen := car.global_position
	car.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 20:
		await physics_frame
	_check(car.global_position.distance_to(frozen) < 0.001, "Vehicle must not move while the map is open")
	car.set_touch_move_input(Vector2.ZERO)

	# Touch: drag pans, pinch zooms, tap places a waypoint.
	var full_map: FullMap = game.hud.full_map
	full_map._search.text = "ENTRANCE OF VIDYA NAGAR 2"
	full_map._on_search_changed(full_map._search.text)
	_check(full_map._results.get_child_count() > 0, "Full map location search must show source-backed matches")
	var entrance_button := full_map._results.get_child(0) as Button
	_check(entrance_button != null and not entrance_button.disabled,
		"Mapped Vidya Nagar 2 entrance should appear as a usable search result")
	full_map._search.text = "SS Mobiles"
	full_map._on_search_changed(full_map._search.text)
	var candidate_buttons := 0
	for child in full_map._results.get_children():
		if child is Button:
			candidate_buttons += 1
			_check(child.disabled, "Unlocated candidate names must not be routeable from the full map")
	_check(candidate_buttons > 0, "Candidate-only shop name should appear as a clearly disabled lead")
	full_map._search.clear()
	var map_center := full_map.canvas.view_center
	_touch(0, Vector2(900, 500), true)
	_drag(0, Vector2(960, 500), Vector2(60, 0))
	_touch(0, Vector2(960, 500), false)
	_check(full_map.canvas.view_center.x < map_center.x - 1.0, "Touch drag must pan the map")
	var zoom := full_map.canvas.pixels_per_meter
	_touch(0, Vector2(800, 400), true)
	_touch(1, Vector2(900, 400), true)
	_drag(1, Vector2(1000, 400), Vector2(100, 0))
	_touch(1, Vector2(1000, 400), false)
	_touch(0, Vector2(800, 400), false)
	_check(full_map.canvas.pixels_per_meter > zoom * 1.5, "Pinch must zoom the map")
	full_map.canvas.view_center = Vector2(-532.0, -910.0)
	full_map.canvas.pixels_per_meter = 1.0
	var tap := full_map.canvas.get_global_transform() * full_map.canvas.map_to_screen(Vector2(-532.0, -910.0))
	_touch(0, tap, true)
	_touch(0, tap, false)
	_check(navigator.has_destination and navigator.target.distance_to(Vector2(-532.0, -910.0)) < 2.0,
		"Tapping the map must place the waypoint where tapped")
	_check(navigator.route.size() >= 2, "Tapped waypoint must produce a drive route")

	game.set_map_open(false)
	_check(not paused and minimap.visible, "Closing the map must resume gameplay")

	# Exit: tracking returns to the person and the waypoint continues in walk mode.
	# Lifting off only coasts, so brake to a stop like a driver would before getting out.
	car.set_touch_move_input(Vector2(0.0, 1.0))
	for _frame in 40:
		await physics_frame
	car.set_touch_move_input(Vector2.ZERO)
	for _frame in 20:
		await physics_frame
	_check(absf(car.current_speed) <= game.exit_speed_limit, "Car must have stopped before exiting")
	game.exit_vehicle()
	for _frame in 300:
		if game.control_state == game.ControlState.ON_FOOT:
			break
		await physics_frame
	await _wait_gps()
	_check(game.tracked_body() == person, "Tracking must return to the person after exiting")
	_check(navigator.has_destination and navigator.mode == RoadNetwork.Mode.WALK and navigator.route.size() >= 2,
		"Waypoint navigation must continue on foot after exiting")

	# Minimap tap opens the full map on touch devices.
	minimap.visible = true
	var minimap_point := minimap.get_global_rect().get_center()
	_touch(0, minimap_point, true)
	_touch(0, minimap_point, false)
	_check(game.is_map_open(), "Tapping the minimap must open the full map")
	game.set_map_open(false)

	# Keyboard: M opens, Esc closes the map; Esc pauses and Esc resumes (no soft-lock).
	await _key(KEY_M)
	_check(game.is_map_open() and paused, "M must open the full map")
	# Mouse: a click without dragging places a waypoint at the cursor.
	full_map.canvas.view_center = Vector2(6.0, -6.0)
	full_map.canvas.pixels_per_meter = 1.0
	navigator.clear()
	var click := full_map.canvas.get_global_transform() * full_map.canvas.map_to_screen(Vector2(6.0, -6.0))
	for pressed in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		mouse.position = root.get_final_transform() * click
		mouse.global_position = mouse.position
		Input.parse_input_event(mouse)
		Input.flush_buffered_events()
	_check(navigator.has_destination and navigator.target.distance_to(Vector2(6.0, -6.0)) < 2.0,
		"Mouse click must place the waypoint under the cursor")
	await _key(KEY_ESCAPE)
	_check(not game.is_map_open() and not paused, "Esc must close the map and resume")
	await _key(KEY_ESCAPE)
	_check(paused and not game.is_map_open(), "Esc must pause the game")
	await _key(KEY_ESCAPE)
	_check(not paused, "Esc must resume a paused game")
	game.queue_free()
	await process_frame

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)

## A point near `origin` that is at least `clearance` metres from every part of the route.
func _point_away_from(route: PackedVector2Array, origin: Vector2, clearance: float) -> Vector2:
	for radius in [100.0, 150.0, 200.0, 300.0]:
		for step in 16:
			var candidate: Vector2 = origin + Vector2.RIGHT.rotated(TAU * step / 16.0) * radius
			var nearest := INF
			for index in range(1, route.size()):
				nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(candidate, route[index - 1], route[index]).distance_to(candidate))
			if nearest > clearance:
				return candidate
	return origin + Vector2(400.0, 400.0)

func _wait_gps() -> void:
	for _frame in 20:
		await physics_frame

func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for _frame in 3:
			await process_frame

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	# Input events arrive in window coordinates; the viewport converts them to its own space.
	event.position = root.get_final_transform() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * position
	event.relative = root.get_final_transform().basis_xform(relative)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
