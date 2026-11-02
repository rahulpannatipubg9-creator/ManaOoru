extends RefCounted
## Runtime copies: source FBX/GLB clips stay untouched. Physics owns actor travel.
const LOOPS := ["Air_Squat_Bent_Arms", "Arm_Stretching", "Boxing", "Crouch_Walking", "Dodging",
 "Firing_Rifle", "Firing_Rifle_while_walking", "Floating", "Idle_Crouching",
 "Jogging", "Moving_Backward_In_Prone_Position", "Pistol_Kneeling_Idle",
 "Prone_Firing_Rifle", "Prone_Forward", "Prone_Idle", "Rifle_Aiming_Idle",
 "Sitting", "Sprint_Backward", "Strafe", "Swimming", "Walk_Backward", "Walk_Crouching_Right",
 "Walk_Left_with_gun", "Walk_Right_with_gun", "Walk_With_Rifle", "Wheelbarrow_Walk"]

static func prepare(player: AnimationPlayer, rig: Skeleton3D, apply_grounding: bool = true) -> void:
 var library := AnimationLibrary.new()
 var walk_source := player.get_animation("Start_Walking")
 var walk_speed := 0.8
 for track in walk_source.get_track_count():
  if walk_source.track_get_type(track) == Animation.TYPE_POSITION_3D and "Hips" in String(walk_source.track_get_path(track)):
   var start := walk_source.position_track_interpolate(track,1.4)
   var end := walk_source.position_track_interpolate(track,2.6)
   walk_speed = Vector2(end.x-start.x,end.y-start.y).length()*rig.global_basis.z.length()/1.2
 for name in player.get_animation_list():
  var clip: Animation = player.get_animation(name).duplicate(true)
  clip.loop_mode = Animation.LOOP_LINEAR if name in LOOPS else Animation.LOOP_NONE
  for track in clip.get_track_count():
   if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not "Hips" in String(clip.track_get_path(track)):
    continue
   var bone := rig.find_bone("mixamorig_Hips")
   var rest := rig.get_bone_rest(bone).origin
   var start: Vector3 = clip.track_get_key_value(track, 0)
   var end: Vector3 = clip.track_get_key_value(track, clip.track_get_key_count(track)-1)
   clip.set_meta("native_speed", Vector2(end.x-start.x,end.y-start.y).length()*rig.global_basis.z.length()/maxf(clip.length,0.001))
   for key in clip.track_get_key_count(track):
    var value: Vector3 = clip.track_get_key_value(track, key)
    var fraction := clip.track_get_key_time(track, key) / maxf(clip.length, 0.001)
    # The imported armature maps local -Z to world up; X/Y are ground travel.
    value.x = rest.x + clampf(value.x - lerpf(start.x, end.x, fraction), -10.0, 10.0)
    value.y = rest.y + clampf(value.y - lerpf(start.y, end.y, fraction), -10.0, 10.0)
    clip.track_set_key_value(track, key, value)
  if name in LOOPS:
   close_loop(clip)
  library.add_animation(name, clip)
 var walk := slice_clip(library.get_animation("Start_Walking"), 1.4, 2.6)
 walk.loop_mode = Animation.LOOP_LINEAR
 close_loop(walk)
 walk.set_meta("native_speed",walk_speed)
 library.add_animation("Walk_Loop", walk)
 var walk_back := reverse_clip(walk)
 walk_back.loop_mode = Animation.LOOP_LINEAR
 close_loop(walk_back)
 walk_back.set_meta("native_speed",walk_speed)
 library.add_animation("Walk_Backward", walk_back)
 var idle := hold_pose(library.get_animation("Start_Walking"),0.0)
 relax_idle_arms(idle,rig)
 library.add_animation("Idle_Natural",idle)
 library.add_animation("Drive_Seated", hold_pose(library.get_animation("Sitting"),1.0))
 var grounding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/mixamo_grounding.json")) if apply_grounding else {}
 for name in grounding:
  if not library.has_animation(name):
   continue
  var clip := library.get_animation(name)
  for track in clip.get_track_count():
   if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not "Hips" in String(clip.track_get_path(track)):
    continue
   var source: Animation = clip.duplicate(true)
   for sample in grounding[name]:
    var value := source.position_track_interpolate(track,float(sample[0]))
    value.z -= float(sample[1])/rig.global_basis.z.length()
    clip.track_insert_key(track,float(sample[0]),value)
  if clip.loop_mode != Animation.LOOP_NONE:
   close_loop(clip)
 for name in player.get_animation_library_list():
  player.remove_animation_library(name)
 player.add_animation_library("", library)

static func slice_clip(source: Animation, start: float, end: float) -> Animation:
 var clip: Animation = source.duplicate(true)
 clip.length = end - start
 for track in clip.get_track_count():
  while clip.track_get_key_count(track) > 0:
   clip.track_remove_key(track, 0)
  var count := int(ceil(clip.length * 30.0))
  for key in count + 1:
   var time := minf(float(key)/30.0, clip.length)
   var type := source.track_get_type(track)
   if type == Animation.TYPE_POSITION_3D:
    clip.track_insert_key(track, time, source.position_track_interpolate(track, start+time))
   elif type == Animation.TYPE_ROTATION_3D:
    clip.track_insert_key(track, time, source.rotation_track_interpolate(track, start+time))
   elif type == Animation.TYPE_SCALE_3D:
    clip.track_insert_key(track, time, source.scale_track_interpolate(track, start+time))
 return clip

static func reverse_clip(source: Animation) -> Animation:
 var clip: Animation = source.duplicate(true)
 var duration: float = source.length
 for track in clip.get_track_count():
  var keys: Array[Dictionary] = []
  for k in source.track_get_key_count(track):
   var old_t: float = source.track_get_key_time(track, k)
   var val: Variant = source.track_get_key_value(track, k)
   keys.append({"time": duration - old_t, "value": val})
  keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
  while clip.track_get_key_count(track) > 0:
   clip.track_remove_key(track, 0)
  for item in keys:
   clip.track_insert_key(track, item["time"], item["value"])
 return clip

static func close_loop(clip: Animation) -> void:
 # Blend only the tail into the first pose; don't loop a one-shot transition.
 var tail := minf(0.15, clip.length * 0.15)
 for track in clip.get_track_count():
  if clip.track_get_key_count(track) == 0:
   continue
  var first: Variant = clip.track_get_key_value(track, 0)
  for key in clip.track_get_key_count(track):
   var weight := smoothstep(clip.length-tail, clip.length, clip.track_get_key_time(track,key))
   if weight <= 0.0:
    continue
   var value: Variant = clip.track_get_key_value(track,key)
   if value is Quaternion:
    value = value.slerp(first, weight)
   elif value is Vector3:
    value = value.lerp(first, weight)
   clip.track_set_key_value(track,key,value)

static func hold_pose(source: Animation, time: float) -> Animation:
 var idle := slice_clip(source,time,time+0.033333)
 idle.length = 2.5
 idle.loop_mode = Animation.LOOP_LINEAR
 for track in idle.get_track_count():
  var value: Variant = idle.track_get_key_value(track,0)
  while idle.track_get_key_count(track)>0:
   idle.track_remove_key(track,0)
  for key in 9:
   var sample: Variant = value
   if idle.track_get_type(track)==Animation.TYPE_ROTATION_3D and "Spine2" in String(idle.track_get_path(track)):
    sample=value*Quaternion(Vector3.RIGHT,sin(float(key)/8.0*TAU)*0.012)
   idle.track_insert_key(track,float(key)/8.0*idle.length,sample)
 return idle

static func relax_idle_arms(idle: Animation, rig: Skeleton3D) -> void:
 for track in idle.get_track_count():
  var bone := rig.find_bone(String(idle.track_get_path(track)).get_slice(":",1))
  if bone < 0:
   continue
  if idle.track_get_type(track)==Animation.TYPE_ROTATION_3D:
   rig.set_bone_pose_rotation(bone,idle.track_get_key_value(track,0))
  elif idle.track_get_type(track)==Animation.TYPE_POSITION_3D:
   rig.set_bone_pose_position(bone,idle.track_get_key_value(track,0))
 for side in ["Left","Right"]:
  var upper := rig.find_bone("mixamorig_"+side+"Arm")
  var lower := rig.find_bone("mixamorig_"+side+"ForeArm")
  var hand := rig.find_bone("mixamorig_"+side+"Hand")
  rig.force_update_all_bone_transforms()
  var shoulder := rig.get_bone_global_pose(upper).origin
  var elbow := rig.get_bone_global_pose(lower).origin
  var direction := (rig.global_basis.inverse()*Vector3(0.06 if side=="Left" else -0.06,-1.0,0.06)).normalized()
  aim_segment(rig,upper,lower,shoulder+direction*shoulder.distance_to(elbow))
  rig.force_update_all_bone_transforms()
  elbow=rig.get_bone_global_pose(lower).origin
  var wrist := rig.get_bone_global_pose(hand).origin
  direction=(rig.global_basis.inverse()*Vector3(0.03 if side=="Left" else -0.03,-1.0,0.22)).normalized()
  aim_segment(rig,lower,hand,elbow+direction*elbow.distance_to(wrist))
  for track in idle.get_track_count():
   if idle.track_get_type(track)!=Animation.TYPE_ROTATION_3D:
    continue
   var name := String(idle.track_get_path(track)).get_slice(":",1)
   if name in ["mixamorig_"+side+"Arm","mixamorig_"+side+"ForeArm"]:
    var bone := rig.find_bone(name)
    for key in idle.track_get_key_count(track):
     idle.track_set_key_value(track,key,rig.get_bone_pose_rotation(bone))

static func aim_segment(rig: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
 rig.force_update_all_bone_transforms()
 var pose := rig.get_bone_global_pose(bone)
 var current := rig.get_bone_global_pose(child).origin-pose.origin
 var desired := target-pose.origin
 var rotation := Basis(Quaternion(current.normalized(),desired.normalized()))*pose.basis.orthonormalized()
 var parent := rig.get_bone_parent(bone)
 var parent_basis := rig.get_bone_global_pose(parent).basis.orthonormalized() if parent>=0 else Basis.IDENTITY
 rig.set_bone_pose_rotation(bone,(parent_basis.inverse()*rotation).get_rotation_quaternion())
