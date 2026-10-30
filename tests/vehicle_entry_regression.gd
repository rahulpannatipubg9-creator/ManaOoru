extends SceneTree

var _failures := 0

func _init() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _frame in 60:
		await physics_frame
	var person := game.get_node("Player") as CharacterBody3D
	var entry: Node = game.entry
	for car: PhysicsBody3D in game.vehicles.slice(0, 2):
		await _check_car(game, entry, person, car)
	if _failures > 0:
		print("FAIL vehicle entry regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS vehicle entry regression: walk to door, door sounds, seated driver rides along, feet on pedals, climbs out driver side")
	quit()

func _check_car(game: Node, entry: Node, person: CharacterBody3D, car: PhysicsBody3D) -> void:
	var label := car.name
	var door: Transform3D = entry.door_transform(car)
	person.global_position = door.origin + door.basis.z * -3.0
	await physics_frame
	var start := person.global_position
	game.enter_vehicle(car)
	var saw_walk := false
	var saw_open := false
	var heard_door := false
	for _frame in 300:
		await physics_frame
		saw_walk = saw_walk or entry.phase == entry.Phase.WALK
		saw_open = saw_open or entry.phase == entry.Phase.OPEN
		heard_door = heard_door or entry._door_audio.playing
		if game.control_state == game.ControlState.DRIVING:
			break
	_check(saw_walk and saw_open and heard_door, "%s: getting in must walk to the door and play the door sound" % label)
	_check(game.control_state == game.ControlState.DRIVING, "%s: getting in must finish" % label)
	_check(person.global_position.distance_to(start) > 0.5, "%s: the person must walk over rather than vanish" % label)
	for _frame in 30:
		await physics_frame
	_check(person.global_position.distance_to(entry.seat_transform(car).origin) < 0.1, "%s: the driver must sit in the seat" % label)
	_check(person.visible, "%s: the driver must stay visible in third person" % label)
	var character := person.get_node("TestCharacter")
	if character.is_active():
		var skeleton: Skeleton3D = character.skeleton
		var foot := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("DEF-foot.L")).origin
		var pedal: Vector3 = car.global_transform * (entry.seat_points(car)[1] as Vector3)
		var ankle_gap := Vector2(car.to_local(foot).z - car.to_local(pedal).z, car.to_local(foot).y - car.to_local(pedal).y).length()
		_check(ankle_gap < 0.2, "%s: the driver's feet must reach the pedals (off by %.2f m)" % [label, ankle_gap])
		_check(car.to_local(foot).y > car.to_local(pedal).y - 0.05, "%s: the driver's feet must not poke through the floor" % label)
	game.exit_vehicle()
	for _frame in 300:
		await physics_frame
		if game.control_state == game.ControlState.ON_FOOT:
			break
	_check(game.control_state == game.ControlState.ON_FOOT, "%s: getting out must finish" % label)
	var seat_side := signf(car.to_local(entry.seat_transform(car).origin).x)
	_check(signf(car.to_local(person.global_position).x) == seat_side, "%s: the driver must climb out on the driver's side" % label)
	_check(not character.seated, "%s: the person must stand up after getting out" % label)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
