class_name CityEnvironment
extends Node3D
## Local weather, lighting and bounded wet-road grip.
var storm := false
var _storm_timer := 8.0
var _flash := 0.0
var sky_material: ShaderMaterial
var thunder: AudioStreamPlayer
var hour := 16.0
var day_seconds := 1440.0
var auto_time := true
var time_mode := "Automatic"
var night := 0.0
var rain := 0.0
var rain_target := 0.0
var wetness := 0.0
var indoors := false
var auto_weather := true
var lamp_count := 0
var _game: Node
var _world: Node
var _environment: Environment
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var effects_budget := 1.0
var _rain: GPUParticles3D
var _lamps: Array[SpotLight3D] = []
var _lens_material: StandardMaterial3D
var _lamp_positions := PackedVector3Array()
var _headlights: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []
var _elapsed := 0.0
var _weather_elapsed := 0.0
var _weather_phase := 0
var _splashes: Array[MeshInstance3D] = []
var _splash_age := PackedFloat32Array()
var _last_splash := Vector3.ZERO
var _splash_index := 0
var ambience: CityAmbience

func setup(game: Node) -> void:
	_game = game
	_world = game.get_node("World")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_environment = game.get_node("DayEnvironment").environment
	_sun = game.get_node("Sun")
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/city_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("#829ec8")
	_moon.rotation_degrees = Vector3(-45, 130, 0)
	_moon.shadow_enabled = false
	add_child(_moon)
	_materials.append(_world.roads._road_material)
	_materials.append(_world.buildings._material)
	var ground := _world.get_node("Ground")
	if ground.get_child_count() > 0:
		_materials.append(ground.get_child(0).get_child(0).material_override)
	_lamp_positions = _world.street_life.lamp_positions
	_lens_material = StandardMaterial3D.new()
	_lens_material.albedo_color = Color("#ffdea3")
	_lens_material.emission_enabled = true
	_lens_material.emission = Color("#ffce80")
	var count := 6 if OS.has_feature("mobile") else 12
	for i in count:
		var lamp := SpotLight3D.new()
		lamp.light_color = Color("#ffdda0")
		lamp.spot_range = 26.0
		lamp.spot_angle = 65.0
		lamp.spot_attenuation = 0.65
		lamp.rotation_degrees.x = -90.0
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		add_child(lamp)
		_lamps.append(lamp)
		var lens := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.07
		lens.mesh = sphere
		lens.material_override = _lens_material
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(lens)
	lamp_count = _lamps.size()
	for vehicle: Node3D in _game.vehicles:
		if vehicle is GdkHelicopter:
			continue
		var pair: Array[SpotLight3D] = []
		for side: float in [-0.65, 0.65]:
			var light := SpotLight3D.new()
			light.position = Vector3(side, 0.70, 1.85)
			light.rotation.y = PI
			light.spot_range = 32.0
			light.spot_angle = 34.0
			light.light_color = Color("#fff2d2")
			light.shadow_enabled = false
			light.light_energy = 0.0
			vehicle.add_child(light)
			pair.append(light)
		_headlights.append({"vehicle": vehicle, "lights": pair})
	_build_rain()
	_build_splashes()
	ambience = CityAmbience.new()
	add_child(ambience)
	ambience.setup(_world)
	thunder = AudioStreamPlayer.new()
	thunder.stream = load("res://assets/audio/gameplay/thunder.wav")
	thunder.volume_db = -10.0
	add_child(thunder)
	apply_state()

func set_weather(raining: bool) -> void:
	auto_weather = false
	rain_target = 1.0 if raining else 0.0

func cycle_weather() -> void:
	set_weather(rain_target < 0.5)

func set_time_mode(mode: String) -> void:
	if mode not in ["Automatic", "Morning", "Afternoon", "Night"]:
		return
	time_mode = mode
	auto_time = mode == "Automatic"
	if not auto_time:
		set_hour({"Morning": 8.0, "Afternoon": 14.0, "Night": 22.0}[mode])

func set_weather_mode(mode: String) -> void:
	if mode == "Automatic":
		storm = false
		auto_weather = true
		_weather_elapsed = 0.0
		return
	if mode in ["Clear", "Rain", "Storm"]:
		storm = mode == "Storm"
		set_weather(mode != "Clear")

func set_hour(value: float) -> void:
	hour = fposmod(value, 24.0)
	apply_state()

func _process(delta: float) -> void:
	if auto_time:
		hour = fposmod(hour + delta * 24.0 / day_seconds, 24.0)
	_weather_elapsed += delta
	if auto_weather and _weather_elapsed >= 180.0:
		_weather_elapsed = 0.0
		_weather_phase = (_weather_phase + 1) % 4
		rain_target = 0.85 if _weather_phase == 1 else 0.0
	rain = move_toward(rain, rain_target, delta * 0.15)
	wetness = move_toward(wetness, rain, delta * (0.07 if rain > wetness else 0.004))
	var tracked: Node3D = _game.tracked_body()
	var point: Vector3 = tracked.global_position
	_rain.position = point + Vector3.UP * 10.0
	_rain.emitting = effects_budget > 0.0 and rain > 0.05 and not indoors
	_rain.amount_ratio = maxf(0.05, rain * effects_budget)
	if effects_budget >= 0.5:
		_update_splashes(point, delta)
	else:
		for splash in _splashes: splash.visible = false
	ambience.update_mix(point, night, rain, indoors, delta)
	for vehicle: Node in _game.vehicles:
		if vehicle is RigidVehicle:
			vehicle.weather_grip = lerpf(1.0, 0.62, wetness)
	_flash = maxf(0.0, _flash - delta * 5.0)
	if storm and rain > 0.5:
		_storm_timer -= delta
		if _storm_timer <= 0.0:
			_storm_timer = randf_range(7.0, 18.0)
			_flash = 1.0
			if thunder:
				thunder.play()
	if _flash > 0.0 and not indoors:
		_sun.light_energy = maxf(_sun.light_energy, _flash * 2.0)
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		apply_state()

func apply_state() -> void:
	var elevation := sin((hour - 6.0) / 24.0 * TAU)
	night = 1.0 - smoothstep(-0.12, 0.25, elevation)
	if sky_material:
		sky_material.set_shader_parameter("daylight", 1.0 - night)
		sky_material.set_shader_parameter("storminess", rain)
		sky_material.set_shader_parameter("clock_hour", hour)
	_sun.rotation_degrees = Vector3(-(hour - 6.0) * 15.0, -28.0, 0.0)
	_sun.light_energy = maxf(0.0, elevation) * 0.78 * (1.0 - rain * 0.4)
	_sun.light_color = Color("#ffbf87").lerp(Color("#fff6e8"), smoothstep(0.0, 0.55, elevation))
	_moon.light_energy = night * 0.20
	_environment.background_color = Color("#91b8cc").lerp(Color("#111e35"), night).lerp(Color("#657b8b"), rain * (1.0 - night) * 0.65)
	_environment.ambient_light_color = Color("#c0cbd2").lerp(Color("#91a3c9"), night)
	_environment.ambient_light_energy = lerpf(0.30, 0.22, night)
	# Keep white walls and dusty ground readable in clear daylight. Night keeps
	# its previous exposure/fill so this daytime correction does not crush it.
	_environment.tonemap_exposure = lerpf(0.78, 0.85, night)
	_environment.fog_light_color = Color("#a1afb5").lerp(Color("#162438"), night).lerp(Color("#71818a"), rain * (1.0 - night) * 0.65)
	_environment.fog_density = lerpf(0.00025, 0.0015, rain)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("city_night", night)
		material.set_shader_parameter("city_wetness", wetness)
	if _world.drainage:
		_world.drainage._water_material.set_shader_parameter("rain_amount", rain)
		_world.drainage._concrete_material.set_shader_parameter("city_wetness", wetness)
	_lens_material.emission_energy_multiplier = night * 2.0
	var at: Vector3 = _game.tracked_body().global_position
	var sorted: Array[int] = []
	for i in _lamp_positions.size():
		if _lamp_positions[i].distance_squared_to(at) < 150.0 * 150.0:
			sorted.append(i)
	sorted.sort_custom(func(a: int, b: int) -> bool: return _lamp_positions[a].distance_squared_to(at) < _lamp_positions[b].distance_squared_to(at))
	for i in _lamps.size():
		_lamps[i].visible = night > 0.03 and i < sorted.size() and not indoors
		if i < sorted.size():
			_lamps[i].global_position = _lamp_positions[sorted[i]]
			_lamps[i].light_energy = night * 4.0
	for entry: Dictionary in _headlights:
		for light: SpotLight3D in entry.lights:
			light.light_energy = 1.5 * maxf(night, rain * 0.6) if entry.vehicle == _game.active_vehicle and _game.control_state == _game.ControlState.DRIVING else 0.0
	var index := 0
	for vehicle: Node in _world.traffic.get_children():
		if vehicle is TrafficVehicle:
			vehicle.night_factor = night
			vehicle.night_active = index % 3 == 0
			index += 1

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 250 if OS.has_feature("mobile") else 800
	_rain.lifetime = 0.8
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-18, -20, -18), Vector3(36, 40, 36))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(12, 7, 12)
	process.direction = Vector3(-0.12, -1, 0.07)
	process.spread = 2.0
	process.initial_velocity_min = 20.0
	process.initial_velocity_max = 25.0
	process.gravity = Vector3(0, -12, 0)
	_rain.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.55)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#9caebc")
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = material
	_rain.draw_pass_1 = mesh
	_rain.emitting = false
	add_child(_rain)

func _build_splashes() -> void:
	for i in 8:
		var splash := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.09
		ring.outer_radius = 0.12
		ring.rings = 8
		ring.ring_segments = 12
		splash.mesh = ring
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.68, 0.74, 0.73, 0.0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		splash.material_override = material
		splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		splash.visible = false
		add_child(splash)
		_splashes.append(splash)
		_splash_age.append(2.0)

func _update_splashes(point: Vector3, delta: float) -> void:
	if rain > 0.2 and not indoors and point.distance_to(_last_splash) > 0.7:
		var ground: float = _world.ground_height(Vector2(point.x, point.z))
		if absf(point.y - ground) < 3.0:
			var splash := _splashes[_splash_index]
			splash.position = Vector3(point.x, ground + 0.06, point.z)
			_splash_age[_splash_index] = 0.0
			_splash_index = (_splash_index + 1) % _splashes.size()
		_last_splash = point
	for i in _splashes.size():
		_splash_age[i] += delta
		_splashes[i].visible = _splash_age[i] < 0.6 and not indoors
		if _splashes[i].visible:
			_splashes[i].scale = Vector3.ONE * (1.0 + _splash_age[i] * 8.0)
			var mat: StandardMaterial3D = _splashes[i].material_override
			mat.albedo_color.a = (1.0 - _splash_age[i] / 0.6) * 0.35

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
