extends CharacterBody3D

## On-foot character: camera-relative walking/running, jumping, crouching with a
## resized collider, stair stepping, slope handling, fall damage and knockback
## from gameplay impacts (e.g. being hit by a car).

signal health_changed(health: float, max_health: float)
signal impacted(severity: float, source: Node)
signal knocked_down

const DEFAULT_SPAWN := Vector3(116.0, 1.2, -105.0)
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
const FOOTSTEP_SOUND := "res://assets/audio/gameplay/step.wav"
## Where to put the body back if it ever falls out of the world; set from the map at start-up.
var respawn_position := DEFAULT_SPAWN
## Below this height the body is treated as fallen out of the world; lowered for deep terrain.
var fall_limit := -10.0
@export var walk_speed: float = 4.2
@export var run_speed: float = 7.0
@export var acceleration: float = 16.0
@export var stopping_acceleration: float = 24.0
## With a rifle out the body faces the aim, so moving sideways and backwards is slower than forwards, as in
## other shooters. Fractions of the forward speed.
@export var strafe_speed_scale := 0.9
@export var backward_speed_scale := 0.75
## How quickly the body turns to follow the aim with a rifle out (per second); a little lag reads as weight.
@export var aim_turn_rate := 14.0
@export var air_control: float = 0.35
@export var jump_velocity: float = 7.0
@export_group("Movement feel")
## Pick-up into a sprint; lower than `acceleration` so a sprint builds instead of snapping on.
@export var sprint_acceleration := 18.0
## Grip when the input points against the motion, so a reversal plants the feet instead of drifting round.
@export var reverse_acceleration := 30.0
## Share of the acceleration lost on reaching the target speed: the body eases into its pace (0 = linear).
@export_range(0.0, 0.9) var top_speed_ease := 0.35
## Fraction of the walking speed while aiming down the sight, as in other shooters.
@export var aim_speed_scale := 0.62
## With a rifle out, sprinting needs the motion this far toward where the body faces (1 = dead ahead).
@export_range(-1.0, 1.0) var sprint_facing_limit := 0.35
## Getting down or up from prone costs a moment, during which the body moves at this fraction of its speed.
@export var stance_settle_seconds := 0.45
@export var stance_settle_speed_scale := 0.35
## How fast (per second) the model and the camera catch up after a kerb or stair step lifts the capsule.
@export var step_smooth_rate := 14.0
@export var camera_height_rate := 16.0
## The camera trails a step or a slope by at most this many metres.
@export var camera_height_lag_limit := 0.4
## Fall speed (m/s) that gives the full landing dip; smaller drops dip less, under 2 m/s not at all.
@export var landing_dip_full_speed := 13.0
@export_group("Slide")
## Crouching out of a sprint slides: speed kept at the start, loss per second, longest time, and how far the
## direction bends toward the input (per second).
@export var slide_boost := 1.1
@export var slide_friction := 7.0
@export var slide_seconds := 0.75
@export var slide_steer := 1.2
@export_group("Footsteps")
@export var footstep_quiet_db := -20.0
@export var footstep_loud_db := -9.0
@export var footstep_crouch_db := -8.0
@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 1.15
@export var crouch_speed_scale := 0.5
@export var prone_height := 0.55
@export var prone_speed_scale := 0.32
@export var step_height := 0.4
@export_group("Weapon")
@export var weapon_hold_offset := Vector3(0.24, 1.18, 0.22)
## Metres the rifle trails per rad/s of view turn, its limit, and how fast it follows.
@export var weapon_sway := 0.012
@export var weapon_sway_limit := 0.035
@export var weapon_sway_rate := 12.0
@export_group("Health")
## Damage is only applied in combat modes; reactions (knockback, stagger) always happen.
@export var combat_mode := false
@export var max_health := 100.0
## Landing faster than this (m/s) hurts; with this project's 18 m/s² gravity that is a ~3.6 m drop.
@export var safe_landing_speed := 11.5
@export var fall_damage_per_speed := 9.0
@export var knockdown_severity := 0.6
@onready var camera_pivot: Node3D = $CameraPivot
@onready var body_mesh: Node3D = $Body
@onready var head_mesh: Node3D = $Head
@onready var legs_mesh: Node3D = $Legs
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var water_system: Node
var swimming := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var touch_move_input := Vector2.ZERO
var touch_run_pressed := false
var movement_enabled := true
var is_running := false
var input_authority := true
var crouching := false
var tactical_enabled := false
var downed := false
var _stand_radius := 0.42
var prone := false
var peek_input := 0.0
var touch_peek_input := 0.0
var _prev_z := false
var health := 100.0
## Seconds left during which the character is reeling from an impact and ignores input.
var stagger_time := 0.0
var _capsule: CapsuleShape3D
var _fall_speed := 0.0
var _reaction_tilt := Vector3.ZERO
var weapon: Node3D
var muzzle: Marker3D
## Which rifle is in the hands (weapon_catalog.gd); city_gameplay.gd decides which ones are owned.
var weapon_id := Weapons.M416
var weapon_kick := 0.0
## 0..1 blends of the rifle presentation: raised to the shoulder when aiming, lowered while sprinting.
var _aim_blend := 0.0
var _carry_blend := 0.0
var weapon_draw_time := 0.0
var weapon_reload_time := 0.0
var _ctrl_crouch := false
var _safe_walk_position := Vector3.ZERO
var _safe_walk_timer := 0.0
## Metres the model is drawn below the capsule after a step up, eased away (see _try_step_up).
var step_visual_offset := 0.0
## Metres the camera sits away from the capsule's height, eased away, so steps and slopes never jolt it.
var camera_height_lag := 0.0
var _stance_settle := 0.0
var _slide_time := 0.0
var _slide_direction := Vector2.ZERO
var _footstep_player: AudioStreamPlayer
## Which reload the hands are in: its full length, read when weapon_reload_time is set.
var _reload_total := 0.0
var _reload_last := 0.0
## Eased hump 0..1 of a reload: the rifle comes down, stays down while the hands work, and comes back.
var _reload_blend := 0.0
var _last_aim_forward := Vector3.ZERO
var _sway := 0.0
var _last_health := 100.0

func recover_person() -> bool:
	for target in [_safe_walk_position, respawn_position]:
		if target == Vector3.ZERO:
			continue
		var ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 2.0, target + Vector3.DOWN * 8.0, collision_mask, [get_rid()])
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).angle_to(Vector3.UP) > floor_max_angle:
			continue
		var position: Vector3 = floor_hit.position + Vector3.UP * 0.04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _capsule
		query.transform = Transform3D(global_basis, position + collision_shape.position)
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		global_position = position
		velocity = Vector3.ZERO
		touch_move_input = Vector2.ZERO
		reset_physics_interpolation()
		return true
	return false

func _ready() -> void:
	health = max_health
	# Own copy of the capsule so crouching never resizes another character.
	_capsule = (collision_shape.shape as CapsuleShape3D).duplicate()
	_stand_radius = _capsule.radius
	collision_shape.shape = _capsule
	floor_snap_length = step_height
	floor_max_angle = deg_to_rad(46.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.02
	_last_health = health
	health_changed.connect(_on_health_changed)
	var character := get_node_or_null("TestCharacter")
	if character != null and character.has_signal("foot_planted"):
		character.foot_planted.connect(_on_foot_planted)

## Health is also set directly by the Team Deathmatch host (tdm_local.gd), so any drop flinches the body.
func _on_health_changed(value: float, _maximum: float) -> void:
	var character := get_node_or_null("TestCharacter")
	if value < _last_health and character != null and character.has_method("play_hit"):
		character.play_hit(global_position + global_basis.z)
	_last_health = value

## A foot came down, on the character's own stride. Louder with speed, quieter crouched, silent prone or swimming.
func _on_foot_planted(_side: int, speed: float) -> void:
	if not input_authority or swimming or prone or not is_on_floor():
		return
	if _footstep_player == null:
		_footstep_player = AudioStreamPlayer.new()
		_footstep_player.stream = load(FOOTSTEP_SOUND)
		add_child(_footstep_player)
	_footstep_player.volume_db = lerpf(footstep_quiet_db, footstep_loud_db, clampf(speed / run_speed, 0.0, 1.0)) \
		+ (footstep_crouch_db if crouching else 0.0)
	_footstep_player.pitch_scale = randf_range(0.92, 1.08)
	_footstep_player.play()

## One tick of ground velocity on the flat: eased into top speed, firm when stopping or reversing. Vector, not per
## axis, so a diagonal keeps its direction while the speed builds.
static func step_ground_velocity(current: Vector2, target: Vector2, pickup: float, stopping: float, reversing: float,
		ease_share: float, delta: float) -> Vector2:
	var target_speed := target.length()
	if target_speed < 0.001:
		return current.move_toward(Vector2.ZERO, stopping * delta)
	var along := current.dot(target / target_speed)
	var rate := pickup
	if along < 0.0:
		rate = reversing
	elif current.length() > target_speed + 0.05:
		rate = stopping
	else:
		var fill := clampf(along / target_speed, 0.0, 1.0)
		rate = pickup * (1.0 - ease_share * fill * fill)
	return current.move_toward(target, rate * delta)

func is_sliding() -> bool:
	return _slide_time > 0.0

## One tick of a slide: the body carries on, slowing, and the input bends its path only a little. It ends in the
## crouch walk, in the air, or when a wall takes the speed away.
func _step_slide(braked: Vector2, wanted: Vector2, crouch_speed: float, grounded: bool, delta: float) -> Vector2:
	_slide_time -= delta
	if wanted.length_squared() > 0.01:
		_slide_direction = _slide_direction.slerp(wanted.normalized(), minf(slide_steer * delta, 1.0)).normalized()
	var speed := Vector2(velocity.x, velocity.z).length() - slide_friction * delta
	if not grounded or speed <= crouch_speed:
		_slide_time = 0.0
		return braked
	return _slide_direction * speed

## 0..1 through the current stride, for anything that keeps time with the feet; negative without a character.
func stride_phase() -> float:
	var character := get_node_or_null("TestCharacter")
	return character.stride_phase() if character != null and character.has_method("stride_phase") else -1.0

## Where the upper body should look up or down (radians, + is up): the camera's pitch.
func aim_pitch() -> float:
	return camera_pivot.aim_pitch() if camera_pivot != null and camera_pivot.has_method("aim_pitch") else 0.0

## 0..1 through the reload, or -1 when not reloading.
func reload_progress() -> float:
	return 1.0 - weapon_reload_time / _reload_total if weapon_reload_time > 0.0 and _reload_total > 0.0 else -1.0

static func resolve_keyboard_input() -> Vector2:
	return GameplayControls.movement()

func set_touch_move_input(value: Vector2) -> void:
	touch_move_input = value.limit_length()

func set_touch_run_pressed(value: bool) -> void:
	touch_run_pressed = value

func set_movement_enabled(value: bool) -> void:
	movement_enabled = value
	set_physics_process(value)
	if not value:
		velocity = Vector3.ZERO

func set_input_authority(value: bool) -> void:
	input_authority = value
	if not value:
		touch_move_input = Vector2.ZERO
		touch_run_pressed = false
		velocity = Vector3.ZERO

func set_collision_enabled(value: bool) -> void:
	if collision_shape:
		collision_shape.disabled = not value

## Shoves the character with a velocity change (m/s). Strong hits stagger it and,
## in combat modes, cost health. Used by vehicle impacts and future weapons.
func apply_knockback(velocity_change: Vector3, severity: float, source: Node = null, damage := 0.0) -> void:
	velocity += velocity_change
	stagger_time = maxf(stagger_time, lerpf(0.2, 1.6, clampf(severity, 0.0, 1.0)))
	var flat := Vector3(velocity_change.x, 0.0, velocity_change.z)
	if flat.length_squared() > 0.0001:
		var local := global_transform.basis.inverse() * flat.normalized()
		_reaction_tilt = Vector3(local.z, 0.0, -local.x) * lerpf(0.3, 1.3, clampf(severity, 0.0, 1.0))
	if damage > 0.0:
		take_damage(damage)
	impacted.emit(severity, source)
	if severity >= knockdown_severity:
		knocked_down.emit()

## Shows or hides the rifle held at the ready on the right side.
func set_weapon_equipped(value: bool) -> void:
	if value and not is_weapon_equipped(): weapon_draw_time = 0.35
	if value and weapon == null:
		_build_weapon()
	if weapon:
		weapon.visible = value
	var character := get_node_or_null("TestCharacter")
	if character: character.visible = true

func is_weapon_equipped() -> bool:
	return weapon != null and weapon.visible

## Puts a different rifle in the hands. A drawn rifle is swapped with a short draw; a holstered one
## is only built when it is next drawn.
func set_weapon_model(id: int) -> void:
	if not Weapons.is_valid(id) or id == weapon_id:
		return
	weapon_id = id
	if weapon == null:
		return
	var shown := weapon.visible
	remove_child(weapon)
	weapon.free()
	_build_weapon()
	weapon.visible = shown
	if shown:
		weapon_draw_time = 0.35

func _build_weapon() -> void:
	weapon = Weapons.build(weapon_id)
	weapon.position = weapon_hold_offset
	# Barrel slightly down and across the body, like a low-ready carry.
	weapon.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(-8.0), 0.0)
	add_child(weapon)
	muzzle = weapon.get_node("Muzzle") as Marker3D

func take_damage(amount: float) -> void:
	if not combat_mode or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)

func heal_full() -> void:
	health = max_health
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	if not movement_enabled or not input_authority:
		return
	var allowed := GameplayControls.allows(self)
	if global_position.y < fall_limit:
		global_position = respawn_position
		velocity = Vector3.ZERO
	stagger_time = maxf(stagger_time - delta, 0.0)
	var water_height: float = water_system.surface_at(global_position) if water_system else -INF
	swimming = is_finite(water_height) and global_position.y < water_height - 0.25
	if swimming:
		_swim(delta, allowed, water_height)
		return
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif allowed and not downed and Input.is_action_just_pressed("jump") and stagger_time <= 0.0 and not crouching and not prone:
		velocity.y = jump_velocity

	var input_vector := touch_move_input if touch_move_input.length_squared() > 0.0 else resolve_keyboard_input()
	if stagger_time > 0.0 or not allowed:
		input_vector = Vector2.ZERO
	var direction := Vector3(input_vector.x, 0.0, input_vector.y)
	if direction.length_squared() > 0.0:
		direction = direction.rotated(Vector3.UP, camera_pivot.movement_yaw()).normalized()

	var z_pressed := allowed and not downed and Input.is_action_pressed("prone")
	if z_pressed and not _prev_z:
		_update_stance(false, not prone)
	_prev_z = z_pressed

	var ctrl_held := allowed and not downed and not prone and Input.is_key_pressed(KEY_CTRL)
	if allowed and not downed and Input.is_action_just_pressed("crouch"):
		_ctrl_crouch = false
		if prone:
			_update_stance(true, false)
		else:
			_update_stance(not crouching, false)
	elif ctrl_held and not crouching:
		_ctrl_crouch = true
		_update_stance(true, false)
	elif _ctrl_crouch and not ctrl_held and not downed:
		# Stays set under a low ceiling, so the player stands as soon as there is headroom.
		if crouching:
			_update_stance(false, false)
		_ctrl_crouch = crouching

	var key_peek := 0.0
	if allowed and not downed:
		if Input.is_action_pressed("lean_left"): key_peek -= 1.0
		if Input.is_action_pressed("lean_right"): key_peek += 1.0
	peek_input = (key_peek if absf(key_peek) > 0.0 else touch_peek_input) if (allowed and not downed) else 0.0
	if camera_pivot and "target_peek" in camera_pivot:
		camera_pivot.target_peek = peek_input

	if allowed and not downed and Input.is_action_just_pressed("weapon_toggle"):
		set_weapon_equipped(not is_weapon_equipped())

	var armed_facing := combat_mode and is_weapon_equipped()
	var aiming: bool = armed_facing and camera_pivot.is_aiming
	var wants_sprint: bool = allowed and (touch_run_pressed or Input.is_action_pressed("run")) and not aiming
	# A rifle out faces the aim: no sprinting sideways or backwards.
	if wants_sprint and armed_facing and direction.length_squared() > 0.01 and direction.dot(global_basis.z) < sprint_facing_limit:
		wants_sprint = false
	var target_speed := run_speed if wants_sprint else walk_speed
	if downed:
		target_speed = walk_speed * 0.15
	elif prone:
		target_speed = walk_speed * prone_speed_scale
	elif crouching:
		target_speed = walk_speed * crouch_speed_scale
	is_running = target_speed == run_speed and direction.length_squared() > 0.01 and not prone
	var speed_factor := minf(input_vector.length(), 1.0) if touch_move_input.length_squared() > 0.0 else 1.0
	if combat_mode and is_weapon_equipped() and direction.length_squared() > 0.01:
		var along := direction.normalized().dot(global_basis.z)
		speed_factor *= lerpf(strafe_speed_scale, 1.0, along) if along >= 0.0 else lerpf(strafe_speed_scale, backward_speed_scale, -along)
	if aiming and not prone:
		speed_factor *= aim_speed_scale
	_stance_settle = maxf(_stance_settle - delta, 0.0)
	if _stance_settle > 0.0:
		speed_factor *= stance_settle_speed_scale
	var target_velocity := direction * (target_speed * speed_factor)
	# Little control in the air or while reeling, so knockback and jumps carry momentum.
	var control := air_control if not was_on_floor or stagger_time > 0.0 else 1.0
	var flat := step_ground_velocity(Vector2(velocity.x, velocity.z), Vector2(target_velocity.x, target_velocity.z),
		(sprint_acceleration if is_running else acceleration) * control, stopping_acceleration * control,
		reverse_acceleration * control, top_speed_ease, delta)
	if is_sliding():
		flat = _step_slide(flat, Vector2(direction.x, direction.z), target_speed, was_on_floor, delta)
	velocity.x = flat.x
	velocity.z = flat.y
	if combat_mode and is_weapon_equipped() and not camera_pivot.touch_free_look and not Input.is_action_pressed("free_look"):
		rotation.y = lerp_angle(rotation.y, camera_pivot.movement_yaw() + PI, minf(1.0, delta * aim_turn_rate))
	elif direction.length_squared() > 0.01 and stagger_time <= 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 10.0))
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var height_before := global_position.y
	move_and_slide()
	if is_on_floor() and is_on_wall() and horizontal.length_squared() > 0.01:
		_try_step_up(horizontal * delta)
	if is_on_floor() and not was_on_floor:
		_land()
	_settle_height(global_position.y - height_before, was_on_floor and is_on_floor(), delta)
	_safe_walk_timer += delta
	if is_on_floor() and not is_on_wall() and _safe_walk_timer >= 2.0:
		_safe_walk_position = global_position
		_safe_walk_timer = 0.0
	_animate(delta)

## Climbs kerbs and stairs up to step_height: lift, move, then drop back onto the step.
func _try_step_up(motion: Vector3) -> void:
	var lift := Vector3.UP * step_height
	if test_move(global_transform, lift):
		return
	var raised := global_transform.translated(lift)
	var forward := motion.normalized() * maxf(motion.length(), 0.12)
	if test_move(raised, forward):
		return
	var collision := KinematicCollision3D.new()
	var advanced := raised.translated(forward)
	if not test_move(advanced, -lift, collision):
		return
	var landing := advanced.translated(collision.get_travel())
	var rise := landing.origin.y - global_position.y
	if rise < 0.02:
		return
	# Only accept real steps: the tread ahead must be walkable floor at the new height.
	# (The capsule touches the step's edge first, so its contact normal is tilted.)
	var probe_from := landing.origin + forward.normalized() * 0.25 + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(probe_from, probe_from + Vector3.DOWN * 0.6, collision_mask, [get_rid()])
	var tread := get_world_3d().direct_space_state.intersect_ray(query)
	if tread.is_empty() or (tread.normal as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return
	global_transform = landing
	# The capsule took the step in one tick; the model keeps its height and rises into it.
	step_visual_offset = clampf(step_visual_offset - rise, -step_height, 0.0)

## Lets the capsule change height at once while what the player sees eases after it.
func _settle_height(rise: float, grounded: bool, delta: float) -> void:
	if grounded:
		camera_height_lag = clampf(camera_height_lag - rise, -camera_height_lag_limit, camera_height_lag_limit)
	camera_height_lag *= exp(-camera_height_rate * delta)
	step_visual_offset *= exp(-step_smooth_rate * delta)

func _land() -> void:
	var impact_speed := _fall_speed
	_fall_speed = 0.0
	if impact_speed > 2.0 and camera_pivot != null and camera_pivot.has_method("add_landing_dip"):
		camera_pivot.add_landing_dip(clampf(impact_speed / landing_dip_full_speed, 0.0, 1.0))
	if impact_speed > safe_landing_speed:
		var severity := clampf((impact_speed - safe_landing_speed) / 10.0, 0.0, 1.0)
		take_damage((impact_speed - safe_landing_speed) * fall_damage_per_speed)
		stagger_time = maxf(stagger_time, 0.2 + severity)
		impacted.emit(severity, null)

func _update_stance(wants_crouch: bool, wants_prone: bool) -> void:
	var target_h := prone_height if wants_prone else (crouch_height if wants_crouch else stand_height)
	# Only growing needs headroom. Shrinking is always allowed: a body squeezed under a low ceiling sits partly in
	# the floor, so a headroom query would hit the ground and keep it standing in the ceiling.
	if target_h > _capsule.height + 0.001 and not _has_headroom(target_h):
		return
	if wants_prone != prone:
		_stance_settle = stance_settle_seconds
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if wants_crouch and not crouching and not wants_prone and is_running and is_on_floor() and flat_speed > walk_speed:
		_slide_time = slide_seconds
		_slide_direction = Vector2(velocity.x, velocity.z) / flat_speed
		velocity.x *= slide_boost
		velocity.z *= slide_boost
	elif not wants_crouch or wants_prone:
		_slide_time = 0.0
	prone = wants_prone
	crouching = wants_crouch and not wants_prone
	_capsule.radius = minf(_stand_radius, target_h * 0.45)
	_capsule.height = target_h
	collision_shape.position.y = target_h * 0.5
	camera_pivot.set_stance_height(1.45 * target_h / stand_height)

func _update_crouch(wants_crouch: bool) -> void:
	_update_stance(wants_crouch, false)

func _has_headroom(check_height: float = stand_height) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var standing := _capsule.duplicate() as CapsuleShape3D
	standing.radius = minf(_stand_radius, check_height * 0.45)
	standing.height = check_height
	query.shape = standing
	query.transform = global_transform.translated(Vector3.UP * (check_height * 0.5 + 0.02))
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _animate(delta: float) -> void:
	_update_weapon_presentation(delta)
	if not body_mesh or not head_mesh or not legs_mesh:
		return
	var walk_amount := clampf(Vector2(velocity.x, velocity.z).length() / run_speed, 0.0, 1.0)
	var stride := sin(Time.get_ticks_msec() * 0.012) * 0.12 * walk_amount
	var stance_scale := crouch_height / stand_height if crouching else (prone_height / stand_height if prone else 1.0)
	legs_mesh.rotation.x = stride * (0.35 if prone else 1.0)
	body_mesh.position.y = (1.0 + absf(stride) * 0.12) * stance_scale
	head_mesh.position.y = (1.85 + absf(stride) * 0.08) * stance_scale
	_reaction_tilt = _reaction_tilt.lerp(Vector3.ZERO, clampf(delta * (1.5 if stagger_time > 0.0 else 6.0), 0.0, 1.0))
	# Peek -1 is left (Q, "< PEEK"): rolling by -0.28 rad about +z (forward) tips the figure toward +x, its left.
	var peek_rot := Vector3(0.0, 0.0, peek_input * 0.28)
	var prone_pitch := Vector3(deg_to_rad(75.0), 0.0, 0.0) if prone else Vector3.ZERO
	body_mesh.rotation = _reaction_tilt + peek_rot + prone_pitch
	head_mesh.rotation = _reaction_tilt * 0.6 + peek_rot * 0.7

func _swim(delta: float, allowed: bool, surface: float) -> void:
	var input := touch_move_input if touch_move_input.length_squared() > 0 else resolve_keyboard_input()
	if not allowed:
		input = Vector2.ZERO
	var direction := Vector3(input.x, 0, input.y).rotated(Vector3.UP, camera_pivot.movement_yaw())
	velocity.x = move_toward(velocity.x, direction.x * 3.0, delta * 5.0)
	velocity.z = move_toward(velocity.z, direction.z * 3.0, delta * 5.0)
	velocity.y = clampf((surface - 0.65 - global_position.y) * 4.0, -2.0, 3.0)
	if allowed and Input.is_action_pressed("jump"):
		velocity.y = 4.0
	is_running = false
	_fall_speed = 0.0
	move_and_slide()
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 5.0)
	_animate(delta)

func weapon_muzzle_position() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position + Vector3.UP * 1.3

func _update_weapon_presentation(delta: float) -> void:
	if not is_weapon_equipped(): return
	var camera := get_viewport().get_camera_3d()
	if not camera: return
	weapon_draw_time = maxf(0.0, weapon_draw_time - delta)
	if weapon_reload_time > _reload_last:
		_reload_total = weapon_reload_time
	weapon_reload_time = maxf(0.0, weapon_reload_time - delta)
	_reload_last = weapon_reload_time
	weapon_kick = move_toward(weapon_kick, 0.0, delta * 0.35)
	var aiming: bool = camera_pivot.is_aiming
	var first: bool = camera_pivot.hides_body()
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var sprinting := is_running and not aiming and Vector2(velocity.x, velocity.z).length() > 4.0
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta / 0.12)
	_carry_blend = move_toward(_carry_blend, 1.0 if sprinting else 0.0, delta / (0.12 if aiming else 0.22))
	var aim_ease := smoothstep(0.0, 1.0, _aim_blend)
	var carry_ease := smoothstep(0.0, 1.0, _carry_blend)
	var base: Vector3
	var pitch_down := 0.0
	if first:
		base = camera.global_position + right * (0.105 if aiming else 0.26) - up * (0.22 if aiming else 0.28) + forward * (0.90 if aiming else 0.75)
	else:
		# Third person: the rifle is carried against the body, not hung off the camera. Ready position
		# at the chest, shouldered when aiming, lowered across the body while sprinting.
		var body_forward := global_basis.z
		var body_right := -global_basis.x
		# Carried relative to the chest, so crouching, lying prone and the gait's bob all move it with the body.
		# The rifle's bore sits 0.105 m to its own left, so the origin is placed that much further right.
		var character := get_node_or_null("TestCharacter")
		var chest: Vector3 = character.chest_position() if character != null and character.has_method("chest_position") else Vector3.INF
		if chest == Vector3.INF:
			chest = global_position + Vector3.UP * (_stance_height() * 0.66 + 0.08)
		var ready := chest - Vector3.UP * 0.08 + body_right * 0.16 + body_forward * 0.22
		var shouldered := chest + Vector3.UP * 0.26 + body_right * 0.17 + body_forward * 0.30
		var lowered := chest - Vector3.UP * 0.16 + body_right * 0.18 + body_forward * 0.18
		if prone:
			ready = chest + body_forward * 0.5 + body_right * 0.12
			shouldered = ready
			lowered = ready
		base = ready.lerp(shouldered, aim_ease).lerp(lowered, carry_ease)
		pitch_down = lerpf(deg_to_rad(8.0), 0.0, aim_ease) + deg_to_rad(28.0) * carry_ease
	var draw := weapon_draw_time / 0.35
	var progress := reload_progress()
	_reload_blend = smoothstep(0.0, 0.18, progress) * (1.0 - smoothstep(0.82, 1.0, progress)) if progress >= 0.0 else 0.0
	pitch_down += _reload_blend * 0.35 - weapon_kick * 1.6
	# The rifle's weight: it trails a turn of the view a little, except on the shoulder.
	if _last_aim_forward != Vector3.ZERO:
		var turn := _last_aim_forward.signed_angle_to(forward, Vector3.UP) / maxf(delta, 0.001)
		_sway = lerpf(_sway, clampf(-turn * weapon_sway, -weapon_sway_limit, weapon_sway_limit), 1.0 - exp(-weapon_sway_rate * delta))
	_last_aim_forward = forward
	base += right * _sway * (1.0 - aim_ease)
	weapon.global_position = base - forward * weapon_kick - up * (draw * 0.35 + _reload_blend * 0.12)
	weapon.global_basis = camera.global_basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch_down) * Basis(Vector3.FORWARD, _reload_blend * 0.45)
	var character := get_node_or_null("TestCharacter")
	if character:
		character.visible = not first

func _stance_height() -> float:
	return prone_height if prone else (crouch_height if crouching else stand_height)
