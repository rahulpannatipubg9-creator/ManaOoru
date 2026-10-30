extends CharacterBody3D

const DEFAULT_SPAWN := Vector3(120.0, 1.2, -105.0)
## Where to put the body back if it ever falls out of the world; set from the map at start-up.
var respawn_position := DEFAULT_SPAWN
## Below this height the body is treated as fallen out of the world; lowered for deep terrain.
var fall_limit := -10.0
## Service-brake deceleration (m/s²); a Thar stops at roughly 0.9 g.
@export var braking_acceleration: float = 9.0
@export var steering_speed: float = 1.8
## Drag coefficient × frontal area (m²); the boxy Thar is about 0.52 × 2.85.
@export var drag_area: float = 1.5
@export var rolling_resistance: float = 0.015
## Engine, gearbox and engine-sound character (drivetrain_profile.gd); empty means the Thar diesel.
@export var drivetrain: Resource
## Body colour for the Thar's painted panels, so parked cars can differ.
@export var paint_color := Color(0.62, 0.03, 0.03)

@export_group("Suspension")
@export var vehicle_mass: float = 1200.0
## Mount-to-wheel-centre length when the car rests on level ground.
@export var suspension_rest_length: float = 0.52
@export var suspension_bump_travel: float = 0.15
@export var suspension_droop_travel: float = 0.18
@export var suspension_frequency: float = 1.6
@export var suspension_damping_ratio: float = 0.45
@export var center_of_mass_height: float = 0.45

@export_group("Tyres")
@export var wheel_radius: float = 0.38
@export var tyre_friction: float = 1.7
## Lateral acceleration per m/s of sideways slide while the tyres still grip.
@export var tyre_cornering_stiffness: float = 20.0
## Share of rear lateral grip left once the handbrake locks the rear wheels.
@export var handbrake_rear_grip: float = 0.1
## Extra yaw while the locked rear swings out.
@export var handbrake_yaw_boost: float = 2.2

const SUSPENSION_MOUNT_HEIGHT := 0.9
const BUMP_STOP_STIFFNESS_SCALE := 10.0
const BODY_ANGLE_LIMIT := 0.3
const BODY_ACCELERATION_LIMIT := 40.0
const SKID_LATERAL_SPEED := 1.0
const LOCKED_TYRE_FRICTION_SCALE := 0.4
const PAINT_MATERIAL_NAME := "Thar_Car Paint"
const AIR_DENSITY := 1.2
## Steering reaches full response at this speed, then eases off so high-speed lane changes stay stable.
const STEERING_FULL_SPEED := 12.0
const STEERING_FADE_SPEED := 18.0
## Below this speed with no pedal the car holds still instead of creeping.
const HOLD_SPEED := 0.5
const Gearbox := preload("res://scripts/player/gearbox.gd")
const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
var gearbox: Gearbox
@onready var camera_pivot: Node3D = $CameraPivot
@onready var chassis: Node3D = $Chassis
@onready var wheels: Array[Node3D] = [
	$FrontLeftWheel,
	$FrontRightWheel,
	$RearLeftWheel,
	$RearRightWheel
]
@onready var wheel_hubs: Array[Node3D] = [
	$FrontLeftHub,
	$FrontRightHub,
	$RearLeftHub,
	$RearRightHub
]
const EngineSound := preload("res://scripts/player/engine_sound.gd")
@onready var engine_audio: EngineSound = $EngineAudio
var _front_wheel_roll := 0.0
var _rear_wheel_roll := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_running := false
var touch_move_input := Vector2.ZERO
var touch_run_pressed := false
var driving_enabled := true
var current_speed := 0.0
var input_authority := true
var handbrake_pressed := false
var keyboard_input_enabled := false
## 0 = full grip, 1 = sliding; drives tyre squeal.
var tyre_slip := 0.0
var wheel_contacts: Array[bool] = [false, false, false, false]
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var body_pitch := 0.0
var body_roll := 0.0
const SAFE_SAMPLE_INTERVAL := 0.5
var _safe_transforms: Array[Transform3D] = []
var _safe_sample_timer := 0.0
var _wheel_mounts: Array[Vector3] = []
var _spring_lengths: Array[float] = []
var _spring_compressions: Array[float] = []
var _body_pitch_velocity := 0.0
var _body_roll_velocity := 0.0
var _body_acceleration := Vector2.ZERO
var _previous_velocity := Vector3.ZERO

func _ready() -> void:
	if not drivetrain is DrivetrainProfile:
		drivetrain = DrivetrainProfile.new()
	gearbox = Gearbox.new(drivetrain)
	engine_audio.configure(drivetrain)
	_apply_paint()
	for wheel in wheels:
		_wheel_mounts.append(Vector3(wheel.position.x, SUSPENSION_MOUNT_HEIGHT, wheel.position.z))
		_spring_lengths.append(suspension_rest_length)
		_spring_compressions.append(_static_compression())
	settle_on_ground()
	_safe_transforms = [global_transform, global_transform]

func _apply_paint() -> void:
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

static func resolve_keyboard_input() -> Vector2:
	var input := Input.get_vector("left", "right", "forward", "backward")
	if input.is_zero_approx():
		input = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
	return input.limit_length()

func set_touch_move_input(value: Vector2) -> void:
	touch_move_input = value.limit_length()

func set_touch_run_pressed(value: bool) -> void:
	touch_run_pressed = value

func set_driving_enabled(value: bool) -> void:
	driving_enabled = value
	if not value:
		touch_move_input = Vector2.ZERO
		touch_run_pressed = false
		velocity = Vector3.ZERO
		current_speed = 0.0
		tyre_slip = 0.0
		gearbox.reset()

func set_input_authority(value: bool) -> void:
	input_authority = value
	if not value:
		touch_move_input = Vector2.ZERO
		touch_run_pressed = false
		velocity = Vector3.ZERO

func set_keyboard_input_enabled(value: bool) -> void:
	keyboard_input_enabled = value
	if not value:
		touch_move_input = Vector2.ZERO

func _physics_process(delta: float) -> void:
	# Only the car being driven has its engine running; parked cars stay silent.
	engine_audio.set_running(driving_enabled and input_authority)
	if not driving_enabled:
		velocity = Vector3.ZERO
		current_speed = 0.0
		return
	if not input_authority:
		velocity = Vector3.ZERO
		current_speed = 0.0
		return
	if global_position.y < fall_limit:
		global_position = respawn_position
		velocity = Vector3.ZERO
	_update_suspension(delta)

	var keyboard_input := resolve_keyboard_input() if keyboard_input_enabled else Vector2.ZERO
	var input_vector := touch_move_input if touch_move_input.length_squared() > 0.0 else keyboard_input
	var throttle := clampf(-input_vector.y, -1.0, 1.0)
	var steering := clampf(input_vector.x, -1.0, 1.0)
	var forward := global_transform.basis.z
	var side := global_transform.basis.x
	var forward_speed := velocity.dot(forward)
	var lateral_speed := velocity.dot(side)
	handbrake_pressed = Input.is_action_pressed("vehicle_handbrake")

	# Tyres can only push as hard as the suspension presses them into the road.
	var front_load := wheel_loads[0] + wheel_loads[1]
	var rear_load := wheel_loads[2] + wheel_loads[3]
	var grip := tyre_friction * (front_load + rear_load) / vehicle_mass
	if keyboard_input_enabled:
		_read_gear_input(forward_speed)
	var drive_force := gearbox.update(forward_speed, throttle, wheel_radius, delta)
	var drive_acceleration := drive_force / (vehicle_mass * gearbox.inertia_factor())
	var resistance := rolling_resistance * _gravity + 0.5 * AIR_DENSITY * drag_area * forward_speed * forward_speed / vehicle_mass
	# Pressing against the direction of travel (S while rolling forward, W while reversing) brakes.
	var braking := (throttle < -0.01 and forward_speed > HOLD_SPEED) or (throttle > 0.01 and forward_speed < -HOLD_SPEED)
	var target_speed := forward_speed
	var speed_step := 0.0
	if handbrake_pressed:
		target_speed = 0.0
		speed_step = tyre_friction * LOCKED_TYRE_FRICTION_SCALE * rear_load / vehicle_mass
	elif braking:
		target_speed = 0.0
		speed_step = braking_acceleration * absf(throttle)
	elif absf(throttle) <= 0.01 and absf(forward_speed) < HOLD_SPEED:
		target_speed = 0.0
		speed_step = braking_acceleration
	var requested_acceleration := (move_toward(forward_speed, target_speed, speed_step * delta) - forward_speed) / delta
	if not handbrake_pressed and not braking:
		requested_acceleration += drive_acceleration
		# Drag and rolling resistance oppose motion but never push the car backwards.
		requested_acceleration -= signf(forward_speed) * minf(resistance, absf(forward_speed) / delta)
	var longitudinal_acceleration := clampf(requested_acceleration, -grip, grip)
	var wheelspin := 0.0
	if absf(requested_acceleration) > grip and grip > 0.0:
		wheelspin = 1.0 - grip / absf(requested_acceleration)
	if handbrake_pressed and absf(forward_speed) > 1.0:
		wheelspin = 1.0
	forward_speed += longitudinal_acceleration * delta

	# Whatever grip braking or driving uses is no longer available for cornering.
	var rear_grip_scale := handbrake_rear_grip if handbrake_pressed else 1.0
	var lateral_grip := tyre_friction * (front_load + rear_load * rear_grip_scale) / vehicle_mass
	lateral_grip = sqrt(maxf(lateral_grip * lateral_grip - longitudinal_acceleration * longitudinal_acceleration, 0.0))
	var wanted_lateral := absf(lateral_speed) * tyre_cornering_stiffness
	lateral_speed = move_toward(lateral_speed, 0.0, minf(wanted_lateral, lateral_grip) * delta)
	var slide := clampf((absf(lateral_speed) - SKID_LATERAL_SPEED) / 3.0, 0.0, 1.0)
	tyre_slip = maxf(slide, wheelspin) if grip > 0.0 else 0.0

	var new_velocity := forward * forward_speed + side * lateral_speed
	velocity.x = new_velocity.x
	velocity.z = new_velocity.z
	current_speed = forward_speed
	# Steering fades only once the front tyres are clearly unloaded (crests, jumps, hard launches).
	var static_front_load := vehicle_mass * _gravity * 0.5
	var front_grip_factor := clampf(front_load / (static_front_load * 0.6), 0.0, 1.0)
	var steering_factor := clampf(absf(forward_speed) / STEERING_FULL_SPEED, 0.2, 1.0) * front_grip_factor
	steering_factor *= minf(1.0, STEERING_FADE_SPEED / maxf(absf(forward_speed), 0.1))
	if handbrake_pressed:
		steering_factor *= handbrake_yaw_boost
	if absf(steering) > 0.01 and absf(forward_speed) > 0.05:
		var reverse_factor := -1.0 if forward_speed < 0.0 else 1.0
		rotation.y -= steering * steering_speed * steering_factor * reverse_factor * delta
	is_running = (Input.is_action_pressed("run") or touch_run_pressed) and throttle > 0.0
	move_and_slide()
	_measure_body_acceleration(delta)
	_record_safe_transform(delta, forward_speed)
	var wheel_distance := forward_speed * delta / wheel_radius
	_front_wheel_roll += wheel_distance
	if not (handbrake_pressed and _has_ground_contact()):
		_rear_wheel_roll += wheel_distance
	_update_wheel_visuals(steering)
	engine_audio.set_engine_rpm(gearbox.rpm, gearbox.gear)
	engine_audio.update_drive_state(forward_speed, throttle, tyre_slip, Input.is_action_pressed("vehicle_horn"), delta)

func _read_gear_input(forward_speed: float) -> void:
	if Input.is_action_just_pressed("vehicle_transmission"):
		toggle_transmission_mode()
	if Input.is_action_just_pressed("vehicle_gear_up"):
		shift_up()
	if Input.is_action_just_pressed("vehicle_gear_down"):
		gearbox.request_shift_down(forward_speed, wheel_radius)

func toggle_transmission_mode() -> void:
	gearbox.toggle_mode()

func is_automatic() -> bool:
	return gearbox.mode == Gearbox.Mode.AUTOMATIC

func shift_up() -> void:
	gearbox.request_shift_up()

func shift_down() -> void:
	gearbox.request_shift_down(current_speed, wheel_radius)

func recover_vehicle() -> void:
	# The older sample is at least one interval behind, so it is clear of the obstacle we hit.
	var recovery := _safe_transforms[0]
	var upright_yaw := recovery.basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, upright_yaw), recovery.origin)
	global_position.y += 0.3
	velocity = Vector3.ZERO
	current_speed = 0.0
	gearbox.reset()
	_reset_body_motion()
	_safe_transforms = [global_transform, global_transform]
	_safe_sample_timer = 0.0

func _record_safe_transform(delta: float, forward_speed: float) -> void:
	_safe_sample_timer += delta
	if _safe_sample_timer < SAFE_SAMPLE_INTERVAL:
		return
	_safe_sample_timer = 0.0
	if not wheel_contacts.all(func(contact: bool) -> bool: return contact) or is_on_wall() or absf(forward_speed) < 1.0:
		return
	_safe_transforms = [_safe_transforms[1], global_transform]

## Raycast spring-damper per wheel. The root only heaves (keeping the collision box
## upright for move_and_slide); pitch and roll are applied to the visual chassis.
func _update_suspension(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var stiffness := _spring_stiffness()
	var damping := 2.0 * suspension_damping_ratio * sqrt(stiffness * vehicle_mass * 0.25)
	var free_length := suspension_rest_length + _static_compression()
	var max_length := suspension_rest_length + suspension_droop_travel
	var min_length := suspension_rest_length - suspension_bump_travel
	var total_force := 0.0
	var pitch_torque := center_of_mass_height * vehicle_mass * -_body_acceleration.y
	var roll_torque := center_of_mass_height * vehicle_mass * _body_acceleration.x
	for index in _wheel_mounts.size():
		var mount := _wheel_mounts[index]
		var lift := -mount.z * body_pitch + mount.x * body_roll
		var origin := global_transform * Vector3(mount.x, mount.y + lift, mount.z)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * (max_length + wheel_radius), 1, [get_rid()])
		var hit := space.intersect_ray(query)
		var length := max_length
		var force := 0.0
		wheel_contacts[index] = not hit.is_empty()
		if wheel_contacts[index]:
			var reach: float = origin.y - (hit.position as Vector3).y - wheel_radius
			length = maxf(reach, min_length)
			var compression := free_length - length
			var compression_speed := (compression - _spring_compressions[index]) / delta
			_spring_compressions[index] = compression
			force = stiffness * compression + damping * compression_speed
			if reach < min_length:
				force += stiffness * BUMP_STOP_STIFFNESS_SCALE * (min_length - reach)
			force = maxf(force, 0.0)
		else:
			_spring_compressions[index] = free_length - max_length
		_spring_lengths[index] = length
		wheel_loads[index] = force
		total_force += force
		pitch_torque -= force * mount.z
		roll_torque += force * mount.x
	velocity.y += (total_force / vehicle_mass - _gravity) * delta
	var pitch_inertia := vehicle_mass * 1.1 * 1.1
	var roll_inertia := vehicle_mass * 0.55 * 0.55
	_body_pitch_velocity += pitch_torque / pitch_inertia * delta
	_body_roll_velocity += roll_torque / roll_inertia * delta
	if not _has_ground_contact():
		_body_pitch_velocity = move_toward(_body_pitch_velocity, -body_pitch * 4.0, 6.0 * delta)
		_body_roll_velocity = move_toward(_body_roll_velocity, -body_roll * 4.0, 6.0 * delta)
	body_pitch = clampf(body_pitch + _body_pitch_velocity * delta, -BODY_ANGLE_LIMIT, BODY_ANGLE_LIMIT)
	body_roll = clampf(body_roll + _body_roll_velocity * delta, -BODY_ANGLE_LIMIT, BODY_ANGLE_LIMIT)
	chassis.rotation = Vector3(body_pitch, 0.0, body_roll)

func _measure_body_acceleration(delta: float) -> void:
	var real_velocity := get_real_velocity()
	var change := (real_velocity - _previous_velocity) / delta
	_previous_velocity = real_velocity
	var local_acceleration := Vector2(change.dot(global_transform.basis.x), change.dot(global_transform.basis.z))
	local_acceleration = local_acceleration.limit_length(BODY_ACCELERATION_LIMIT)
	_body_acceleration = _body_acceleration.lerp(local_acceleration, clampf(delta * 12.0, 0.0, 1.0))

## Drops the car onto its springs at static ride height so parked cars sit on the road.
func settle_on_ground() -> void:
	if not is_inside_tree():
		return
	var origin := global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 50.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_update_wheel_visuals(0.0)
		return
	global_position.y = (hit.position as Vector3).y - (SUSPENSION_MOUNT_HEIGHT - suspension_rest_length - wheel_radius)
	_reset_body_motion()
	# A car placed somewhere new must not recover back to where it used to be.
	_safe_transforms = [global_transform, global_transform]
	_safe_sample_timer = 0.0

func _reset_body_motion() -> void:
	body_pitch = 0.0
	body_roll = 0.0
	_body_pitch_velocity = 0.0
	_body_roll_velocity = 0.0
	_body_acceleration = Vector2.ZERO
	_previous_velocity = Vector3.ZERO
	for index in _spring_lengths.size():
		_spring_lengths[index] = suspension_rest_length
		_spring_compressions[index] = _static_compression()
	chassis.rotation = Vector3.ZERO
	_update_wheel_visuals(0.0)

func _spring_stiffness() -> float:
	var angular_frequency := TAU * suspension_frequency
	return vehicle_mass * 0.25 * angular_frequency * angular_frequency

func _static_compression() -> float:
	return vehicle_mass * 0.25 * _gravity / _spring_stiffness()

func _has_ground_contact() -> bool:
	return wheel_contacts.any(func(contact: bool) -> bool: return contact)

func _update_wheel_visuals(steering: float) -> void:
	# D (positive steering) yaws the car clockwise, so the front wheels turn by a negative angle too.
	var front_steering_angle := -steering * 0.52
	for index in wheels.size():
		var roll := _front_wheel_roll if index < 2 else _rear_wheel_roll
		var wheel_rotation := Vector3(roll, 0.0, PI * 0.5)
		if index < 2:
			wheel_rotation.y = front_steering_angle
		var mount := _wheel_mounts[index]
		var lift := -mount.z * body_pitch + mount.x * body_roll
		var wheel_height := mount.y + lift - _spring_lengths[index]
		wheels[index].rotation = wheel_rotation
		wheels[index].position.y = wheel_height
		wheel_hubs[index].rotation = wheel_rotation
		wheel_hubs[index].position.y = wheel_height
