extends Node3D

## What a shot looks and sounds like on this device: a tracer that travels, a muzzle flash, an impact puff and the
## hit click. Purely local; nothing here reaches the Team Deathmatch host. Meshes and particles are pooled and share
## their materials, so a long burst allocates nothing on a phone.

## Metres per second a tracer travels, how long its streak is, and the shortest time a close shot's tracer lasts.
@export var tracer_speed := 380.0
@export var tracer_length := 7.0
@export var tracer_min_seconds := 0.05
@export var tracer_radius := 0.012
## Muzzle flash: seconds on screen, size in metres, and the brief light it throws (off on mobile, see _ready).
@export var flash_seconds := 0.05
@export var flash_size := 0.42
@export var flash_light_energy := 1.6
@export var flash_light_range := 5.0
## The hit click gets quieter with the distance of the shot, down to `hit_far_db` at `hit_far_distance` metres.
@export var hit_near_db := -7.0
@export var hit_far_db := -15.0
@export var hit_far_distance := 90.0

const PUFF_DUST := Color(0.72, 0.68, 0.6, 0.75)
const PUFF_BODY := Color(0.62, 0.1, 0.08, 0.85)
const PUFF_POOL := 4
const TRACER_POOL := 6
const CLICK_RATE := 22050

var _tracers: Array[Dictionary] = []
var _tracer_mesh: CylinderMesh
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_left := 0.0
var _puffs: Array[CPUParticles3D] = []
var _next_puff := 0
var _click: AudioStreamPlayer
var _head_click: AudioStreamPlayer

func _ready() -> void:
	# Drawn in rendered frames at places the tick knows nothing about.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_tracer_mesh = CylinderMesh.new()
	_tracer_mesh.height = 1.0
	_tracer_mesh.radial_segments = 4
	_tracer_mesh.rings = 1
	_tracer_mesh.top_radius = tracer_radius
	_tracer_mesh.bottom_radius = tracer_radius
	_tracer_mesh.material = _glow_material(Color(1.0, 0.86, 0.55), null)
	_build_flash()
	for _i in PUFF_POOL:
		_puffs.append(_build_puff())
	_click = _build_click(false)
	_head_click = _build_click(true)

func _glow_material(color: Color, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_texture = texture
	return material

func _build_flash() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.62, 0.15, 0.55), Color(1.0, 0.4, 0.05, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := _glow_material(Color.WHITE, texture)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	var mesh := QuadMesh.new()
	mesh.material = material
	_flash = MeshInstance3D.new()
	_flash.mesh = mesh
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	if not OS.has_feature("mobile"):
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = Color(1.0, 0.75, 0.4)
		_flash_light.omni_range = flash_light_range
		_flash_light.visible = false
		add_child(_flash_light)

func _build_puff() -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	mesh.material = material
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))
	var puff := CPUParticles3D.new()
	puff.mesh = mesh
	puff.emitting = false
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.amount = 6
	puff.lifetime = 0.4
	puff.local_coords = false
	puff.direction = Vector3.UP
	puff.spread = 32.0
	puff.gravity = Vector3(0.0, -1.2, 0.0)
	puff.initial_velocity_min = 0.8
	puff.initial_velocity_max = 2.6
	puff.damping_min = 3.0
	puff.damping_max = 5.0
	puff.scale_amount_curve = grow
	puff.color_ramp = fade
	add_child(puff)
	return puff

## A short tick, made here so the game needs no extra sound file. A headshot is higher and rings twice.
func _build_click(headshot: bool) -> AudioStreamPlayer:
	var seconds := 0.11 if headshot else 0.05
	var pitch := 3100.0 if headshot else 2200.0
	var count := int(seconds * CLICK_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in count:
		var time := float(index) / CLICK_RATE
		var ring := exp(-time * 90.0)
		if headshot and time > 0.055:
			ring = exp(-(time - 0.055) * 90.0)
		data.encode_s16(index * 2, int(sin(TAU * pitch * time) * ring * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CLICK_RATE
	stream.data = data
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

## A streak flying from `from` to `to`. Oldest is reused if the pool is full.
func tracer(from: Vector3, to: Vector3) -> void:
	var distance := from.distance_to(to)
	if distance < 0.01:
		return
	var entry: Dictionary
	if _tracers.size() < TRACER_POOL:
		var line := MeshInstance3D.new()
		line.mesh = _tracer_mesh
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		entry = {"line": line}
		_tracers.append(entry)
	else:
		entry = _tracers.pop_front()
		_tracers.append(entry)
	entry.from = from
	entry.direction = (to - from) / distance
	entry.distance = distance
	entry.head = minf(tracer_length, distance)
	entry.speed = minf(tracer_speed, distance / maxf(tracer_min_seconds, 0.001))
	entry.flying = true
	_draw_tracer(entry)

func _draw_tracer(entry: Dictionary) -> void:
	var line: MeshInstance3D = entry.line
	var tip: float = minf(entry.head, entry.distance)
	var tail: float = maxf(entry.head - tracer_length, 0.0)
	if tail >= entry.distance:
		entry.flying = false
		line.visible = false
		return
	line.visible = true
	var direction: Vector3 = entry.direction
	var axis_basis := Basis(Quaternion(Vector3.UP, direction))
	line.global_transform = Transform3D(axis_basis.scaled_local(Vector3(1.0, maxf(tip - tail, 0.01), 1.0)), entry.from + direction * (tip + tail) * 0.5)

## How many tracers are in the air.
func active_tracers() -> int:
	return _tracers.filter(func(entry: Dictionary) -> bool: return entry.flying).size()

func flash(at: Vector3) -> void:
	_flash_left = flash_seconds
	_flash.global_position = at
	_flash.scale = Vector3.ONE * flash_size * randf_range(0.8, 1.2)
	_flash.visible = true
	if _flash_light != null:
		_flash_light.global_position = at
		_flash_light.light_energy = flash_light_energy
		_flash_light.visible = true

func flash_visible() -> bool:
	return _flash.visible

## A puff of dust off the surface, or of red off a body. `normal` points away from the surface.
func puff(at: Vector3, normal: Vector3, body := false) -> void:
	var particles := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	var up := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	particles.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, up)), at + up * 0.03)
	particles.color = PUFF_BODY if body else PUFF_DUST
	particles.restart()

func puffs_playing() -> int:
	return _puffs.filter(func(particles: CPUParticles3D) -> bool: return particles.emitting).size()

## The volume of the click for a hit this many metres away.
func click_volume(distance: float) -> float:
	return lerpf(hit_near_db, hit_far_db, clampf(distance / hit_far_distance, 0.0, 1.0))

func hit_click(headshot: bool, distance: float) -> void:
	var player := _head_click if headshot else _click
	player.volume_db = click_volume(distance)
	player.play()

func _process(delta: float) -> void:
	for entry in _tracers:
		if entry.flying:
			entry.head += entry.speed * delta
			_draw_tracer(entry)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
			if _flash_light != null:
				_flash_light.visible = false
