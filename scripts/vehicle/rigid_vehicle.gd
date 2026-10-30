class_name RigidVehicle
extends RigidBody3D

## Rigid-body car with raycast suspension and a friction-circle tyre model.
##
## Every force is applied through the physics engine (apply_force / impulses),
## never by writing the transform, so collisions exchange momentum: a driven car
## shoves a parked one according to their masses, tyre friction and parking brake.
## Steps at the fixed physics rate, so behaviour is frame-rate independent.
##
## Exports keep the names of the earlier kinematic car (player_controller.gd), so a
## car scene converts by changing only its root type and script. Wheel mounts come
## from the wheel nodes; every visual node is optional so test cars can be bare boxes.

signal impact(other: Node, relative_speed: float, normal: Vector3, at: Vector3)

enum Surface { ROAD, DIRT }

const Gearbox := preload("res://scripts/player/gearbox.gd")
const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
const WHEEL_NAMES := ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
const SUSPENSION_MOUNT_HEIGHT := 0.9
const AIR_DENSITY := 1.2
const ROAD_LAYER := 2
## Below this rolling speed (m/s) slip angles use it as the reference, so they stay finite when crawling.
const SLIP_REFERENCE_SPEED := 2.5
## Shape of the lateral grip curve (simplified Pacejka): rises with slip angle,
## peaks around 8-9 degrees, then falls to ~80% of peak once the tyre slides.
const TYRE_CURVE_SHAPE := 1.4
const HOLD_SPEED := 0.5
const SKID_LATERAL_SPEED := 1.0
const IMPACT_REPORT_SPEED := 1.5
const PARK_SLEEP_SPEED := 0.15
const PARK_SLEEP_DELAY := 0.4
const SURFACE_FRICTION := {Surface.ROAD: 1.0, Surface.DIRT: 0.75}
const PAINT_MATERIAL_NAME := "Thar_Car Paint"
## Centre of mass sits slightly ahead of the axle midpoint (engine in front).
const CENTER_OF_MASS_FORWARD := 0.1
## Car-hits-person tuning (arcade-balanced): severity ramps from a nudge to a
## full hit between these relative speeds (m/s).
const PERSON_IMPACT_MIN_SPEED := 1.5
const PERSON_IMPACT_FULL_SPEED := 18.0
const PERSON_MASS := 80.0
const PERSON_MAX_DAMAGE := 100.0
const PERSON_HIT_COOLDOWN := 0.8

## Service-brake deceleration (m/s²).
@export var braking_acceleration := 9.0
## Drag coefficient × frontal area (m²).
@export var drag_area := 1.5
@export var rolling_resistance := 0.015
@export var drivetrain: Resource
## Body colour for the painted panels, so parked cars can differ.
@export var paint_color := Color(0.62, 0.03, 0.03)
@export_group("Suspension")
@export var vehicle_mass := 1800.0
## Mount-to-wheel-centre length when the car rests on level ground.
@export var suspension_rest_length := 0.52
@export var suspension_bump_travel := 0.15
@export var suspension_droop_travel := 0.18
@export var suspension_frequency := 1.6
@export var suspension_damping_ratio := 0.45
@export var center_of_mass_height := 0.55
@export var anti_roll := 0.6
@export_group("Tyres and steering")
@export var wheel_radius := 0.38
## Peak tyre grip as a multiple of wheel load.
@export var tyre_friction := 1.7
## Share of rear lateral grip left once the handbrake locks the rear wheels.
@export var handbrake_rear_grip := 0.35
@export var max_steer_angle := 0.6
## Steering lock left at high speed, as a share of max_steer_angle.
@export var high_speed_steer_share := 0.25
@export var steer_rate := 2.5
## How fast the wheel returns to centre when the steering is released (rad/s).
@export var steer_return_rate := 4.5
## Lateral grip build-up per radian of slip angle (higher = sharper turn-in).
@export var tyre_cornering_stiffness := 14.0
## With no steering input, the front wheels follow a slide by this share of the
## body slip angle, so drifts are easy to catch, like GTA's driving assist.
@export var countersteer_assist := 0.7
@export var rear_wheel_drive := false
## Optional measurements for non-car vehicles. Zero means use the generic car
## defaults in VehicleEntry; the Tuk Tuk supplies its real cabin measurements.
@export var seat_hip := Vector3.ZERO
@export var pedal_point := Vector3.ZERO
@export var entry_half_width := 0.0
## Vehicle-local wrist contact points; zero preserves the generic car pose.
@export var left_hand_grip := Vector3.ZERO
@export var right_hand_grip := Vector3.ZERO

var condition := 100.0
var weather_grip := 1.0
var _damage_cooldown := 0.0

func take_damage(amount: float) -> void:
	condition = clampf(condition - maxf(amount, 0.0), 0.0, 100.0)

func repair() -> void:
	condition = 100.0

var gearbox: Gearbox
## True while the player drives this car; false = parked with the parking brake on.
## Like the earlier car, a standalone car starts drivable; main.gd parks the others.
var driving_enabled := true
var input_authority := true
var keyboard_input_enabled := false
var touch_move_input := Vector2.ZERO
var touch_run_pressed := false
var handbrake_pressed := false
var is_running := false
var current_speed := 0.0
## 0 = full grip, 1 = sliding; drives tyre squeal.
var tyre_slip := 0.0
var respawn_position := Vector3.ZERO
var fall_limit := -10.0
var wheel_contacts: Array[bool] = [false, false, false, false]
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_surfaces: Array[int] = [Surface.ROAD, Surface.ROAD, Surface.ROAD, Surface.ROAD]
var wheels: Array[Node3D] = []

## CharacterBody-style alias so code that reads or zeroes `velocity` keeps working.
var velocity: Vector3:
	get:
		return linear_velocity
	set(value):
		linear_velocity = value

## Body attitude (the whole body tilts now), for the HUD and tests.
var body_pitch: float:
	get:
		return asin(clampf(global_transform.basis.z.normalized().y, -1.0, 1.0))
var body_roll: float:
	get:
		return asin(clampf(-global_transform.basis.x.normalized().y, -1.0, 1.0))

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mounts: Array[Vector3] = []
var _compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lengths: Array[float] = []
var _spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _steer := 0.0
var _hub_nodes: Array[Node3D] = []
var _safe_transforms: Array[Transform3D] = []
var _safe_timer := 0.0
var _pending_person_hits: Array[Dictionary] = []
var _hit_cooldowns: Dictionary = {}
## Velocity at the start of the last physics step: the solver has already stopped the
## car against a (kinematic) person by the time the contact is reported.
var _pre_contact_velocity := Vector3.ZERO
var _parked_still_time := 0.0

func _ready() -> void:
	if not drivetrain is DrivetrainProfile:
		drivetrain = DrivetrainProfile.new()
	gearbox = Gearbox.new(drivetrain)
	mass = vehicle_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, center_of_mass_height, CENTER_OF_MASS_FORWARD)
	# Box inertia of the collision body, so pitch, roll and yaw respond like a real chassis.
	var size := Vector3(1.9, 1.4, 4.3)
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node and shape_node.shape is BoxShape3D:
		size = (shape_node.shape as BoxShape3D).size
	inertia = Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z,
		size.x * size.x + size.y * size.y) * vehicle_mass / 12.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = true
	angular_damp = 0.3
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
		physics_material_override.friction = 0.6
		physics_material_override.bounce = 0.05
	var default_mounts := [Vector3(-0.858, 0, 1.3), Vector3(0.858, 0, 1.3), Vector3(-0.858, 0, -1.3), Vector3(0.858, 0, -1.3)]
	for index in 4:
		var wheel := get_node_or_null(WHEEL_NAMES[index] + "Wheel") as Node3D
		wheels.append(wheel)
		_hub_nodes.append(get_node_or_null(WHEEL_NAMES[index] + "Hub") as Node3D)
		var at: Vector3 = wheel.position if wheel else default_mounts[index]
		_mounts.append(Vector3(at.x, SUSPENSION_MOUNT_HEIGHT, at.z))
		_lengths.append(suspension_rest_length)
	var audio := get_node_or_null("EngineAudio")
	if audio and audio.has_method("configure"):
		audio.configure(drivetrain)
	_apply_paint()
	if respawn_position == Vector3.ZERO:
		respawn_position = global_position
	settle_on_ground()

func _apply_paint() -> void:
	var chassis := get_node_or_null("Chassis")
	if chassis == null:
		return
	var paint: StandardMaterial3D = null
	for node in chassis.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.resource_name != PAINT_MATERIAL_NAME:
				continue
			if paint == null:
				paint = source.duplicate() as StandardMaterial3D
				paint.albedo_color = paint_color
			mesh_instance.set_surface_override_material(surface, paint)

# --- Control API shared with main.gd / hud.gd --------------------------------

func set_touch_move_input(value: Vector2) -> void:
	touch_move_input = value.limit_length()
	if value != Vector2.ZERO:
		sleeping = false

func set_touch_run_pressed(value: bool) -> void:
	touch_run_pressed = value

## Parking a car only engages its parking brake; it stays a live physics body.
## main.gd re-asserts these flags every frame, so only a real change does anything.
func set_driving_enabled(value: bool) -> void:
	if value == driving_enabled:
		return
	driving_enabled = value
	if not value:
		touch_move_input = Vector2.ZERO
		touch_run_pressed = false
		tyre_slip = 0.0
		gearbox.reset()
		sleeping = linear_velocity.length() < PARK_SLEEP_SPEED
	else:
		sleeping = false

func set_input_authority(value: bool) -> void:
	if value == input_authority:
		return
	input_authority = value
	if not value:
		touch_move_input = Vector2.ZERO
		touch_run_pressed = false

func set_keyboard_input_enabled(value: bool) -> void:
	if value == keyboard_input_enabled:
		return
	keyboard_input_enabled = value
	if not value:
		touch_move_input = Vector2.ZERO

func is_automatic() -> bool:
	return gearbox.mode == Gearbox.Mode.AUTOMATIC

func toggle_transmission_mode() -> void:
	gearbox.toggle_mode()

func shift_up() -> void:
	gearbox.request_shift_up()

func shift_down() -> void:
	gearbox.request_shift_down(current_speed, wheel_radius)

## Puts a stuck or flipped car back upright at a recent safe spot, at rest.
func recover_vehicle() -> bool:
	var recovery := _safe_transforms[0] if not _safe_transforms.is_empty() else global_transform
	var yaw := recovery.basis.get_euler().y
	var target := Transform3D(Basis(Vector3.UP, yaw), recovery.origin + Vector3.UP * 0.5)
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = target * shape.transform
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	_teleport(target)
	gearbox.reset()
	_safe_transforms = [recovery, recovery]
	return true

## Drops the car onto its springs at static ride height so parked cars sit on the road.
func settle_on_ground() -> void:
	if not is_inside_tree():
		return
	var origin := global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 50.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var placed := global_transform
	if not hit.is_empty():
		# Wheel centres at wheel_radius above the ground with the springs at rest length.
		placed.origin.y = (hit.position as Vector3).y - (SUSPENSION_MOUNT_HEIGHT - suspension_rest_length - wheel_radius)
	_teleport(placed)
	if not driving_enabled:
		sleeping = true
	# A car placed somewhere new must not recover back to where it used to be.
	_safe_transforms = [global_transform, global_transform]
	_safe_timer = 0.0
	_update_visuals()

func _teleport(target: Transform3D) -> void:
	global_transform = target
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	current_speed = 0.0
	_pre_contact_velocity = Vector3.ZERO
	# Start the dampers at the static sag, or the first step sees a huge compression
	# speed and kicks the car into the air.
	var static_compression := vehicle_mass * 0.25 * _gravity / _spring_stiffness()
	for index in 4:
		_compressions[index] = static_compression
	if is_inside_tree():
		reset_physics_interpolation()

static func resolve_keyboard_input() -> Vector2:
	return GameplayControls.movement()

# --- Simulation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
	_resolve_person_hits(delta)
	_pre_contact_velocity = linear_velocity
	if global_position.y < fall_limit:
		_teleport(Transform3D(Basis(), respawn_position))
	var controlled := driving_enabled and input_authority and GameplayControls.allows(self)
	var input := Vector2.ZERO
	if controlled:
		var keyboard := resolve_keyboard_input() if keyboard_input_enabled else Vector2.ZERO
		input = touch_move_input if touch_move_input.length_squared() > 0.0 else keyboard
		handbrake_pressed = Input.is_action_pressed("vehicle_handbrake")
		is_running = (Input.is_action_pressed("run") or touch_run_pressed) and input.y < 0.0
		if keyboard_input_enabled:
			_read_gear_input()
	else:
		handbrake_pressed = false
	if controlled and (input != Vector2.ZERO or handbrake_pressed):
		sleeping = false
	# Parked cars that have come to rest sleep, so springs and tyres never let them creep.
	if not controlled and not sleeping:
		var still := linear_velocity.length() < PARK_SLEEP_SPEED and angular_velocity.length() < PARK_SLEEP_SPEED
		_parked_still_time = _parked_still_time + delta if still else 0.0
		if _parked_still_time > PARK_SLEEP_DELAY:
			sleeping = true
	var throttle := clampf(-input.y, -1.0, 1.0)
	_update_audio(controlled, throttle, delta)
	if sleeping:
		return
	var forward := global_transform.basis.z
	current_speed = linear_velocity.dot(forward)
	_update_steering(input.x, delta)

	# Pressing against the direction of travel (S while rolling forward, W while reversing) brakes.
	var braking := controlled and ((throttle < -0.01 and current_speed > HOLD_SPEED) or (throttle > 0.01 and current_speed < -HOLD_SPEED))
	var drive_force := 0.0
	if controlled and not braking and not handbrake_pressed:
		drive_force = gearbox.update(current_speed, throttle, wheel_radius, delta)
	drive_force *= (0.0 if condition <= 0.0 else lerpf(0.35, 1.0, condition / 100.0))
	var brake := 0.0
	if not controlled:
		brake = 1.0 # parking brake
	elif braking:
		brake = absf(throttle)
	elif absf(throttle) <= 0.01 and absf(current_speed) < HOLD_SPEED:
		brake = 1.0 # hold still on slopes with no pedal

	apply_central_force(-linear_velocity * linear_velocity.length() * 0.5 * AIR_DENSITY * drag_area)
	_apply_wheels(delta, drive_force, brake)
	_record_safe_transform(delta)
	_update_visuals()

## Speed-sensitive lock, eased so the wheel turns rather than snaps, self-centring
## when released, and pointing the front wheels into a slide when the player is
## not steering.
func _update_steering(steer_input: float, delta: float) -> void:
	var lock := max_steer_angle * lerpf(1.0, high_speed_steer_share, clampf(absf(current_speed) / 30.0, 0.0, 1.0))
	if absf(steer_input) > 0.01:
		_steer = move_toward(_steer, -steer_input * lock, steer_rate * delta)
		return
	var target := 0.0
	var local_velocity := global_transform.basis.inverse() * linear_velocity
	# Only while rolling forward (a slide often scrubs speed down to a few m/s).
	if local_velocity.z > 0.5 and Vector2(local_velocity.x, local_velocity.z).length() > 2.0:
		var body_slip := atan2(local_velocity.x, local_velocity.z)
		target = clampf(body_slip * countersteer_assist, -max_steer_angle, max_steer_angle)
	_steer = move_toward(_steer, target, steer_return_rate * delta)

## Lateral tyre force from the slip angle: grows with slip up to a peak, then
## eases off as the tyre slides. Scales with the load the tyre carries.
func lateral_tyre_force(side_speed: float, long_speed: float, grip: float) -> float:
	var slip_angle := atan2(side_speed, maxf(absf(long_speed), SLIP_REFERENCE_SPEED))
	return -grip * sin(TYRE_CURVE_SHAPE * atan(tyre_cornering_stiffness * slip_angle))

func _read_gear_input() -> void:
	if Input.is_action_just_pressed("vehicle_transmission"):
		toggle_transmission_mode()
	if Input.is_action_just_pressed("vehicle_gear_up"):
		shift_up()
	if Input.is_action_just_pressed("vehicle_gear_down"):
		shift_down()

func _spring_stiffness() -> float:
	return vehicle_mass * 0.25 * pow(TAU * suspension_frequency, 2.0)

func _apply_wheels(delta: float, drive_force: float, brake: float) -> void:
	var space := get_world_3d().direct_space_state
	var up := global_transform.basis.y
	var stiffness := _spring_stiffness()
	var damping := 2.0 * suspension_damping_ratio * sqrt(stiffness * vehicle_mass * 0.25)
	var static_compression := vehicle_mass * 0.25 * _gravity / stiffness
	var max_length := suspension_rest_length + suspension_droop_travel
	var min_length := suspension_rest_length - suspension_bump_travel
	var driven := [2, 3] if rear_wheel_drive else [0, 1, 2, 3]
	var hits: Array[Dictionary] = []
	for index in 4:
		var origin := global_transform * _mounts[index]
		var query := PhysicsRayQueryParameters3D.create(origin, origin - up * (max_length + wheel_radius),
			1, [get_rid()])
		var hit := space.intersect_ray(query)
		# Wheels roll over the world, not over people.
		if not hit.is_empty() and hit.collider is CharacterBody3D:
			hit = {}
		hits.append(hit)
		wheel_contacts[index] = not hit.is_empty()
		if hit.is_empty():
			_lengths[index] = max_length
			_compressions[index] = 0.0
			wheel_loads[index] = 0.0
			continue
		var reach := origin.distance_to(hit.position) - wheel_radius
		_lengths[index] = maxf(reach, min_length)
		var on_road: bool = hit.collider is CollisionObject3D and (hit.collider.collision_layer & (1 << (ROAD_LAYER - 1))) != 0
		wheel_surfaces[index] = Surface.ROAD if on_road else Surface.DIRT
		hit["bump"] = maxf(min_length - reach, 0.0)
	# Anti-roll bars move load from the extended to the compressed side of each axle.
	var roll_forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for axle in [[0, 1], [2, 3]]:
		var difference: float = (_lengths[axle[1]] - _lengths[axle[0]]) * stiffness * anti_roll
		if wheel_contacts[axle[0]]:
			roll_forces[axle[0]] += difference
		if wheel_contacts[axle[1]]:
			roll_forces[axle[1]] -= difference
	var slip_total := 0.0
	for index in 4:
		if not wheel_contacts[index]:
			continue
		var hit := hits[index]
		var compression := (suspension_rest_length + static_compression) - _lengths[index]
		var compression_speed := (compression - _compressions[index]) / delta
		_compressions[index] = compression
		# Spring, damper, anti-roll, and a stiff bump stop once travel runs out.
		var bump: float = hit.bump
		var load := maxf(stiffness * compression + damping * compression_speed + roll_forces[index] + stiffness * 10.0 * bump, 0.0)
		wheel_loads[index] = load
		var contact: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		apply_force(up * load, contact - global_position)

		var steer := _steer if index < 2 else 0.0
		var heading := global_transform.basis.z.rotated(up, steer)
		var wheel_forward := (heading - normal * heading.dot(normal)).normalized()
		var wheel_side := normal.cross(wheel_forward).normalized()
		var point_velocity := linear_velocity + angular_velocity.cross(contact - (global_transform * center_of_mass))
		var long_speed := point_velocity.dot(wheel_forward)
		var side_speed := point_velocity.dot(wheel_side)
		var mass_share := vehicle_mass * 0.25
		var surface_friction: float = SURFACE_FRICTION[wheel_surfaces[index]]
		var grip := tyre_friction * surface_friction * weather_grip * load

		var longitudinal := 0.0
		if index in driven:
			longitudinal += drive_force / driven.size()
		longitudinal -= signf(long_speed) * minf(rolling_resistance * load, mass_share * absf(long_speed) / delta)
		var locked := handbrake_pressed and index >= 2
		if brake > 0.0 or locked:
			var stop := mass_share * absf(long_speed) / delta
			var brake_limit: float = grip if locked else minf(brake * braking_acceleration * mass_share, grip)
			longitudinal = -signf(long_speed) * minf(stop, brake_limit)
		var limit: float = grip * (handbrake_rear_grip if locked else 1.0)
		var lateral := lateral_tyre_force(side_speed, long_speed, limit)
		# A tyre can at most stop the sideways slide this step; more would overshoot and wobble.
		var cancel := mass_share * absf(side_speed) / delta
		lateral = clampf(lateral, -cancel, cancel)
		# Friction circle: braking/driving and cornering share the same grip.
		var combined := Vector2(longitudinal, lateral)
		if combined.length() > limit:
			slip_total += 1.0 - limit / combined.length()
			combined = combined.limit_length(limit)
		if absf(side_speed) > SKID_LATERAL_SPEED:
			slip_total += clampf((absf(side_speed) - SKID_LATERAL_SPEED) / 3.0, 0.0, 1.0)
		apply_force(wheel_forward * combined.x + wheel_side * combined.y, contact - global_position)
		if not locked:
			_spin[index] += long_speed / wheel_radius * delta
	tyre_slip = clampf(slip_total / 4.0, 0.0, 1.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	for contact in state.get_contact_count():
		var other := state.get_contact_collider_object(contact)
		if other == null:
			continue
		var normal := state.get_contact_local_normal(contact)
		var other_velocity := Vector3.ZERO
		if other is RigidBody3D:
			other_velocity = other.linear_velocity
		elif other is CharacterBody3D:
			other_velocity = other.velocity
		var relative := (_pre_contact_velocity - other_velocity).dot(-normal)
		if other is CharacterBody3D and other.has_method("apply_knockback"):
			# The car's own velocity at impact (people barely slow a car).
			_pending_person_hits.append({"person": other, "velocity": _pre_contact_velocity, "normal": normal})
		elif relative > IMPACT_REPORT_SPEED:
			if relative > 5.0 and _damage_cooldown <= 0.0:
				take_damage((relative - 5.0) * 1.8)
				_damage_cooldown = 0.6
			impact.emit(other, relative, normal, state.get_contact_collider_position(contact))

## A moving car that touches a character throws it along the car's path. Severity
## comes from the closing speed; the car loses the momentum it hands over, and
## briefly ignores the person so it does not snag on them.
func _resolve_person_hits(delta: float) -> void:
	for person in _hit_cooldowns.keys():
		_hit_cooldowns[person] -= delta
		if _hit_cooldowns[person] <= 0.0:
			_hit_cooldowns.erase(person)
			if is_instance_valid(person) and person in get_collision_exceptions():
				remove_collision_exception_with(person)
	for hit in _pending_person_hits:
		var person: CharacterBody3D = hit.person
		if not is_instance_valid(person) or _hit_cooldowns.has(person):
			continue
		var car_velocity: Vector3 = hit.velocity
		var closing := (car_velocity - person.velocity).dot(-(hit.normal as Vector3))
		if closing < PERSON_IMPACT_MIN_SPEED:
			continue
		var severity := clampf((closing - PERSON_IMPACT_MIN_SPEED) / (PERSON_IMPACT_FULL_SPEED - PERSON_IMPACT_MIN_SPEED), 0.0, 1.0)
		var push := Vector3(car_velocity.x, 0.0, car_velocity.z)
		var throw := push * lerpf(0.6, 1.1, severity) + Vector3.UP * lerpf(1.5, 7.0, severity)
		person.apply_knockback(throw - person.velocity, severity, self, PERSON_MAX_DAMAGE * pow(severity, 1.3))
		# A thrown person is let through briefly so the car doesn't snag on them, and the
		# car keeps its momentum minus what it handed over (a person is ~80 kg, the car ~1.8 t).
		# A slow nudge keeps colliding, so the car is held back rather than driving into them.
		if severity > 0.3:
			add_collision_exception_with(person)
			linear_velocity = car_velocity - push.normalized() * PERSON_MASS * closing * 0.5 / vehicle_mass
		_hit_cooldowns[person] = PERSON_HIT_COOLDOWN
		impact.emit(person, closing, hit.normal, person.global_position)
	_pending_person_hits.clear()

func _record_safe_transform(delta: float) -> void:
	_safe_timer += delta
	if _safe_timer < 0.5:
		return
	_safe_timer = 0.0
	if wheel_contacts.all(func(contact: bool) -> bool: return contact) and global_transform.basis.y.y > 0.9 and absf(current_speed) > 1.0:
		_safe_transforms = [_safe_transforms[1], global_transform]

## Engine sound is optional (bare test cars have none).
## Only the driven vehicle's engine audio runs; parked cars are completely muted.
func _update_audio(controlled: bool, throttle: float, delta: float) -> void:
	var audio := get_node_or_null("EngineAudio")
	if audio == null:
		return
	if not controlled:
		if audio.has_method("mute"):
			audio.mute()
		elif audio.has_method("set_running"):
			audio.set_running(false)
		return
	if audio.has_method("set_running"):
		audio.set_running(true)
	if audio.has_method("set_engine_rpm"):
		audio.set_engine_rpm(gearbox.rpm, gearbox.gear)
	if audio.has_method("update_drive_state"):
		audio.update_drive_state(current_speed, throttle, tyre_slip, controlled and Input.is_action_pressed("vehicle_horn"), delta)

func _update_visuals() -> void:
	for index in 4:
		var wheel := wheels[index]
		if wheel == null:
			continue
		var wheel_rotation := Vector3(_spin[index], _steer if index < 2 else 0.0, PI * 0.5)
		wheel.position.y = SUSPENSION_MOUNT_HEIGHT - _lengths[index]
		wheel.rotation = wheel_rotation
		var hub := _hub_nodes[index]
		if hub:
			hub.position.y = wheel.position.y
			hub.rotation = wheel_rotation
