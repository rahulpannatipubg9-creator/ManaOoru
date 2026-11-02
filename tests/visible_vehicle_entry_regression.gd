extends SceneTree
var failures := 0
func _init() -> void:
 run.call_deferred()
func run() -> void:
 var floor := StaticBody3D.new()
 var col := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size=Vector3(100,1,100)
 col.shape=shape;col.position.y=-.5;floor.add_child(col);root.add_child(floor)
 var person: CharacterBody3D=load("res://scenes/player/person.tscn").instantiate()
 root.add_child(person);person.set_movement_enabled(false);person.set_collision_enabled(false)
 var entry: Node=load("res://scripts/vehicle/vehicle_entry.gd").new()
 root.add_child(entry)
 for path in ["res://scenes/vehicles/porsche_911.tscn","res://scenes/vehicles/imported/bmw_i8.tscn","res://scenes/vehicles/royal_enfield_bullet.tscn"]:
  var car: PhysicsBody3D=load(path).instantiate()
  root.add_child(car);car.freeze=true;person.global_position=Vector3(2.5,0,0)
  entry.begin_enter(person,car)
  var saw_open:=false
  var saw_bend:=false
  var saw_swing:=false
  for frame in 400:
   await physics_frame
   if entry._door_rig:
    saw_open=saw_open or entry._door_rig.fraction>.8
   var actor:=person.get_node("TestCharacter")
   saw_bend=saw_bend or actor.vehicle_entry_bend>.2
   saw_swing=saw_swing or actor.vehicle_mount_swing>.5
   if entry.is_seated():break
  for settle_frame in 30:await physics_frame
  if path.contains("bullet"):
   var actor:=person.get_node("TestCharacter")
   var is_mixamo:bool=actor.mixamo_model != null and actor.mixamo_model.visible
   var skeleton:Skeleton3D=actor.mixamo_skeleton if is_mixamo else actor.male_skeleton
   for side in ["L","R"]:
    var prefix:String="mixamorig_"+("Left" if side=="L" else "Right")
    var bone:=skeleton.find_bone(prefix+"Hand" if is_mixamo else "CC_Base_%s_Hand"%side)
    if bone>=0:
     var wrist:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
     var target:Vector3=car.global_transform*(car.left_hand_grip if side=="L" else car.right_hand_grip)
     var upper:=skeleton.find_bone(prefix+"Arm" if is_mixamo else "CC_Base_%s_Upperarm"%side)
     var lower:=skeleton.find_bone(prefix+"ForeArm" if is_mixamo else "CC_Base_%s_Forearm"%side)
     var shoulder:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(upper).origin
     var elbow:Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(lower).origin
     print("BIKE_WRIST ",side," gap=",wrist.distance_to(target)," wrist=",car.to_local(wrist)," target=",car.to_local(target)," shoulder=",car.to_local(shoulder)," lengths=",shoulder.distance_to(elbow),"/",elbow.distance_to(wrist)," enabled=",actor.use_vehicle_grips," seat=",actor._seat)
     check(wrist.distance_to(target)<.05,"Bike rider hands reach the handlebar grips")
  check(entry.is_seated(),path+": reaches seat")
  check(saw_bend,path+": bends while entering")
  if path.contains("bullet"):
   check(entry._door_rig==null and saw_swing,"Bike must mount with a leg swing, without a car door")
  else:
   check(saw_open,path+": visible door opens")
   check(entry._door_rig.triangle_count>20,path+": actual door geometry isolated")
   check(entry._door_rig.fraction==0,path+": door closes after sitting")
  entry.begin_exit(car.global_position+Vector3(2,0,0))
  var exit_bend:=false
  for frame in 400:
   await physics_frame
   exit_bend=exit_bend or person.get_node("TestCharacter").vehicle_entry_bend>.2
   if entry.phase==entry.Phase.IDLE:break
  check(exit_bend and entry.phase==entry.Phase.IDLE,path+": bends and finishes outside")
  check(person.visible,path+": driver remains visible")
  print("ENTRY_CHECK ",path)
  car.queue_free();await process_frame
 print("PASS visible car and bike entry regression" if failures==0 else "FAIL visible car and bike entry regression")
 quit(0 if failures==0 else 1)
func check(ok:bool,message:String)->void:
 if not ok:failures+=1;push_error(message)
