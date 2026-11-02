extends SceneTree
var failures := 0
var camera: Camera3D
var capture_index := 0
func _init() -> void:
 run.call_deferred()
func run() -> void:
 root.size=Vector2i(800,600)
 Engine.time_scale=2.0
 var environment:=WorldEnvironment.new()
 environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color(.12,.14,.17)
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color.WHITE
 environment.environment.ambient_light_energy=.8
 root.add_child(environment)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-45,-35,0)
 root.add_child(sun)
 camera=Camera3D.new();root.add_child(camera);camera.fov=48
 DirAccess.make_dir_recursive_absolute("res://outputs/vehicle_rigs/entry")
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
  if not OS.get_cmdline_user_args().is_empty() and not path.contains(OS.get_cmdline_user_args()[0]):
   continue
  var car: PhysicsBody3D=load(path).instantiate()
  root.add_child(car);car.freeze=true;person.global_position=Vector3(2.5,0,0)
  camera.position=Vector3(5,2.4,4)
  camera.look_at(Vector3(0,.7,0));camera.make_current()
  entry.begin_enter(person,car)
  var saw_open:=false
  var saw_bend:=false
  var saw_swing:=false
  for frame in 400:
   await physics_frame
   if frame%15==0:
    capture(car,entry,"enter",frame)
   if entry._door_rig:
    saw_open=saw_open or entry._door_rig.fraction>.8
   var actor:=person.get_node("TestCharacter")
   saw_bend=saw_bend or actor.vehicle_entry_bend>.2
   saw_swing=saw_swing or actor.vehicle_mount_swing>.5
   if entry.is_seated():break
  for settle_frame in 30:await physics_frame
  capture(car,entry,"seated",0)
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
   if frame%15==0:
    capture(car,entry,"exit",frame)
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

func capture(car:Node,entry:Node,direction:String,frame:int)->void:
 camera.make_current()
 RenderingServer.force_draw(false)
 var name:=car.name
 root.get_texture().get_image().save_png("res://outputs/vehicle_rigs/entry/%s_%s_%03d.png"%[name,direction,frame])
 print("ANIM_CAPTURE ",name," ",direction," ",frame," phase=",entry.phase)
