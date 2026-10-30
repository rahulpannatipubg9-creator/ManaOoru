extends SceneTree

## The Godavari bridge must be reachable from the city: the trunk approach runs whole to the south
## abutment, the decks and the north turnaround are in the road network (map, minimap, GPS), and there is
## something to drive on every few metres from the city terrain, across the deck, to the north landing.

var _failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var data := MapData.load_shared()
	var south := GodavariBridgeBuilder.south_end()
	var north := GodavariBridgeBuilder.north_end()
	var f := GodavariBridgeBuilder.forward2()
	var r := GodavariBridgeBuilder.right2()
	var approach_ends := []
	var decks := 0
	for road: Dictionary in data.roads:
		if road.way_id in GodavariBridgeBuilder.APPROACH_WAYS:
			approach_ends.append(road.points[road.points.size() - 1] if road.way_id == GodavariBridgeBuilder.APPROACH_WAYS[0] else road.points[0])
		if road.get("structure", "") == "bridge":
			decks += 1
	_check(approach_ends.size() == 2, "both trunk approaches are present (%d)" % approach_ends.size())
	for end: Vector2 in approach_ends:
		_check(end.distance_to(south) < 12.0, "an approach reaches the south abutment (%.1f m off)" % end.distance_to(south))
	_check(decks == 2, "both bridge decks are in the road data (%d)" % decks)

	var network := RoadNetwork.new(data)
	var chowrastha := Vector2(120.0, -105.0)
	var far_side := north + f * 40.0
	var there := network.find_route(chowrastha, far_side, RoadNetwork.Mode.DRIVE)
	_check(there.ok, "GPS drives from Chowrastha across the bridge: %s" % there.error)
	if there.ok:
		var crossed := false
		for point: Vector2 in there.points:
			if point.distance_to(north) < 30.0:
				crossed = true
		_check(crossed, "the route runs over the bridge deck (%.0f m long)" % there.length)
	var back := network.find_route(far_side, chowrastha, RoadNetwork.Mode.DRIVE)
	_check(back.ok, "GPS drives back from the north landing: %s" % back.error)

	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _frame in 3:
		await physics_frame
	var space := world.get_world_3d().direct_space_state
	# Northbound lane: from the city terrain, along the approach, the deck and onto the north landing.
	var gaps := []
	var lane := -r * GodavariBridgeBuilder.LANE_OFFSET
	var start := south + lane - f * 200.0
	var length := 200.0 + GodavariBridgeBuilder.BRIDGE_LENGTH + 30.0
	var step := 0.0
	var deck_low := INF
	while step <= length:
		var point := start + f * step
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 40.0, point.y), Vector3(point.x, -120.0, point.y))
		var hit := space.intersect_ray(query)
		var expected: float = world.ground_height(point)
		if hit.is_empty() or absf(hit.position.y - expected) > 1.2:
			gaps.append("%.0f m: %s" % [step, "nothing" if hit.is_empty() else "%.2f vs %.2f" % [hit.position.y, expected]])
		elif step > 210.0 and step < 1290.0:
			deck_low = minf(deck_low, hit.position.y)
		step += 5.0
	_check(gaps.is_empty(), "drivable surface every 5 m from the city to the north landing; gaps: %s" % str(gaps.slice(0, 6)))
	var car: RigidBody3D = (load("res://scenes/vehicles/rigid_thar.tscn") as PackedScene).instantiate()
	var mid := south + lane + f * 550.0
	car.position = Vector3(mid.x, world.ground_height(mid) + 1.0, mid.y)
	car.rotation.y = deg_to_rad(GodavariBridgeBuilder.HEADING_DEG)
	root.add_child(car)
	for _frame in 90:
		await physics_frame
	var settled: float = car.global_position.y - world.ground_height(mid)
	_check(settled > -0.3 and settled < 1.2, "a car rests on the middle of the deck (%.2f m above the road line)" % settled)
	print("Godavari bridge connection: deck surface lowest %.2f, car %.2f m above road line" % [deck_low, settled])
	if _failures > 0:
		print("FAIL godavari bridge connection: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS godavari bridge connection: approach reaches the abutment, GPS routes over the bridge, continuous road surface, car rests on the deck")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
	else:
		print("ok: ", message)
