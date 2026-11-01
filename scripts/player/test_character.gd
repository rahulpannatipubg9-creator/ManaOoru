extends Node3D

## Optional stand-in model for the on-foot person, for local testing only.
## Loads MODEL_PATH when it exists (it is gitignored and excluded from exports),
## hides the block figure's meshes and poses the skeleton procedurally from the
## person's movement: walk/run cycle (the realistic male blends authored walk and run
## clips from its model on top), idle breathing, airborne and crouch poses,
## and a seated driving pose with hands on the wheel following the steering.
## Without the file it does nothing, so the shipped game keeps the block figure.

## Rahul, the player's own likeness (see ASSET_LICENSES.md), is the default playable
## look everywhere; the test-only lady stays selectable on desktop checkouts.
const MODEL_PATH := "res://assets/test_only/magic_girl/magic_girl.glb"
## Rahul (tools/rahul_character, 11_export.py): the from-scratch rebuild at true scale (1.77 m to the top of
## the hair), soles at y = 0, CC_Base skeleton resting in an A-pose. Every clip the game samples is inside
## the model: the locomotion contract below (17_game_clips.py) and the AK-47 set (15_rifle.py).
const MALE_MODEL_PATH := "res://assets/models/characters/rahul/rahul.glb"
## Deliberately a little below the legacy avatar's 1.8 m collision shell so
## the high-detail rig never appears oversized beside roads, doors or vehicles.
const TARGET_HEIGHT := 1.70
## Metres covered per full walk cycle (two steps) at the model's scale.
const STRIDE_LENGTH := 1.5
## Relaxed arms hang this far out from vertical, whatever the model's rest pose (T or A).
const ARM_HANG_ANGLE := 0.14
const FINGER_CURL := 0.3
const WRIST_IN := 0.35
const FINGERS := ["f_index", "f_middle", "f_ring", "f_pinky"]
const POSE_SMOOTHING := 10.0
## The realistic male plays the Walk_Cycle / Run_Cycle clips authored in tools/character_actions.py,
## stepped by distance travelled so the feet keep pace with the body. Metres per full cycle (two
## steps) while walking and while running; the player walks at 4.2 m/s and runs at 7 m/s.
const MALE_WALK_STRIDE := 2.2
const MALE_RUN_STRIDE := 3.6
## Speeds (m/s) over which the walk clip blends into the run clip.
const MALE_RUN_BLEND := Vector2(4.4, 6.8)
## An optional separate clip library that overrides the model's own clips by name. Empty: Rahul carries
## his own clips, and a library authored on another body would override them with its joint offsets.
const MALE_ANIMATIONS_PATH := ""
const DEFAULT_MIXAMO_HEIGHT := 1.78
const MIXAMO_MODEL_PATH := "res://assets/models/characters/virat/virat.glb"

## Gait clips authored for the speeds the game actually uses (tools/rahul_character, 17_game_clips.py):
## a planted foot then moves back under the body at exactly the body's speed, so feet do not slide.
## Name and the speed in m/s each clip was built for; strides are measured from the clips themselves.
const GAIT_CLIPS := [["WALK_Realistic", 1.17], ["WALK_Brisk", 2.0], ["JOG_Realistic", 4.2], ["SPRINT_Realistic", 7.0]]
## The last frame of a looping clip repeats the first, so a cycle is one frame shorter than the clip.
const CLIP_FRAME := 1.0 / 30.0
## Movement more than this far from straight ahead counts as backwards.
const BACKWARD_ANGLE := deg_to_rad(110.0)
## The legs turn toward the travel direction while the chest keeps facing where the character aims. The
## counter-twist is shared between the two spine bones and the head.
const HEADING_SPINE_01 := 0.4
const HEADING_SPINE_02 := 0.4
const HEADING_HEAD := 0.2
var _heading := 0.0
var _moving_backward := false

## Crouch: an authored crouched stance and crouch walk (tools/character_animation, CROUCH_Idle / CROUCH_Walk).
## The walk was built for the game's crouch speed of 2.1 m/s, 1.4 m per cycle.
const CROUCH_STRIDE := 1.4
var _crouch_idle: Animation
var _crouch_walk: Animation
var _anim_lod_timer := 0.0
var _accumulated_anim_delta := 0.0
## Bone index -> [idle rotation, idle position, walk rotation, walk position] track indices.
var _crouch_tracks := {}
var _crouch_phase := 0.0
var _crouch_idle_time := 0.0

## Prone: lying on the chest, head up, legs straight; moving draws one knee up at a time (a low crawl).
const CRAWL_STRIDE := 0.9
## Lying on the chest: the body pitches this far forward and drops this much (set in _pose_static_male; it
## used to be blended a little each frame from an upright reset, so the body never actually lay down).
const PRONE_PITCH := deg_to_rad(80.0)
const PRONE_DROP := 0.06
const PRONE_HEAD_LIFT := -0.9
var _crawl_phase := 0.0

## Hit and death reactions. A hit jolts the chest and head away from the shot for a moment; a death drops the
## body over in the direction the shot was travelling.
const HIT_SECONDS := 0.3
const DEATH_SECONDS := 0.7
var _hit_time := 0.0
var _hit_direction := Vector3.FORWARD
var _dead := false
var _death_time := 0.0
var _death_forward := true
var _gait_clips: Array[Dictionary] = []
## Bone index -> per gait clip [rotation track, position track].
var _gait_tracks := {}

## The AK-47 set (tools/rahul_character, 15_rifle.py), layered over the locomotion while a rifle is out. The
## clips set the body's stance (bladed chest, shoulders forward, feet apart) and the game still solves the
## arms onto its own rifle afterwards (_pose_armed), so aiming, recoil and the sights stay the game's.
##   Rifle_Idle                          standing at the low ready
##   Rifle_Jog_InPlace / _Sprint_InPlace  over the jog and sprint (same strides and timing, 4.2 / 7.0 m/s)
##   Rifle_ADS_Idle                      spine, neck and head down to the sights while aiming
##   Rifle_Peek_Left / _Right            standing peek: the upper body leans over planted feet
##   Rifle_Jump                          legs tucked from take-off, sampled by time in the air
const RIFLE_CLIPS := ["Rifle_Idle", "Rifle_Jog_InPlace", "Rifle_Sprint_InPlace", "Rifle_ADS_Idle",
	"Rifle_Peek_Left", "Rifle_Peek_Right", "Rifle_Jump"]
## The jog and sprint speeds the rifle gait clips were authored for (person_controller.gd walk/run speed).
const RIFLE_GAIT_SPEEDS := Vector2(4.2, 7.0)
## Below this speed (m/s) the unarmed walk carries the legs; the rifle jog fades in up to RIFLE_GAIT_SPEEDS.x.
const RIFLE_GAIT_FROM := 2.0
## Bones the aim takes from Rifle_ADS_Idle while moving: the spine, neck and head (the legs keep stepping).
const UPPER_BODY := ["CC_Base_Waist", "CC_Base_Spine01", "CC_Base_Spine02", "CC_Base_NeckTwist01",
	"CC_Base_NeckTwist02", "CC_Base_Head"]
## Share of the procedural blade (BLADE_*) kept over the rifle clips' own stance while the body faces the aim:
## enough for the left hand to reach the handguard in the sprint carry (within 2.5 cm), with the chest turned
## about 33 degrees at the low ready instead of 52 with the full turn on top.
const RIFLE_CLIP_BLADE := 0.35
## Body lean of a peek when the whole model tips, as the block figure (person_controller.gd). Peek -1 is left
## (Q, "< PEEK"), so the model rolls by -0.28 rad about +z (forward) and tips toward +x, the character's left.
const PEEK_TILT := 0.28
var _rifle_clips := {}
## Clip name -> {bone index: [rotation track, position track]}.
var _rifle_tracks := {}
var _upper_body: Array[int] = []
## 0..1: how far the rifle stance has blended in, and how much of the chest the rifle clips set this frame
## (the procedural blade in _pose_armed makes up the rest).
var _armed := 0.0
var _rifle_body := 0.0
## 0..1 aim (the holder's own shoulder blend) and seconds since the feet left the ground.
var _aim := 0.0
var _air_time := 0.0
var _rifle_time := 0.0

## Set by the vehicle entry sequence: sitting in a car seat, hands on the wheel.
var seated := false
var vehicle_entry_bend := 0.0
var vehicle_mount_swing := 0.0
var vehicle_foot_half_width := 0.0
var use_vehicle_grips := false
var left_grip_target := Vector3.ZERO
var right_grip_target := Vector3.ZERO
## -1..1 steering input while seated; turns the wheel with both hands.
var steering := 0.0
## While a scripted move carries the person (walking to a car door), its speed in m/s; -1 = use physics.
var scripted_speed := -1.0
## Seated: heel position (relative to the person root) the legs reach for, i.e. the pedals.
var foot_target := Vector3(0.0, 0.35, 0.75)
## Ankle height above the heel.
const ANKLE_HEIGHT := 0.07
var model: Node3D
var male_model: Node3D
var _mixamo_base_height := 0.0
var mixamo_model: Node3D
var mixamo_anim_player: AnimationPlayer
var mixamo_skeleton: Skeleton3D
var _mixamo_reload_active := false
var male_skeleton: Skeleton3D
var skeleton: Skeleton3D
var _character_index := 0
var _mixamo_action_lock := 0.0
var _mixamo_current_clip := ""
var _melee_combo := [
	"Boxing", "Hook", "Flying_Knee_Punch_Combo", "Mma_Kick",
	"Drop_Kick", "Flying_Kick", "Headbutt", "Fist_Fight_B", "Illegal_Elbow_Punch"
]
var _melee_index := 0
var _prev_striking := false
var _phase := 0.0
var _gait := 0.0
var _air := 0.0
var _crouch := 0.0
var _prone := 0.0
var _peek := 0.0
var _breath := 0.0
var _bones := {}
var _base_height := 0.0
var _arm_drop := 0.0
var _seat := 0.0
var _wheel := 0.0
var _face_time := 0.0
var _hip := Vector3.ZERO
var _thigh_length := 0.45
var _shin_length := 0.45
var _male_base_height := 0.0
var _male_bones: Dictionary = {}
var _cached_meshes: Dictionary = {}
var _walk_clip: Animation
var _run_clip: Animation
var _idle_clip: Animation
## Bone index -> [walk rot, run rot, idle rot, walk pos, run pos, idle pos] track indices (-1 = none).
var _clip_tracks: Dictionary = {}
var _male_phase := 0.0
var _clip_weight := 0.0
var _idle_weight := 0.0
var _idle_time := 0.0

## Set before the node enters the tree. Remote players in a match use only the realistic character, which is
## the one that ships on the tablet and phone; the desktop-only test model is skipped.
var male_only := false

func _ready() -> void:
	var has_model := not male_only and ResourceLoader.exists(MODEL_PATH)
	var has_male := ResourceLoader.exists(MALE_MODEL_PATH)
	if not has_model and not has_male:
		return
	if has_model:
		model = (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
		add_child(model)
		skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var bounds := _model_bounds()
		# Some downloaded rigs retain a Z-up mesh bound even after import. Use the
		# largest vertical candidate so this avatar matches the 1.7 m legacy player
		# instead of being scaled from its thin front/back dimension.
		var source_height := maxf(bounds.size.y, bounds.size.z)
		var scale_factor := TARGET_HEIGHT / maxf(source_height, 0.01)
		model.scale = Vector3.ONE * scale_factor
		model.position.y = -bounds.position.y * scale_factor
		_base_height = model.position.y
		for bone_name in ["DEF-thigh.L", "DEF-thigh.R", "DEF-shin.L", "DEF-shin.R", "DEF-foot.L", "DEF-foot.R",
				"DEF-upper_arm.L", "DEF-upper_arm.R", "DEF-forearm.L", "DEF-forearm.R", "DEF-spine.001",
				"DEF-spine.003", "DEF-spine.006", "head", "DEF-jaw", "DEF-eye.L", "DEF-eye.R"]:
			var index := skeleton.find_bone(bone_name)
			if index >= 0:
				_bones[bone_name] = index
		_scale_realistic_feet()
		var thigh := skeleton.find_bone("DEF-thigh.L")
		var shin := skeleton.find_bone("DEF-shin.L")
		var foot := skeleton.find_bone("DEF-foot.L")
		if thigh >= 0 and shin >= 0 and foot >= 0:
			var to_model := Transform3D(Basis.from_scale(model.scale), model.position)
			_hip = to_model * skeleton.get_bone_global_rest(thigh).origin
			var knee := to_model * skeleton.get_bone_global_rest(shin).origin
			var ankle := to_model * skeleton.get_bone_global_rest(foot).origin
			_thigh_length = _hip.distance_to(knee)
			_shin_length = knee.distance_to(ankle)
		# How far the arm must come down from its rest direction to hang relaxed.
		var arm := skeleton.find_bone("DEF-upper_arm.L")
		if arm >= 0:
			var rest_direction := skeleton.get_bone_global_rest(arm).basis.y.normalized()
			_arm_drop = maxf(atan2(absf(rest_direction.x), -rest_direction.y) - ARM_HANG_ANGLE, 0.0)
		_relax_hands()
	if has_male:
		male_model = (load(MALE_MODEL_PATH) as PackedScene).instantiate() as Node3D
		add_child(male_model)
		# True scale: no fitting to a height (the bounds include the hair). Godot's glTF importer has
		# already converted the source to Y-up, so keep its native upright axis.
		male_model.rotation = Vector3.ZERO
		male_model.scale = Vector3.ONE
		male_model.position.y = -_model_bounds_for(male_model).position.y
		_male_base_height = male_model.position.y
		var male_skeletons := male_model.find_children("*", "Skeleton3D", true, false)
		if not male_skeletons.is_empty():
			male_skeleton = male_skeletons[0] as Skeleton3D
			_cache_male_bones()
			_cache_male_clips()
		male_model.visible = true
		_character_index = 1
		if model:
			model.visible = false
	var has_mixamo := ResourceLoader.exists(MIXAMO_MODEL_PATH)
	if has_mixamo:
		mixamo_model = (load(MIXAMO_MODEL_PATH) as PackedScene).instantiate() as Node3D
		add_child(mixamo_model)
		# Virat carries authored skin/hair/clothing colours in COLOR_0.
		# Godot's glTF material import does not enable the albedo switch here.
		if "/virat/" in MIXAMO_MODEL_PATH:
			for part: MeshInstance3D in mixamo_model.find_children("*", "MeshInstance3D", true, false):
				for surface in part.mesh.get_surface_count():
					var imported_material := part.get_active_material(surface) as StandardMaterial3D
					if imported_material:
						var coloured_material := imported_material.duplicate() as StandardMaterial3D
						coloured_material.vertex_color_use_as_albedo = true
						part.set_surface_override_material(surface, coloured_material)
		mixamo_model.rotation = Vector3.ZERO
		# Skin bind matrices already convert the centimetre skeleton to metres.
		# Measure deformed vertices; static mesh bounds omit that conversion.
		mixamo_model.scale = Vector3.ONE
		var upright_bounds := _skinned_model_bounds(mixamo_model)
		var model_scale := DEFAULT_MIXAMO_HEIGHT / maxf(upright_bounds.size.y, 0.001)
		mixamo_model.scale = Vector3.ONE * model_scale
		_mixamo_base_height = -upright_bounds.position.y * model_scale
		mixamo_model.position = Vector3(0.0, _mixamo_base_height, 0.0)
		if get_parent().get("stand_height") != null:
			get_parent().set("stand_height", DEFAULT_MIXAMO_HEIGHT)
		mixamo_model.visible = true
		if male_model:
			male_model.visible = false
		if model:
			model.visible = false
		_character_index = 3
		var players := mixamo_model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			mixamo_anim_player = players[0] as AnimationPlayer
			_setup_mixamo_animations()
			_play_mixamo_clip("Idle_Natural")
	for mesh_name in ["Body", "Head", "Legs"]:
		var mesh := get_parent().get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			_cached_meshes[mesh_name] = mesh.mesh
			mesh.mesh = null
			mesh.visible = false

func is_active() -> bool:
	return (skeleton != null and model != null and model.visible) \
		or (male_skeleton != null and male_model != null and male_model.visible) \
		or (mixamo_model != null and mixamo_model.visible)

func toggle_character() -> String:
	if model == null and male_model == null and mixamo_model == null:
		return "Legacy Avatar"
	if model == null:
		if mixamo_model != null:
			match _character_index:
				1: _character_index = 2
				2: _character_index = 3
				3: _character_index = 1
				_: _character_index = 1
		else:
			_character_index = 1 if _character_index == 2 else 2
		if male_model:
			male_model.visible = _character_index == 1
		if mixamo_model:
			mixamo_model.visible = _character_index == 3
		for mesh_name in ["Body", "Head", "Legs"]:
			var mesh := get_parent().get_node_or_null(mesh_name) as MeshInstance3D
			if mesh:
				if _character_index == 2:
					if _cached_meshes.has(mesh_name):
						mesh.mesh = _cached_meshes[mesh_name]
					mesh.visible = true
				else:
					if mesh.mesh != null and not _cached_meshes.has(mesh_name):
						_cached_meshes[mesh_name] = mesh.mesh
					mesh.mesh = null
					mesh.visible = false
		match _character_index:
			1: return "Rahul"
			3: return "Virat"
			_: return "Legacy Avatar"
	if mixamo_model != null:
		match _character_index:
			1: _character_index = 2
			2: _character_index = 0
			0: _character_index = 3
			3: _character_index = 1
			_: _character_index = 3
	else:
		_character_index = (_character_index + 1) % 3
	if model:
		model.visible = _character_index == 0
	if male_model:
		male_model.visible = _character_index == 1
	if mixamo_model:
		mixamo_model.visible = _character_index == 3
	for mesh_name in ["Body", "Head", "Legs"]:
		var mesh := get_parent().get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			if _character_index == 2:
				if _cached_meshes.has(mesh_name):
					mesh.mesh = _cached_meshes[mesh_name]
				mesh.visible = true
			else:
				if mesh.mesh != null and not _cached_meshes.has(mesh_name):
					_cached_meshes[mesh_name] = mesh.mesh
				mesh.mesh = null
				mesh.visible = false
	match _character_index:
		0: return "Lady Character"
		1: return "Rahul"
		3: return "Virat"
		_: return "Legacy Avatar"

func select_mixamo() -> String:
	if mixamo_model == null:
		return toggle_character()
	_character_index = 1 if _character_index == 3 else 3
	if model:
		model.visible = false
	if male_model:
		male_model.visible = _character_index == 1
	mixamo_model.visible = _character_index == 3
	for mesh_name in ["Body", "Head", "Legs"]:
		var mesh := get_parent().get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			if mesh.mesh != null and not _cached_meshes.has(mesh_name):
				_cached_meshes[mesh_name] = mesh.mesh
			mesh.mesh = null
			mesh.visible = false
	return "Virat" if _character_index == 3 else "Rahul"

func play_grenade() -> void:
	if mixamo_model != null and mixamo_model.visible and mixamo_anim_player != null:
		_start_mixamo_action("Throw_Grenade" if _prone > 0.5 else "Grenade_Throw", 1.2)

func _setup_mixamo_animations() -> void:
	if mixamo_anim_player == null:
		return
	mixamo_skeleton = mixamo_model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	preload("res://scripts/player/mixamo_animation_library.gd").prepare(mixamo_anim_player, mixamo_skeleton)
	mixamo_anim_player.mixer_applied.connect(_apply_mixamo_pose)

func _play_mixamo_clip(clip_name: String, custom_speed: float = 1.0) -> void:
	if mixamo_anim_player == null or not mixamo_anim_player.has_animation(clip_name):
		return
	if _mixamo_current_clip != clip_name:
		_mixamo_current_clip = clip_name
		mixamo_anim_player.play(clip_name, 0.15)
	mixamo_anim_player.speed_scale = custom_speed

func _process_mixamo(delta: float, body: CharacterBody3D, speed: float, on_floor: bool) -> void:
	if mixamo_anim_player == null:
		return
	_mixamo_action_lock = maxf(0.0, _mixamo_action_lock - delta)

	if _dead:
		if _prone > 0.5:
			_play_mixamo_clip("Prone_Death")
		elif _crouch > 0.5:
			_play_mixamo_clip("Crouch_Death")
		else:
			_play_mixamo_clip("Death_From_The_Front")
		return

	if seated:
		_play_mixamo_clip("Drive_Seated")
		return

	if body.get("swimming") == true:
		_play_mixamo_clip("Swimming" if speed > 0.2 else "Floating")
		return

	var armed: bool = body.has_method("is_weapon_equipped") and body.is_weapon_equipped()
	# city_gameplay uses attack_until for rifle shots as well as punches.
	var striking := not armed and int(get_meta("attack_until", 0)) > Time.get_ticks_msec()
	if striking and not _prev_striking:
		var clip_name: String = _melee_combo[_melee_index % _melee_combo.size()]
		_melee_index += 1
		_start_mixamo_action(clip_name, 1.2)
	_prev_striking = striking

	var reloading: bool = float(body.get("weapon_reload_time")) > 0.0 if body.get("weapon_reload_time") != null else false
	if reloading and not _mixamo_reload_active:
		var duration := maxf(float(body.get("weapon_reload_time")), 0.1)
		_start_mixamo_action("Reload", mixamo_anim_player.get_animation("Reload").length / duration)
	_mixamo_reload_active = reloading
	if _mixamo_action_lock > 0.0:
		return

	var firing := body.get("weapon_kick") != null and float(body.get("weapon_kick")) > 0.001

	if not on_floor:
		var jump: float = float(body.get("jump_velocity")) if body.get("jump_velocity") != null else 7.0
		var flight := 2.0 * jump / maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.1)
		if _air_time <= flight:
			var clip := "Rifle_Jump" if armed else ("Running_Jump" if speed > 3.0 else "Jump")
			_play_mixamo_clip(clip, mixamo_anim_player.get_animation(clip).length / flight)
		else:
			_play_mixamo_clip("Jumping_Down", 1.0)
		return

	# Prone stance
	if _prone > 0.5:
		if speed > 0.2:
			_play_mixamo_locomotion("Moving_Backward_In_Prone_Position" if _moving_backward else "Prone_Forward", speed)
		else:
			_play_mixamo_clip("Prone_Firing_Rifle" if armed and firing else "Prone_Idle")
		return

	# Crouch stance
	if _crouch > 0.5:
		if speed > 0.2:
			_play_mixamo_locomotion("Crouch_Walking", speed)
		else:
			_play_mixamo_clip("Idle_Crouching")
		return

	if armed and firing:
		_play_mixamo_clip("Firing_Rifle_while_walking" if speed > 0.3 else "Firing_Rifle")
		return

	var lateral := (body.global_basis.inverse() * body.velocity).x
	if speed > 0.3 and absf(lateral) > speed * 0.7:
		_play_mixamo_locomotion(("Walk_Left_with_gun" if lateral > 0.0 else "Walk_Right_with_gun") if armed else "Strafe", speed)
		return
	# Backward travel takes priority over the forward jog threshold.
	if speed > 0.3 and _moving_backward:
		_play_mixamo_locomotion("Sprint_Backward", speed)
		return
	# Standing locomotion
	if speed > 2.8:
		if armed:
			_play_mixamo_locomotion("Walk_With_Rifle", speed)
		else:
			_play_mixamo_locomotion("Jogging", speed)
	elif speed > 0.3:
		if armed:
			_play_mixamo_locomotion("Walk_With_Rifle", speed)
		elif _moving_backward:
			_play_mixamo_locomotion("Sprint_Backward", speed)
		else:
			_play_mixamo_locomotion("Walk_Loop", speed)
	else:
		if armed:
			_play_mixamo_clip("Rifle_Aiming_Idle")
		else:
			_play_mixamo_clip("Idle_Natural", 1.0)

## Hip-joint height above the feet, so a car seat can place the hips on its cushion.
func hip_height() -> float:
	if mixamo_skeleton != null and mixamo_model.visible:
		var hip := mixamo_skeleton.find_bone("mixamorig_Hips")
		return to_local(mixamo_skeleton.to_global(mixamo_skeleton.get_bone_global_rest(hip).origin)).y
	return _hip.y if _hip.y > 0.1 else 0.95

func _scale_realistic_feet() -> void:
	_scale_realistic_feet_on(skeleton)

func _scale_realistic_feet_on(target_skeleton: Skeleton3D) -> void:
	# The supplied CC-style model has intentionally oversized footwear. Scale the
	# foot and toe chains only; legs, torso and collision dimensions stay intact.
	if target_skeleton == null:
		return
	for bone_index in target_skeleton.get_bone_count():
		var bone_name := target_skeleton.get_bone_name(bone_index)
		if "_Foot" in bone_name or "_Toe" in bone_name:
			target_skeleton.set_bone_pose_scale(bone_index, Vector3(0.70, 0.70, 0.70))

func _scale_character_model(target: Node3D, target_height: float = TARGET_HEIGHT) -> void:
	var bounds := _model_bounds_for(target)
	var source_height := maxf(bounds.size.y, bounds.size.z)
	var scale_factor := target_height / maxf(source_height, 0.01)
	target.scale = Vector3.ONE * scale_factor
	target.position.y = -bounds.position.y * scale_factor

## Thigh lift and knee bend (radians) that put the ankle over `foot_target`:
## two-bone IK in the side plane, knee bending upward.
func _seated_leg_angles() -> Vector2:
	var to_ankle := Vector2(foot_target.z - _hip.z, foot_target.y + ANKLE_HEIGHT - _hip.y)
	var reach := clampf(to_ankle.length(), absf(_thigh_length - _shin_length) + 0.01, _thigh_length + _shin_length - 0.01)
	var towards := atan2(to_ankle.x, -to_ankle.y)
	var hip_offset := acos(clampf((_thigh_length * _thigh_length + reach * reach - _shin_length * _shin_length) / (2.0 * _thigh_length * reach), -1.0, 1.0))
	var knee_inner := acos(clampf((_thigh_length * _thigh_length + _shin_length * _shin_length - reach * reach) / (2.0 * _thigh_length * _shin_length), -1.0, 1.0))
	return Vector2(towards + hip_offset, PI - knee_inner)

func _process(delta: float) -> void:
	if skeleton == null and male_skeleton == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var dist_sq := global_position.distance_squared_to(camera.global_position)
		if dist_sq > 15.0 * 15.0:
			var target_fps := 15.0 if dist_sq > 35.0 * 35.0 else 30.0
			_anim_lod_timer += delta
			_accumulated_anim_delta += delta
			if _anim_lod_timer < 1.0 / target_fps:
				return
			delta = _accumulated_anim_delta
			_anim_lod_timer = 0.0
			_accumulated_anim_delta = 0.0
	var body := get_parent() as CharacterBody3D
	var scripted := scripted_speed >= 0.0 or seated
	var speed := maxf(scripted_speed, 0.0) if scripted else Vector2(body.velocity.x, body.velocity.z).length()
	# A remote player is never moved by physics, so it reports its own grounded state.
	var on_floor: bool = scripted or (body.puppet_on_floor() if body.has_method("puppet_on_floor") else body.is_on_floor())
	var crouching: bool = body.get("crouching") == true
	var prone: bool = body.get("prone") == true
	var blend := 1.0 - exp(-POSE_SMOOTHING * delta)
	_gait = lerpf(_gait, clampf(speed / 6.0, 0.0, 1.0), blend)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, blend)
	_crouch = lerpf(_crouch, 1.0 if crouching and not scripted else 0.0, blend)
	_prone = lerpf(_prone, 1.0 if prone and not scripted else 0.0, blend)
	var peek_val: float = float(body.get("peek_input")) if body.get("peek_input") != null else 0.0
	_peek = lerpf(_peek, peek_val, blend)
	# Rifle stance (the local and remote players both expose is_weapon_equipped() and their own _aim_blend).
	var armed: bool = body.has_method("is_weapon_equipped") and body.is_weapon_equipped()
	_armed = lerpf(_armed, 1.0 if armed and not scripted else 0.0, blend)
	_aim = clampf(float(body.get("_aim_blend")), 0.0, 1.0) if armed and body.get("_aim_blend") != null else 0.0
	_air_time = 0.0 if on_floor else _air_time + delta
	_rifle_time += delta
	_seat = move_toward(_seat, 1.0 if seated else 0.0, delta / 0.45)
	_wheel = lerpf(_wheel, clampf(steering, -1.0, 1.0) if seated else 0.0, blend)
	_phase = fmod(_phase + speed * delta / STRIDE_LENGTH * TAU, TAU)
	var run_mix := smoothstep(MALE_RUN_BLEND.x, MALE_RUN_BLEND.y, speed)
	var stride := _gait_stride(speed) if not _gait_clips.is_empty() else lerpf(MALE_WALK_STRIDE, MALE_RUN_STRIDE, run_mix)
	# Which way the legs travel relative to where the body faces (+ is toward the character's left). Moving
	# backwards plays the cycle in reverse, turned to the nearest diagonal; sideways and diagonal movement
	# turns the legs toward the travel direction (see _apply_heading).
	var local_velocity := body.global_basis.inverse() * body.velocity
	var raw_heading := atan2(local_velocity.x, local_velocity.z) if speed > 0.5 and not scripted else 0.0
	var backward := absf(raw_heading) > BACKWARD_ANGLE
	var target_heading := raw_heading - signf(raw_heading) * PI if backward else raw_heading
	_heading = lerp_angle(_heading, target_heading, 1.0 - exp(-12.0 * delta))
	_male_phase = fposmod(_male_phase + (-1.0 if backward else 1.0) * speed * delta / stride, 1.0)
	_moving_backward = backward
	_crouch_phase = fposmod(_crouch_phase + (-1.0 if backward else 1.0) * speed * delta / CROUCH_STRIDE, 1.0)
	_crawl_phase = fposmod(_crawl_phase + speed * delta / CRAWL_STRIDE, 1.0)
	if _crouch_idle:
		_crouch_idle_time = fmod(_crouch_idle_time + delta, _crouch_idle.length)
	if _dead:
		speed = 0.0
	var clip_target := clampf(speed / 1.0, 0.0, 1.0) * (1.0 - _crouch) * (1.0 - _prone) if on_floor and not seated else 0.0
	_clip_weight = lerpf(_clip_weight, clip_target, blend)
	# Standing still on the ground plays the authored idle (breathing, weight shifts).
	var idle_target := (1.0 if on_floor and not seated else 0.0) * (1.0 - _crouch) * (1.0 - _prone)
	_idle_weight = lerpf(_idle_weight, idle_target, blend)
	if _idle_clip:
		_idle_time = fmod(_idle_time + delta, _idle_clip.length)
	_breath = fmod(_breath + delta * 1.6, TAU)
	_face_time += delta
	if skeleton != null:
		_relax_hands()
		_pose(speed)
		_pose_lady_face(speed)
	if male_skeleton != null:
		_pose_static_male(speed, speed > 0.1)
		_apply_heading(scripted)
	if male_skeleton != null and vehicle_entry_bend > 0.001:
		_pose_male_bone("CC_Base_Spine01", Vector3.RIGHT, 0.2 + vehicle_entry_bend * 0.62)
		_pose_male_bone("CC_Base_NeckTwist01", Vector3.RIGHT, -vehicle_entry_bend * 0.20)
		male_skeleton.force_update_all_bone_transforms()
	_pose_male_face()
	_pose_actions(body)
	_pose_hit_and_head(delta)
	if _dead and male_model != null:
		_death_time += delta
		var fall := smoothstep(0.0, 1.0, minf(1.0, _death_time / DEATH_SECONDS))
		male_model.rotation.x = (1.45 if _death_forward else -1.45) * fall
		male_model.rotation.z = 0.0
		male_model.position.y = _male_base_height - 0.08 * fall
	elif not seated:
		if model and model.visible:
			model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(76.0) * _prone, blend)
			model.rotation.z = lerp_angle(model.rotation.z, _peek * PEEK_TILT, blend)
			model.position.y = lerpf(_base_height, _base_height - 0.72, _prone)
	if not seated and male_skeleton != null and male_model != null and male_model.visible \
			and body.has_method("is_weapon_equipped") and body.is_weapon_equipped():
		_pose_armed(body)
	elif not seated and body.has_method("is_weapon_equipped") and body.is_weapon_equipped():
		var saved_left := left_grip_target
		var saved_right := right_grip_target
		left_grip_target = to_local(body.weapon.to_global(Vector3(0.105, 0.02, 0.20)))
		right_grip_target = to_local(body.weapon.to_global(Vector3(0.105, -0.03, -0.07)))
		_pose_vehicle_grips()
		left_grip_target = saved_left
		right_grip_target = saved_right
	if seated and use_vehicle_grips and _seat > 0.95:
		_pose_vehicle_grips()
	if mixamo_model != null and mixamo_model.visible:
		_process_mixamo(delta, body, speed, on_floor)

## Where each hand holds the M416, in the rifle's own space (it is 0.85 m long, z forward, y up, +x its left).
## The right hand takes the pistol grip, the left cups the handguard. Other rifles carry their own grips as
## metadata on the weapon holder (scripts/gameplay/weapon_catalog.gd).
const GRIP_RIGHT := Vector3(0.085, -0.03, -0.075)
const GRIP_LEFT := Vector3(0.135, 0.117, 0.22)
## Wrist to the middle of the palm.
const WRIST_TO_PALM := 0.075
const GRIP_CURL_RIGHT := 0.95
const GRIP_CURL_LEFT := 0.75
var _hand_axes := {}

## Finger direction and palm normal of each hand in its own bone space, read from the T-pose rest
## (fingers point outward, thumb forward, palm down).
func _cache_hand_axes() -> void:
	_hand_axes.clear()
	for side in ["L", "R"]:
		var hand := male_skeleton.find_bone("CC_Base_%s_Hand" % side)
		var middle := male_skeleton.find_bone("CC_Base_%s_Mid1" % side)
		var thumb := male_skeleton.find_bone("CC_Base_%s_Thumb1" % side)
		if mini(hand, mini(middle, thumb)) < 0:
			continue
		var origin := male_skeleton.get_bone_global_rest(hand)
		var finger := (male_skeleton.get_bone_global_rest(middle).origin - origin.origin).normalized()
		var thumb_direction := male_skeleton.get_bone_global_rest(thumb).origin - origin.origin
		thumb_direction = (thumb_direction - finger * thumb_direction.dot(finger)).normalized()
		var palm := finger.cross(thumb_direction) * (1.0 if side == "L" else -1.0)
		var inverse := origin.basis.orthonormalized().inverse()
		_hand_axes[side] = {"finger": inverse * finger, "palm": inverse * palm}

## Turns a hand so its fingers point along `finger_direction` and its palm faces `palm_direction`
## (both in skeleton space).
func _orient_hand(side: String, finger_direction: Vector3, palm_direction: Vector3) -> void:
	if not _hand_axes.has(side):
		return
	var hand := male_skeleton.find_bone("CC_Base_%s_Hand" % side)
	var axes: Dictionary = _hand_axes[side]
	var finger_local: Vector3 = axes.finger
	var palm_local: Vector3 = (axes.palm - finger_local * (axes.palm as Vector3).dot(finger_local)).normalized()
	var local_frame := Basis(finger_local, palm_local, finger_local.cross(palm_local))
	var finger := finger_direction.normalized()
	var palm := (palm_direction - finger * palm_direction.dot(finger)).normalized()
	var target_frame := Basis(finger, palm, finger.cross(palm))
	var parent := male_skeleton.get_bone_parent(hand)
	var parent_basis := male_skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	male_skeleton.set_bone_pose_rotation(hand, (parent_basis.inverse() * (target_frame * local_frame.inverse())).get_rotation_quaternion())

## Strafing and diagonal movement: the hips, and so the legs, turn toward the travel direction and the torso
## and head twist back so the character still faces its aim. The gait clips only step forward, so this is
## what makes them work in every direction.
func _apply_heading(scripted: bool) -> void:
	# The hip was put back to its rest rotation before this frame's clips (_pose_static_male), so this turn
	# builds on the clips' pelvis motion without stacking up from frame to frame.
	if scripted or seated or absf(_heading) < 0.02:
		return
	_twist_bone("CC_Base_Hip", _heading)
	_twist_bone("CC_Base_Spine01", -_heading * HEADING_SPINE_01)
	_twist_bone("CC_Base_Spine02", -_heading * HEADING_SPINE_02)
	_twist_bone("CC_Base_Head", -_heading * HEADING_HEAD)
	male_skeleton.force_update_all_bone_transforms()

## Shooter's stance: the chest turns toward the rifle's side so the left shoulder comes forward, which lets
## the left hand reach the handguard (the arms alone are too short), and the head turns back to face forward.
const BLADE_SPINE_01 := -0.22
const BLADE_SPINE_02 := -0.28
const BLADE_HEAD := 0.45

## Turns a bone about the vertical axis on top of its current pose.
func _twist_bone(bone_name: String, angle: float) -> void:
	_rotate_bone_about(bone_name, Vector3.UP, angle)

## Turns a bone about a world-space axis on top of its current pose.
func _rotate_bone_about(bone_name: String, world_axis: Vector3, angle: float) -> void:
	var index := male_skeleton.find_bone(bone_name)
	if index < 0 or world_axis.length_squared() < 0.000001:
		return
	male_skeleton.force_update_all_bone_transforms()
	var parent := male_skeleton.get_bone_parent(index)
	var parent_basis := male_skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var axis := parent_basis.inverse() * (male_skeleton.global_basis.orthonormalized().inverse() * world_axis.normalized())
	male_skeleton.set_bone_pose_rotation(index, Quaternion(axis.normalized(), angle) * male_skeleton.get_bone_pose_rotation(index))

## Where the chest is (the top of the spine), so the rifle is carried at the chest in every stance.
func chest_position() -> Vector3:
	if mixamo_model != null and mixamo_model.visible:
		var skeletons := mixamo_model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var sk := skeletons[0] as Skeleton3D
			var bone_idx := sk.find_bone("mixamorig_Spine2")
			if bone_idx >= 0:
				return sk.to_global(sk.get_bone_global_pose(bone_idx).origin)
		return global_position + Vector3.UP * 1.2
	if male_skeleton == null or male_model == null or not male_model.visible:
		return Vector3.INF
	var chest := male_skeleton.find_bone("CC_Base_Spine02")
	return male_skeleton.to_global(male_skeleton.get_bone_global_pose(chest).origin) if chest >= 0 else Vector3.INF

## A hit from `from_position`: the chest and head jolt away from the shot.
func play_hit(from_position: Vector3) -> void:
	if mixamo_model != null and mixamo_model.visible and mixamo_anim_player != null:
		var hits := ["Big_Side_Hit", "Kidney_Hit", "Hit_Reaction", "Medium_Hit_To_Head"]
		_start_mixamo_action(hits[randi() % hits.size()], 1.2)
	var direction := global_position - from_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		_hit_direction = direction.normalized()
	_hit_time = HIT_SECONDS

## The body drops over in the direction the shot was travelling. reset_death() stands it back up.
func play_death(from_position: Vector3) -> void:
	if mixamo_model != null and mixamo_model.visible and mixamo_anim_player != null:
		_play_mixamo_clip("Death_From_The_Front")
	var direction := global_position - from_position
	direction.y = 0.0
	_death_forward = direction.length_squared() < 0.0001 or direction.dot(global_basis.z) > 0.0
	_dead = true
	_death_time = 0.0
	_hit_time = 0.0

func reset_death() -> void:
	_dead = false
	_death_time = 0.0
	if male_model != null:
		male_model.rotation = Vector3.ZERO
		male_model.position.y = _male_base_height
	if mixamo_model != null:
		mixamo_model.rotation = Vector3.ZERO
		mixamo_model.position = Vector3(0.0, _mixamo_base_height, 0.0)
		_mixamo_current_clip = ""
		_mixamo_action_lock = 0.0
		_mixamo_reload_active = false
		_play_mixamo_clip("Idle_Natural")

func is_dead() -> bool:
	return _dead

func _pose_hit_and_head(delta: float) -> void:
	if male_skeleton == null or male_model == null or not male_model.visible:
		return
	if _prone > 0.01:
		# Lying on the chest, the head lifts to look ahead.
		_rotate_bone_about("CC_Base_Head", male_model.global_basis.x, PRONE_HEAD_LIFT * _prone)
	if _hit_time > 0.0:
		var strength := _hit_time / HIT_SECONDS
		var axis := Vector3.UP.cross(_hit_direction)
		_rotate_bone_about("CC_Base_Spine02", axis, 0.28 * strength)
		_rotate_bone_about("CC_Base_Head", axis, 0.22 * strength)
		_hit_time = maxf(0.0, _hit_time - delta)
	male_skeleton.force_update_all_bone_transforms()

## Maps the crouch clips' tracks to bones.
func _cache_crouch_clips(clips: Dictionary) -> void:
	_crouch_idle = clips.get("CROUCH_Idle")
	_crouch_walk = clips.get("CROUCH_Walk")
	_crouch_tracks.clear()
	if _crouch_idle == null or _crouch_walk == null:
		_crouch_idle = null
		_crouch_walk = null
		return
	for pair in [[_crouch_idle, 0], [_crouch_walk, 2]]:
		var clip: Animation = pair[0]
		for track in clip.get_track_count():
			var index := male_skeleton.find_bone(String(clip.track_get_path(track)).get_slice(":", 1))
			if index < 0:
				continue
			if not _crouch_tracks.has(index):
				_crouch_tracks[index] = [-1, -1, -1, -1]
			match clip.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					_crouch_tracks[index][pair[1]] = track
				Animation.TYPE_POSITION_3D:
					_crouch_tracks[index][pair[1] + 1] = track

## The crouched stance, blended into the crouch walk as the body moves, weighted by how crouched it is.
func _apply_crouch_clips(speed: float) -> void:
	var weight := _crouch * (1.0 - _prone) * (0.0 if _dead else 1.0)
	if _crouch_walk == null or weight < 0.001 or seated:
		return
	var move := clampf(speed / 1.0, 0.0, 1.0)
	var walk_time := _crouch_phase * (_crouch_walk.length - CLIP_FRAME)
	for index: int in _crouch_tracks:
		var tracks: Array = _crouch_tracks[index]
		if tracks[0] >= 0 and tracks[2] >= 0:
			var rotation := _crouch_idle.rotation_track_interpolate(tracks[0], _crouch_idle_time).slerp(
				_crouch_walk.rotation_track_interpolate(tracks[2], walk_time), move)
			male_skeleton.set_bone_pose_rotation(index, male_skeleton.get_bone_pose_rotation(index).slerp(rotation, weight))
		if tracks[1] >= 0 and tracks[3] >= 0:
			var position := _crouch_idle.position_track_interpolate(tracks[1], _crouch_idle_time).lerp(
				_crouch_walk.position_track_interpolate(tracks[3], walk_time), move)
			male_skeleton.set_bone_pose_position(index, male_skeleton.get_bone_pose_position(index).lerp(position, weight))

## Maps the rifle clips' tracks to bones. All or nothing: a model without the full set keeps the procedural
## armed pose alone.
func _cache_rifle_clips(clips: Dictionary) -> void:
	_rifle_clips.clear()
	_rifle_tracks.clear()
	_upper_body.clear()
	for clip_name: String in RIFLE_CLIPS:
		var clip: Animation = clips.get(clip_name)
		if clip == null:
			_rifle_clips.clear()
			_rifle_tracks.clear()
			return
		var tracks := {}
		for track in clip.get_track_count():
			var index := male_skeleton.find_bone(String(clip.track_get_path(track)).get_slice(":", 1))
			if index < 0:
				continue
			if not tracks.has(index):
				tracks[index] = [-1, -1]
			match clip.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					tracks[index][0] = track
				Animation.TYPE_POSITION_3D:
					tracks[index][1] = track
		_rifle_clips[clip_name] = clip
		_rifle_tracks[clip_name] = tracks
	for bone_name: String in UPPER_BODY:
		var index := male_skeleton.find_bone(bone_name)
		if index >= 0:
			_upper_body.append(index)

## The rifle stance over the locomotion (see RIFLE_CLIPS), weighted by how far the rifle is out. Crouching
## and lying prone have their own clips and poses, so the rifle stance fades out with them.
func _apply_rifle_clips(speed: float) -> void:
	_rifle_body = 0.0
	if _rifle_clips.is_empty() or seated or _dead:
		return
	var weight := _armed * (1.0 - _crouch) * (1.0 - _prone)
	if weight < 0.001:
		return
	var standing := weight * (1.0 - _clip_weight)
	var moving := weight * _clip_weight * smoothstep(RIFLE_GAIT_FROM, RIFLE_GAIT_SPEEDS.x, speed)
	var aim_moving := weight * _clip_weight * _aim
	# Standing: the low ready, the aim stance over it, then a held peek leaning over the planted feet.
	_blend_rifle_clip("Rifle_Idle", _rifle_time, standing)
	_blend_rifle_clip("Rifle_ADS_Idle", _rifle_time, standing * _aim)
	_blend_rifle_clip("Rifle_Peek_Left" if _peek < 0.0 else "Rifle_Peek_Right", _rifle_time, standing * absf(_peek))
	# Moving: the rifle jog and sprint step in time with the unarmed gait (same strides, same foot timing),
	# so they are sampled at the same stride phase; aiming lowers only the upper body to the sights.
	if moving > 0.001:
		var sprint := smoothstep(RIFLE_GAIT_SPEEDS.x, RIFLE_GAIT_SPEEDS.y, speed)
		_blend_rifle_clip("Rifle_Jog_InPlace", _male_phase * (_rifle_clips.Rifle_Jog_InPlace.length - CLIP_FRAME), moving)
		_blend_rifle_clip("Rifle_Sprint_InPlace", _male_phase * (_rifle_clips.Rifle_Sprint_InPlace.length - CLIP_FRAME),
			moving * sprint)
	_blend_rifle_clip("Rifle_ADS_Idle", _rifle_time, aim_moving, _upper_body)
	# In the air the legs tuck from take-off to landing.
	_blend_rifle_clip("Rifle_Jump", minf(_air_time, _rifle_clips.Rifle_Jump.length), weight * _air)
	_rifle_body = clampf(standing + maxf(moving, aim_moving), 0.0, 1.0)

## Slerps the listed bones (all the clip's bones when empty) toward `clip_name` at `time` by `weight`.
## Looping clips wrap; the jump is clamped by its caller.
func _blend_rifle_clip(clip_name: String, time: float, weight: float, bones: Array[int] = []) -> void:
	if weight < 0.001:
		return
	var clip: Animation = _rifle_clips[clip_name]
	var tracks: Dictionary = _rifle_tracks[clip_name]
	var at := fposmod(time, clip.length) if clip_name != "Rifle_Jump" else time
	for index: int in (bones if not bones.is_empty() else tracks.keys()):
		var pair: Array = tracks.get(index, [-1, -1])
		if pair[0] >= 0:
			male_skeleton.set_bone_pose_rotation(index, male_skeleton.get_bone_pose_rotation(index).slerp(
				clip.rotation_track_interpolate(pair[0], at), weight))
		if pair[1] >= 0:
			male_skeleton.set_bone_pose_position(index, male_skeleton.get_bone_pose_position(index).lerp(
				clip.position_track_interpolate(pair[1], at), weight))

## How much of a peek the rifle clips lean over planted feet (standing with a rifle out); the whole model
## tips for the rest (moving, unarmed, crouched, prone), as the block figure and the lady do.
func _rifle_peek_share() -> float:
	if _rifle_clips.is_empty():
		return 0.0
	return _armed * (1.0 - _clip_weight) * (1.0 - _crouch) * (1.0 - _prone)

## Prone legs: straight behind, and while moving one knee at a time draws up beside the body.
func _pose_prone(speed: float) -> void:
	if _prone < 0.5 or seated or _dead:
		return
	var crawl := clampf(speed / 0.6, 0.0, 1.0)
	for side: float in [1.0, -1.0]:
		var suffix := "L" if side > 0.0 else "R"
		var draw := maxf(0.0, sin(_crawl_phase * TAU + (0.0 if side > 0.0 else PI))) * crawl
		_pose_male_bone("CC_Base_%s_Thigh" % suffix, Vector3.RIGHT, -0.85 * draw)
		_pose_male_bone("CC_Base_%s_Calf" % suffix, Vector3.RIGHT, 0.08 + 1.25 * draw)
	male_skeleton.force_update_all_bone_transforms()

## Two hands on the rifle: arms solved to the grips, hands turned to wrap the pistol grip and handguard,
## fingers closed around them. Used for the realistic character whenever a weapon is out.
func _pose_armed(body: CharacterBody3D) -> void:
	if _hand_axes.is_empty():
		_cache_hand_axes()
	var weapon: Node3D = body.weapon
	var weapon_basis := weapon.global_basis
	# The rifle clips blade the chest only part of the way the left hand needs to reach the game's handguard
	# (their own rifle sits closer to the body), so a share of the procedural turn stays on top of them. Only
	# while the body faces the aim (combat mode; a remote player's yaw is its aim): otherwise the rifle can
	# point well off the body's front and the full turn is needed to reach it.
	var faces_aim: bool = body.get("combat_mode") != false
	var blade := 1.0 - (1.0 - RIFLE_CLIP_BLADE) * _rifle_body if faces_aim else 1.0
	_twist_bone("CC_Base_Spine01", BLADE_SPINE_01 * blade)
	_twist_bone("CC_Base_Spine02", BLADE_SPINE_02 * blade)
	_twist_bone("CC_Base_Head", BLADE_HEAD * blade)
	male_skeleton.force_update_all_bone_transforms()
	# Right hand: handshake grip on the pistol grip, palm toward the rifle's left. Left hand: C-clamp on the
	# left side of the handguard, palm toward the rifle's right, fingers forward.
	var fingers := {"R": Vector3(0.0, -0.25, 0.97).normalized(), "L": Vector3(0.0, 0.1, 0.995).normalized()}
	var palms := {"R": Vector3(1.0, 0.0, 0.0), "L": Vector3(-1.0, 0.0, 0.0)}
	var grips := {"R": weapon.get_meta("grip_right", GRIP_RIGHT), "L": weapon.get_meta("grip_left", GRIP_LEFT)}
	for side: String in ["L", "R"]:
		var wrist: Vector3 = weapon.to_global(grips[side]) - weapon_basis * fingers[side] * WRIST_TO_PALM
		if side == "L":
			left_grip_target = to_local(wrist)
		else:
			right_grip_target = to_local(wrist)
	_pose_vehicle_grips()
	var rig_basis := male_skeleton.global_basis.orthonormalized().inverse()
	for side: String in ["L", "R"]:
		_orient_hand(side, rig_basis * (weapon_basis * fingers[side]), rig_basis * (weapon_basis * palms[side]))
		_pose_male_fingers(side, GRIP_CURL_RIGHT if side == "R" else -GRIP_CURL_LEFT)
	male_skeleton.force_update_all_bone_transforms()

## The supplied lady rig has eye, jaw and head bones but no eyelid/lip shapes.
## Give those available controls a restrained, human idle performance instead
## of leaving the face as a permanently fixed statue.
func _pose_lady_face(speed: float) -> void:
	if model == null or not model.visible:
		return
	var moving := clampf(speed / 3.5, 0.0, 1.0)
	# Small eye saccades plus a slower head follow-through; values stay subtle
	# so they work both while walking and while seated in a vehicle.
	var gaze_yaw := sin(_face_time * 0.83) * 0.10 + sin(_face_time * 0.29) * 0.045
	var gaze_pitch := sin(_face_time * 0.57 + 0.8) * 0.045
	var head_yaw := gaze_yaw * 0.30 + sin(_face_time * 0.22) * 0.025
	var head_pitch := gaze_pitch * 0.45 - moving * 0.025
	_rotate_pair("DEF-eye.L", Vector3.UP, gaze_yaw, Vector3.RIGHT, gaze_pitch)
	_rotate_pair("DEF-eye.R", Vector3.UP, gaze_yaw, Vector3.RIGHT, gaze_pitch)
	_rotate_pair("head", Vector3.UP, head_yaw, Vector3.RIGHT, head_pitch)
	# A very small jaw cycle gives breathing/attention without pretending this
	# non-facial rig has lip-sync capability.
	_turn("DEF-jaw", Vector3.RIGHT, maxf(0.0, sin(_face_time * 1.15)) * 0.018)
	skeleton.force_update_all_bone_transforms()

func _pose_static_male(speed: float, moving: bool) -> void:
	if male_model == null or not male_model.visible:
		return
	# Rahul's clips turn the pelvis (CC_Base_Hip) and the clips blend from the current pose, while the heading
	# twist (_apply_heading) and the stance turns build on it. Back to rest first every frame, so neither the
	# twist nor a clip's partial blend stacks up from the frame before.
	var hip := male_skeleton.find_bone("CC_Base_Hip") if male_skeleton != null else -1
	if hip >= 0:
		male_skeleton.set_bone_pose_rotation(hip, male_skeleton.get_bone_rest(hip).basis.get_rotation_quaternion())
	if seated:
		_pose_male_driving()
		return
	var gait := clampf(speed / 6.0, 0.0, 1.0) if moving else 0.0
	var stride := sin(_phase) * lerpf(0.42, 0.90, gait) * gait
	# The gait clips carry their own pelvis bob and forward lean.
	var bob := absf(sin(_phase)) * 0.045 * gait * (1.0 - _clip_weight)
	# Prone lowers the body to the ground (the smoothing is in _prone itself).
	male_model.position.y = _male_base_height + bob * (1.0 - _prone) - PRONE_DROP * _prone
	# The crouch clips carry their own lean; only the procedural fallback tips the whole model.
	var crouch_tilt := 0.0 if _crouch_walk != null else 0.16
	# Prone pitches the whole body forward onto the chest; peeking leans it sideways.
	var upright_tilt := 0.06 * gait * (1.0 - _clip_weight) + crouch_tilt * _crouch - 0.08 * _air
	male_model.rotation = Vector3(upright_tilt * (1.0 - _prone) + PRONE_PITCH * _prone, 0.0,
		_peek * PEEK_TILT * (1.0 - _rifle_peek_share()))
	if male_skeleton == null:
		return
	for side: float in [1.0, -1.0]:
		var suffix := "L" if side > 0.0 else "R"
		var leg := stride * side
		var knee := maxf(0.0, sin(_phase + (0.0 if side > 0.0 else PI))) * 0.72 * gait + 0.82 * _crouch + 0.62 * _air
		var thigh := -leg - 0.55 * _crouch - 0.42 * _air
		var arm := leg * 0.78 - 0.30 * _air
		# Opposite arm/leg swing and a bent knee/elbow make both walk and run
		# readable at third-person distance.
		_pose_male_bone("CC_Base_%s_Thigh" % suffix, Vector3.RIGHT, thigh)
		_pose_male_bone("CC_Base_%s_Calf" % suffix, Vector3.RIGHT, knee)
		_pose_male_bone("CC_Base_%s_Hand" % suffix, Vector3.RIGHT, -leg * 0.22)
		_pose_male_fingers(suffix, 0.22 + 0.5 * gait * gait)  # loose fists when running
	_pose_male_bone("CC_Base_Spine01", Vector3.UP, stride * 0.13)
	_pose_male_bone("CC_Base_Spine02", Vector3.RIGHT, 0.05 * gait + 0.10 * _crouch + sin(_breath) * 0.014)
	male_skeleton.force_update_all_bone_transforms()
	# The CC rig rests in a T-pose, so swinging the arms about their rest axis kept
	# them horizontal. Aim them down from the shoulder instead; sprinting bends the
	# elbows like a BGMI run. Armed grips still override this afterwards.
	for side: float in [1.0, -1.0]:
		var swing := stride * side * 0.78 - 0.30 * _air
		var elbow_bend := lerpf(0.22, 1.15, gait * gait) + 0.35 * _crouch + 0.25 * _air
		_hang_male_arm("L" if side > 0.0 else "R", side, swing, elbow_bend)
	_apply_male_clips(speed)
	_apply_rifle_clips(speed)
	_apply_crouch_clips(speed)
	_pose_prone(speed)
	male_skeleton.force_update_all_bone_transforms()

## Finds the authored clips (the realistic library first, then the model's own) and maps their
## tracks to bones. Players are left stopped: clips are sampled by stride phase or idle time in
## _apply_male_clips, so the feet keep pace with the body.
func _cache_male_clips() -> void:
	var clips := _male_clip_library()
	_cache_gait_clips(clips)
	_cache_crouch_clips(clips)
	_cache_rifle_clips(clips)
	# Godot's importer reads the "_Cycle" suffix as a loop hint and strips it: "Walk_Cycle" -> "Walk".
	_walk_clip = _first_clip(clips, ["WALK_Realistic", "Walk", "Walk_Cycle"])
	_run_clip = _first_clip(clips, ["RUN_Realistic", "Run", "Run_Cycle", "Run_InPlace"])
	_idle_clip = _first_clip(clips, ["IDLE_Natural"])
	if _walk_clip == null or _run_clip == null:
		_walk_clip = null
		return
	for clip_slot in 3:
		var clip: Animation = [_walk_clip, _run_clip, _idle_clip][clip_slot]
		if clip == null:
			continue
		for track in clip.get_track_count():
			var bone_name := String(clip.track_get_path(track)).get_slice(":", 1)
			var index := male_skeleton.find_bone(bone_name)
			if index < 0:
				continue
			var slots: Array = _clip_tracks.get(index, [-1, -1, -1, -1, -1, -1])
			match clip.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					slots[clip_slot] = track
				Animation.TYPE_POSITION_3D:
					slots[3 + clip_slot] = track
			_clip_tracks[index] = slots

## Collects the speed-matched gait clips and maps their tracks to bones. All or nothing: if any is missing
## the older walk/run pair is used instead.
func _cache_gait_clips(clips: Dictionary) -> void:
	_gait_clips.clear()
	_gait_tracks.clear()
	for entry: Array in GAIT_CLIPS:
		var clip: Animation = clips.get(entry[0])
		if clip == null:
			_gait_clips.clear()
			return
		var cycle := clip.length - CLIP_FRAME
		_gait_clips.append({"clip": clip, "speed": float(entry[1]), "cycle": cycle, "stride": float(entry[1]) * cycle})
	for slot in _gait_clips.size():
		var clip: Animation = _gait_clips[slot].clip
		for track in clip.get_track_count():
			var index := male_skeleton.find_bone(String(clip.track_get_path(track)).get_slice(":", 1))
			if index < 0:
				continue
			if not _gait_tracks.has(index):
				var slots: Array = []
				for _clip in _gait_clips.size():
					slots.append([-1, -1])
				_gait_tracks[index] = slots
			match clip.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					_gait_tracks[index][slot][0] = track
				Animation.TYPE_POSITION_3D:
					_gait_tracks[index][slot][1] = track

## The two gait clips either side of `speed` and how far between them: [lower, upper, weight 0..1].
func _gait_pair(speed: float) -> Array:
	var last := _gait_clips.size() - 1
	if speed <= _gait_clips[0].speed:
		return [0, 0, 0.0]
	if speed >= _gait_clips[last].speed:
		return [last, last, 0.0]
	for index in last:
		var low: float = _gait_clips[index].speed
		var high: float = _gait_clips[index + 1].speed
		if speed <= high:
			return [index, index + 1, smoothstep(0.0, 1.0, (speed - low) / (high - low))]
	return [last, last, 0.0]

## Metres per cycle for the current speed: the blend of the neighbouring clips' strides.
func _gait_stride(speed: float) -> float:
	var pair := _gait_pair(speed)
	return lerpf(_gait_clips[pair[0]].stride, _gait_clips[pair[1]].stride, pair[2])

## Every clip by name: the model's own AnimationPlayer, overridden by the realistic library.
func _male_clip_library() -> Dictionary:
	var clips := {}
	var library: Node = null
	if not MALE_ANIMATIONS_PATH.is_empty() and ResourceLoader.exists(MALE_ANIMATIONS_PATH):
		library = (load(MALE_ANIMATIONS_PATH) as PackedScene).instantiate()
	for source: Node in [male_model, library]:
		if source == null:
			continue
		for player: AnimationPlayer in source.find_children("*", "AnimationPlayer", true, false):
			player.stop()
			for clip_name in player.get_animation_list():
				clips[String(clip_name)] = player.get_animation(clip_name)
	if library:
		library.free()
	return clips

static func _first_clip(clips: Dictionary, names: Array) -> Animation:
	for clip_name: String in names:
		if clips.has(clip_name):
			return clips[clip_name]
	return null

## Blends the walk and run clips (by speed) at the current stride phase over the procedural pose,
## weighted by how much the person is moving on foot. Weapon grips and actions still apply afterwards.
func _apply_male_clips(speed: float) -> void:
	if _walk_clip == null:
		return
	# Idle carries the standing pose; the gait clips take over as the body starts moving.
	var idle_weight := _idle_weight * (1.0 - _clip_weight) if _idle_clip else 0.0
	if idle_weight > 0.001:
		for index: int in _clip_tracks:
			var slots: Array = _clip_tracks[index]
			if slots[2] >= 0:
				male_skeleton.set_bone_pose_rotation(index, male_skeleton.get_bone_pose_rotation(index).slerp(
					_idle_clip.rotation_track_interpolate(slots[2], _idle_time), idle_weight))
			if slots[5] >= 0:
				male_skeleton.set_bone_pose_position(index, male_skeleton.get_bone_pose_position(index).lerp(
					_idle_clip.position_track_interpolate(slots[5], _idle_time), idle_weight))
	if _clip_weight < 0.001:
		return
	if not _gait_clips.is_empty():
		_apply_gait_clips(speed)
		return
	var run_mix := smoothstep(MALE_RUN_BLEND.x, MALE_RUN_BLEND.y, speed)
	var walk_time := _male_phase * _walk_clip.length
	var run_time := _male_phase * _run_clip.length
	for index: int in _clip_tracks:
		var slots: Array = _clip_tracks[index]
		if slots[0] >= 0 and slots[1] >= 0:
			var rotation := _walk_clip.rotation_track_interpolate(slots[0], walk_time).slerp(
				_run_clip.rotation_track_interpolate(slots[1], run_time), run_mix)
			male_skeleton.set_bone_pose_rotation(index,
				male_skeleton.get_bone_pose_rotation(index).slerp(rotation, _clip_weight))
		if slots[3] >= 0 and slots[4] >= 0:
			var position := _walk_clip.position_track_interpolate(slots[3], walk_time).lerp(
				_run_clip.position_track_interpolate(slots[4], run_time), run_mix)
			male_skeleton.set_bone_pose_position(index,
				male_skeleton.get_bone_pose_position(index).lerp(position, _clip_weight))

## Blends the two gait clips around `speed` at the current stride phase over the procedural pose.
func _apply_gait_clips(speed: float) -> void:
	var pair := _gait_pair(speed)
	var low: Dictionary = _gait_clips[pair[0]]
	var high: Dictionary = _gait_clips[pair[1]]
	var weight: float = pair[2]
	var low_time: float = _male_phase * low.cycle
	var high_time: float = _male_phase * high.cycle
	for index: int in _gait_tracks:
		var slots: Array = _gait_tracks[index]
		var rotation_low: int = slots[pair[0]][0]
		var rotation_high: int = slots[pair[1]][0]
		if rotation_low >= 0 and rotation_high >= 0:
			var rotation: Quaternion = (low.clip as Animation).rotation_track_interpolate(rotation_low, low_time).slerp(
				(high.clip as Animation).rotation_track_interpolate(rotation_high, high_time), weight)
			male_skeleton.set_bone_pose_rotation(index, male_skeleton.get_bone_pose_rotation(index).slerp(rotation, _clip_weight))
		var position_low: int = slots[pair[0]][1]
		var position_high: int = slots[pair[1]][1]
		if position_low >= 0 and position_high >= 0:
			var position: Vector3 = (low.clip as Animation).position_track_interpolate(position_low, low_time).lerp(
				(high.clip as Animation).position_track_interpolate(position_high, high_time), weight)
			male_skeleton.set_bone_pose_position(index, male_skeleton.get_bone_pose_position(index).lerp(position, _clip_weight))

## Points the upper arm down beside the body, swung forward or back by `swing`
## (same sign convention as the legs), and bends the elbow forward by `bend`.
## Directions are character-space (forward +Z, left +X) converted into the rig.
func _hang_male_arm(suffix: String, side: float, swing: float, bend: float) -> void:
	var upper := male_skeleton.find_bone("CC_Base_%s_Upperarm" % suffix)
	var lower := male_skeleton.find_bone("CC_Base_%s_Forearm" % suffix)
	var hand := male_skeleton.find_bone("CC_Base_%s_Hand" % suffix)
	if mini(upper, mini(lower, hand)) < 0:
		return
	var to_rig := male_skeleton.global_basis.inverse() * global_basis
	var shoulder := male_skeleton.get_bone_global_pose(upper).origin
	var upper_length := shoulder.distance_to(male_skeleton.get_bone_global_pose(lower).origin)
	var lower_length := male_skeleton.get_bone_global_pose(lower).origin.distance_to(male_skeleton.get_bone_global_pose(hand).origin)
	var outward := Vector3(side * 0.12, 0.0, 0.0)
	var upper_direction := (to_rig * (Vector3.DOWN.rotated(Vector3.RIGHT, swing) + outward)).normalized()
	var elbow := shoulder + upper_direction * upper_length
	var lower_direction := (to_rig * (Vector3.DOWN.rotated(Vector3.RIGHT, swing - bend) + outward * 0.5)).normalized()
	_aim_bone_segment(male_skeleton, upper, lower, elbow)
	_aim_bone_segment(male_skeleton, lower, hand, elbow + lower_direction * lower_length)

func _pose_male_fingers(side: String, curl: float) -> void:
	for finger in ["Index", "Mid", "Ring", "Pinky"]:
		for joint in ["1", "2", "3"]:
			_pose_male_local("CC_Base_%s_%s%s" % [side, finger, joint], Vector3.RIGHT, curl)
	for joint in ["1", "2", "3"]:
		_pose_male_local("CC_Base_%s_Thumb%s" % [side, joint], Vector3.RIGHT, curl * 0.6)

## Where the hands hold a car's wheel when the car gives no grip points: 9 and 3 o'clock on a wheel this far
## ahead of and above the hip joint (character space, +z forward, +x the character's left).
const WHEEL_ABOVE_HIP := 0.40
const WHEEL_AHEAD_OF_HIP := 0.42
const WHEEL_RADIUS := 0.19

func _pose_male_driving() -> void:
	# Seated driving pose. The CC rig rests in a T-pose, so fixed swings about the character's x axis only
	# twisted the arms (they stayed straight out through the windows) and fixed leg angles left the feet short
	# of the pedals, under the floor of a low car. Both are solved to targets instead: legs to the pedals
	# (foot_target from vehicle_entry.gd), hands to the wheel. See docs/lessons/CHARACTERS.md.
	_pose_male_bone("CC_Base_Spine01", Vector3.RIGHT, 0.20)
	male_skeleton.force_update_all_bone_transforms()
	for side in ["L", "R"]:
		var thigh := male_skeleton.find_bone("CC_Base_%s_Thigh" % side)
		if thigh < 0:
			continue
		var hip_joint: Vector3 = to_local(male_skeleton.global_transform * male_skeleton.get_bone_global_pose(thigh).origin)
		# Each foot on its own side of the footwell, straight ahead of its hip.
		var ankle := Vector3(hip_joint.x, foot_target.y + ANKLE_HEIGHT, foot_target.z)
		if vehicle_foot_half_width > 0.0:
			ankle.x = signf(hip_joint.x) * vehicle_foot_half_width
		if vehicle_mount_swing > 0.001 and side == "R":
			ankle.x -= vehicle_mount_swing * 0.55
			ankle.y += vehicle_mount_swing * 0.40
			ankle.z -= vehicle_mount_swing * 0.45
		_solve_male_limb("CC_Base_%s_Thigh" % side, "CC_Base_%s_Calf" % side, "CC_Base_%s_Foot" % side, ankle,
			Vector3(0.0, 0.6, 1.0))
	if not use_vehicle_grips:
		# Hands at 9 and 3; steering turns them round the wheel's centre.
		var hip := _male_hip_local()
		var centre := hip + Vector3(0.0, WHEEL_ABOVE_HIP, WHEEL_AHEAD_OF_HIP)
		var turn := -clampf(steering, -1.0, 1.0) * 0.6
		left_grip_target = centre + Vector3(cos(turn), sin(turn), 0.0) * WHEEL_RADIUS
		right_grip_target = centre - Vector3(cos(turn), sin(turn), 0.0) * WHEEL_RADIUS
		_pose_vehicle_grips()
		_pose_male_fingers("L", 0.9)
		_pose_male_fingers("R", 0.9)
	male_skeleton.force_update_all_bone_transforms()

## The pelvis joint in this node's space.
func _male_hip_local() -> Vector3:
	var pelvis := male_skeleton.find_bone("CC_Base_Hip")
	if pelvis < 0:
		return Vector3(0.0, hip_height(), 0.0)
	return to_local(male_skeleton.global_transform * male_skeleton.get_bone_global_pose(pelvis).origin)

## Two-bone solve on the realistic rig: `root`..`end` reaches `target` (this node's space), bending toward
## `pole` (this node's space). The same method as the wheel grips in _pose_vehicle_grips().
func _solve_male_limb(root_name: String, middle_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var upper := male_skeleton.find_bone(root_name)
	var lower := male_skeleton.find_bone(middle_name)
	var tip := male_skeleton.find_bone(end_name)
	if mini(upper, mini(lower, tip)) < 0:
		return
	male_skeleton.force_update_all_bone_transforms()
	var goal := male_skeleton.to_local(to_global(target))
	var start := male_skeleton.get_bone_global_pose(upper).origin
	var joint := male_skeleton.get_bone_global_pose(lower).origin
	var end := male_skeleton.get_bone_global_pose(tip).origin
	var upper_length := start.distance_to(joint)
	var lower_length := joint.distance_to(end)
	var reach := clampf(start.distance_to(goal), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var forward := (goal - start).normalized()
	var bend_hint := male_skeleton.global_basis.inverse() * global_basis * pole
	var bend := (bend_hint - forward * bend_hint.dot(forward)).normalized()
	var along := (upper_length * upper_length + reach * reach - lower_length * lower_length) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	_aim_bone_segment(male_skeleton, upper, lower, start + forward * along + bend * height)
	_aim_bone_segment(male_skeleton, lower, tip, start + forward * reach)

func _cache_male_bones() -> void:
	for bone_name in ["CC_Base_L_Thigh", "CC_Base_R_Thigh", "CC_Base_L_Calf", "CC_Base_R_Calf",
		"CC_Base_L_Upperarm", "CC_Base_R_Upperarm", "CC_Base_L_Forearm", "CC_Base_R_Forearm",
		"CC_Base_L_Hand", "CC_Base_R_Hand",
		"CC_Base_Spine01", "CC_Base_Spine02"]:
		var index := male_skeleton.find_bone(bone_name)
		if index >= 0:
			_male_bones[bone_name] = index

func _pose_male_bone(bone_name: String, axis: Vector3, angle: float) -> void:
	if not _male_bones.has(bone_name):
		return
	var index: int = _male_bones[bone_name]
	# Convert the character-space swing axis into this bone's local space.
	# Local-X on this CC rig twists a limb; this produces visible forward/back
	# arm and leg movement instead.
	var rest_global := male_skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var local_axis := (rest_global.inverse() * axis).normalized()
	male_skeleton.set_bone_pose_rotation(index,
		male_skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(local_axis, angle))

func _pose_male_local(bone_name: String, axis: Vector3, angle: float) -> void:
	var index := male_skeleton.find_bone(bone_name)
	if index < 0:
		return
	male_skeleton.set_bone_pose_rotation(index,
		male_skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(axis, angle))

## Analytic two-bone arm solve in skeleton space. Uses the current rig lengths,
## preserving the shoulders, proportions, and the vehicle's fixed grip contacts.
func _pose_vehicle_grips() -> void:
	var mixamo := mixamo_model != null and mixamo_model.visible
	var rig := mixamo_skeleton if mixamo else (male_skeleton if male_model != null and male_model.visible else skeleton)
	if rig == null:
		return
	for side in ["L", "R"]:
		var male := rig == male_skeleton
		var upper_name := "CC_Base_%s_Upperarm" % side if male else "DEF-upper_arm.%s" % side
		var lower_name := "CC_Base_%s_Forearm" % side if male else "DEF-forearm.%s" % side
		var hand_name := "CC_Base_%s_Hand" % side if male else "DEF-hand.%s" % side
		if mixamo:
			var prefix := "mixamorig_Left" if side == "L" else "mixamorig_Right"
			upper_name = prefix + "Arm"
			lower_name = prefix + "ForeArm"
			hand_name = prefix + "Hand"
		var upper := rig.find_bone(upper_name)
		var lower := rig.find_bone(lower_name)
		var hand := rig.find_bone(hand_name)
		if mini(upper, mini(lower, hand)) < 0:
			continue
		rig.force_update_all_bone_transforms()
		var target := left_grip_target if side == "L" else right_grip_target
		target = rig.to_local(to_global(target))
		var shoulder := rig.get_bone_global_pose(upper).origin
		var elbow := rig.get_bone_global_pose(lower).origin
		var wrist := rig.get_bone_global_pose(hand).origin
		var upper_length := shoulder.distance_to(elbow)
		var lower_length := elbow.distance_to(wrist)
		var reach := clampf(shoulder.distance_to(target), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
		var forward := (target - shoulder).normalized()
		var pole := rig.global_basis.inverse() * global_basis * Vector3(0.3 if side == "L" else -0.3, -1.0, -0.15)
		var bend := (pole - forward * pole.dot(forward)).normalized()
		var along := (upper_length * upper_length + reach * reach - lower_length * lower_length) / (2.0 * reach)
		var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
		var desired_elbow := shoulder + forward * along + bend * height
		_aim_bone_segment(rig, upper, lower, desired_elbow)
		_aim_bone_segment(rig, lower, hand, target)
		if not male and not mixamo:
			for finger: String in FINGERS:
				for joint in [".01", ".02", ".03"]:
					_curl("DEF-%s%s.%s" % [finger, joint, side], 0.85)
			for joint in [".02", ".03"]:
				_curl("DEF-thumb%s.%s" % [joint, side], 0.55)
		rig.force_update_all_bone_transforms()

func _aim_bone_segment(rig: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	rig.force_update_all_bone_transforms()
	var pose := rig.get_bone_global_pose(bone)
	var current := rig.get_bone_global_pose(child).origin - pose.origin
	var desired := target - pose.origin
	if current.length_squared() < 0.00001 or desired.length_squared() < 0.00001:
		return
	var rotation := Basis(Quaternion(current.normalized(), desired.normalized())) * pose.basis.orthonormalized()
	var parent := rig.get_bone_parent(bone)
	var parent_basis := rig.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	rig.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotation).get_rotation_quaternion())

func _pose(speed: float) -> void:
	var moving := clampf(speed / 1.2, 0.0, 1.0) * (1.0 - _air) * (1.0 - _seat)
	var swing := sin(_phase) * lerpf(0.45, 0.8, _gait) * moving
	var sit := smoothstep(0.0, 1.0, _seat)
	var seated_legs := _seated_leg_angles()
	# This imported rig parents its arm roots directly to the rig root, outside
	# the spine chain. Carry those roots with the same seated torso lean.
	var pivot := (skeleton.get_bone_global_rest(skeleton.find_bone("DEF-thigh.L")).origin + skeleton.get_bone_global_rest(skeleton.find_bone("DEF-thigh.R")).origin) * 0.5
	for side_name in ["L", "R"]:
		var arm_index := skeleton.find_bone("DEF-upper_arm." + side_name)
		var rest_origin := skeleton.get_bone_global_rest(arm_index).origin
		var carried := pivot + Basis(Vector3.RIGHT, 0.22 * sit if use_vehicle_grips else 0.0) * (rest_origin - pivot)
		var parent_index := skeleton.get_bone_parent(arm_index)
		var parent_rest := skeleton.get_bone_global_rest(parent_index)
		skeleton.set_bone_pose_position(arm_index, parent_rest.affine_inverse() * carried)
	for side: float in [1.0, -1.0]:
		var suffix := ".L" if side > 0.0 else ".R"
		var leg := swing * side
		# Knee bends most while that leg swings through; crouching and jumping tuck it.
		var knee := maxf(0.0, sin(_phase + (0.0 if side > 0.0 else PI) + 0.6)) * lerpf(0.6, 1.2, _gait) * moving
		knee += 0.9 * _crouch + 0.7 * _air
		# Seated: legs solved so the feet reach the pedals.
		_rotate("DEF-thigh" + suffix, Vector3.RIGHT, lerpf(-leg - 0.6 * _crouch - 0.5 * _air, -seated_legs.x, sit))
		_rotate("DEF-shin" + suffix, Vector3.RIGHT, lerpf(knee, seated_legs.y, sit))
		# Feet rest flat on the pedals whatever the knee angle.
		_rotate("DEF-foot" + suffix, Vector3.RIGHT, lerpf(-0.3 * _crouch, seated_legs.x - seated_legs.y, sit))
		# Arms come down from the rest pose and swing against the legs; seated they reach
		# forward to the wheel, and steering lifts one hand while the other drops.
		var arm_swing := lerpf(swing * side * 0.8, -0.95 - 0.3 * _wheel * side, sit)
		var drop := lerpf(_arm_drop - 0.4 * _air, _arm_drop - 0.15, sit)
		_rotate_pair("DEF-upper_arm" + suffix, Vector3.BACK, -drop * side, Vector3.RIGHT, arm_swing)
		# Elbows hinge about their own lateral axis, so the forearm comes forward, never outward.
		_turn("DEF-forearm" + suffix, Vector3.RIGHT, lerpf(0.15 + 0.4 * _gait * moving + 0.3 * _air, 0.75, sit))
	var lean := 0.12 * _gait * moving + 0.25 * _crouch + (0.22 if use_vehicle_grips else -0.08) * sit
	_rotate("DEF-spine.001", Vector3.RIGHT, lean + sin(_breath) * 0.015 * (1.0 - moving))
	_rotate("DEF-spine.003", Vector3.UP, swing * 0.25)
	_rotate("DEF-spine.006", Vector3.RIGHT, -lean * 0.6)
	var bob := (absf(sin(_phase)) * 0.04 * moving - 0.25 * _crouch) * (1.0 - sit)
	model.position.y = _base_height + bob

## Fingers curl a little so the hands do not stay flat as in the modelling pose.
func _relax_hands() -> void:
	for suffix in [".L", ".R"]:
		for finger: String in FINGERS:
			for joint in [".01", ".02", ".03"]:
				_curl("DEF-%s%s%s" % [finger, joint, suffix], FINGER_CURL)
		for joint in [".02", ".03"]:
			_curl("DEF-thumb%s%s" % [joint, suffix], FINGER_CURL * 0.6)
		# Wrists turn in towards the thighs instead of flaring out like the modelling pose.
		_turn("DEF-hand" + suffix, Vector3.BACK, -WRIST_IN * (1.0 if suffix == ".L" else -1.0))

func _curl(bone_name: String, angle: float) -> void:
	_turn(bone_name, Vector3.RIGHT, angle)

## Rotates a bone about one of its own local axes, relative to its rest pose.
func _turn(bone_name: String, local_axis: Vector3, angle: float) -> void:
	var index := skeleton.find_bone(bone_name)
	if index >= 0:
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(local_axis, angle))

## Rotates a bone about an axis given in the skeleton's (model) space, relative to its rest pose.
func _rotate(bone_name: String, axis: Vector3, angle: float) -> void:
	if not _bones.has(bone_name):
		return
	var index: int = _bones[bone_name]
	skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * _local(index, axis, angle))

func _rotate_pair(bone_name: String, first_axis: Vector3, first: float, second_axis: Vector3, second: float) -> void:
	if not _bones.has(bone_name):
		return
	var index: int = _bones[bone_name]
	var delta := _local(index, first_axis, first) * _local_after(index, first_axis, first, second_axis, second)
	skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * delta)

func _local(index: int, axis: Vector3, angle: float) -> Quaternion:
	var rest := skeleton.get_bone_global_rest(index).basis.orthonormalized()
	return Quaternion((rest.inverse() * axis).normalized(), angle)

## Second rotation about a model-space axis, applied after the first one has already turned the bone.
func _local_after(index: int, first_axis: Vector3, first: float, axis: Vector3, angle: float) -> Quaternion:
	var turned := skeleton.get_bone_global_rest(index).basis.orthonormalized() * Basis(_local(index, first_axis, first))
	return Quaternion((turned.inverse() * axis).normalized(), angle)

func _model_bounds() -> AABB:
	return _model_bounds_for(model)

func _model_bounds_for(target: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.transform * mesh.get_aabb()
		var node := mesh.get_parent() as Node3D
		while node and node != target:
			box = node.transform * box
			node = node.get_parent() as Node3D
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

## Both supplied rigs expose eyes, head and jaw, but lack eyelid/lip morphs.
func _pose_male_face() -> void:
	if male_skeleton == null or male_model == null or not male_model.visible:
		return
	var yaw := sin(_face_time * 0.83) * 0.10
	var pitch := sin(_face_time * 0.57) * 0.035
	_pose_male_local("CC_Base_L_Eye", Vector3.UP, yaw)
	_pose_male_local("CC_Base_R_Eye", Vector3.UP, yaw)
	_pose_male_local("CC_Base_Head", Vector3.UP, yaw * 0.25)
	_pose_male_local("CC_Base_JawRoot", Vector3.RIGHT, maxf(0.0, sin(_face_time * 1.15)) * 0.018)

func _pose_actions(body: CharacterBody3D) -> void:
	if seated:
		return
	var striking := int(get_meta("attack_until", 0)) > Time.get_ticks_msec()
	var swimming: bool = body.get("swimming") == true
	if not striking and not swimming:
		return
	var swing := sin(_face_time * 5.0) * 0.8 if swimming else -1.3
	if skeleton != null and model != null and model.visible:
		_turn("DEF-upper_arm.R", Vector3.RIGHT, swing)
		_turn("DEF-forearm.R", Vector3.RIGHT, -0.35)
		if swimming:
			_turn("DEF-upper_arm.L", Vector3.RIGHT, -swing)
	if male_skeleton != null and male_model != null and male_model.visible:
		_pose_male_bone("CC_Base_R_Upperarm", Vector3.RIGHT, swing)
		_pose_male_bone("CC_Base_R_Forearm", Vector3.RIGHT, 0.35)
		if swimming:
			_pose_male_bone("CC_Base_L_Upperarm", Vector3.RIGHT, -swing)

# Bounds in target space, including skin bind matrices (also works headless).
func _skinned_model_bounds(target: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if rig == null or mesh.skin == null:
			continue
		var palettes: Array[Transform3D] = []
		var to_target := target.global_transform.affine_inverse() * rig.global_transform
		for i in mesh.skin.get_bind_count():
			var bone := rig.find_bone(mesh.skin.get_bind_name(i))
			if bone < 0:
				bone = mesh.skin.get_bind_bone(i)
			palettes.append(to_target * rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(i))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				for influence in influences:
					var index := vertex * influences + influence
					point += (palettes[bones[index]] * vertices[vertex]) * weights[index]
				if first:
					bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(point)
	return bounds

func _start_mixamo_action(clip: String, speed: float = 1.0) -> void:
	_mixamo_current_clip = ""
	_play_mixamo_clip(clip, speed)
	_mixamo_action_lock = mixamo_anim_player.get_animation(clip).length / speed

# AnimationMixer applies first; contacts and doorway poses must be solved afterwards.
func _apply_mixamo_pose() -> void:
	if mixamo_skeleton == null or not mixamo_model.visible:
		return
	var rig := mixamo_skeleton
	var hip := rig.find_bone("mixamorig_Hips")
	# Full-body standing actions must not stand up a crouched/prone collider.
	if not _dead and not seated and _mixamo_action_lock > 0.0 and (_prone > 0.5 or _crouch > 0.5):
		var base := mixamo_anim_player.get_animation("Prone_Idle" if _prone > 0.5 else "Idle_Crouching")
		var time := fposmod(mixamo_anim_player.current_animation_position,base.length)
		for track in base.get_track_count():
			var name := String(base.track_get_path(track)).get_slice(":",1)
			if not ("Hips" in name or "UpLeg" in name or "Leg" in name or "Foot" in name or "Toe" in name or "Spine" in name):
				continue
			var bone := rig.find_bone(name)
			if base.track_get_type(track) == Animation.TYPE_POSITION_3D and "Hips" in name:
				rig.set_bone_pose_position(bone, base.position_track_interpolate(track, time))
			elif base.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rig.set_bone_pose_rotation(bone, base.rotation_track_interpolate(track, time))
	if seated:
		var position := rig.get_bone_pose_position(hip)
		var desired := rig.to_local(to_global(Vector3(0.0, hip_height(), 0.0)))
		rig.set_bone_pose_position(hip, position.lerp(desired, _seat))
	if vehicle_entry_bend > 0.001:
		var spine := rig.find_bone("mixamorig_Spine1")
		var axis := rig.global_basis.orthonormalized().inverse() * global_basis.x
		var pose := rig.get_bone_global_pose(spine)
		var parent := rig.get_bone_parent(spine)
		var rotation := Basis(Quaternion(axis.normalized(), vehicle_entry_bend * 0.7)) * pose.basis
		rig.set_bone_pose_rotation(spine, (rig.get_bone_global_pose(parent).basis.inverse() * rotation).get_rotation_quaternion())
	if seated:
		for side in ["Left", "Right"]:
			var foot := foot_target
			foot.x += (1.0 if side == "Left" else -1.0) * (vehicle_foot_half_width if vehicle_foot_half_width > 0.0 else 0.12)
			foot.y += ANKLE_HEIGHT
			if side == "Right" and vehicle_mount_swing > 0.0:
				foot += Vector3(-0.5, 0.45, -0.5) * vehicle_mount_swing
			_solve_mixamo_limb(side+"UpLeg", side+"Leg", side+"Foot", foot, Vector3(0,0,1))
			var ankle := rig.find_bone("mixamorig_"+side+"Foot")
			var toe := rig.find_bone("mixamorig_"+side+"ToeBase")
			var toe_target := rig.to_local(to_global(foot+Vector3(0.0,-0.05,0.13)))
			_aim_bone_segment(rig,ankle,toe,toe_target)
		if not use_vehicle_grips:
			var centre := Vector3(0.0, hip_height()+WHEEL_ABOVE_HIP, WHEEL_AHEAD_OF_HIP)
			var turn := -clampf(steering,-1.0,1.0)*0.6
			left_grip_target = centre + Vector3(cos(turn),sin(turn),0.0)*WHEEL_RADIUS
			right_grip_target = centre - Vector3(cos(turn),sin(turn),0.0)*WHEEL_RADIUS
		_pose_vehicle_grips()
	elif get_parent().has_method("is_weapon_equipped") and get_parent().is_weapon_equipped() and _mixamo_action_lock <= 0.0:
		_rotate_mixamo_world("mixamorig_Spine1", Vector3.UP, -0.28)
		_rotate_mixamo_world("mixamorig_Spine2", Vector3.UP, -0.28)
		_rotate_mixamo_world("mixamorig_Head", Vector3.UP, 0.40)
		var weapon: Node3D = get_parent().weapon
		var saved_left := left_grip_target
		var saved_right := right_grip_target
		var fingers := {"Left": Vector3(0,0.1,0.995).normalized(), "Right": Vector3(0,-0.25,0.97).normalized()}
		left_grip_target = to_local(weapon.to_global(weapon.get_meta("grip_left", GRIP_LEFT))-weapon.global_basis*fingers.Left*WRIST_TO_PALM)
		right_grip_target = to_local(weapon.to_global(weapon.get_meta("grip_right", GRIP_RIGHT))-weapon.global_basis*fingers.Right*WRIST_TO_PALM)
		_pose_vehicle_grips()
		for side in ["Left","Right"]:
			_orient_mixamo_hand(side, weapon.global_basis*fingers[side], weapon.global_basis*Vector3(-1 if side=="Left" else 1,0,0))
			_pose_mixamo_fingers(side, GRIP_CURL_RIGHT if side == "Right" else GRIP_CURL_LEFT)
		left_grip_target = saved_left
		right_grip_target = saved_right
	rig.force_update_all_bone_transforms()

func _solve_mixamo_limb(upper_name: String, lower_name: String, tip_name: String, target: Vector3, pole: Vector3) -> void:
	var rig := mixamo_skeleton
	var upper := rig.find_bone("mixamorig_"+upper_name)
	var lower := rig.find_bone("mixamorig_"+lower_name)
	var tip := rig.find_bone("mixamorig_"+tip_name)
	rig.force_update_all_bone_transforms()
	var start := rig.get_bone_global_pose(upper).origin
	var joint := rig.get_bone_global_pose(lower).origin
	var end := rig.get_bone_global_pose(tip).origin
	var goal := rig.to_local(to_global(target))
	var a := start.distance_to(joint)
	var b := joint.distance_to(end)
	var reach := clampf(start.distance_to(goal), absf(a-b)+0.001, a+b-0.001)
	var forward := (goal-start).normalized()
	var hint := rig.global_basis.inverse()*global_basis*pole
	var bend := (hint-forward*hint.dot(forward)).normalized()
	var along := (a*a+reach*reach-b*b)/(2.0*reach)
	var height := sqrt(maxf(0.0,a*a-along*along))
	_aim_bone_segment(rig,upper,lower,start+forward*along+bend*height)
	_aim_bone_segment(rig,lower,tip,start+forward*reach)

func _play_mixamo_locomotion(clip: String, speed: float) -> void:
	var native := float(mixamo_anim_player.get_animation(clip).get_meta("native_speed", 1.0))
	_play_mixamo_clip(clip, clampf(speed/maxf(native,0.1),0.2,5.0))

func _orient_mixamo_hand(side: String, finger_world: Vector3, palm_world: Vector3) -> void:
	var rig := mixamo_skeleton
	var hand := rig.find_bone("mixamorig_"+side+"Hand")
	var middle := rig.find_bone("mixamorig_"+side+"HandMiddle1")
	var thumb := rig.find_bone("mixamorig_"+side+"HandThumb1")
	if mini(hand,mini(middle,thumb)) < 0:
		return
	var rest := rig.get_bone_global_rest(hand)
	var finger := (rig.get_bone_global_rest(middle).origin-rest.origin).normalized()
	var across := rig.get_bone_global_rest(thumb).origin-rest.origin
	across = (across-finger*across.dot(finger)).normalized()
	var local_finger := rest.basis.inverse()*finger
	var local_palm := rest.basis.inverse()*finger.cross(across)*(1.0 if side=="Left" else -1.0)
	var local_frame := Basis(local_finger,local_palm,local_finger.cross(local_palm))
	var inverse := rig.global_basis.orthonormalized().inverse()
	var direction := (inverse*finger_world).normalized()
	var palm := inverse*palm_world
	palm = (palm-direction*palm.dot(direction)).normalized()
	var target := Basis(direction,palm,direction.cross(palm))
	var parent := rig.get_bone_parent(hand)
	rig.set_bone_pose_rotation(hand,(rig.get_bone_global_pose(parent).basis.orthonormalized().inverse()*target*local_frame.inverse()).get_rotation_quaternion())

func _pose_mixamo_local(bone_name: String, axis: Vector3, angle: float) -> void:
	if mixamo_skeleton == null:
		return
	var index := mixamo_skeleton.find_bone(bone_name)
	if index < 0:
		return
	var rest_quat := mixamo_skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	mixamo_skeleton.set_bone_pose_rotation(index, rest_quat * Quaternion(axis, angle))

func _pose_mixamo_fingers(side: String, curl: float) -> void:
	if mixamo_skeleton == null:
		return
	var prefix := "mixamorig_" + side + "Hand"
	var sign_val := 1.0 if side == "Left" else -1.0
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		var finger_curl := curl
		if side == "Right" and finger == "Index":
			finger_curl = 0.45 # Trigger finger poised on gun trigger
		for joint in ["1", "2", "3"]:
			var joint_angle := finger_curl * (0.85 if joint == "1" else 1.1) * sign_val
			_pose_mixamo_local(prefix + finger + joint, Vector3(0, 0, 1), joint_angle)
	for joint in ["1", "2", "3"]:
		_pose_mixamo_local(prefix + "Thumb" + joint, Vector3(0, 1, 0), curl * 0.5 * sign_val)


func _rotate_mixamo_world(name: String, world_axis: Vector3, angle: float) -> void:
	var rig := mixamo_skeleton
	var bone := rig.find_bone(name)
	rig.force_update_all_bone_transforms()
	var parent := rig.get_bone_parent(bone)
	var parent_basis := rig.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var axis := parent_basis.inverse() * (rig.global_basis.orthonormalized().inverse() * world_axis)
	rig.set_bone_pose_rotation(bone,Quaternion(axis.normalized(),angle)*rig.get_bone_pose_rotation(bone))

## Mixamo's Spine2 is higher on the chest than Rahul's CC Spine02.
func weapon_shoulder_lift() -> float:
	return 0.10 if mixamo_model != null and mixamo_model.visible else 0.26

func weapon_prone_reach() -> float:
	return 0.38 if mixamo_model != null and mixamo_model.visible else 0.50
