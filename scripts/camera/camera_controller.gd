extends Node3D

const GyroLook := preload("res://scripts/mobile/gyro_look.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

enum ViewMode { THIRD_PERSON, FIRST_PERSON }

@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -0.75
@export var max_pitch: float = 0.55
@export var camera_distance: float = 7.0
## Eye position relative to the followed body in first-person view.
@export var first_person_offset := Vector3(0.0, 1.8, 0.0)
## Vehicles keep the first-person view locked to the dashboard; people look around freely.
@export var first_person_follows_body := false
@export var first_person_min_pitch: float = -1.2
@export var first_person_max_pitch: float = 1.0
@export_group("Chase camera")
## Seconds without mouse or touch look before the driving camera swings back behind the car.
@export var chase_delay: float = 1.0
@export var chase_stiffness: float = 3.0
@export var chase_pitch: float = -0.2
## Extra field of view at speed, for a sense of pace.
@export var speed_fov_boost: float = 10.0
const SPEED_FOV_FULL := 30.0
@export_group("On-foot feel")
## Extra field of view while sprinting, eased in and out (BGMI-style run widening).
@export var sprint_fov_boost := 6.0
## First person on foot sits wider than third person, as in BGMI's FPP.
@export var first_person_fov := 80.0
## Head bob depth in metres, walking and sprinting, in first person; third person uses a third.
@export var bob_walk := 0.025
@export var bob_run := 0.055
## Rate (rad/s) at which pitch recoil settles back once the trigger rests, unless the rifle in the hands has its
## own `recoil_recovery` in weapon_catalog.gd.
@export var recoil_recovery := 0.35
## A big climb comes back quicker than a small one: extra rate per radian still to recover.
@export var recoil_recovery_stiffness := 3.0
@export var recoil_settle_delay := 0.12
## How fast each shot's kick reaches the view (per second): high enough to read as a shot, not a cut.
@export var recoil_kick_rate := 60.0
## A shot shakes the view: shake gained per radian of kick, metres at full shake, how fast it dies (per second), its
## share while aiming, and degrees the field of view jumps per shot.
@export var shot_shake_per_kick := 22.0
@export var shot_shake_offset := 0.035
@export var shot_shake_decay := 7.0
@export var shot_shake_aim_scale := 0.5
@export var shot_fov_punch := 0.7
## Aiming narrows the field of view to this share, at this rate (per second).
@export var ads_fov_scale := 0.62
@export var ads_zoom_rate := 14.0
## Seconds the view takes to travel from the shoulder to the sight, and back.
@export var ads_view_seconds := 0.11
## How fast (per second) the view follows a change of stance, and a swap of shoulder.
@export var stance_camera_rate := 9.0
@export var shoulder_swap_rate := 10.0
## After an obstacle has shortened the boom it lengthens again at this speed (m/s) instead of popping out.
@export var boom_recover_rate := 4.0
## Radius of the ball the boom sweeps on foot: a ray alone flickers on poles and railings.
@export var boom_probe_radius := 0.12
## The landing dip: downward kick (m/s) at full strength, then a damped spring back to level.
@export var landing_dip_speed := 1.7
@export var landing_dip_stiffness := 110.0
@export var landing_dip_damping := 14.0
## Fallback only, when the body has no animated character to keep time with.
const BOB_STRIDE := 1.5
## Stride phase at which a foot is down, so the dip of the bob lands on the footstep.
const BOB_PLANT_PHASE := 0.0
var view_mode := ViewMode.THIRD_PERSON
var looking_behind := false
var _pitch: float = -0.18
var _yaw := 0.0
var _captured := false
var _look_touch_index := -1
var _look_candidate_index := -1
var _shoulder_sign := 1.0
var _third_person_position := Vector3.ZERO
var _since_look := 0.0
var _camera: Camera3D
var _base_fov := 68.0

enum GyroMode { OFF, SCOPE_ON, ALWAYS_ON }
var gyro_mode: GyroMode = GyroMode.OFF
var look_sensitivity := 1.0
var ads_sensitivity := 0.75
var ads_gyro_sensitivity := 1.4
var gyro_sensitivity: float = 1.8
var gyro_invert_x: bool = false
var gyro_invert_y: bool = false
var target_peek: float = 0.0
var _current_peek: float = 0.0
var _peek_roll: float = 0.0
var touch_aim := false
var is_aiming: bool = false
var gyro_deadzone := 0.015
var gyro_smoothing := 12.0
var _gyro := GyroLook.new()
var _free_yaw := 0.0
var _free_active := false
var touch_free_look := false
var _stance_y := 1.45
var _run_blend := 0.0
var _bob_phase := 0.0
var _recoil_debt := 0.0
## Third-person aim borrowed the first-person sight view and gives it back on release.
var _ads_sight := false
var _since_recoil := 0.0
## Recoil on its way into the view: x pitch, y yaw.
var _recoil_pending := Vector2.ZERO
## 0 at the shoulder, 1 at the sight, while third-person aim travels to the sight view.
var _ads_blend := 0.0
## The boom's own length before obstacles, and the most it may be while recovering from one.
var _boom_length := 7.0
var _boom_limit := INF
var _boom_exclude_timer := 0.0
var _stance_target := 1.45
var _mount_x := 0.0
var _dip := 0.0
var _shake := 0.0
var _dip_velocity := 0.0
var _bob_offset := Vector2.ZERO

func _process(delta: float) -> void:
	if not _camera or not _camera.current or GameplayControls.blocked:
		return
	var behind := Input.is_action_pressed("camera_look_behind")
	if behind != looking_behind:
		# Looking behind is a cut, not a pan: apply it at once without interpolating across.
		looking_behind = behind
		_apply_orbit_rotation()
		reset_physics_interpolation()
	if not Input.is_action_pressed("free_look") and not touch_free_look:
		_free_yaw = lerpf(_free_yaw, 0.0, 1.0 - exp(-10.0 * delta))
		_free_active = false
	_since_look += delta
	_update_chase(delta)
	_update_aim(delta)
	_update_gyro(delta)
	_update_peek(delta)
	_update_bob(delta)
	_update_recoil_recovery(delta)

static func clamp_pitch_value(value: float, lower: float, upper: float) -> float:
	return clampf(value, lower, upper)

func _ready() -> void:
	_third_person_position = position
	_mount_x = position.x
	_set_level_mount(view_mode == ViewMode.THIRD_PERSON)
	var spring_arm := get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm:
		spring_arm.spring_length = camera_distance
		_boom_length = camera_distance
		spring_arm.margin = 0.45
		spring_arm.collision_mask = 1
		if _on_foot():
			var probe := SphereShape3D.new()
			probe.radius = boom_probe_radius
			spring_arm.shape = probe
			# A swept ball, unlike a ray, stops dead inside the capsule it starts in.
			spring_arm.add_excluded_object((get_parent() as CollisionObject3D).get_rid())
		_camera = spring_arm.get_node_or_null("Camera3D") as Camera3D
		if _camera:
			# A larger near plane keeps depth precision for road markings across the town.
			_camera.near = 0.15
			_base_fov = _camera.fov
	_yaw = PI * 0.5
	_apply_orbit_rotation()
	if not OS.has_feature("mobile"):
		_capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if not _camera or not _camera.current or GameplayControls.blocked or GameplayControls.text_focused(get_viewport()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_capture_mouse()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_camera_distance(camera_distance - 0.6)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_camera_distance(camera_distance + 0.6)
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_captured = false
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * mouse_sensitivity * (ads_sensitivity if is_aiming else look_sensitivity))
	elif event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			if event.index == _look_touch_index: _look_touch_index = -1
			if event.index == _look_candidate_index: _look_candidate_index = -1
		elif event.pressed and _is_look_zone(event.position):
			_look_candidate_index = event.index
	elif event is InputEventScreenDrag:
		if event.index == _look_candidate_index and event.relative.length_squared() > 16.0:
			_look_touch_index = event.index
		if event.index != _look_touch_index:
			return
		_look(event.relative * mouse_sensitivity * 1.7 * (ads_sensitivity if is_aiming else look_sensitivity))

func _look(amount: Vector2) -> void:
	_since_look = 0.0
	var free := Input.is_action_pressed("free_look") or touch_free_look
	if free and not _free_active: _free_yaw = 0.0
	if free:
		_free_yaw -= amount.x
	else:
		_yaw -= amount.x
	_free_active = free
	_pitch = clamp_pitch_value(_pitch - amount.y, _min_pitch(), _max_pitch())
	# Pulling down against a spray already pays back the recoil; don't settle twice.
	_recoil_debt = maxf(0.0, _recoil_debt - maxf(amount.y, 0.0))

func _capture_mouse() -> void:
	if not _camera or not _camera.current or GameplayControls.blocked:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured = true

func reset_view() -> void:
	if view_mode == ViewMode.FIRST_PERSON:
		_yaw = _forward_yaw()
		_pitch = 0.0
	else:
		_yaw = PI * 0.5
		_pitch = -0.18
	_apply_orbit_rotation()

func toggle_shoulder() -> void:
	_shoulder_sign *= -1.0
	_third_person_position.x = _shoulder_sign * 0.65
	_apply_orbit_rotation()

func set_view_mode(mode: ViewMode) -> void:
	_ads_sight = false
	_ads_blend = 0.0
	if mode == view_mode:
		return
	view_mode = mode
	_set_level_mount(mode == ViewMode.THIRD_PERSON)
	var spring_arm := get_node_or_null("SpringArm3D") as SpringArm3D
	if mode == ViewMode.FIRST_PERSON:
		position = first_person_offset
		if spring_arm:
			spring_arm.spring_length = 0.0
		reset_view()
	else:
		if spring_arm:
			spring_arm.spring_length = camera_distance
			_boom_length = camera_distance
		_yaw = _world_yaw()
		_pitch = clamp_pitch_value(_pitch, min_pitch, max_pitch)
		_apply_orbit_rotation()

## set_view_mode without the reset: yaw and pitch carry over so the aim point holds.
func _switch_view_keep_aim(mode: ViewMode) -> void:
	view_mode = mode
	var spring_arm := get_node_or_null("SpringArm3D") as SpringArm3D
	if mode == ViewMode.FIRST_PERSON:
		position = first_person_offset
		if spring_arm:
			spring_arm.spring_length = 0.0
	elif spring_arm:
		# Start at the eye (_ads_blend is 1): the view travels back out to the shoulder without a jump.
		spring_arm.spring_length = 0.0
	_pitch = clamp_pitch_value(_pitch, _min_pitch(), _max_pitch())
	_set_level_mount(mode == ViewMode.THIRD_PERSON)

## True while third-person aim is borrowing the sight view; the player's chosen view is still TPP.
func is_sight_view() -> bool:
	return _ads_sight

func is_first_person() -> bool:
	return view_mode == ViewMode.FIRST_PERSON

## True while the eye is at the body's head: the model is hidden and the rifle is held to the view.
func hides_body() -> bool:
	return view_mode == ViewMode.FIRST_PERSON or _ads_blend > 0.7

## Where the player is looking up or down (radians, + is up), for the upper body to follow.
func aim_pitch() -> float:
	return _pitch

func _on_foot() -> bool:
	return get_parent() is CharacterBody3D and get_parent().has_method("is_weapon_equipped")

## World yaw that walking directions are measured against; looking behind never flips WASD.
func movement_yaw() -> float:
	return _world_yaw()

func _set_camera_distance(value: float) -> void:
	camera_distance = clampf(value, 3.0, 11.0)
	var spring_arm := get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm and view_mode == ViewMode.THIRD_PERSON:
		spring_arm.spring_length = camera_distance

func _follows_body() -> bool:
	return view_mode == ViewMode.FIRST_PERSON and first_person_follows_body

func _body_yaw() -> float:
	var followed_body := get_parent() as Node3D
	return followed_body.global_rotation.y if followed_body else 0.0

## Converts the stored yaw (body-relative when following the body) into world space.
func _world_yaw() -> float:
	return _yaw + _body_yaw() if _follows_body() else _yaw

## Yaw that points the camera along the body's forward (+Z) axis.
func _forward_yaw() -> float:
	var offset := 0.0 if get_parent().has_method("forward_direction") else PI
	return offset if _follows_body() else _body_yaw() + offset

func _min_pitch() -> float:
	return first_person_min_pitch if view_mode == ViewMode.FIRST_PERSON else min_pitch

func _max_pitch() -> float:
	return first_person_max_pitch if view_mode == ViewMode.FIRST_PERSON else max_pitch

## GTA-style chase camera: once the player stops looking around, the camera eases
## back behind the car's direction of travel, faster the quicker the car goes.
func _update_chase(delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null or not body.has_method("recover_vehicle"):
		return
	var velocity := _body_velocity(body)
	var speed := Vector2(velocity.x, velocity.z).length()
	if _camera:
		var target_fov := _base_fov + speed_fov_boost * clampf(speed / SPEED_FOV_FULL, 0.0, 1.0)
		_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-2.0 * delta))
	if view_mode != ViewMode.THIRD_PERSON or _since_look < chase_delay or speed < 1.5:
		return
	var forward: Vector3 = body.forward_direction() if body.has_method("forward_direction") else body.global_basis.z
	# Follow the direction of travel (so a slide shows the car sideways), but stay behind it when reversing.
	var heading := Vector3(velocity.x, 0.0, velocity.z) if velocity.dot(forward) > 0.0 else forward
	var weight := 1.0 - exp(-chase_stiffness * clampf(speed / 6.0, 0.3, 1.0) * delta)
	_yaw = lerp_angle(_yaw, atan2(heading.x, heading.z) + PI, weight)
	_pitch = lerpf(_pitch, chase_pitch, weight * 0.5)

static func _body_velocity(body: Node3D) -> Vector3:
	if body is CharacterBody3D:
		return (body as CharacterBody3D).velocity
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity
	return Vector3.ZERO

## Third person keeps the pivot level: each physics tick its local transform is
## set so that, through the body, its global basis is yaw/pitch only and its
## offset is yaw-only. Bumps and body roll no longer rock the camera, and because
## the pose is recorded per tick it is interpolated with the body (no 60 Hz steps).
## First person rides with the body as before.
func _set_level_mount(_level: bool) -> void:
	_apply_orbit_rotation()
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	_settle_mount(delta)
	_apply_recoil(delta)
	_apply_orbit_rotation()

## Stance height and shoulder side ease here, in the tick, so they are interpolated with the body.
func _settle_mount(delta: float) -> void:
	if not _on_foot():
		return
	var body := get_parent()
	_stance_y = lerpf(_stance_y, _stance_target, 1.0 - exp(-stance_camera_rate * delta))
	var side := -0.62 * _shoulder_sign if body.is_weapon_equipped() and body.get("combat_mode") == true else _third_person_position.x
	_mount_x = lerpf(_mount_x, side, 1.0 - exp(-shoulder_swap_rate * delta))

## A shot's kick arrives over a few ticks; applying it at once would be a step the interpolation cannot hide.
func _apply_recoil(delta: float) -> void:
	if _recoil_pending == Vector2.ZERO:
		return
	var step := _recoil_pending * (1.0 - exp(-recoil_kick_rate * delta))
	if _recoil_pending.length_squared() < 0.0000001:
		step = _recoil_pending
	_recoil_pending -= step
	_pitch = clamp_pitch_value(_pitch + step.x, _min_pitch(), _max_pitch())
	_yaw += step.y

## How far the camera trails the capsule's height (person_controller.gd), 0 for anything else.
func _height_lag() -> float:
	var lag: Variant = get_parent().get("camera_height_lag")
	return float(lag) if lag != null else 0.0

func _apply_orbit_rotation() -> void:
	var body := get_parent() as Node3D
	if view_mode == ViewMode.THIRD_PERSON and body:
		var body_basis := body.global_basis.orthonormalized()
		var body_yaw := body_basis.get_euler().y
		if body.has_method("forward_direction"):
			body_yaw += PI
		var world_yaw := body_yaw if looking_behind else _yaw + _free_yaw
		var pitch := -0.12 if looking_behind else _pitch
		var roll := -_peek_roll
		var level := Basis.from_euler(Vector3(pitch, world_yaw, roll))
		# Peek -1 is left (Q, "< PEEK"): the camera slides to the character's left (+x), the same way as the
		# roll above and the body's lean (docs/lessons/CHARACTERS.md).
		var peek_lateral := Vector3(-_current_peek * 0.45, 0.0, 0.0)
		var mount := _third_person_position
		var mount_yaw := body_yaw
		if _on_foot():
			mount.x = _mount_x
			mount.y = _stance_y + _height_lag()
			# With a rifle out the body chases the aim with some lag. The shoulder offset follows the aim itself, or
			# the view would swing sideways on every turn while the body caught up.
			if body.is_weapon_equipped() and body.get("combat_mode") == true and not looking_behind:
				mount_yaw = _yaw + PI
			mount = mount.lerp(Vector3(0.0, _stance_y + 0.12 + _height_lag(), 0.0), smoothstep(0.0, 1.0, _ads_blend))
		var offset := Basis(Vector3.UP, mount_yaw) * (mount + peek_lateral)
		transform = Transform3D(body_basis.inverse() * level, body_basis.inverse() * offset)
		return
	var body_yaw := _body_yaw()
	if body and body.has_method("is_weapon_equipped") and body.get("combat_mode") == true:
		position = Vector3(0.0, _stance_y + 0.12 + _height_lag(), 0.0)
	elif _on_foot():
		position.y = first_person_offset.y * _stance_y / 1.45 + _height_lag()
	if looking_behind:
		# GTA-style rear view: face backwards along the body, so first person looks out the back.
		rotation = Vector3(0.0, 0.0, 0.0)
		return
	var relative_yaw := (_yaw if _follows_body() else _yaw - body_yaw) + _free_yaw
	rotation = Vector3(_pitch, relative_yaw, -_peek_roll)

func _is_look_zone(position: Vector2) -> bool:
	var size := get_viewport().get_visible_rect().size
	var normalized := Vector2(position.x / size.x, position.y / size.y)
	return normalized.x >= 0.55 and normalized.y >= 0.08 and normalized.y < 0.88

func _update_aim(delta: float) -> void:
	var body := get_parent()
	if not body is CharacterBody3D or not body.has_method("is_weapon_equipped"):
		is_aiming = false
		return
	var wants_aim: bool = body.get("combat_mode") == true and body.is_weapon_equipped() and (Input.is_action_pressed("aim") or touch_aim)
	is_aiming = wants_aim
	# BGMI/PUBG: aiming from third person looks down the sight in first person and
	# returns to the shoulder view on release, without moving the aim point. The view
	# travels between the two (see _ads_blend) rather than cutting.
	var borrow := wants_aim and (view_mode == ViewMode.THIRD_PERSON or _ads_sight)
	_ads_blend = move_toward(_ads_blend, 1.0 if borrow else 0.0, delta / maxf(ads_view_seconds, 0.001))
	if borrow and view_mode == ViewMode.THIRD_PERSON and _ads_blend >= 1.0:
		_ads_sight = true
		_switch_view_keep_aim(ViewMode.FIRST_PERSON)
	elif not wants_aim and _ads_sight:
		_ads_sight = false
		_switch_view_keep_aim(ViewMode.THIRD_PERSON)
	var running: bool = body.get("is_running") == true and not wants_aim
	_run_blend = lerpf(_run_blend, 1.0 if running else 0.0, 1.0 - exp(-6.0 * delta))
	var view_fov := first_person_fov if view_mode == ViewMode.FIRST_PERSON else lerpf(_base_fov, first_person_fov, _ads_blend)
	var target_fov: float = view_fov * (ads_fov_scale if wants_aim else 1.0) + sprint_fov_boost * _run_blend
	if _camera:
		_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-ads_zoom_rate * delta))
	var spring_arm := get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm and view_mode == ViewMode.THIRD_PERSON:
		var target_distance := (2.2 if wants_aim else 3.2) if body.is_weapon_equipped() and body.get("combat_mode") == true else camera_distance
		_boom_length = lerpf(_boom_length, target_distance, 1.0 - exp(-14.0 * delta))
		_update_boom(spring_arm, delta)
	_boom_exclude_timer -= delta
	if spring_arm and _boom_exclude_timer <= 0.0:
		_boom_exclude_timer = 1.0
		# Other players are solid for the rifle but must not shove the view around.
		for player in get_tree().get_nodes_in_group("network_players"):
			spring_arm.add_excluded_object((player as CollisionObject3D).get_rid())

## An obstacle shortens the boom at once (the camera must not enter the wall); when it clears, the boom lengthens at
## boom_recover_rate instead of popping out. boom_recover_rate alone would also slow zooming, so _boom_limit only
## applies from the moment something was hit until the boom has caught up.
func _update_boom(spring_arm: SpringArm3D, delta: float) -> void:
	var wanted := _boom_length * (1.0 - smoothstep(0.0, 1.0, _ads_blend))
	var hit := spring_arm.get_hit_length()
	if hit < spring_arm.spring_length - spring_arm.margin - 0.05:
		_boom_limit = hit + spring_arm.margin
	elif _boom_limit < wanted:
		_boom_limit += boom_recover_rate * delta
	else:
		_boom_limit = INF
	spring_arm.spring_length = minf(wanted, _boom_limit)

func _update_peek(delta: float) -> void:
	_current_peek = lerpf(_current_peek, target_peek, 1.0 - exp(-16.0 * delta))
	_peek_roll = _current_peek * deg_to_rad(18.0)

func _update_gyro(delta: float) -> void:
	if gyro_mode == GyroMode.OFF:
		return
	if gyro_mode == GyroMode.SCOPE_ON and not is_aiming:
		return
	apply_gyro_sample(Input.get_gyroscope(), delta)

func apply_gyro_sample(sample: Vector3, delta: float) -> void:
	if gyro_mode == GyroMode.OFF or (gyro_mode == GyroMode.SCOPE_ON and not is_aiming): return
	# "Phone as a window": turning the device right looks right, tilting its top towards you looks up.
	_gyro.sensitivity = ads_gyro_sensitivity if is_aiming else gyro_sensitivity
	_gyro.invert_x = gyro_invert_x
	_gyro.invert_y = gyro_invert_y
	_gyro.deadzone = gyro_deadzone
	_gyro.smoothing = gyro_smoothing
	var amount := _gyro.step(sample, delta)
	if amount != Vector2.ZERO:
		_look(amount)

## The view eases to a new stance height (_settle_mount); the capsule has already changed.
func set_stance_height(height: float) -> void:
	_stance_target = height

## A landing: the view drops and springs back. `strength` is 0..1.
func add_landing_dip(strength: float) -> void:
	_dip_velocity -= landing_dip_speed * clampf(strength, 0.0, 1.0) * (0.5 if is_aiming else 1.0)

func clear_touch_look() -> void:
	_look_touch_index = -1
	_look_candidate_index = -1
	touch_aim = false
	touch_free_look = false
	target_peek = 0
	_gyro.reset()

func add_recoil(pitch_kick: float = 0.022, yaw_kick: float = 0.008, yaw_bias := 0.0) -> void:
	_since_look = 0.0
	_recoil_pending += Vector2(pitch_kick, yaw_bias + (randf() - 0.5) * 2.0 * yaw_kick)
	_recoil_debt += pitch_kick
	_since_recoil = 0.0
	if pitch_kick > 0.0:
		_shake = minf(_shake + pitch_kick * shot_shake_per_kick, 1.0)
		if _camera:
			_camera.fov += shot_fov_punch * (shot_shake_aim_scale if is_aiming else 1.0)

## Step-timed head bob through the camera's view offsets (the spring arm owns its
## position): a dip on each footstep and a sway per stride, stronger when sprinting
## and in first person, and still while aiming, airborne or standing.
func _update_bob(delta: float) -> void:
	if not _camera:
		return
	var body := get_parent() as CharacterBody3D
	var target := Vector2.ZERO
	if body and body.has_method("is_weapon_equipped") and body.is_on_floor() and not is_aiming:
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		# Keep time with the character's own stride, so the dip lands on the footstep at every speed.
		var stride: float = body.stride_phase() if body.has_method("stride_phase") else -1.0
		_bob_phase = fposmod((stride - BOB_PLANT_PHASE) * TAU, TAU) if stride >= 0.0 else fmod(_bob_phase + speed * delta / BOB_STRIDE * TAU, TAU)
		var depth := lerpf(bob_walk, bob_run, _run_blend) * clampf(speed / 4.0, 0.0, 1.0)
		if view_mode == ViewMode.THIRD_PERSON:
			depth /= 3.0
		target = Vector2(sin(_bob_phase) * depth * 0.6, -absf(sin(_bob_phase)) * depth)
	var weight := 1.0 - exp(-18.0 * delta)
	var step := minf(delta, 1.0 / 30.0)
	_dip_velocity += (-landing_dip_stiffness * _dip - landing_dip_damping * _dip_velocity) * step
	_dip += _dip_velocity * step
	_bob_offset = _bob_offset.lerp(target, weight)
	_shake = move_toward(_shake, 0.0, shot_shake_decay * delta * maxf(_shake, 0.15))
	var jolt := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * _shake * shot_shake_offset * (shot_shake_aim_scale if is_aiming else 1.0)
	_camera.h_offset = _bob_offset.x + jolt.x
	_camera.v_offset = _bob_offset.y + _dip + jolt.y

## After a burst the muzzle climb eases back down, as in BGMI, instead of leaving
## the view pointing at the sky.
func _update_recoil_recovery(delta: float) -> void:
	_since_recoil += delta
	if _recoil_debt <= 0.0 or _since_recoil < recoil_settle_delay:
		return
	var step := minf(_recoil_debt, maxf(_recoil_recovery_rate(), _recoil_debt * recoil_recovery_stiffness) * delta)
	_recoil_debt -= step
	_pitch = clamp_pitch_value(_pitch - step, _min_pitch(), _max_pitch())

## The rifle in the hands sets how quickly its climb comes back (weapon_catalog.gd).
func _recoil_recovery_rate() -> float:
	var id: Variant = get_parent().get("weapon_id")
	return float(Weapons.stats(int(id)).get("recoil_recovery", recoil_recovery)) if id != null else recoil_recovery
