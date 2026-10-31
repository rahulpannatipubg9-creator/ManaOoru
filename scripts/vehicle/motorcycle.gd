extends "res://scripts/vehicle/rigid_vehicle.gd"
## Motorcycle with two visible wheels and paired centre-line suspension probes.
## Balance assistance keeps low-speed play usable; lean follows lateral acceleration.
@export var rider_foot_half_width := 0.24
var _bike_body: Node3D
var _handlebars: Node3D
var _lean_target := 0.0
func _ready() -> void:
 var model := get_node("BikeModel")
 _bike_body = model.find_child("BikeBody", true, false)
 _bike_body.reparent(get_node("Chassis"), false)
 for pair in [["FrontWheelMesh", "FrontLeftWheel"], ["RearWheelMesh", "RearLeftWheel"]]:
  var visual := model.find_child(pair[0], true, false) as Node3D
  visual.reparent(get_node(pair[1]), false)
  visual.position.x = 0.025
 _handlebars = model.find_child("Handlebars", true, false)
 if _handlebars:
  _handlebars.reparent(self, false)
  _handlebars.position = Vector3(0, .75, .35)
 model.queue_free()
 freeze = not driving_enabled
 super._ready()
func set_driving_enabled(value: bool) -> void:
 super.set_driving_enabled(value)
 if value:
  freeze = false
  sleeping = false
 else:
  # Parked on its stand; wake and release the stand when mounting.
  freeze = true
func _physics_process(delta: float) -> void:
 var saved_touch := touch_move_input
 var saved_keyboard := keyboard_input_enabled
 var command := touch_move_input if touch_move_input.length_squared() > 0.0 else resolve_keyboard_input() if keyboard_input_enabled else Vector2.ZERO
 # A Bullet has no reverse gear: S brakes while rolling, then holds the bike.
 if command.y > 0.0 and current_speed < 0.5:
  command.y = 0.0
 touch_move_input = command
 keyboard_input_enabled = false
 super._physics_process(delta)
 touch_move_input = saved_touch
 keyboard_input_enabled = saved_keyboard
 if freeze or sleeping:
  return
 var forward := global_basis.z
 var target_lean := clampf(atan(current_speed * current_speed * tan(_steer) / (1.39 * _gravity)), -.48, .48) if driving_enabled else 0.0
 # Balanced physical chassis: rider, body and wheels bank together.
 _lean_target = move_toward(_lean_target, target_lean, delta * 0.9)
 var target_up := Vector3.UP.rotated(forward, -_lean_target)
 # Tune balance against roll inertia, not total mass. Excess angular damping
 # in an explicit torque controller reverses roll velocity every physics tick.
 var frequency := 11.0
 var error := global_basis.y.cross(target_up).dot(forward)
 var rate := angular_velocity.dot(forward)
 var desired_acceleration := frequency * frequency * error - 2.0 * frequency * rate
 var acceleration := desired_acceleration / (1.0 + 2.0 * frequency * delta + frequency * frequency * delta * delta)
 apply_torque(forward * inertia.z * acceleration)
 if _handlebars:
  _handlebars.rotation.y = _steer
func entry_door_position(side: float) -> Vector3:
 return global_transform * Vector3(side * .65, .1, seat_hip.z)

func _lateral_stop_mass(contact: Vector3, direction: Vector3) -> float:
 # Four near-centreline probes share the same roll/yaw response. Limiting each
 # by a quarter of chassis mass ignores that response and overshoots sideways.
 var lever := contact - (global_transform * center_of_mass)
 var angular := global_basis.inverse() * lever.cross(direction)
 var inverse_mass := 1.0 / mass
 inverse_mass += angular.x * angular.x / inertia.x
 inverse_mass += angular.y * angular.y / inertia.y
 inverse_mass += angular.z * angular.z / inertia.z
 return 0.125 / inverse_mass
