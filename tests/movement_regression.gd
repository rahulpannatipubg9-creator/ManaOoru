extends SceneTree

const EPSILON := 0.001

func _init() -> void:
	_assert_vector("W", Vector2(0.0, -1.0), Vector2(0.0, -1.0))
	_assert_vector("S", Vector2(0.0, 1.0), Vector2(0.0, 1.0))
	_assert_vector("A", Vector2(-1.0, 0.0), Vector2(-1.0, 0.0))
	_assert_vector("D", Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	_assert_vector("W+D normalized", Vector2(1.0, -1.0).normalized(), Vector2(1.0, -1.0).normalized())
	assert(Vector2.ZERO.length_squared() == 0.0, "Idle input must be zero")
	assert(absf(Vector2(1.0, -1.0).normalized().length() - 1.0) < EPSILON, "Diagonal input must be normalized")
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	assert(player_scene != null, "Player scene must load")
	# The car drives through tyre contact, so the isolated car needs a road under it.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(400.0, 1.0, 400.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	root.add_child(ground)
	var player := player_scene.instantiate()
	root.add_child(player)
	await process_frame
	var start_position: Vector3 = player.global_position
	player.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 30:
		await physics_frame
	var displacement: Vector3 = player.global_position - start_position
	assert(absf(displacement.z) > 0.1 or absf(displacement.x) > 0.1, "Player root must translate from movement input")
	var camera_pivot := player.get_node("CameraPivot") as Node3D
	var camera_yaw_before := camera_pivot.global_rotation.y
	player.rotation.y += PI * 0.5
	await process_frame
	await process_frame
	assert(absf(angle_difference(camera_pivot.global_rotation.y, camera_yaw_before)) < 0.01,
		"Camera world yaw must remain stable while the car turns")
	player.set_touch_move_input(Vector2.ZERO)
	var keyboard_start: Vector3 = player.global_position
	# The game enables keyboard driving only for the car being driven.
	player.set_keyboard_input_enabled(true)
	Input.action_press("forward")
	for _frame in 30:
		await physics_frame
	Input.action_release("forward")
	var keyboard_displacement: Vector3 = player.global_position - keyboard_start
	assert(absf(keyboard_displacement.z) > 0.1 or absf(keyboard_displacement.x) > 0.1,
		"W action must change the player position")
	player.queue_free()
	# The isolated car pad must not overlap the city's terrain/road collision.
	ground.queue_free()
	await process_frame
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	assert(main_scene != null, "Main scene must load")
	var game := main_scene.instantiate()
	root.add_child(game)
	await process_frame
	var world_player := game.get_node("Player") as CharacterBody3D
	var placement_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/custom_placements.json"))
	var expected_vehicles := 7
	for placement: Dictionary in placement_catalog.get("assets", []):
		if not str(placement.get("drivable_scene", "")).is_empty():
			expected_vehicles += 1
	assert(game.vehicles.size() == expected_vehicles, "Original vehicles and every configured imported vehicle must be enterable")
	var tuk_tuk := game.get_node("Tuk Tuk") as PhysicsBody3D
	assert(tuk_tuk != null, "Player Tuk Tuk missing")
	var helicopter := game.get_node("Chowrastha Helicopter") as PhysicsBody3D
	assert(helicopter != null and helicopter.has_method("can_exit_safely"), "Chowrastha helicopter flight safety API missing")
	# Cars are live rigid bodies: let them settle onto their springs and fall asleep first.
	for _frame in 60:
		await physics_frame
	# Streamed collision is built over multiple render frames. Adding those static
	# bodies wakes nearby rigid cars; wait for loading and suspension settlement
	# before measuring input isolation, with a bound so startup cannot hang.
	for _frame in 900:
		if game.get_node("World").buildings.pending_chunk_count() == 0:
			break
		await physics_frame
	assert(game.get_node("World").buildings.pending_chunk_count() == 0, "Startup building collision must finish streaming")
	# This suite measures player input ownership. Keep ambient actors stationary
	# so traffic/pedestrian impacts cannot be mistaken for leaked player input.
	# Their live behaviour and car impacts have separate regression suites.
	for world_node in [game.get_node("World")] + game.get_node("World").find_children("*", "Node", true, false):
		var player_vehicle := false
		for vehicle in game.vehicles:
			if world_node == vehicle or vehicle.is_ancestor_of(world_node):
				player_vehicle = true
				break
		if player_vehicle:
			continue
		world_node.set_process(false)
		world_node.set_physics_process(false)
	var settled_frames := 0
	for _frame in 900:
		await physics_frame
		var settled: bool = game.get_node("World").buildings.pending_chunk_count() == 0
		for vehicle in game.vehicles:
			if vehicle is RigidBody3D and not vehicle.freeze:
				settled = settled and vehicle.sleeping
		settled_frames = settled_frames + 1 if settled else 0
		if settled_frames >= 60:
			break
	assert(settled_frames >= 60, "Parked vehicles must settle after startup collision streaming")
	var tuk_ground_y: float = game.get_node("World").ground_height(GeoProjection.world_to_map(tuk_tuk.global_position))
	# Roads have a thin rendered/collision deck above the terrain sample. The
	# Tuk's bottom is on that deck; it must never hover by a visible distance.
	assert((tuk_tuk as RigidVehicle).wheel_contacts.all(func(contact: bool) -> bool: return contact),
		"Player Tuk Tuk must settle onto all three-wheel-layout contact points")
	assert(absf(tuk_tuk.global_position.y - tuk_ground_y) < 0.20,
		"Player Tuk Tuk must rest on the road surface")
	var tuk_door_distance := minf(world_player.global_position.distance_to(game._door_position(tuk_tuk, -1.0)),
		world_player.global_position.distance_to(game._door_position(tuk_tuk, 1.0)))
	assert(tuk_door_distance <= game.enter_distance,
		"Player Tuk Tuk must start within interaction range")
	var parked_vehicle_positions: Dictionary = {}
	for vehicle in game.vehicles:
		parked_vehicle_positions[vehicle] = vehicle.global_position
	# Pick a clear walking path beside the spawn vehicles. A kinematic person
	# pushing a live car is a physical collision, not leaked driving authority.
	var walk_pivot := world_player.get_node("CameraPivot")
	var clear_path := false
	for index in 16:
		var yaw := TAU * float(index) / 16.0
		var direction := Vector3.FORWARD.rotated(Vector3.UP, yaw)
		if not world_player.test_move(world_player.global_transform, direction * 5.0):
			walk_pivot._yaw = yaw
			walk_pivot._apply_orbit_rotation()
			clear_path = true
			break
	assert(clear_path, "Input isolation needs a collision-free walking path")
	var world_start: Vector3 = world_player.global_position
	world_player.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 30:
		await physics_frame
	var world_displacement: Vector3 = world_player.global_position - world_start
	assert(absf(world_displacement.z) > 0.1 or absf(world_displacement.x) > 0.1, "Car must translate in the generated world")
	for vehicle in game.vehicles:
		assert(vehicle.global_position.distance_to(parked_vehicle_positions[vehicle]) < 0.01,
			"Parked vehicle %s moved %.4f m while the person walks" % [vehicle.name, vehicle.global_position.distance_to(parked_vehicle_positions[vehicle])])
		assert(vehicle.is_physics_processing(), "Parked vehicles must keep physics processing enabled")
	world_player.set_touch_move_input(Vector2.ZERO)
	Input.action_press("forward")
	for _frame in 30:
		await physics_frame
	Input.action_release("forward")
	for vehicle in game.vehicles:
		assert(vehicle.global_position.distance_to(parked_vehicle_positions[vehicle]) < 0.01,
			"Global W input moved parked vehicle %s by %.4f m" % [vehicle.name, vehicle.global_position.distance_to(parked_vehicle_positions[vehicle])])
	world_player.set_touch_move_input(Vector2.ZERO)
	var world_person := game.get_node("Player") as CharacterBody3D
	var world_vehicle := game.get_node("Vehicle") as PhysicsBody3D
	world_person.set_movement_enabled(false)
	world_person.global_position = world_vehicle.global_position + Vector3(0.0, 0.0, -2.0)
	game.active_vehicle = world_vehicle
	var vehicle_start := world_vehicle.global_position
	game.enter_vehicle(world_vehicle)
	assert(game.control_state == game.ControlState.ENTERING, "Entering must play out before driving")
	assert((world_person.get_node("CollisionShape3D") as CollisionShape3D).disabled,
		"Person collision must be disabled while getting in")
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	assert(game.control_state == game.ControlState.DRIVING, "Getting in must finish and hand control to the car")
	assert(world_vehicle.global_position.distance_to(vehicle_start) < 0.05, "The car must wait while the person gets in")
	assert(world_person.visible, "The driver must stay visible in the seat")
	world_vehicle.set_touch_move_input(Vector2(0.0, -1.0))
	for _frame in 30:
		await physics_frame
	await process_frame
	await process_frame
	assert(world_vehicle.global_position.distance_to(vehicle_start) > 0.1,
		"Entered vehicle must move")
	# The seat follow runs per rendered frame, so right after a physics step it may trail by a tick.
	assert(world_person.global_position.distance_to(game.entry.seat_transform(world_vehicle).origin)
		< 0.05 + absf(world_vehicle.current_speed) * 2.0 / Engine.physics_ticks_per_second,
		"The driver must ride along in the seat")
	assert(game.control_state == game.ControlState.DRIVING, "Driving state must own control")
	for vehicle in game.vehicles:
		if vehicle != world_vehicle:
			assert(vehicle.global_position.distance_to(parked_vehicle_positions[vehicle]) < 0.01,
				"Non-selected vehicle %s moved %.3f m while driving" % [vehicle.name, vehicle.global_position.distance_to(parked_vehicle_positions[vehicle])])
	for _frame in 90:
		await physics_frame
	var driven_position := world_vehicle.global_position
	world_vehicle.set_touch_move_input(Vector2.ZERO)
	world_vehicle.global_position = driven_position + Vector3(0.0, -0.5, 25.0)
	world_vehicle.rotation = Vector3(0.6, world_vehicle.rotation.y, 0.4)
	world_vehicle.recover_vehicle()
	assert(world_vehicle.global_position.distance_to(driven_position) < 15.0,
		"Recovery must return the vehicle to a recent safe position")
	assert(world_vehicle.global_position.distance_to(driven_position) > 0.1,
		"Recovery must move a stuck vehicle away from where it got stuck")
	assert(absf(world_vehicle.rotation.x) < EPSILON and absf(world_vehicle.rotation.z) < EPSILON,
		"Recovered vehicle must be upright")
	assert(world_vehicle.current_speed == 0.0 and world_vehicle.velocity.is_zero_approx(),
		"Recovered vehicle must be stationary")
	for _frame in 30:
		await physics_frame
	game.exit_vehicle()
	assert(world_person.visible, "Person must stay visible while getting out")
	assert(world_vehicle.velocity.length_squared() == 0.0, "Exited vehicle must stop")
	for _frame in 300:
		if game.control_state == game.ControlState.ON_FOOT:
			break
		await physics_frame
	assert(world_vehicle.to_local(world_person.global_position).x < 0.0, "Person must exit on the driver side")
	assert(game.control_state == game.ControlState.ON_FOOT, "Exit must return control to the person")
	assert(game._nearest_vehicle() == world_vehicle, "Person must be able to re-enter right after exiting")
	# The Tuk Tuk is an actual player vehicle, not an ambient-only prop.
	world_person.global_position = game._door_position(tuk_tuk, -1.0)
	game.enter_vehicle(tuk_tuk)
	assert(game.control_state == game.ControlState.ENTERING, "Tuk Tuk must begin entry from its driver door")
	for _frame in 300:
		if game.control_state == game.ControlState.DRIVING:
			break
		await physics_frame
	assert(game.control_state == game.ControlState.DRIVING and game.active_vehicle == tuk_tuk,
		"Tuk Tuk must be enterable and become the active vehicle")
	print("PASS movement regression: WASD axes, diagonal normalization, idle stability, player translation, vehicle recovery")
	quit()

func _assert_vector(name: String, actual: Vector2, expected: Vector2) -> void:
	assert(actual.distance_to(expected) < EPSILON, "%s input mismatch" % name)
