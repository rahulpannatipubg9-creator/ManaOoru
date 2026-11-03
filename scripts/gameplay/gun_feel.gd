extends Node

## How a rifle sounds and looks when it fires: shots, reload sounds, muzzle flash, tracers, casings, impacts
## and hit feedback. Presentation only: it never touches damage, fire rate or network claims.
##
## Everything comes from fixed pools built once in setup(), so a long spray allocates nothing. A new shot
## takes over the oldest entry of its pool, which keeps every count bounded on phones.

const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

const AUDIO_PATH := "res://assets/audio/guns/%s.wav"
const SHOT_VARIATIONS := 4
## The longest tail is 0.54 s and the fastest rifle fires every 0.11 s, so six voices never cut a tail short.
const SHOT_VOICES := 6
const SHOT_DB := -11.0
const FEEDBACK_DB := -12.0
const REMOTE_VOICES := 6
const REMOTE_RANGE := 220.0
## Beyond this a shot is the low thud of a distant rifle, arriving late.
const DISTANT_METERS := 45.0
const SPEED_OF_SOUND := 343.0
const MAX_DELAYED_SOUNDS := 8
## A round passing this close to the listener snaps past them.
const NEAR_MISS_METERS := 2.5
const NEAR_MISS_MIN_RANGE := 8.0
const TRACER_EVERY := 3
const TRACER_SECONDS := 0.06
const TRACER_POOL := 6
const FLASH_SECONDS := 0.045
const MARK_POOL := 32
const MARK_SIZE := 0.11
const PUFF_POOL := 5
const CASING_POOL := 8
const CASING_SECONDS := 0.5
const GRAVITY := 9.8
## Phones keep half of every pool and fewer particles: effects must never cost a frame in a fight.
const MOBILE_POOL_SHARE := 0.5
const MOBILE_PARTICLE_SHARE := 0.6
## Shots further apart than this start a new burst, so the first round of a tap is always the steadiest.
const BURST_GAP_SECONDS := 0.28
const CLIMB_PER_SHOT := 0.05
const CLIMB_SHOTS := 8
const SPREAD_PER_SHOT := 0.09
const ADS_RECOIL := 0.7
const FOV_KICK := 0.45

## The pieces of a reload, as parts of its length.
const RELOAD_STEPS := [["mag_out", 0.05], ["mag_in", 0.6], ["bolt", 0.85]]
const SOUND_NAMES := {Weapons.M416: "m416", Weapons.AK47: "ak47", Weapons.BREN2: "bren2"}

enum Surface { DUST, SPARK, FLESH }

var game: Node
var shots_fired := 0

var _shot_streams: Dictionary = {}
var _distant_streams: Array[AudioStream] = []
var _feedback: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_index := 0
var _last_variation := -1
var _remote_voices: Array[AudioStreamPlayer3D] = []
var _remote_index := 0
var _delayed: Array[Dictionary] = []
var _feedback_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer
var _reload_steps: Array[Dictionary] = []
var _reload_elapsed := 0.0
var _burst_shots := 0
var _since_shot := 1000.0
var _tracers: Array[MeshInstance3D] = []
var _tracer_left: Array[float] = []
var _tracer_index := 0
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_left := 0.0
var _marks: Array[MeshInstance3D] = []
var _mark_index := 0
var _puffs: Dictionary = {}
var _puff_index: Dictionary = {}
var _casings: Array[Dictionary] = []
var _casing_index := 0
var _session: Node
var _pending_flesh := Vector3.INF

## How many of an effect this device keeps.
static func pool_size(desktop: int, mobile := OS.has_feature("mobile")) -> int:
	return ceili(desktop * MOBILE_POOL_SHARE) if mobile else desktop

## How many particles one puff throws on this device.
static func particle_count(desktop: int, mobile := OS.has_feature("mobile")) -> int:
	return ceili(desktop * MOBILE_PARTICLE_SHARE) if mobile else desktop

func setup(owner_game: Node) -> void:
	game = owner_game
	name = "GunFeel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("gun_feel")
	_load_sounds()
	_build_voices()
	_build_tracers()
	_build_flash()
	_build_marks()
	_build_puffs()
	if not OS.has_feature("mobile"):
		_build_casings()

# --- Called by the game ------------------------------------------------------------

## One local round. `hit` is the physics result (or empty), and `struck_flesh` is true when it stopped in
## a person who is hurt at once (free-roam residents). Team Deathmatch players bleed only on the host's word.
func on_shot(weapon_id: int, muzzle: Vector3, endpoint: Vector3, hit: Dictionary, struck_flesh: bool) -> void:
	shots_fired += 1
	_since_shot = 0.0
	_play_shot(weapon_id)
	_show_flash(muzzle)
	_eject_casing(muzzle)
	if shots_fired % TRACER_EVERY == 1:
		_show_tracer(muzzle, endpoint)
	_kick_fov()
	_pending_flesh = Vector3.INF
	if struck_flesh:
		_impact_flesh(endpoint)
		play_feedback("hit_body")
	elif not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("tdm_claim_hit"):
			_pending_flesh = endpoint
		elif collider != null and collider.has_method("tdm_dummy_hit"):
			_impact_flesh(endpoint)
			play_feedback("hit_body")
		else:
			_impact_surface(endpoint, hit.get("normal", Vector3.UP), collider)

## The camera kick for the next round: a climb that builds over a burst, with the side wander widening.
func recoil_for(base: Vector2) -> Vector2:
	var kick := recoil_step(base, _burst_shots)
	_burst_shots += 1
	var pivot: Node = game.person.camera_pivot if game != null else null
	if pivot != null and pivot.get("is_aiming") == true:
		kick *= ADS_RECOIL
	return kick

static func recoil_step(base: Vector2, shot_index: int) -> Vector2:
	var step := mini(shot_index, CLIMB_SHOTS)
	return Vector2(base.x * (1.0 + step * CLIMB_PER_SHOT), base.y * (1.0 + step * SPREAD_PER_SHOT))

func play_dry() -> void:
	play_feedback("dry_click")

func play_reload(seconds: float) -> void:
	_reload_steps.clear()
	_reload_elapsed = 0.0
	for step: Array in RELOAD_STEPS:
		_reload_steps.append({"sound": step[0], "at": seconds * float(step[1])})

func cancel_reload() -> void:
	_reload_steps.clear()

## Hit marker sounds, from the host's confirmation.
func on_hit_confirmed(_victim: int, headshot: bool, killed: bool) -> void:
	if _pending_flesh != Vector3.INF:
		_impact_flesh(_pending_flesh)
		_pending_flesh = Vector3.INF
	if killed:
		_ui_player.stream = _feedback.kill_confirm
		_ui_player.play()
	play_feedback("hit_head" if headshot else "hit_body")

## A shot by someone else: close ones crack, far ones thud and arrive late, and a round that passes the
## listener snaps by. `forward` is where the shooter faces. Returns true when the shot was handled here.
func remote_shot(weapon_id: int, position: Vector3, forward: Vector3) -> bool:
	var listener := _listener_position()
	var distance := listener.distance_to(position)
	if distance > REMOTE_RANGE:
		return true
	var far := distance > DISTANT_METERS
	var stream: AudioStream = _distant_streams.pick_random() if far else _shot_streams[_sound_name(weapon_id)].pick_random()
	if far:
		if _delayed.size() < MAX_DELAYED_SOUNDS:
			_delayed.append({"stream": stream, "position": position, "in": distance / SPEED_OF_SOUND})
	else:
		_play_remote(stream, position)
	if near_miss(position, forward, listener):
		play_feedback("near_crack")
	return true

static func near_miss(position: Vector3, forward: Vector3, listener: Vector3) -> bool:
	var along := (listener - position).dot(forward)
	if along < NEAR_MISS_MIN_RANGE:
		return false
	return listener.distance_to(position + forward * along) < NEAR_MISS_METERS

func play_feedback(sound: String) -> void:
	_feedback_player.stream = _feedback[sound]
	_feedback_player.pitch_scale = randf_range(0.97, 1.03)
	_feedback_player.play()

# --- Per frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_connect_session()
	_since_shot += delta
	if _since_shot > BURST_GAP_SECONDS:
		_burst_shots = 0
	_tick_reload(delta)
	_tick_delayed(delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
			if _flash_light != null:
				_flash_light.visible = false
	for index in _tracers.size():
		if _tracer_left[index] > 0.0:
			_tracer_left[index] -= delta
			if _tracer_left[index] <= 0.0:
				_tracers[index].visible = false
	for casing: Dictionary in _casings:
		if casing.left > 0.0:
			_tick_casing(casing, delta)

## The session is created after the gameplay node.
func _connect_session() -> void:
	if _session != null or game == null:
		return
	_session = game.get("tdm_session")
	if _session != null:
		_session.hit_confirmed.connect(on_hit_confirmed)

func _tick_reload(delta: float) -> void:
	if _reload_steps.is_empty():
		return
	_reload_elapsed += delta
	if _reload_elapsed >= float(_reload_steps[0].at):
		play_feedback(String(_reload_steps.pop_front().sound))

func _tick_delayed(delta: float) -> void:
	for index in range(_delayed.size() - 1, -1, -1):
		var sound: Dictionary = _delayed[index]
		sound.in -= delta
		if sound.in <= 0.0:
			_play_remote(sound.stream, sound.position)
			_delayed.remove_at(index)

func _tick_casing(casing: Dictionary, delta: float) -> void:
	casing.left -= delta
	var node: MeshInstance3D = casing.node
	if casing.left <= 0.0:
		node.visible = false
		return
	casing.velocity += Vector3.DOWN * GRAVITY * delta
	node.global_position += casing.velocity * delta
	node.rotate_x(delta * 24.0)

# --- Sound -------------------------------------------------------------------------

func _load_sounds() -> void:
	for sound_name: String in SOUND_NAMES.values():
		var streams: Array[AudioStream] = []
		for variation in range(1, SHOT_VARIATIONS + 1):
			streams.append(load(AUDIO_PATH % ("%s_%d" % [sound_name, variation])))
		_shot_streams[sound_name] = streams
	for variation in [1, 2]:
		_distant_streams.append(load(AUDIO_PATH % ("distant_%d" % variation)))
	for sound in ["near_crack", "dry_click", "mag_out", "mag_in", "bolt", "hit_body", "hit_head", "kill_confirm"]:
		_feedback[sound] = load(AUDIO_PATH % sound)

func _build_voices() -> void:
	for _i in pool_size(SHOT_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = SHOT_DB
		add_child(voice)
		_voices.append(voice)
	for _i in pool_size(REMOTE_VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = REMOTE_RANGE
		voice.unit_size = 14.0
		voice.volume_db = -5.0
		add_child(voice)
		_remote_voices.append(voice)
	_feedback_player = AudioStreamPlayer.new()
	_feedback_player.volume_db = FEEDBACK_DB
	add_child(_feedback_player)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.volume_db = FEEDBACK_DB - 4.0
	add_child(_ui_player)

func _sound_name(weapon_id: int) -> String:
	return String(SOUND_NAMES.get(weapon_id, SOUND_NAMES[Weapons.M416]))

## Never the same take twice running, and a small pitch change on top: no machine-gun repetition.
func _play_shot(weapon_id: int) -> void:
	var streams: Array = _shot_streams[_sound_name(weapon_id)]
	var variation := randi_range(0, streams.size() - 2)
	if variation >= _last_variation:
		variation += 1
	_last_variation = variation
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = streams[variation]
	voice.pitch_scale = randf_range(0.97, 1.03)
	voice.play()

func _play_remote(stream: AudioStream, position: Vector3) -> void:
	var voice := _remote_voices[_remote_index]
	_remote_index = (_remote_index + 1) % _remote_voices.size()
	voice.stream = stream
	voice.global_position = position
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()

func _listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else game.person.global_position

# --- Sight -------------------------------------------------------------------------

func _unlit(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _build_tracers() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009
	mesh.bottom_radius = 0.009
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 1
	mesh.material = _unlit(Color("ffe29a"))
	for _i in pool_size(TRACER_POOL):
		var line := MeshInstance3D.new()
		line.mesh = mesh
		line.visible = false
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.top_level = true
		add_child(line)
		_tracers.append(line)
		_tracer_left.append(0.0)

func _show_tracer(from: Vector3, to: Vector3) -> void:
	var distance := from.distance_to(to)
	if distance < 0.5:
		return
	var line := _tracers[_tracer_index]
	_tracer_left[_tracer_index] = TRACER_SECONDS
	_tracer_index = (_tracer_index + 1) % _tracers.size()
	line.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, (to - from).normalized())).scaled(Vector3(1.0, distance, 1.0)), (from + to) * 0.5)
	line.visible = true

func _build_flash() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := _unlit(Color(1.0, 0.78, 0.25))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.albedo_texture = _flash_texture()
	mesh.material = material
	_flash = MeshInstance3D.new()
	_flash.mesh = mesh
	_flash.visible = false
	_flash.top_level = true
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	# A light each frame of fire is the one thing phones can't afford.
	if not OS.has_feature("mobile"):
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = Color(1.0, 0.75, 0.4)
		_flash_light.light_energy = 2.2
		_flash_light.omni_range = 7.0
		_flash_light.visible = false
		_flash_light.top_level = true
		add_child(_flash_light)

## A soft star, drawn once: the billboard's spin and size make each flash different.
func _flash_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	gradient.set_color(1, Color(1.0, 0.55, 0.1, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 48
	texture.height = 48
	return texture

func _show_flash(at: Vector3) -> void:
	var size := randf_range(0.22, 0.4)
	_flash.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(size, size * randf_range(0.8, 1.2), 1.0)), at)
	_flash.visible = true
	_flash_left = FLASH_SECONDS
	if _flash_light != null:
		_flash_light.global_position = at
		_flash_light.light_energy = randf_range(1.6, 2.6)
		_flash_light.visible = true

func _kick_fov() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		camera.fov += FOV_KICK

func _build_marks() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := _unlit(Color(0.05, 0.05, 0.05, 0.75))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _mark_texture()
	mesh.material = material
	for _i in pool_size(MARK_POOL):
		var mark := MeshInstance3D.new()
		mark.mesh = mesh
		mark.visible = false
		mark.top_level = true
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		_marks.append(mark)

func _mark_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.45, Color(1, 1, 1, 0.8))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture

func _place_mark(at: Vector3, normal: Vector3) -> void:
	var mark := _marks[_mark_index]
	_mark_index = (_mark_index + 1) % _marks.size()
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var size := MARK_SIZE * randf_range(0.7, 1.2)
	var facing := Basis.looking_at(-normal, up).rotated(normal, randf() * TAU)
	mark.global_transform = Transform3D(facing.scaled(Vector3.ONE * size), at + normal * 0.012)
	mark.visible = true

func _puff_emitter(color: Color, count: int, speed: float, life: float, size: float) -> CPUParticles3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size
	var material := _unlit(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = material
	var puff := CPUParticles3D.new()
	puff.mesh = mesh
	puff.amount = particle_count(count)
	puff.lifetime = life
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.emitting = false
	puff.top_level = true
	puff.local_coords = false
	puff.direction = Vector3.BACK
	puff.spread = 35.0
	puff.initial_velocity_min = speed * 0.5
	puff.initial_velocity_max = speed
	puff.gravity = Vector3.DOWN * 3.0
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	return puff

func _build_puffs() -> void:
	var looks := {
		Surface.DUST: [Color(0.62, 0.56, 0.46, 0.55), 5, 1.6, 0.35, 0.09],
		Surface.SPARK: [Color(1.0, 0.82, 0.4, 1.0), 6, 5.5, 0.14, 0.025],
		Surface.FLESH: [Color(0.5, 0.03, 0.03, 0.85), 6, 2.4, 0.25, 0.07],
	}
	for surface: int in looks:
		var look: Array = looks[surface]
		var list: Array[CPUParticles3D] = []
		for _i in pool_size(PUFF_POOL):
			list.append(_puff_emitter(look[0], look[1], look[2], look[3], look[4]))
		_puffs[surface] = list
		_puff_index[surface] = 0

func _emit_puff(surface: int, at: Vector3, normal: Vector3) -> void:
	var list: Array = _puffs[surface]
	var index: int = _puff_index[surface]
	_puff_index[surface] = (index + 1) % list.size()
	var puff: CPUParticles3D = list[index]
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	puff.global_transform = Transform3D(Basis.looking_at(-normal, up), at)
	puff.restart()

## Metal bodies spark; walls and ground give dust and keep a mark.
static func surface_of(collider: Object) -> int:
	return Surface.SPARK if collider is PhysicsBody3D and not collider is StaticBody3D else Surface.DUST

func _impact_surface(at: Vector3, normal: Vector3, collider: Object) -> void:
	var surface := surface_of(collider)
	_emit_puff(surface, at, normal)
	if surface == Surface.DUST:
		_place_mark(at, normal)

func _impact_flesh(at: Vector3) -> void:
	var toward := (_listener_position() - at).normalized()
	_emit_puff(Surface.FLESH, at, toward)

func _build_casings() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0055
	mesh.bottom_radius = 0.0055
	mesh.height = 0.045
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.material = _unlit(Color(0.78, 0.6, 0.25))
	for _i in CASING_POOL:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.visible = false
		node.top_level = true
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_casings.append({"node": node, "velocity": Vector3.ZERO, "left": 0.0})

## Thrown out to the rifle's right, a little up and back. Purely for the eye: casings pass through the world.
func _eject_casing(muzzle: Vector3) -> void:
	if _casings.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var casing: Dictionary = _casings[_casing_index]
	_casing_index = (_casing_index + 1) % _casings.size()
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	var node: MeshInstance3D = casing.node
	node.global_position = muzzle - forward * 0.35
	casing.velocity = right * randf_range(1.8, 2.8) + Vector3.UP * randf_range(1.4, 2.2) - forward * randf_range(0.2, 0.6)
	casing.left = CASING_SECONDS
	node.visible = true
