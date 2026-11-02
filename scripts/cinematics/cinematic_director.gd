extends Node3D

## Cinematic Sequence Director for "Mana Ooru: Chowrastha Takedown"
## Coordinates 8 frame-synchronized cinematic shots, vehicle chase, helicopter air support,
## sunset sky atmosphere, deterministic shootout with muzzle flashes, frame-accurate martial arts CQC,
## soft radial impact sparks, camera trauma shake, and visceral fatal knockdown.

const DURATION := 20.0 # Exactly 20.0 seconds
const FPS := 30.0
const TOTAL_FRAMES := int(DURATION * FPS) # Exactly 600 frames

var current_frame := 0
var elapsed := 0.0
var is_initialized := false

# Scene Nodes
@onready var camera: Camera3D = $Camera3D
var environment: WorldEnvironment
var sun: DirectionalLight3D
var road_root: Node3D

# Actors
var hero: Node3D
var hero_anim: AnimationPlayer
var hero_skeleton: Skeleton3D
var hero_gun: Node3D
var hero_muzzle_light: OmniLight3D
var hero_muzzle_flash: MeshInstance3D

var target_op: Node3D
var target_anim: AnimationPlayer
var target_skeleton: Skeleton3D
var target_gun: Node3D
var target_muzzle_light: OmniLight3D
var target_muzzle_flash: MeshInstance3D

# Hit Spark & Camera Shake FX
var impact_spark: MeshInstance3D
var impact_light: OmniLight3D
var impact_frames_remaining := 0
var trauma := 0.0
const TRAUMA_DECAY := 2.6
const MAX_TRAUMA_OFFSET := Vector3(0.09, 0.09, 0.06)
const MAX_TRAUMA_ROT := Vector3(0.03, 0.03, 0.04)

# Vehicles
var target_car: Node3D
var pursuit_car: Node3D
var helicopter: Node3D
var heli_spotlight: SpotLight3D

# Audio Players
var sfx_engine: AudioStreamPlayer
var sfx_siren: AudioStreamPlayer
var sfx_shot: AudioStreamPlayer
var sfx_punch: AudioStreamPlayer
var sfx_crash: AudioStreamPlayer
var sfx_door: AudioStreamPlayer

# UI Overlay
var letterbox_top: ColorRect
var letterbox_bottom: ColorRect
var title_label: Label
var subtitle_label: Label
var location_label: Label

# Bullet Tracers
var tracers: Array[Dictionary] = []

func _ready() -> void:
	if not is_initialized:
		_initialize_all()
	print("Cinematic Pursuit Director ready. Total frames: %d (%.1fs at %.0f FPS)" % [TOTAL_FRAMES, DURATION, FPS])

func _initialize_all() -> void:
	is_initialized = true
	_setup_environment()
	_setup_road_and_scenery()
	_setup_actors()
	_setup_impact_fx()
	_setup_vehicles()
	_setup_audio()
	_setup_ui()
	if camera:
		camera.make_current()

func _setup_environment() -> void:
	if not camera:
		camera = $Camera3D
	camera.make_current()
	camera.fov = 40.0

	environment = WorldEnvironment.new()
	add_child(environment)

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.14, 0.28) # Deep twilight zenith
	sky_mat.sky_horizon_color = Color(0.88, 0.48, 0.20) # Brilliant orange sunset horizon
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.10)
	sky_mat.ground_horizon_color = Color(0.40, 0.22, 0.15)
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_energy = 1.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_bloom = 0.25
	environment.environment = env

	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-16), deg_to_rad(130), 0)
	sun.light_color = Color(1.0, 0.82, 0.62) # Warm golden sunlight
	sun.light_energy = 2.4
	sun.shadow_enabled = true

func _setup_road_and_scenery() -> void:
	road_root = Node3D.new()
	road_root.name = "RoadRoot"
	add_child(road_root)

	# 4-Lane Asphalt Road Surface
	var road_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(26.0, 400.0)
	road_mesh.mesh = plane
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.11, 0.11, 0.12)
	road_mat.roughness = 0.9
	road_mesh.material_override = road_mat
	road_mesh.position = Vector3(0, 0, 0)
	road_root.add_child(road_mesh)

	# Double Yellow Center Median Lines
	for side in [-0.2, 0.2]:
		var line := MeshInstance3D.new()
		var p := PlaneMesh.new()
		p.size = Vector2(0.18, 400.0)
		line.mesh = p
		var yel := StandardMaterial3D.new()
		yel.albedo_color = Color(0.98, 0.75, 0.1)
		yel.emission_enabled = true
		yel.emission = Color(0.98, 0.75, 0.1)
		yel.emission_energy_multiplier = 0.4
		line.material_override = yel
		line.position = Vector3(side, 0.02, 0)
		road_root.add_child(line)

	# White Lane Dividers
	for side in [-4.5, 4.5]:
		for i in range(-12, 13):
			var dash := MeshInstance3D.new()
			var p := PlaneMesh.new()
			p.size = Vector2(0.2, 6.0)
			dash.mesh = p
			var wmat := StandardMaterial3D.new()
			wmat.albedo_color = Color(0.9, 0.9, 0.9)
			dash.material_override = wmat
			dash.position = Vector3(side, 0.02, i * 15.0)
			road_root.add_child(dash)

	# Concrete Guard Barriers
	for side in [-11.0, 11.0]:
		for i in range(-10, 11):
			var barrier := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 0.95, 18.0)
			barrier.mesh = box
			var b_mat := StandardMaterial3D.new()
			b_mat.albedo_color = Color(0.55, 0.52, 0.48)
			barrier.material_override = b_mat
			barrier.position = Vector3(side, 0.47, i * 19.0)
			road_root.add_child(barrier)

	# Streetlights with Warm Sodium pools
	for i in range(-6, 7):
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.1
		cyl.bottom_radius = 0.14
		cyl.height = 8.5
		pole.mesh = cyl
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.2, 0.22, 0.26)
		pole.material_override = pmat
		pole.position = Vector3(10.2, 4.25, i * 28.0)
		road_root.add_child(pole)

		var lamp_light := SpotLight3D.new()
		lamp_light.position = Vector3(8.5, 8.0, i * 28.0)
		lamp_light.rotation = Vector3(deg_to_rad(-90), 0, 0)
		lamp_light.spot_angle = 55.0
		lamp_light.light_color = Color(1.0, 0.85, 0.6)
		lamp_light.light_energy = 4.0
		lamp_light.spot_range = 18.0
		road_root.add_child(lamp_light)

	# Background Billboard: Chowrastha Junction
	var billboard := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(16.0, 6.0)
	billboard.mesh = q
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.08, 0.12)
	bmat.emission_enabled = true
	bmat.emission = Color(0.2, 0.6, 1.0) # Glowing neon cyan
	bmat.emission_energy_multiplier = 1.2
	billboard.material_override = bmat
	billboard.position = Vector3(-18.0, 8.0, 45.0)
	billboard.rotation = Vector3(0, deg_to_rad(30), 0)
	road_root.add_child(billboard)

func _create_radial_flash_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 0.85, 0.3, 0.85), Color(1.0, 0.4, 0.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex

func _setup_actors() -> void:
	var char_scn := load("res://assets/models/characters/rahul/rahul_mixamo.glb") as PackedScene
	if not char_scn:
		push_error("Failed to load rahul_mixamo.glb")
		return

	var flash_tex := _create_radial_flash_texture()

	# 1. Hero (Rahul)
	hero = char_scn.instantiate()
	hero.name = "HeroRahul"
	add_child(hero)
	hero_anim = hero.find_child("AnimationPlayer", true, false)
	hero_skeleton = hero.find_child("Skeleton3D", true, false)
	hero.position = Vector3(0.5, 0, -1.0)
	hero.visible = false # Hidden during Beat 1 pursuit

	# Attach AK-47 assault rifle to Hero right hand
	if hero_skeleton:
		var bone_id := hero_skeleton.find_bone("mixamorig_RightHand")
		if bone_id != -1:
			var attach := BoneAttachment3D.new()
			attach.bone_name = "mixamorig_RightHand"
			attach.bone_idx = bone_id
			hero_skeleton.add_child(attach)
			var w_scn := load("res://assets/models/weapons/ak47.glb") as PackedScene
			if w_scn:
				hero_gun = w_scn.instantiate()
				hero_gun.scale = Vector3(1.15, 1.15, 1.15)
				hero_gun.position = Vector3(0.08, 0.12, -0.15)
				hero_gun.rotation = Vector3(deg_to_rad(-80), deg_to_rad(90), 0)
				attach.add_child(hero_gun)

				# Muzzle flash light & soft quad
				hero_muzzle_light = OmniLight3D.new()
				hero_muzzle_light.light_color = Color(1.0, 0.8, 0.2)
				hero_muzzle_light.light_energy = 0.0
				hero_muzzle_light.omni_range = 8.0
				hero_muzzle_light.position = Vector3(0, 0, -0.6)
				hero_gun.add_child(hero_muzzle_light)

				hero_muzzle_flash = MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.42, 0.42)
				hero_muzzle_flash.mesh = q
				var fmat := StandardMaterial3D.new()
				fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				fmat.albedo_texture = flash_tex
				fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				hero_muzzle_flash.material_override = fmat
				hero_muzzle_flash.visible = false
				hero_muzzle_flash.position = Vector3(0, 0, -0.65)
				hero_gun.add_child(hero_muzzle_flash)

	# 2. Target Operative
	target_op = char_scn.instantiate()
	target_op.name = "TargetOperative"
	add_child(target_op)
	target_anim = target_op.find_child("AnimationPlayer", true, false)
	target_skeleton = target_op.find_child("Skeleton3D", true, false)
	target_op.position = Vector3(-1.5, 0, 8.0)
	target_op.visible = false # Hidden during Beat 1 pursuit

	# Dark tactical finish for Target Operative
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.18, 0.2, 0.22)
	dark_mat.roughness = 0.7
	for mesh: MeshInstance3D in target_op.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = dark_mat

	# Attach weapon to Target right hand
	if target_skeleton:
		var bone_id := target_skeleton.find_bone("mixamorig_RightHand")
		if bone_id != -1:
			var attach := BoneAttachment3D.new()
			attach.bone_name = "mixamorig_RightHand"
			attach.bone_idx = bone_id
			target_skeleton.add_child(attach)
			var w_scn := load("res://assets/models/weapons/ak47.glb") as PackedScene
			if w_scn:
				target_gun = w_scn.instantiate()
				target_gun.scale = Vector3(1.15, 1.15, 1.15)
				target_gun.position = Vector3(0.08, 0.12, -0.15)
				target_gun.rotation = Vector3(deg_to_rad(-80), deg_to_rad(90), 0)
				attach.add_child(target_gun)

				target_muzzle_light = OmniLight3D.new()
				target_muzzle_light.light_color = Color(1.0, 0.7, 0.2)
				target_muzzle_light.light_energy = 0.0
				target_muzzle_light.omni_range = 8.0
				target_muzzle_light.position = Vector3(0, 0, -0.6)
				target_gun.add_child(target_muzzle_light)

				target_muzzle_flash = MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.42, 0.42)
				target_muzzle_flash.mesh = q
				var fmat := StandardMaterial3D.new()
				fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				fmat.albedo_texture = flash_tex
				fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				target_muzzle_flash.material_override = fmat
				target_muzzle_flash.visible = false
				target_muzzle_flash.position = Vector3(0, 0, -0.65)
				target_gun.add_child(target_muzzle_flash)

func _setup_impact_fx() -> void:
	# Impact Hit Spark Quad with soft radial glow
	impact_spark = MeshInstance3D.new()
	impact_spark.name = "ImpactHitSpark"
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	impact_spark.mesh = q
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.albedo_texture = _create_radial_flash_texture()
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	impact_spark.material_override = smat
	impact_spark.visible = false
	add_child(impact_spark)

	# Impact Hit Light Flash
	impact_light = OmniLight3D.new()
	impact_light.name = "ImpactHitLight"
	impact_light.light_color = Color(1.0, 0.82, 0.35)
	impact_light.light_energy = 0.0
	impact_light.omni_range = 6.0
	add_child(impact_light)

func trigger_impact(pos: Vector3, shake_amount: float = 0.85) -> void:
	if impact_spark:
		impact_spark.position = pos
		impact_spark.visible = true
	if impact_light:
		impact_light.position = pos
		impact_light.light_energy = 16.0
	impact_frames_remaining = 3 # Active for 3 frames (100ms)
	trauma = clampf(trauma + shake_amount, 0.0, 1.0)
	if sfx_punch:
		sfx_punch.play()

func _setup_vehicles() -> void:
	var supra_scn := load("res://scenes/vehicles/imported/toyota_supra_gr.tscn") as PackedScene
	if supra_scn:
		target_car = supra_scn.instantiate()
		target_car.position = Vector3(-3.0, 0.35, -80.0)
		if target_car is RigidBody3D:
			target_car.freeze = true
		target_car.set_physics_process(false)
		_strip_internal_cameras(target_car)
		add_child(target_car)
		var hl1 := SpotLight3D.new()
		hl1.position = Vector3(-0.7, 0.6, 2.1)
		hl1.spot_angle = 35.0
		hl1.spot_range = 40.0
		hl1.light_color = Color(0.9, 0.95, 1.0)
		hl1.light_energy = 4.0
		target_car.add_child(hl1)

	var thar_scn := load("res://scenes/vehicles/rigid_thar.tscn") as PackedScene
	if thar_scn:
		pursuit_car = thar_scn.instantiate()
		pursuit_car.position = Vector3(3.0, 0.45, -95.0)
		if pursuit_car is RigidBody3D:
			pursuit_car.freeze = true
		pursuit_car.set_physics_process(false)
		_strip_internal_cameras(pursuit_car)
		add_child(pursuit_car)

	var heli_scn := load("res://scenes/vehicles/gdk_helicopter.tscn") as PackedScene
	if heli_scn:
		helicopter = heli_scn.instantiate()
		helicopter.position = Vector3(8.0, 14.0, -60.0)
		helicopter.rotation = Vector3(deg_to_rad(10), deg_to_rad(-25), deg_to_rad(-15))
		if helicopter is RigidBody3D:
			helicopter.freeze = true
		helicopter.set_physics_process(false)
		_strip_internal_cameras(helicopter)
		add_child(helicopter)

		heli_spotlight = SpotLight3D.new()
		heli_spotlight.position = Vector3(0, -1.0, 0.5)
		heli_spotlight.rotation = Vector3(deg_to_rad(-65), 0, 0)
		heli_spotlight.spot_angle = 32.0
		heli_spotlight.spot_range = 50.0
		heli_spotlight.light_color = Color(0.95, 0.98, 1.0)
		heli_spotlight.light_energy = 14.0
		helicopter.add_child(heli_spotlight)

func _strip_internal_cameras(node: Node) -> void:
	if not node:
		return
	for cam in node.find_children("*", "Camera3D", true, false):
		if cam is Camera3D:
			cam.current = false
			cam.queue_free()

func _setup_audio() -> void:
	sfx_engine = AudioStreamPlayer.new()
	sfx_engine.stream = load("res://assets/audio/porsche_911/rev_2600rpm.wav")
	sfx_engine.volume_db = -1.0
	add_child(sfx_engine)

	sfx_siren = AudioStreamPlayer.new()
	sfx_siren.stream = load("res://assets/audio/gameplay/siren.wav")
	sfx_siren.volume_db = -5.0
	add_child(sfx_siren)

	sfx_shot = AudioStreamPlayer.new()
	sfx_shot.stream = load("res://assets/audio/gameplay/shot.wav")
	sfx_shot.volume_db = 3.0
	add_child(sfx_shot)

	sfx_punch = AudioStreamPlayer.new()
	sfx_punch.stream = load("res://assets/audio/gameplay/punch.wav")
	sfx_punch.volume_db = 5.0
	add_child(sfx_punch)

	sfx_crash = AudioStreamPlayer.new()
	sfx_crash.stream = load("res://assets/audio/gameplay/explosion.wav")
	sfx_crash.volume_db = 1.0
	add_child(sfx_crash)

	sfx_door = AudioStreamPlayer.new()
	sfx_door.stream = load("res://assets/audio/car_doors/door_open.wav")
	sfx_door.volume_db = 0.0
	add_child(sfx_door)

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# 2.39:1 CinemaScope letterbox bars (720p -> 75px top/bottom)
	letterbox_top = ColorRect.new()
	letterbox_top.color = Color.BLACK
	letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	letterbox_top.custom_minimum_size = Vector2(0, 75)
	canvas.add_child(letterbox_top)

	letterbox_bottom = ColorRect.new()
	letterbox_bottom.color = Color.BLACK
	letterbox_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	letterbox_bottom.offset_top = -75
	letterbox_bottom.custom_minimum_size = Vector2(0, 75)
	canvas.add_child(letterbox_bottom)

	title_label = Label.new()
	title_label.text = "MANA OORU"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_label.offset_top = 85
	title_label.offset_left = -200
	title_label.offset_right = 200
	title_label.modulate = Color(1, 1, 1, 0)
	title_label.add_theme_font_size_override("font_size", 30)
	canvas.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "CHOWRASTHA TAKEDOWN"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle_label.offset_top = 125
	subtitle_label.offset_left = -300
	subtitle_label.offset_right = 300
	subtitle_label.modulate = Color(0.95, 0.82, 0.35, 0)
	subtitle_label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(subtitle_label)

	location_label = Label.new()
	location_label.text = "GODAVARIKHANI SECTOR 3 // 18:45 IST"
	location_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	location_label.offset_left = 30
	location_label.offset_top = -105
	location_label.modulate = Color(0.8, 0.8, 0.8, 0.7)
	location_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(location_label)

func _process(_delta: float) -> void:
	if not is_initialized or not hero or not target_op or not camera:
		return
	if not camera.is_current():
		camera.make_current()

	var drawn := Engine.get_frames_drawn()
	current_frame = drawn
	var step := 1.0 / FPS
	elapsed = float(current_frame) * step

	if current_frame % 50 == 0 or current_frame == 1:
		print("Frame %d / %d (%.2fs, drawn=%d)" % [current_frame, TOTAL_FRAMES, elapsed, drawn])

	# Spin helicopter rotors
	if helicopter:
		var main_rotor := helicopter.find_child("AnimatedMainRotor", true, false)
		if main_rotor:
			main_rotor.rotation.y += step * 35.0
		var tail_rotor := helicopter.find_child("AnimatedTailRotor", true, false)
		if tail_rotor:
			tail_rotor.rotation.x += step * 45.0

	# Process Impact FX decay
	if impact_frames_remaining > 0:
		impact_frames_remaining -= 1
		if impact_frames_remaining == 0:
			if impact_spark: impact_spark.visible = false
			if impact_light: impact_light.light_energy = 0.0

	_update_tracers(step)
	_direct_timeline(elapsed, step)

	if drawn >= TOTAL_FRAMES:
		get_tree().quit()

func _direct_timeline(t: float, step: float) -> void:
	var cam_target := Vector3.ZERO
	var cam_look := Vector3.ZERO
	var cam_fov := 40.0

	# -------------------------------------------------------------------------
	# BEAT 1: HIGH-SPEED HIGHWAY PURSUIT (0.0s - 4.2s / Frames 0 - 125)
	# -------------------------------------------------------------------------
	if t < 4.2:
		var progress := t / 4.2
		if target_car:
			target_car.position.z = lerpf(-75.0, 5.0, progress)
			target_car.position.x = -2.5 + sin(t * 4.0) * 0.4
			target_car.position.y = 0.35
		if pursuit_car:
			pursuit_car.position.z = lerpf(-90.0, -10.0, progress)
			pursuit_car.position.x = 2.0 + cos(t * 3.5) * 0.3
			pursuit_car.position.y = 0.45
		if helicopter:
			helicopter.position.z = lerpf(-60.0, 15.0, progress)
			helicopter.position.x = 5.0 + sin(t * 1.5) * 2.0

		if t < 0.1 and sfx_engine and not sfx_engine.playing:
			sfx_engine.play()
			sfx_siren.play()

		# Actors stationed out of frame
		hero.position = Vector3(0.5, 0, -15.0)
		target_op.position = Vector3(-1.5, 0, -15.0)

		# Shot 1 (0.0 - 2.2s): Low-angle asphalt cam looking down the highway
		if t < 2.2:
			cam_target = Vector3(-4.5, 1.2, target_car.position.z - 16.0)
			cam_look = Vector3(0, 1.0, target_car.position.z + 8.0)
			cam_fov = 36.0
		# Shot 2 (2.2 - 4.2s): Dynamic side-tracking pursuit cam
		else:
			cam_target = Vector3(4.8, 1.4, target_car.position.z - 6.0)
			cam_look = Vector3(-1.0, 0.95, target_car.position.z + 5.0)
			cam_fov = 44.0

	# -------------------------------------------------------------------------
	# BEAT 2: CRASH & BAILOUT PURSUIT (4.2s - 7.5s / Frames 126 - 225)
	# -------------------------------------------------------------------------
	elif t >= 4.2 and t < 7.5:
		var t_rel := t - 4.2

		# Park cars off to the sides
		if target_car:
			target_car.position = Vector3(-5.5, 0.35, 6.0)
			target_car.rotation = Vector3(0, deg_to_rad(35), deg_to_rad(3))
		if pursuit_car:
			pursuit_car.position = Vector3(5.5, 0.45, -5.0)
			pursuit_car.rotation = Vector3(0, deg_to_rad(-12), 0)

		if t_rel < 0.1:
			hero.visible = true
			target_op.visible = true
			if sfx_crash and not sfx_crash.playing:
				sfx_crash.play()
				sfx_door.play()

		# Target flees on foot down the road
		if target_anim.current_animation != "Jogging":
			target_anim.play("Jogging")
		target_op.position = Vector3(-1.2, 0, 7.0 + t_rel * 2.8)
		target_op.rotation = Vector3(0, deg_to_rad(0), 0)

		# Rahul tactical advance with rifle
		if hero_anim.current_animation != "Walk_With_Rifle":
			hero_anim.play("Walk_With_Rifle")
		hero.position = Vector3(0.5, 0, -1.0 + t_rel * 2.2)
		hero.rotation = Vector3(0, deg_to_rad(0), 0)

		# Shot 3 (4.2 - 5.8s): Tracking side view of crash & foot chase
		if t_rel < 1.6:
			cam_target = Vector3(6.5, 1.6, 2.5 + t_rel * 2.2)
			cam_look = Vector3(0, 1.2, target_op.position.z)
			cam_fov = 42.0
		# Shot 4 (5.8 - 7.5s): Hero tracking shot moving with Rahul
		else:
			cam_target = Vector3(hero.position.x - 0.9, 1.35, hero.position.z + 3.2)
			cam_look = Vector3(hero.position.x, 1.25, hero.position.z)
			cam_fov = 36.0

	# -------------------------------------------------------------------------
	# BEAT 3: THE SHOOTOUT & EVASIVE ROLL (7.5s - 11.8s / Frames 226 - 353)
	# -------------------------------------------------------------------------
	elif t >= 7.5 and t < 11.8:
		var t_rel := t - 7.5

		# 7.5s - 9.5s: Target turns and fires 3-round burst at Rahul
		if t_rel < 2.0:
			target_op.position = Vector3(-0.8, 0, 16.5)
			target_op.rotation = Vector3(0, deg_to_rad(180), 0) # Faces Rahul
			if target_anim.current_animation != "Firing_Rifle_while_walking":
				target_anim.play("Firing_Rifle_while_walking")

			# Deterministic 3-round burst at Frames 240 (8.0s), 246 (8.2s), 252 (8.4s)
			var is_burst_frame := (current_frame in [240, 246, 252])
			if is_burst_frame:
				if sfx_shot: sfx_shot.play()
				if target_muzzle_light: target_muzzle_light.light_energy = 8.0
				if target_muzzle_flash: target_muzzle_flash.visible = true
				var spread := Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.4), 0)
				_spawn_tracer(target_op.position + Vector3(0.2, 1.3, -0.5), hero.position + spread)
			elif current_frame not in [241, 247, 253]:
				if target_muzzle_light: target_muzzle_light.light_energy = 0.0
				if target_muzzle_flash: target_muzzle_flash.visible = false

			# Rahul performs combat dive roll underneath the burst!
			if t_rel > 0.4:
				if hero_anim.current_animation != "Dodging":
					hero_anim.play("Dodging")
				var roll_p := clampf((t_rel - 0.4) / 1.5, 0.0, 1.0)
				hero.position.x = lerpf(0.5, 2.4, roll_p)
				hero.position.z = lerpf(5.5, 8.2, roll_p)
			else:
				hero.position = Vector3(0.5, 0, 5.5)

			# Shot 5: Over-the-shoulder behind Target looking at Rahul dive-rolling
			cam_target = Vector3(-0.25, 1.50, target_op.position.z + 1.8)
			cam_look = Vector3(hero.position.x, 0.9, hero.position.z)
			cam_fov = 36.0

		# 9.5s - 11.8s: Rahul returns precision fire, Target hit & disarmed
		else:
			var t_hero := t_rel - 2.0
			if target_muzzle_light: target_muzzle_light.light_energy = 0.0
			if target_muzzle_flash: target_muzzle_flash.visible = false

			hero.position = Vector3(2.4, 0, 8.2)
			hero.rotation = Vector3(0, deg_to_rad(0), 0)
			if hero_anim.current_animation != "Firing_Rifle":
				hero_anim.play("Firing_Rifle")

			# Hero fires double tap at Frame 297 (9.90s) and Frame 305 (10.167s)
			if current_frame == 297:
				if sfx_shot: sfx_shot.play()
				if hero_muzzle_light: hero_muzzle_light.light_energy = 9.0
				if hero_muzzle_flash: hero_muzzle_flash.visible = true
				_spawn_tracer(hero.position + Vector3(0.15, 1.3, 0.5), target_op.position + Vector3(0.1, 1.25, 0))
			elif current_frame == 305:
				if sfx_shot: sfx_shot.play()
				if hero_muzzle_light: hero_muzzle_light.light_energy = 9.0
				if hero_muzzle_flash: hero_muzzle_flash.visible = true
				_spawn_tracer(hero.position + Vector3(0.15, 1.3, 0.5), target_op.position + Vector3(-0.6, 1.4, 0))
			elif current_frame not in [298, 306]:
				if hero_muzzle_light: hero_muzzle_light.light_energy = 0.0
				if hero_muzzle_flash: hero_muzzle_flash.visible = false

			# Bullet impact connects with Target at Frame 300 (10.00s)
			if current_frame == 300:
				trigger_impact(target_op.position + Vector3(0.1, 1.25, 0.0), 0.45)
				if target_anim.current_animation != "Hit_Reaction":
					target_anim.play("Hit_Reaction")
				if target_gun:
					target_gun.visible = false # Weapon shot out of hands!

			target_op.position = Vector3(-0.8, 0, 15.2)

			# Shot 6: Low heroic angle over Rahul's shoulder framing Target disarmed
			cam_target = Vector3(hero.position.x + 0.95, 1.35, hero.position.z - 1.4)
			cam_look = Vector3(target_op.position.x, 1.2, target_op.position.z)
			cam_fov = 32.0

	# -------------------------------------------------------------------------
	# BEAT 4: FRAME-SYNCHRONIZED MARTIAL ARTS CQC & FATAL KNOCKDOWN (11.8s - 16.2s / Frames 354 - 485)
	# -------------------------------------------------------------------------
	elif t >= 11.8 and t < 16.2:
		var t_cqc := t - 11.8
		if hero_muzzle_light: hero_muzzle_light.light_energy = 0.0
		if hero_muzzle_flash: hero_muzzle_flash.visible = false
		if hero_gun: hero_gun.visible = false # Holster weapon for martial arts CQC

		# 11.8s - 14.1s (Frames 354 - 422):
		# Target throws Hook, Rahul slips and counters with Mma_Kick.
		# Frame-accurate timing:
		# Mma_Kick starts at Frame 363 (12.10s).
		# Mma_Kick right leg extension reaches peak at +0.600s = Frame 381 (12.70s)!
		# On Frame 381: Boot impacts Target's jaw -> sfx_punch, radial hit spark, trauma shake,
		# Big_Side_Hit triggers ON THIS FRAME, target recoils back Z: 13.50 -> 14.40!
		if current_frame < 423:
			# Fighters positioned at exact 1.10m strike range
			hero.rotation = Vector3(0, deg_to_rad(0), 0)
			target_op.rotation = Vector3(0, deg_to_rad(180), 0)

			# Phase A: Setup and Hook windup (11.8s - 12.1s / Frames 354 - 362)
			if current_frame < 363:
				hero.position = Vector3(0.0, 0, 12.40)
				target_op.position = Vector3(0.05, 0, 13.50)
				if hero_anim.current_animation != "Boxing":
					hero_anim.play("Boxing")
				if target_anim.current_animation != "Hook":
					target_anim.play("Hook")

			# Phase B-D: Roundhouse Kick & Impact Recoil (Frames 363 - 422 / 12.10s - 14.07s)
			else:
				if hero_anim.current_animation != "Mma_Kick":
					hero_anim.play("Mma_Kick")

				if current_frame == 381:
					hero.position = Vector3(0.0, 0, 12.40)
					target_op.position = Vector3(0.05, 0, 13.50)
					trigger_impact(Vector3(0.05, 1.28, 13.50), 0.9)
					target_anim.play("Big_Side_Hit") # Starts ON THE IMPACT FRAME!
				elif current_frame > 381:
					hero.position = Vector3(0.0, 0, 12.50)
					if target_anim.current_animation != "Big_Side_Hit":
						target_anim.play("Big_Side_Hit")
					var stagger_p := clampf(float(current_frame - 381) / 18.0, 0.0, 1.0)
					target_op.position = Vector3(0.05, 0, lerpf(13.50, 14.40, stagger_p))
				else:
					# Windup before impact (Frames 363 - 380)
					hero.position = Vector3(0.0, 0, 12.40)
					target_op.position = Vector3(0.05, 0, 13.50)
					if target_anim.current_animation != "Hook":
						target_anim.play("Hook")

			# Shot 7: Handheld side combat profile with zero occlusion
			cam_target = Vector3(-2.1, 1.30, 13.0)
			cam_look = Vector3(0.0, 1.20, 13.0)
			cam_fov = 42.0

		# 14.1s - 16.2s (Frames 423 - 485):
		# Rahul launches Flying Kick finisher!
		# Flying_Kick starts at Frame 423 (14.10s).
		# Hero leaps forward Z: 12.50 -> 13.55. (Mixamo animation already elevates mesh to chest height).
		# Flying_Kick peak foot extension is at +0.400s = Frame 435 (14.50s)!
		# On Frame 435: Flying boot slams squarely into Target chest at Z = 14.40!
		# Simultaneous triggers: sfx_punch, hit spark flare, heavy camera trauma (1.0),
		# Death_From_The_Front triggers ON THIS FRAME, target skids back Z: 14.40 -> 16.00!
		else:
			if hero_anim.current_animation != "Flying_Kick":
				hero_anim.play("Flying_Kick")

			# Phase E: Rahul launches airborne flying kick (Frames 423 - 434 / 14.10s - 14.49s)
			if current_frame < 435:
				var leap_p := float(current_frame - 423) / 12.0 # 0.0 to 1.0
				var hero_z := lerpf(12.50, 13.55, leap_p)
				hero.position = Vector3(0.0, 0.0, hero_z)
				target_op.position = Vector3(0.0, 0.0, 14.40)
				if target_anim.current_animation != "Big_Side_Hit":
					target_anim.play("Big_Side_Hit")

			# Phase F: FLYING KICK IMPACT (Frame 435 / 14.50s)
			elif current_frame == 435:
				hero.position = Vector3(0.0, 0.0, 13.55)
				target_op.position = Vector3(0.0, 0.0, 14.40)
				# Direct contact: boot slams into target chest at Z = 14.40
				trigger_impact(Vector3(0.0, 1.15, 14.40), 1.0)
				target_anim.play("Death_From_The_Front") # Starts ON THE IMPACT FRAME!

			# Phase G: Fatal knockdown slide across pavement (Frames 436 - 485 / 14.53s - 16.19s)
			else:
				hero.position = Vector3(0.0, 0.0, 13.55)
				if target_anim.current_animation != "Death_From_The_Front":
					target_anim.play("Death_From_The_Front")
				# Target slides back from kinetic transfer onto asphalt
				var knock_p := clampf(float(current_frame - 435) / 45.0, 0.0, 1.0)
				var target_z := lerpf(14.40, 16.00, 1.0 - pow(1.0 - knock_p, 2.0)) # Ease out quad
				target_op.position = Vector3(0.15, 0.0, target_z)

			# Shot 8: Dynamic wide profile framing the airborne strike & flight with sunset backdrop
			var track_z := lerpf(13.6, 15.0, clampf(float(current_frame - 423) / 60.0, 0.0, 1.0))
			cam_target = Vector3(3.3, 1.25, track_z)
			cam_look = Vector3(0.0, 1.10, track_z)
			cam_fov = 46.0

	# -------------------------------------------------------------------------
	# BEAT 5: CLIMAX, HELICOPTER SPOTLIGHT & SUNSET CRANE SHOT (16.2s - 20.0s / Frames 486 - 600)
	# -------------------------------------------------------------------------
	else:
		var t_end := t - 16.2
		if hero_gun: hero_gun.visible = true # Bring rifle back to ready position

		# Target lies motionless on asphalt in spotlight pool
		target_op.position = Vector3(0.2, 0.0, 15.80)
		target_op.rotation = Vector3(0, deg_to_rad(180), 0)
		if target_anim.current_animation != "Death_From_The_Front":
			target_anim.play("Death_From_The_Front")
		target_anim.seek(3.4, true) # Hold final motionless collapsed pose

		# Rahul stands tall and victorious in ready stance
		hero.position = Vector3(0.0, 0.0, 13.60)
		hero.rotation = Vector3(0, deg_to_rad(0), 0)
		if hero_anim.current_animation != "Rifle_Aiming_Idle":
			hero_anim.play("Rifle_Aiming_Idle")

		# Helicopter hovers overhead, spotlight locked on Rahul and the fallen target
		if helicopter:
			helicopter.position = Vector3(0.0, 12.5, 14.7)
			helicopter.rotation = Vector3(deg_to_rad(-12), deg_to_rad(-90), 0)
			if heli_spotlight:
				heli_spotlight.look_at(Vector3(0.1, 0.0, 14.7), Vector3.UP)
				heli_spotlight.spot_angle = 34.0
				heli_spotlight.light_energy = 16.0

		# Shot 9: Grand crane shot elevating into the sunset sky
		var crane_t := clampf(t_end / 3.8, 0.0, 1.0)
		var crane_y := lerpf(1.6, 7.2, crane_t)
		var crane_z := lerpf(9.0, 0.0, crane_t)
		cam_target = Vector3(0.0, crane_y, crane_z)
		cam_look = Vector3(0.0, 0.8, 14.7)
		cam_fov = lerpf(38.0, 50.0, crane_t)

		# Fade in cinematic title text
		var alpha := clampf((t_end - 0.4) / 1.5, 0.0, 1.0)
		if title_label: title_label.modulate.a = alpha
		if subtitle_label: subtitle_label.modulate.a = alpha

	# Apply Camera Position, Orientation, and Camera Trauma Shake
	_apply_camera(cam_target, cam_look, cam_fov, step)

func _apply_camera(base_pos: Vector3, look_target: Vector3, fov: float, step: float) -> void:
	camera.fov = fov
	camera.position = base_pos
	camera.look_at(look_target, Vector3.UP)

	# Apply non-linear Camera Trauma Shake on top of look_at
	var shake := trauma * trauma
	if shake > 0.001:
		var pos_jitter := Vector3(
			randf_range(-1.0, 1.0) * MAX_TRAUMA_OFFSET.x * shake,
			randf_range(-1.0, 1.0) * MAX_TRAUMA_OFFSET.y * shake,
			randf_range(-1.0, 1.0) * MAX_TRAUMA_OFFSET.z * shake
		)
		var rot_jitter := Vector3(
			randf_range(-1.0, 1.0) * MAX_TRAUMA_ROT.x * shake,
			randf_range(-1.0, 1.0) * MAX_TRAUMA_ROT.y * shake,
			randf_range(-1.0, 1.0) * MAX_TRAUMA_ROT.z * shake
		)
		camera.position += pos_jitter
		camera.rotation += rot_jitter

	# Trauma decay
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * step)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 1.3
	tracer.mesh = cyl
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1.0, 0.65, 0.15) # Glowing tracer round
	tracer.material_override = tmat
	add_child(tracer)
	tracer.position = from
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

	var dir := (to - from).normalized()
	tracers.append({"node": tracer, "dir": dir, "life": 0.4, "speed": 75.0})

func _update_tracers(delta: float) -> void:
	for i in range(tracers.size() - 1, -1, -1):
		var t: Dictionary = tracers[i]
		t.life -= delta
		var node: MeshInstance3D = t.node
		node.position += t.dir * t.speed * delta
		if t.life <= 0.0:
			node.queue_free()
			tracers.remove_at(i)
