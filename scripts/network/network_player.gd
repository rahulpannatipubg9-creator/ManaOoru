extends CharacterBody3D
class_name NetworkPlayer

@export var peer_id: int = 1
@export var nickname: String = "RemotePlayer"

var health: float = 100.0
var max_health: float = 100.0
var is_downed: bool = false
var bleedout_time: float = 60.0
var stance: int = 0 # 0 = Stand, 1 = Crouch, 2 = Prone, 3 = Downed
var armed: bool = true
## The same properties and methods the local person offers, so the character animation script can drive a
## remote player exactly like the local one (scripts/player/test_character.gd).
var crouching := false
var prone := false
var peek_input := 0.0
var weapon: Node3D
## The rifle they hold (weapon_catalog.gd), from bits 8 and up of the synced stance code.
var weapon_id := Weapons.M416
## Aiming down the sight (bit 4 of the synced stance code): the rifle is shouldered.
var aiming := false
var _aim_blend := 0.0
var _alive := true
var _hide_at_msec := -1
## Squad: when an eliminated player may reappear; -1 while they are not eliminated.
var _return_at_msec := -1
## How long a dead player's body stays on the ground before it disappears.
const BODY_SECONDS := 2.5

var network_manager: Node = null

# Interpolation targets
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _target_peek: float = 0.0
var _current_peek: float = 0.0

# Visual nodes
var _visual_root: Node3D
var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _legs_mesh: MeshInstance3D
var _weapon_mesh: Node3D
var _muzzle_flash: MeshInstance3D
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _overhead_label: Label3D
var _overhead_status: Label3D

var _flash_timer: float = 0.0
var _character: Node3D
var _skeleton: Skeleton3D
var _previous_position := Vector3.ZERO
var _range_timer := 0.0
var _glow_material: StandardMaterial3D

# Team Deathmatch presentation (docs/TDM_DESIGN.md, section 5). Inactive in free roam.
const TDM_TEAM_COLORS: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.25, 0.45, 1.0)]
const TDM_HEAD_ZONE := 0.35
var tdm_mode := false
var tdm_team := -1
var tdm_show_name := false
var _body_material: StandardMaterial3D
var _armband: MeshInstance3D
## Gunshots carry about 120 m, footsteps about 25 m (docs/TDM_DESIGN.md); both fade with distance.
const TDM_SHOT_RANGE := 120.0
const TDM_STEP_RANGE := 25.0
var last_fired_msec := -100000
var _shot_player: AudioStreamPlayer3D
var _step_player: AudioStreamPlayer3D
var _step_timer := 0.0
var _last_step_position := Vector3.ZERO

const CharacterScript := preload("res://scripts/player/test_character.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
## Beyond this distance from the camera a remote character stops animating (a phone cannot afford 7 rigs).
const ANIMATION_RANGE := 70.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const PRONE_HEIGHT := 0.55
const STAND_RADIUS := 0.42

func _ready() -> void:
	add_to_group("network_players")
	add_to_group("combat_target")
	collision_layer = 1
	collision_mask = 1
	_target_position = global_position
	_target_yaw = rotation.y

	_setup_collision()
	_setup_visuals()
	_setup_character()
	_setup_overhead_ui()
	_previous_position = global_position

func _setup_collision() -> void:
	_collision = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = STAND_RADIUS
	_capsule.height = STAND_HEIGHT
	_collision.shape = _capsule
	_collision.position = Vector3(0, STAND_HEIGHT * 0.5, 0)
	add_child(_collision)

func _setup_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	# Body
	_body_mesh = MeshInstance3D.new()
	var body_capsule := CapsuleMesh.new()
	body_capsule.radius = 0.34
	body_capsule.height = 1.15
	_body_mesh.mesh = body_capsule
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.24, 0.40, 0.55, 1.0) # Tactical squad blue
	_body_material = body_mat
	_body_mesh.material_override = body_mat
	_body_mesh.position = Vector3(0, 1.0, 0)
	_visual_root.add_child(_body_mesh)

	# Head
	_head_mesh = MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = 0.27
	head_sphere.height = 0.54
	_head_mesh.mesh = head_sphere
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.65, 0.48, 0.36, 1.0)
	_head_mesh.material_override = head_mat
	_head_mesh.position = Vector3(0, 1.85, 0)
	_visual_root.add_child(_head_mesh)

	# Legs
	_legs_mesh = MeshInstance3D.new()
	var legs_capsule := CapsuleMesh.new()
	legs_capsule.radius = 0.15
	legs_capsule.height = 0.82
	_legs_mesh.mesh = legs_capsule
	var legs_mat := StandardMaterial3D.new()
	legs_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	_legs_mesh.material_override = legs_mat
	_legs_mesh.position = Vector3(0, 0.42, 0)
	_visual_root.add_child(_legs_mesh)

	# Weapon
	_weapon_mesh = Node3D.new()
	_weapon_mesh.name = "PuppetWeapon"
	var rifle_box := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.12, 0.75)
	rifle_box.mesh = box
	var rifle_mat := StandardMaterial3D.new()
	rifle_mat.albedo_color = Color(0.1, 0.1, 0.12, 1.0)
	rifle_box.material_override = rifle_mat
	_weapon_mesh.add_child(rifle_box)

	# Muzzle flash
	_muzzle_flash = MeshInstance3D.new()
	var flash_sphere := SphereMesh.new()
	flash_sphere.radius = 0.08
	flash_sphere.height = 0.16
	_muzzle_flash.mesh = flash_sphere
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.85, 0.2, 1.0)
	_muzzle_flash.material_override = flash_mat
	_muzzle_flash.position = Vector3(0, 0, -0.42)
	_muzzle_flash.visible = false
	_weapon_mesh.add_child(_muzzle_flash)

	_weapon_mesh.position = Vector3(0.35, 1.15, -0.2)
	_visual_root.add_child(_weapon_mesh)

## Replaces the placeholder capsules with the real character: the same rig, clips and rifle hold as the local
## player. Without the model file the capsules stay.
func _setup_character() -> void:
	if not ResourceLoader.exists(CharacterScript.MALE_MODEL_PATH):
		return
	_character = CharacterScript.new()
	_character.male_only = true
	_character.name = "TestCharacter"
	add_child(_character)
	if _character.male_skeleton == null:
		_character.queue_free()
		_character = null
		return
	_skeleton = _character.male_skeleton
	_visual_root.visible = false
	_build_weapon()

## The rifle in their hands, with the muzzle flash moved onto its barrel.
func _build_weapon() -> void:
	weapon = Weapons.build(weapon_id)
	add_child(weapon)
	if _muzzle_flash.get_parent() != null:
		_muzzle_flash.get_parent().remove_child(_muzzle_flash)
	weapon.add_child(_muzzle_flash)
	_muzzle_flash.position = (weapon.get_node("Muzzle") as Node3D).position + Vector3(0.0, 0.0, 0.02)

## Swaps the rifle when they switch (only once the real character is in use; the capsule keeps its box).
func set_weapon_model(id: int) -> void:
	if not Weapons.is_valid(id) or id == weapon_id:
		return
	weapon_id = id
	if weapon == null:
		return
	_muzzle_flash.get_parent().remove_child(_muzzle_flash)
	_weapon_mesh.add_child(_muzzle_flash)
	remove_child(weapon)
	weapon.free()
	_build_weapon()

## True while the character rig is in use (the capsules are the fallback).
func has_character() -> bool:
	return _character != null

func is_weapon_equipped() -> bool:
	return armed and not is_downed

## Remote players are not moved by physics: they count as standing on the ground unless they are rising or falling.
func puppet_on_floor() -> bool:
	return absf(velocity.y) < 1.5

func _setup_overhead_ui() -> void:
	_overhead_label = Label3D.new()
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.font_size = 18
	_overhead_label.outline_size = 4
	_overhead_label.outline_modulate = Color(0, 0, 0, 0.9)
	_overhead_label.modulate = Color(0.4, 0.85, 1.0, 1.0)
	_overhead_label.position = Vector3(0, 2.3, 0)
	_overhead_label.no_depth_test = true
	add_child(_overhead_label)

	_overhead_status = Label3D.new()
	_overhead_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_status.font_size = 14
	_overhead_status.outline_size = 3
	_overhead_status.outline_modulate = Color(0, 0, 0, 0.9)
	_overhead_status.modulate = Color(0.2, 1.0, 0.4, 1.0)
	_overhead_status.position = Vector3(0, 2.1, 0)
	_overhead_status.no_depth_test = true
	add_child(_overhead_status)
	_update_overhead_display()

func _update_overhead_display() -> void:
	if not _overhead_label or not _overhead_status:
		return
	if tdm_mode:
		# Teammates get a name in their team colour; enemies show nothing. No HP bars.
		_overhead_label.text = nickname
		_overhead_label.visible = tdm_show_name
		_overhead_label.modulate = TDM_TEAM_COLORS[tdm_team] if tdm_team >= 0 else Color.WHITE
		_overhead_status.visible = false
		return
	_overhead_label.text = nickname
	if is_downed:
		_overhead_label.modulate = Color(1.0, 0.25, 0.25, 1.0)
		_overhead_status.text = "Down %.0fs  [H] Revive" % bleedout_time
		_overhead_status.modulate = Color(1.0, 0.3, 0.3, 1.0)
	else:
		_overhead_label.modulate = Color(0.4, 0.85, 1.0, 1.0)
		var hp_percent := int((health / max_health) * 100.0)
		var bars := int((health / max_health) * 10.0)
		var bar_str := ""
		for i in range(10):
			bar_str += "█" if i < bars else "░"
		_overhead_status.text = "HP %d%% [%s]" % [hp_percent, bar_str]
		_overhead_status.modulate = Color(0.2, 1.0, 0.4, 1.0) if hp_percent > 50 else (Color(1.0, 0.8, 0.2, 1.0) if hp_percent > 25 else Color(1.0, 0.3, 0.3, 1.0))

func update_network_state(pos: Vector3, yaw: float, pitch: float, target_stance: int, peek: float, armed: bool, firing: bool) -> void:
	_target_position = pos
	_target_yaw = yaw
	_target_pitch = pitch
	stance = target_stance
	_target_peek = peek
	self.armed = armed
	aiming = (target_stance & 4) != 0
	set_weapon_model(target_stance >> 3)
	target_stance &= 3
	stance = target_stance
	crouching = target_stance == 1
	prone = target_stance == 2 or target_stance == 3
	peek_input = peek
	if firing:
		trigger_firing_effect()

func trigger_firing_effect() -> void:
	last_fired_msec = Time.get_ticks_msec()
	if tdm_mode:
		_play_tdm_sound(true)
	if _muzzle_flash:
		_muzzle_flash.visible = true
		_flash_timer = 0.06

func _process(delta: float) -> void:
	# Flash timer
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and _muzzle_flash:
			_muzzle_flash.visible = false

	# Smooth interpolation
	global_position = global_position.lerp(_target_position, 1.0 - exp(-20.0 * delta))
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-18.0 * delta))
	_current_peek = lerpf(_current_peek, _target_peek, 1.0 - exp(-16.0 * delta))

	if _weapon_mesh:
		_weapon_mesh.visible = armed and not is_downed
	if _character != null:
		var step := global_position - _previous_position
		_previous_position = global_position
		velocity = velocity.lerp(step / maxf(delta, 0.0001), 1.0 - exp(-10.0 * delta))
		_update_rifle(delta)
		_update_animation_range(delta)
		if not _alive and _hide_at_msec > 0 and Time.get_ticks_msec() >= _hide_at_msec:
			visible = false
			_hide_at_msec = -1

	# Downed bleedout handling
	if is_downed:
		# Only a countdown for the name tag: the host decides when they are out (network_manager.gd).
		bleedout_time = maxf(0.0, bleedout_time - delta)

	if tdm_mode:
		_step_timer -= delta
		var moved := global_position.distance_to(_last_step_position)
		_last_step_position = global_position
		if _step_timer <= 0.0 and moved > 0.06 and stance == 0:
			_step_timer = 0.4
			_play_tdm_sound(false)
	_apply_stance_visuals(delta)
	_update_overhead_display()

## Where the rifle is carried, from the synced facing and aim: at the chest, lowered while sprinting.
## (The local player's version is in person_controller.gd.)
func _update_rifle(_delta: float) -> void:
	if weapon == null:
		return
	weapon.visible = armed and not is_downed and _alive
	var sprinting := Vector2(velocity.x, velocity.z).length() > 4.0 and not aiming
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, _delta / 0.16)
	var body_forward := global_basis.z
	var body_right := -global_basis.x
	var chest: Vector3 = _character.chest_position()
	if chest == Vector3.INF:
		var height := PRONE_HEIGHT if (prone or is_downed) else (CROUCH_HEIGHT if crouching else STAND_HEIGHT)
		chest = global_position + Vector3.UP * (height * 0.66 + 0.08)
	var ready := chest - Vector3.UP * 0.08 + body_right * 0.16 + body_forward * 0.22
	var shouldered := chest + Vector3.UP * 0.26 + body_right * 0.17 + body_forward * 0.30
	var lowered := chest - Vector3.UP * 0.16 + body_right * 0.18 + body_forward * 0.18
	if prone:
		ready = chest + body_forward * 0.5 + body_right * 0.12
		shouldered = ready
		lowered = ready
	weapon.global_position = ready.lerp(shouldered, _aim_blend).lerp(lowered, 1.0 if sprinting else 0.0)
	var camera_basis := Basis(Vector3.UP, rotation.y - PI) * Basis(Vector3.RIGHT, _target_pitch)
	var pitch_down := lerpf(deg_to_rad(28.0) if sprinting else deg_to_rad(8.0), 0.0, _aim_blend)
	weapon.global_basis = camera_basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch_down)

## The rig only animates while it is near the camera.
func _update_animation_range(delta: float) -> void:
	_range_timer -= delta
	if _range_timer > 0.0:
		return
	_range_timer = 0.5
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_character.set_process(camera.global_position.distance_to(global_position) < ANIMATION_RANGE)

func _apply_stance_visuals(delta: float) -> void:
	var target_h := STAND_HEIGHT
	var is_prone_pose := (stance == 2 or stance == 3 or is_downed) # Prone or Downed
	var is_crouch_pose := (stance == 1)

	if is_prone_pose:
		target_h = PRONE_HEIGHT
	elif is_crouch_pose:
		target_h = CROUCH_HEIGHT

	_capsule.height = target_h
	_capsule.radius = minf(STAND_RADIUS, target_h * 0.45)
	_collision.position.y = target_h * 0.5

	# Tilt visual root when prone or peeking
	if _visual_root:
		var target_pitch := deg_to_rad(76.0) if is_prone_pose else 0.0
		var target_roll := _current_peek * deg_to_rad(18.0)    # peek -1 leans left, as the local player
		_visual_root.rotation.x = lerpf(_visual_root.rotation.x, target_pitch, 1.0 - exp(-14.0 * delta))
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, target_roll, 1.0 - exp(-14.0 * delta))
		var visual_y := 0.25 if is_prone_pose else (0.65 if is_crouch_pose else 0.0)
		_visual_root.position.y = lerpf(_visual_root.position.y, visual_y, 1.0 - exp(-14.0 * delta))

	# Position overhead label appropriately for stance
	if _overhead_label:
		_overhead_label.position.y = target_h + 0.45
		_overhead_status.position.y = target_h + 0.25

## Marks this puppet as a TDM player: team armband, a name only for teammates, no downed state.
func set_tdm_team(team: int, show_name: bool) -> void:
	tdm_mode = true
	tdm_team = team
	tdm_show_name = show_name
	if _armband == null:
		_armband = MeshInstance3D.new()
		_armband.name = "TeamArmband"
		if _skeleton != null:
			_attach_armband_to_arm()
		else:
			var band := BoxMesh.new()
			band.size = Vector3(0.14, 0.22, 0.24)
			_armband.mesh = band
			_armband.position = Vector3(-0.36, 1.25, 0.0)
			_visual_root.add_child(_armband)
	var band_material := StandardMaterial3D.new()
	band_material.albedo_color = TDM_TEAM_COLORS[team]
	band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_armband.material_override = band_material
	_update_overhead_display()

func _play_tdm_sound(gunshot: bool) -> void:
	var player := _shot_player if gunshot else _step_player
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.stream = load("res://assets/audio/gameplay/%s.wav" % ("shot" if gunshot else "step"))
		player.max_distance = TDM_SHOT_RANGE if gunshot else TDM_STEP_RANGE
		player.unit_size = 12.0 if gunshot else 4.0
		player.volume_db = -6.0 if gunshot else -12.0
		add_child(player)
		if gunshot:
			_shot_player = player
		else:
			_step_player = player
	player.pitch_scale = randf_range(0.93, 1.07)
	player.play()

## A hit from `from_position`: the character flinches away from it, and a following death falls that way.
func notify_hit(from_position: Vector3) -> void:
	_last_hit_from = from_position
	if _character != null:
		_character.play_hit(from_position)

var _last_hit_from := Vector3.INF

## A dead player falls, stays on the ground briefly and then disappears; it cannot be hit while dead.
## A protected one glows softly.
func set_tdm_alive(alive: bool, protected: bool) -> void:
	if _character != null:
		if not alive and _alive:
			_character.play_death(_last_hit_from if _last_hit_from != Vector3.INF else global_position - global_basis.z)
			_hide_at_msec = Time.get_ticks_msec() + int(BODY_SECONDS * 1000.0)
		elif alive and not _alive:
			_character.reset_death()
			_hide_at_msec = -1
			_last_hit_from = Vector3.INF
		visible = alive or (_hide_at_msec > 0 and Time.get_ticks_msec() < _hide_at_msec)
	else:
		visible = alive
	_alive = alive
	if _collision:
		_collision.set_deferred("disabled", not alive)
	if _character != null:
		if _glow_material == null:
			_glow_material = StandardMaterial3D.new()
			_glow_material.albedo_color = Color(0.4, 0.9, 1.0, 0.25)
			_glow_material.emission_enabled = true
			_glow_material.emission = Color(0.4, 0.9, 1.0)
			_glow_material.emission_energy_multiplier = 0.8
			_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mesh_node in _character.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).material_overlay = _glow_material if alive and protected else null
	if _body_material:
		_body_material.emission_enabled = alive and protected
		_body_material.emission = Color(0.4, 0.9, 1.0)
		_body_material.emission_energy_multiplier = 0.9

## A band around the left upper arm, in the team colour (the armband of the design).
func _attach_armband_to_arm() -> void:
	var upper := _skeleton.find_bone("CC_Base_L_Upperarm")
	var forearm := _skeleton.find_bone("CC_Base_L_Forearm")
	if upper < 0 or forearm < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "ArmbandAttachment"
	attachment.bone_name = "CC_Base_L_Upperarm"
	_skeleton.add_child(attachment)
	var upper_rest := _skeleton.get_bone_global_rest(upper)
	var toward_elbow := (_skeleton.get_bone_global_rest(forearm).origin - upper_rest.origin).normalized()
	var axis := upper_rest.basis.orthonormalized().inverse() * toward_elbow
	var band := CylinderMesh.new()
	band.top_radius = 0.062
	band.bottom_radius = 0.062
	band.height = 0.09
	_armband.mesh = band
	_armband.position = axis * 0.12
	_armband.basis = Basis(Quaternion(Vector3.UP, axis))
	attachment.add_child(_armband)

## True when a hit at this height lands on the head (the top of the current stance).
func is_head_hit(hit_y: float) -> bool:
	return hit_y >= global_position.y + _capsule.height - TDM_HEAD_ZONE

## The shooter's client reports what its crosshair hit; the host decides whether it counts.
func tdm_claim_hit(hit_position: Vector3, origin: Vector3, weapon_used := Weapons.M416) -> void:
	if network_manager != null and network_manager.tdm != null and network_manager.tdm.active:
		network_manager.tdm.claim_hit(peer_id, is_head_hit(hit_position.y), origin, hit_position, weapon_used)

func set_nickname(value: String) -> void:
	nickname = value
	_update_overhead_display()

## Squad elimination: the body falls where they died, then try_return() brings them back.
func set_eliminated() -> void:
	is_downed = false
	stance = 0
	set_tdm_alive(false, false)
	_return_at_msec = Time.get_ticks_msec() + int(BODY_SECONDS * 1000.0)

func is_eliminated() -> bool:
	return _return_at_msec >= 0

## Called with each position they report. Once the body has had its time they appear there, without
## sliding across the map from where they died.
func try_return(position_now: Vector3) -> bool:
	if Time.get_ticks_msec() < _return_at_msec:
		return false
	_return_at_msec = -1
	health = max_health
	global_position = position_now
	_target_position = position_now
	_previous_position = position_now
	set_tdm_alive(true, false)
	return true

func set_downed(down: bool) -> void:
	is_downed = down
	if down:
		stance = 3
		bleedout_time = 60.0
	else:
		stance = 0
		health = 25.0
	_update_overhead_display()

## Called when shot by local player or NPC
func take_damage(amount: float) -> void:
	var hit_zone := "body"
	var camera := get_viewport().get_camera_3d()
	if camera:
		var hit_y := camera.global_position.y
		if hit_y >= global_position.y + 1.5:
			hit_zone = "head"
			amount *= 2.5
	if network_manager and network_manager.has_method("report_hit"):
		network_manager.report_hit(peer_id, amount, hit_zone, global_position)
	else:
		# Local fallback if offline testing
		apply_local_damage(amount, hit_zone)

func apply_local_damage(amount: float, hit_zone: String) -> void:
	health = clampf(health - amount, 0.0, max_health)
	# With a network, only the host's word puts someone down: their armour may have saved them.
	if health <= 0.0 and not is_downed and network_manager == null:
		set_downed(true)
	_update_overhead_display()
