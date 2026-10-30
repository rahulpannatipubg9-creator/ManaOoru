class_name GdkHelicopter
extends RigidBody3D

## An original arcade helicopter controller for town exploration.  It is a
## stable hover craft rather than a simulation aircraft: this lets a new player
## take off and return safely among the dense Godavarikhani buildings.

@export var keep_custom_spawn := true
@export var entry_half_width := 1.5
@export var seat_hip := Vector3(-0.45, 1.35, -0.15)
@export var pedal_point := Vector3(-0.45, 0.9, 0.75)
@export var vehicle_mass := 2200.0
@export var max_horizontal_speed := 42.0
@export var cruise_speed := 25.0
@export var max_vertical_speed := 6.0
@export var horizontal_acceleration := 8.0
@export var hover_braking := 12.0
@export var vertical_acceleration := 7.0
@export var yaw_rate := 1.05
@export var visual_bank_angle := 0.16

signal impact(other: Node, relative_speed: float, normal: Vector3, at: Vector3)
var condition := 100.0
var _impact_cooldown := 0.0
var _impact_velocity := Vector3.ZERO

func take_damage(amount: float) -> void:
	condition = clampf(condition - maxf(0.0, amount), 0.0, 100.0)

func repair() -> void:
	condition = 100.0

var driving_enabled := false
var input_authority := false
var keyboard_input_enabled := false
var touch_move_input := Vector2.ZERO
var touch_run_pressed := false
var handbrake_pressed := false
var current_speed := 0.0
var velocity: Vector3:
	get: return linear_velocity
	set(value): linear_velocity = value
var fall_limit := -10.0
var respawn_position := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rotors: Array[Node3D] = []
var _collective := 0.0
var _rotor_spool := 0.0
var _model: Node3D
var _rotor_hub: Node3D
var _engine_audio: AudioStreamPlayer3D
var _engine_playback: AudioStreamGeneratorPlayback
var _audio_phase := 0.0
var _engine_phase := 0.0
var _hover_height := 0.0
var _vertical_command := false
var _grounded := false
var touch_descend_pressed := false
var touch_yaw_input := 0.0
var _safe_landing := Transform3D.IDENTITY

func forward_direction() -> Vector3:
	return -global_basis.z.slide(Vector3.UP).normalized()

func _ready() -> void:
	mass = vehicle_mass
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.3
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	for rotor: Node in find_children("*", "Node3D", true, false):
		if "rotor" in rotor.name.to_lower():
			_rotors.append(rotor as Node3D)
	respawn_position = global_position
	_hover_height = global_position.y
	_safe_landing = global_transform
	_model = get_node_or_null("Model") as Node3D
	_create_visible_rotor()
	_create_engine_audio()
	freeze = true

func set_touch_move_input(value: Vector2) -> void:
	touch_move_input = value.limit_length()

func set_touch_run_pressed(value: bool) -> void:
	touch_run_pressed = value

func set_touch_descend_pressed(value: bool) -> void:
	touch_descend_pressed = value

func set_driving_enabled(value: bool) -> void:
	if value == driving_enabled:
		return
	driving_enabled = value
	if _engine_audio:
		if value:
			_engine_audio.play()
			_engine_playback = _engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback
		else:
			_engine_audio.stop()
			_engine_playback = null
	if not value:
		clear_control_input()
		handbrake_pressed = false
		# Parked craft are locked to their pad, preventing physics drift or a
		# playerless crash into the Chowrastha traffic.
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		freeze = false
		sleeping = false
		_hover_height = global_position.y
		# Neutral collective holds the craft on its skids. W or Space raises it;
		# a player is never required to discover an invisible throttle control.
		_collective = maxf(_collective, 0.5)

func set_input_authority(value: bool) -> void:
	input_authority = value
	if not value:
		clear_control_input()

func clear_control_input() -> void:
	touch_move_input = Vector2.ZERO
	touch_run_pressed = false
	touch_descend_pressed = false
	touch_yaw_input = 0.0

func set_keyboard_input_enabled(value: bool) -> void:
	keyboard_input_enabled = value
	if not value:
		clear_control_input()

func settle_on_ground() -> void:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 50.0, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var placed := Transform3D(Basis(Vector3.UP, global_rotation.y), global_position)
	placed.origin.y = hit.position.y - 0.12
	global_transform = placed
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, placed)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_hover_height = placed.origin.y
	_safe_landing = placed
	respawn_position = placed.origin
	reset_physics_interpolation()

func recover_vehicle() -> bool:
	var shape := get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = _safe_landing * shape.transform
	query.transform.origin += Vector3.UP * 0.10
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	freeze = true
	global_transform = _safe_landing
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_hover_height = global_position.y
	clear_control_input()
	reset_physics_interpolation()
	if driving_enabled:
		freeze = false
	return true

func can_exit_safely() -> bool:
	var hit := _ground_probe()
	return not hit.is_empty() and global_position.y - float(hit.position.y) < 0.50 and linear_velocity.length() < 1.0 and global_basis.y.dot(Vector3.UP) > 0.96

func _ground_probe() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3,
		global_position + Vector3.DOWN * 1.5, collision_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

## Shared by the interaction prompt and VehicleEntry so boarding uses the
## helicopter's real cabin width and pilot-seat depth.
func entry_door_position(side: float) -> Vector3:
	var requested_side := -1.0 if side < 0.0 else 1.0
	return global_transform * Vector3(requested_side * (entry_half_width + 0.35), 0.12, seat_hip.z)

func vehicle_hud_state() -> Dictionary:
	return {"label": "LAND" if _grounded else "FLY", "rpm": _rotor_spool * 1450.0, "automatic": true,
		"altitude": global_position.y - _safe_landing.origin.y}

func _process(delta: float) -> void:
	_rotor_spool = move_toward(_rotor_spool, 1.0 if driving_enabled else 0.0, delta * 1.8)
	var spin := 48.0 * _rotor_spool
	if _rotor_hub:
		_rotor_hub.rotate_y(spin * delta)
	for rotor in _rotors:
		rotor.rotate_object_local(Vector3.UP, spin * delta)
	_fill_engine_audio()

func _create_visible_rotor() -> void:
	# The supplied helicopter mesh has baked rotor geometry. Add four separate,
	# lightweight blades so rotor rotation remains visible at every camera range.
	_rotor_hub = Node3D.new()
	_rotor_hub.name = "AnimatedMainRotor"
	_rotor_hub.position = Vector3(0.0, 2.77, -0.15)
	add_child(_rotor_hub)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#1f2527")
	material.metallic = 0.65
	material.roughness = 0.38
	for rotation in [0.0, PI * 0.5]:
		var blade := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(7.0, 0.045, 0.18)
		blade.mesh = mesh
		blade.rotation.y = rotation
		blade.material_override = material
		_rotor_hub.add_child(blade)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.14
	hub_mesh.bottom_radius = 0.18
	hub_mesh.height = 0.22
	hub.mesh = hub_mesh
	hub.material_override = material
	_rotor_hub.add_child(hub)

func _create_engine_audio() -> void:
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.name = "RotorEngineAudio"
	_engine_audio.unit_size = 32.0
	_engine_audio.max_distance = 180.0
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.35
	_engine_audio.stream = generator
	_engine_audio.volume_db = 5.0
	add_child(_engine_audio)
	if driving_enabled:
		_engine_audio.play()
		_engine_playback = _engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback

func _fill_engine_audio() -> void:
	if _engine_playback == null or not driving_enabled:
		return
	var frames := mini(_engine_playback.get_frames_available(), 2048)
	var rotor_frequency := lerpf(10.0, 32.0, _rotor_spool)
	var engine_frequency := lerpf(75.0, 185.0, _rotor_spool)
	var amplitude := lerpf(0.01, 0.32, _rotor_spool) if driving_enabled else 0.006
	for _frame in frames:
		_audio_phase = fmod(_audio_phase + rotor_frequency / 22050.0, 1.0)
		_engine_phase = fmod(_engine_phase + engine_frequency / 22050.0, 1.0)
		var rotor_wave := sin(_audio_phase * TAU) * 0.55
		var engine_wave := sin(_engine_phase * TAU) * 0.35 + sin(_engine_phase * TAU * 2.01) * 0.16
		var blade_pulse := sin(_audio_phase * TAU * 4.0) * 0.22
		var sample := (rotor_wave + engine_wave + blade_pulse) * amplitude
		_engine_playback.push_frame(Vector2(sample, sample))

func _physics_process(delta: float) -> void:
	_impact_velocity = linear_velocity
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if global_position.y < fall_limit:
		recover_vehicle()
		return
	if not driving_enabled:
		return
	if condition <= 0.0:
		# A wreck has no lift, but the exit prompt still has to follow it to the ground.
		current_speed = linear_velocity.slide(Vector3.UP).length()
		_grounded = can_exit_safely()
		return
	var allowed := input_authority and GameplayControls.allows(self)
	var input := touch_move_input if allowed else Vector2.ZERO
	var keyboard := keyboard_input_enabled and allowed
	if keyboard and input.is_zero_approx():
		input = GameplayControls.movement()
	var ascend := float((keyboard and Input.is_key_pressed(KEY_SPACE)) or (allowed and touch_run_pressed))
	var descend := float((keyboard and Input.is_key_pressed(KEY_SHIFT)) or (allowed and touch_descend_pressed))
	var yaw := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)) if keyboard else touch_yaw_input if allowed else 0.0
	var fast := keyboard and Input.is_key_pressed(KEY_CTRL)
	var flat_forward := forward_direction()
	var flat_right := global_basis.x.slide(Vector3.UP).normalized()
	var vertical := ascend - descend
	if absf(vertical) > 0.01:
		_hover_height = global_position.y
		_vertical_command = true
	elif _vertical_command:
		_hover_height = global_position.y
		_vertical_command = false
	var target_vertical_speed := vertical * max_vertical_speed if absf(vertical) > 0.01 else clampf((_hover_height - global_position.y) * 1.8, -3.0, 3.0)
	var target_horizontal := (flat_forward * -input.y + flat_right * input.x) * (max_horizontal_speed if fast else cruise_speed)
	var horizontal := linear_velocity.slide(Vector3.UP)
	var acceleration := ((target_horizontal - horizontal) * 2.5).limit_length(hover_braking if input.is_zero_approx() else horizontal_acceleration)
	var lift_acceleration := clampf((target_vertical_speed - linear_velocity.y) * 3.0, -vertical_acceleration, vertical_acceleration)
	# Physics forces preserve collision response. Only the visual fuselage banks;
	# the collision body stabilizes upright for forgiving beginner handling.
	apply_central_force(mass * (acceleration + Vector3.UP * (_gravity + lift_acceleration)))
	var tilt_error := global_basis.y.cross(Vector3.UP)
	apply_torque(tilt_error * mass * 10.0)
	apply_torque(-Vector3(angular_velocity.x, 0.0, angular_velocity.z) * mass * 4.5)
	# Positive key yaw is clockwise when seen from above (-Y in Godot).
	apply_torque(Vector3.UP * (-yaw * yaw_rate - angular_velocity.y) * mass * 24.0)
	# Keep the source-model axis alignment while the rigid body supplies the
	# actual pitch and bank. Do not reset this to zero: its long axis is Z-up.
	if _model:
		var blend := 1.0 - exp(-5.0 * delta)
		_model.rotation.x = lerpf(_model.rotation.x, PI * 0.5 + input.y * visual_bank_angle, blend)
		_model.rotation.z = lerpf(_model.rotation.z, -input.x * visual_bank_angle, blend)
	angular_velocity = angular_velocity.limit_length(2.4)
	current_speed = linear_velocity.slide(Vector3.UP).length()
	_grounded = can_exit_safely()
	if _grounded:
		_safe_landing = Transform3D(Basis(Vector3.UP, global_rotation.y), global_position)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _impact_cooldown > 0.0:
		return
	for index in state.get_contact_count():
		var other := state.get_contact_collider_object(index)
		var normal := state.get_contact_local_normal(index)
		var relative := maxf(0.0, _impact_velocity.dot(-normal))
		if other != null and relative > 5.0:
			take_damage((relative - 5.0) * 2.0)
			_impact_cooldown = 0.6
			impact.emit(other, relative, normal, state.get_contact_collider_position(index))
			break
