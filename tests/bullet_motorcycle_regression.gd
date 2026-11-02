extends SceneTree
var failures := 0
func _init() -> void:
 run.call_deferred()
func run() -> void:
 var ground := StaticBody3D.new()
 var col := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(1000,1,1000)
 col.shape = box
 col.position.y = -.5
 ground.add_child(col)
 root.add_child(ground)
 var bike: RigidVehicle = load("res://scenes/vehicles/royal_enfield_bullet.tscn").instantiate()
 root.add_child(bike)
 GameplayControls.blocked = false
 bike.set_input_authority(true)
 for i in 90: await physics_frame
 check(not bike.freeze,"Bullet must not remain frozen")
 check(bike.wheel_contacts.all(func(c):return c),"Bullet tyres must contact ground")
 var start := bike.global_position
 bike.set_touch_move_input(Vector2(0,-1))
 for i in 180: await physics_frame
 print("BULLET speed=",bike.current_speed," travelled=",bike.global_position.distance_to(start)," contacts=",bike.wheel_contacts)
 check(bike.current_speed>3,"Bullet must accelerate beyond 10.8 km/h")
 check(bike.global_position.distance_to(start)>4,"Bullet must translate under throttle")
 check(bike.wheels[0].find_children("*","MeshInstance3D",true,false).size()>1,"Bullet must have its actual front wheel")
 bike.set_touch_move_input(Vector2(.4,-1))
 for i in 60:await physics_frame
 check(bike.global_basis.y.dot(Vector3.UP)>.7,"Bike balance assistance must prevent falling over")
 bike.set_driving_enabled(false)
 for i in 5:await physics_frame
 check(not bike.get_node("EngineAudio").engine_running,"Parked Bullet engine muted")
 print("PASS Bullet motorcycle regression" if failures==0 else "FAIL Bullet motorcycle regression")
 quit(0 if failures==0 else 1)
func check(ok:bool,message:String)->void:
 if not ok:
  failures+=1
  push_error(message)
