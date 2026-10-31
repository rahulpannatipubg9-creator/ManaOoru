extends SceneTree
var failures := 0
var checks := 0
var worst_hand := 0.0
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks+=1
 if not ok:
  failures+=1
  push_error(message)
func run() -> void:
 var p=load('res://scenes/player/person.tscn').instantiate()
 root.add_child(p)
 await process_frame
 p.set_physics_process(false);p.set_process(false)
 var v=p.get_node('TestCharacter');v.set_process(false)
 var sk: Skeleton3D=v.mixamo_skeleton
 var a: AnimationPlayer=v.mixamo_anim_player
 a.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 v.seated=true;v._seat=1
 for path in ['res://scenes/vehicles/porsche_911.tscn','res://scenes/vehicles/jeep_compass.tscn','res://scenes/vehicles/rigid_thar.tscn','res://scenes/vehicles/royal_enfield_bullet.tscn']:
  var car=load(path).instantiate();root.add_child(car);car.freeze=true
  var entry=load('res://scripts/vehicle/vehicle_entry.gd').new();root.add_child(entry);entry.person=p;entry.vehicle=car
  p.global_transform=entry.seat_transform(car);entry._follow_seat()
  for time in [0.1,1.0,3.0]:
   a.play('Drive_Seated',0);a.seek(time,true)
   var hip=p.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_Hips')).origin))
   check(hip.distance_to(Vector3(0,v.hip_height(),0))<.01,path+': pelvis on seat')
   for side in ['Left','Right']:
    var hand=p.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_'+side+'Hand')).origin))
    var foot=p.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_'+side+'Foot')).origin))
    var goal:Vector3=v.foot_target+Vector3((1 if side=='Left' else -1)*(v.vehicle_foot_half_width if v.vehicle_foot_half_width>0 else .12),.07,0)
    var hand_gap:float=hand.distance_to(v.left_grip_target if side=='Left' else v.right_grip_target)
    check(hand_gap<.03,path+': '+side+' hand contact '+str(hand_gap))
    check(foot.distance_to(goal)<.03,path+': '+side+' foot reaches pedal/peg')
    var toe=p.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_'+side+'ToeBase')).origin))
    check(toe.y>foot.y-.09 and toe.z>foot.z+.04,path+': '+side+' foot points forward on pedal/peg')
  print('SEAT CONTACT CHECK ',path)
  entry.queue_free();car.queue_free();await process_frame
 v.seated=false;v._mixamo_action_lock=0;p.global_transform=Transform3D.IDENTITY;p.combat_mode=true;p.set_weapon_equipped(true);p.camera_pivot.rotation.y=PI
 for weapon in [0,1,2]:
  p.set_weapon_model(weapon);p.weapon_draw_time=0
  for pose in [['Rifle_Aiming_Idle',false,false],['Crouch_Walking',true,false],['Prone_Idle',false,true],['Walk_With_Rifle',false,false],['Firing_Rifle',false,false],['Firing_Rifle_while_walking',false,false],['Walk_Left_with_gun',false,false],['Walk_Right_with_gun',false,false],['Rifle_Jump',false,false],['Prone_Firing_Rifle',false,true],['Prone_Forward',false,true],['Moving_Backward_In_Prone_Position',false,true],['Sprint_Backward',false,false]]:
   p.crouching=pose[1];p.prone=pose[2]
   for aim in [0.0,1.0]:
    p._aim_blend=aim
    for time in [.1,.5,.8]:
     a.play(pose[0],0);a.seek(time,true);p._update_weapon_presentation(0);a.seek(time,true)
     for side in ['Left','Right']:
      var hand=sk.to_global(sk.get_bone_global_pose(sk.find_bone('mixamorig_'+side+'Hand')).origin)
      var fingers=Vector3(0,.1,.995).normalized() if side=='Left' else Vector3(0,-.25,.97).normalized()
      var target=p.weapon.to_global(p.weapon.get_meta('grip_left' if side=='Left' else 'grip_right',v.GRIP_LEFT if side=='Left' else v.GRIP_RIGHT))-p.weapon.global_basis*fingers*v.WRIST_TO_PALM
      var gap:float=hand.distance_to(target);worst_hand=maxf(worst_hand,gap)
      check(gap<.03,'rifle '+str(weapon)+' '+str(pose[0])+' '+side+' aim='+str(aim)+' t='+str(time)+' gap='+str(gap))
 print('Mixamo contacts: ',checks,' checks, ',failures,' failed; worst rifle wrist error=',worst_hand,'m')
 p.queue_free();await process_frame
 quit(1 if failures else 0)
