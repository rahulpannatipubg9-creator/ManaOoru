extends SceneTree
const OUT = 'res://outputs/animation_audit/'
func _init(): call_deferred('run')
func run():
 var person=load('res://scenes/player/person.tscn').instantiate()
 root.add_child(person)
 await process_frame
 person.set_physics_process(false)
 var v=person.get_node('TestCharacter')
 v.set_process(false)
 var m=v.mixamo_model
 var a=v.mixamo_anim_player
 a.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var sk=m.find_children('*','Skeleton3D',true,false)[0]
 var rows=[]
 var failures=0
 var frames_checked=0
 for clip in a.get_animation_list():
  var anim=a.get_animation(clip)
  var row={'clip':clip,'duration':anim.length,'tracks':anim.get_track_count(),'loop':anim.loop_mode,'bad_paths':[],'nonfinite':false}
  for t in anim.get_track_count():
   var path=String(anim.track_get_path(t))
   if ':' in path and sk.find_bone(path.get_slice(':',1))<0: row.bad_paths.append(path)
  a.play(clip,0)
  for frame in int(ceil(anim.length*30.0))+1:
   a.seek(minf(float(frame)/30.0,anim.length-0.0001),true)
   sk.force_update_all_bone_transforms()
   frames_checked+=1
   for bone in sk.get_bone_count():
    var pose=sk.get_bone_global_pose(bone)
    if not pose.origin.is_finite() or not pose.basis.is_finite():row.nonfinite=true
  var centers=[];var extents=[];var soles=[];var hips=[];var heads=[]
  var first_pose=[];var last_pose=[]
  for i in 13:
   var time=anim.length*float(i)/12.0
   a.seek(minf(time,anim.length-0.0001),true)
   sk.force_update_all_bone_transforms()
   var b=m.transform*v._skinned_model_bounds(m)
   centers.append(b.get_center());extents.append(b.size);soles.append(b.position.y)
   hips.append(v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_Hips')).origin)))
   heads.append(v.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_Head')).origin)))
   for bone in sk.get_bone_count():
    var p=sk.get_bone_global_pose(bone)
    if not p.origin.is_finite() or not p.basis.is_finite(): row.nonfinite=true
    if i==0:first_pose.append(p)
    if i==12:last_pose.append(p)
  var max_jump=0.0;var loop_angle=0.0;var min_y=100.0;var max_size=0.0;var hip_travel=0.0
  for i in 13:
   min_y=minf(min_y,soles[i]);max_size=maxf(max_size,extents[i].length())
   hip_travel=maxf(hip_travel,Vector2(hips[i].x-hips[0].x,hips[i].z-hips[0].z).length())
   if i>0:max_jump=maxf(max_jump,centers[i].distance_to(centers[i-1]))
  for b in sk.get_bone_count():loop_angle=maxf(loop_angle,first_pose[b].basis.get_rotation_quaternion().angle_to(last_pose[b].basis.get_rotation_quaternion()))
  if row.nonfinite or not row.bad_paths.is_empty() or max_size>3.5 or min_y < -0.025 or hip_travel > 0.29 or (anim.loop_mode!=Animation.LOOP_NONE and rad_to_deg(loop_angle)>2.0):
   failures+=1
   push_error('Animation integrity failed: '+clip)
  row['min_sole_m']=min_y;row['max_extent_m']=max_size;row['hip_horizontal_travel_m']=hip_travel;row['max_sample_center_step_m']=max_jump;row['loop_max_bone_angle_deg']=rad_to_deg(loop_angle)
  row['sole_samples']=soles;row['start_hip']=str(hips[0]);row['end_hip']=str(hips[12]);row['mid_size']=str(extents[6]);row['mid_head']=str(heads[6]);rows.append(row)
  print(clip,' size=',snapped(max_size,.01),' floor=',snapped(min_y,.01),' drift=',snapped(hip_travel,.01),' loopdeg=',snapped(rad_to_deg(loop_angle),1))
 var blend_samples=0
 var names=a.get_animation_list()
 for i in range(1,names.size()):
  a.play(names[i-1],0)
  a.seek(a.get_animation(names[i-1]).length*.8,true)
  a.play(names[i],.15)
  for step in 4:
   a.advance(.05)
   sk.force_update_all_bone_transforms()
   var box=m.transform*v._skinned_model_bounds(m)
   blend_samples+=1
   if not box.position.is_finite() or not box.size.is_finite() or box.size.length()>3.5:
    failures+=1
    push_error('Unsafe animation blend: '+names[i-1]+' -> '+names[i])
 print('Blend samples checked: ',blend_samples)
 var f=FileAccess.open(OUT+'after.json',FileAccess.WRITE);f.store_string(JSON.stringify(rows,'\t'))
 if rows.size()!=76:failures+=1
 print('Mixamo library audit: ',rows.size(),' clips, ',frames_checked,' full-rate bone frames, ',rows.size()*13,' skinned samples, ',failures,' failed')
 person.queue_free()
 await process_frame
 quit(1 if failures else 0)
