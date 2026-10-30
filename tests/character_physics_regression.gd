extends SceneTree

## Character physics: grounding on slopes, walls, stairs, crouch headroom, jumping,
## fall damage, parked cars as solid obstacles, and being hit by a moving car.

const PERSON_SCENE := preload("res://scenes/player/person.tscn")

var _failures := 0
var _lab: VehicleLab

func _init() -> void:
	_lab = VehicleLab.new()
	_lab.interactive = false
	root.add_child(_lab)
	_lab.build_arena()
	_build_course()
	await physics_frame
	await _test_slope_and_ground()
	await _test_wall_and_stairs()
	await _test_crouch_headroom()
	await _test_jump_and_fall_damage()
	await _test_parked_car_is_solid()
	await _test_vehicle_hits()
	if _failures > 0:
		print("FAIL character physics regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS character physics regression: slopes, grounding, walls, stairs, crouch headroom, jump/land, fall damage, parked cars solid, car impacts scale with speed")
	quit()

func _build_course() -> void:
	# Stairs: five 0.25 m steps rising along +X from x = 100.
	for index in 5:
		var height := (index + 1) * 0.25
		_lab._box("Step_%d" % index, Vector3(100.0 + index * 0.6, height * 0.5, -100.0), Vector3(0.6, height, 4.0), Basis(), Color.GRAY)
	# Low ceiling for the crouch test, 1.4 m clear.
	_lab._box("LowCeiling", Vector3(130, 1.6, -100), Vector3(4, 0.4, 4), Basis(), Color.DIM_GRAY)
	# A 30 m high ledge for falls.
	_lab._box("Tower", Vector3(160, 4.0, -100), Vector3(4, 8, 4), Basis(), Color.DIM_GRAY)

func _spawn(at: Vector3) -> CharacterBody3D:
	var person: CharacterBody3D = PERSON_SCENE.instantiate()
	person.position = at
	_lab.add_child(person)
	person.get_node("CameraPivot/SpringArm3D/Camera3D").current = false
	return person

func _walk(person: CharacterBody3D, direction: Vector2, frames: int) -> void:
	# Touch input is camera-relative; point the camera yaw at 0 for predictable axes.
	for _frame in frames:
		person.set_touch_move_input(direction)
		await physics_frame
	person.set_touch_move_input(Vector2.ZERO)

func _test_slope_and_ground() -> void:
	# Walk up the 15% ramp (it rises along -Z from z = -20) and check the feet stay on it.
	var person := _spawn(Vector3(-20, 0.2, -16))
	await _frames(20)
	_check(person.is_on_floor(), "Character must stand on flat ground")
	var floating := 0.0
	for _frame in 420:
		person.set_touch_move_input(_toward(person, Vector3(-20, 0, -55)))
		await physics_frame
		if person.is_on_floor():
			floating = maxf(floating, _height_above_ground(person))
	person.set_touch_move_input(Vector2.ZERO)
	_check(person.global_position.y > 3.0, "Character must walk up a 15%% ramp (reached %.1f m)" % person.global_position.y)
	_check(floating < 0.08, "Feet must stay on the slope, not float (%.2f m gap)" % floating)
	# Standing still on the slope must not slide.
	await _frames(30)
	var rest := person.global_position
	await _frames(120)
	_check(person.global_position.distance_to(rest) < 0.05, "Character must not slide down a walkable slope")
	person.queue_free()

func _test_wall_and_stairs() -> void:
	var person := _spawn(Vector3(97.5, 0.2, -100))
	await _frames(20)
	var start_y := person.global_position.y
	var highest := start_y
	# The flight ends in a drop, so measure the highest tread reached.
	for _frame in 160:
		person.set_touch_move_input(_toward(person, Vector3(110, 0, -100)))
		await physics_frame
		highest = maxf(highest, person.global_position.y)
	person.set_touch_move_input(Vector2.ZERO)
	_check(highest - start_y > 1.0, "Character must climb 0.25 m stairs (rose %.2f m)" % (highest - start_y))
	person.queue_free()
	# The wall at z = 80 is 3 m tall: walking into it must stop, not pass through.
	var walker := _spawn(Vector3(0, 0.2, 76))
	await _frames(20)
	await _walk_toward(walker, Vector3(0, 0, 90), 180)
	_check(walker.global_position.z < 79.6, "Character must not pass through a wall (z %.2f)" % walker.global_position.z)
	walker.queue_free()

func _test_crouch_headroom() -> void:
	var person := _spawn(Vector3(130, 0.2, -100))
	await _frames(5)
	# Spawned under a 1.4 m ceiling: the full-height capsule would intersect, so crouch first.
	person._update_crouch(true)
	await _frames(10)
	_check(person.crouching and is_equal_approx(person._capsule.height, person.crouch_height), "Crouch must shrink the collider")
	person._update_crouch(false)
	_check(person.crouching, "Character must stay crouched while there is no headroom")
	PhysicsServer3D.body_set_state(person.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(136, 0.1, -100)))
	person.global_position = Vector3(136, 0.1, -100)
	await _frames(10)
	person._update_crouch(false)
	_check(not person.crouching and is_equal_approx(person._capsule.height, person.stand_height), "Character must stand up once clear of the ceiling")
	person.queue_free()

func _test_jump_and_fall_damage() -> void:
	var person := _spawn(Vector3(140, 0.2, -110))
	person.combat_mode = true
	await _frames(20)
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var peak := 0.0
	for _frame in 90:
		await physics_frame
		peak = maxf(peak, person.global_position.y)
	_check(peak > 1.0 and person.is_on_floor(), "Jump must leave the ground and land again (peak %.2f m)" % peak)
	_check(is_equal_approx(person.health, person.max_health), "A normal jump must not hurt")
	# Drop from the 8 m tower top.
	person.global_position = Vector3(160, 8.2, -100)
	await _frames(20)
	person.global_position = Vector3(160, 8.2, -103.5)
	await _frames(120)
	var after_drop: float = person.health
	_check(after_drop < person.max_health, "Falling 8 m must cause fall damage in combat mode (health %.0f)" % after_drop)
	var calm := _spawn(Vector3(150, 8.2, -110))
	calm.combat_mode = false
	await _frames(120)
	_check(is_equal_approx(calm.health, calm.max_health), "Outside combat mode a fall must not cost health")
	person.queue_free()
	calm.queue_free()

func _test_parked_car_is_solid() -> void:
	var car := _lab.spawn_car(Vector3(-60, 0.6, 60), 0.0, false)
	var person := _spawn(Vector3(-60, 0.2, 54))
	await _frames(60)
	var car_start := car.global_position
	await _walk_toward(person, Vector3(-60, 0, 70), 240)
	var local := car.global_transform.affine_inverse() * person.global_position
	_check(absf(local.z) > 2.1 or absf(local.x) > 0.95, "Character must not walk through a parked car")
	_check(car.global_position.distance_to(car_start) < 0.05, "A walking character must not shove a parked car")
	person.queue_free()
	car.queue_free()

func _test_vehicle_hits() -> void:
	var severities := {}
	for speed_kmh in [12.0, 45.0]:
		var person := _spawn(Vector3(-100.0 - speed_kmh, 0.2, 40))
		person.combat_mode = true
		var car := _lab.spawn_car(Vector3(-100.0 - speed_kmh, 0.6, 0), 0.0, true)
		var hit := {"severity": -1.0}
		person.impacted.connect(func(severity: float, _source: Node) -> void: hit.severity = maxf(hit.severity, severity))
		await _frames(60)
		var guard := 0
		while car.global_position.z < 38.0 and guard < 900:
			var speed: float = car.linear_velocity.length() * 3.6
			car.set_touch_move_input(Vector2(0, -1.0 if speed < speed_kmh else 0.0))
			await physics_frame
			guard += 1
		var person_start := person.global_position
		for _frame in 90:
			await physics_frame
		car.set_touch_move_input(Vector2(0, 1.0))
		_check(hit.severity >= 0.0, "A car at %.0f km/h must register hitting the character" % speed_kmh)
		severities[speed_kmh] = {"severity": hit.severity, "health": person.health, "thrown": person.global_position.distance_to(person_start)}
		var local := car.global_transform.affine_inverse() * person.global_position
		_check(not (absf(local.x) < 0.9 and absf(local.z) < 2.0 and local.y < 1.6), "The character must not end up inside the car")
		person.queue_free()
		car.queue_free()
		await _frames(5)
	var slow: Dictionary = severities[12.0]
	var fast: Dictionary = severities[45.0]
	print("car impacts: 12 km/h severity %.2f health %.0f thrown %.1f m; 45 km/h severity %.2f health %.0f thrown %.1f m" %
		[slow.severity, slow.health, slow.thrown, fast.severity, fast.health, fast.thrown])
	_check(fast.severity > slow.severity, "A faster car must hit harder")
	_check(fast.health < slow.health, "A faster car must do more damage in combat mode")
	_check(fast.thrown > slow.thrown, "A faster car must throw the character further")

func _walk_toward(person: CharacterBody3D, target: Vector3, frames: int) -> void:
	for _frame in frames:
		person.set_touch_move_input(_toward(person, target))
		await physics_frame
	person.set_touch_move_input(Vector2.ZERO)

## Touch input that walks toward a world point, given the camera's yaw.
func _toward(person: CharacterBody3D, target: Vector3) -> Vector2:
	var flat := Vector3(target.x - person.global_position.x, 0.0, target.z - person.global_position.z)
	if flat.length() < 0.2:
		return Vector2.ZERO
	var local := flat.normalized().rotated(Vector3.UP, -person.camera_pivot.movement_yaw())
	return Vector2(local.x, local.z)

func _height_above_ground(person: CharacterBody3D) -> float:
	var from := person.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0, 1, [person.get_rid()])
	var hit := person.get_world_3d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else person.global_position.y - (hit.position as Vector3).y

func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
