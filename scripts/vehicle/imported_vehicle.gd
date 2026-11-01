extends "res://scripts/vehicle/rigid_vehicle.gd"
## Uses the same suspension, tyre forces, collision and entry contract as the
## Thar/911/Compass, with a measured, model-specific body and four wheel meshes.
@export var vehicle_id := ""
@export var keep_placement_spawn := true
var _extra_wheels: Array[Node3D] = []
var _extra_rest_heights: Array[float] = []
var _glass_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
 var model := get_node("Model")
 var body := model.find_child("Body", true, false) as Node3D
 assert(body != null, "%s: missing body assembly" % vehicle_id)
 body.reparent(get_node("Chassis"), false)
 var assembly_names := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
 for index in 4:
  var assembly := model.find_child(assembly_names[index], true, false) as Node3D
  assert(assembly != null, "%s: missing wheel assembly" % vehicle_id)
  assembly.reparent(get_node(WHEEL_NAMES[index] + "Wheel"), false)
 for candidate in model.find_children("ExtraWheel*", "Node3D", true, false):
  if candidate is MeshInstance3D:
   continue
  var wheel := candidate as Node3D
  wheel.reparent(self, false)
  _extra_wheels.append(wheel)
  _extra_rest_heights.append(wheel.position.y)
 model.queue_free()
 super._ready()
 _apply_vehicle_finish()
 _apply_wheel_finish()
 _apply_glass_finish()

func entry_door_position(side: float) -> Vector3:
 return global_transform * Vector3((entry_half_width + 0.35) * side, 0.1, seat_hip.z)

func _update_visuals() -> void:
 super._update_visuals()
 var pivot := get_node_or_null("CameraPivot")
 var is_fpp: bool = driving_enabled and pivot != null and pivot.has_method("is_first_person") and bool(pivot.is_first_person())
 for mat in _glass_materials:
  mat.albedo_color.a = 0.0 if is_fpp else 0.18
 for index in _extra_wheels.size():
  var wheel := _extra_wheels[index]
  wheel.rotation = Vector3(_spin[2], 0.0, PI * 0.5)
  wheel.position.y = _extra_rest_heights[index] + wheels[2].position.y - wheel_radius

## Distant districts have no terrain collider until their stream sector loads.
## Hold only unoccupied out-of-range vehicles; nearby cars remain live bodies.
var _stream_held := true
var _stream_check := 0.0

func _physics_process(delta: float) -> void:
 if has_meta("placement_spawn"):
  _stream_check -= delta
  if _stream_check <= 0.0:
   _stream_check = 0.25
   var game := get_tree().current_scene
   if game == null or not game.has_method("_nearest_vehicle"):
    game = get_parent().get_parent().get_parent()
   var person := game.get_node_or_null("Player") as Node3D
   if person != null:
    var focus: Node3D = person
    if game.get("control_state") == 2 and game.get("active_vehicle") != null:
     focus = game.active_vehicle
    var far := global_position.distance_to(focus.global_position) > 100.0
    if far and not driving_enabled:
     freeze = true
     _stream_held = true
    elif _stream_held:
     var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 50.0, 1, [get_rid()])
     if _find_supported_parking():
      settle_on_ground()
      freeze = false
      _stream_held = false
  if _stream_held:
   return
 super._physics_process(delta)

func _find_supported_parking() -> bool:
 var space := get_world_3d().direct_space_state
 var collider := get_node("CollisionShape3D") as CollisionShape3D
 var origin := respawn_position
 for radius in [0.0, 5.0, 10.0, 18.0, 28.0]:
  for angle_index in (1 if radius == 0.0 else 12):
   var angle := TAU * float(angle_index) / 12.0
   var candidate := origin + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
   var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 8.0, candidate + Vector3.DOWN * 30.0, 1, [get_rid()])
   var floor_hit := space.intersect_ray(ray)
   if floor_hit.is_empty() or (floor_hit.normal as Vector3).dot(Vector3.UP) < .95:
    continue
   candidate.y = (floor_hit.position as Vector3).y + .025
   var query := PhysicsShapeQueryParameters3D.new()
   query.shape = collider.shape
   query.transform = Transform3D(global_basis, candidate) * collider.transform
   query.exclude = [get_rid()]
   if not space.intersect_shape(query, 1).is_empty():
    continue
   var supported := true
   for mount: Vector3 in _mounts:
    var at := Transform3D(global_basis, candidate) * Vector3(mount.x, 0, mount.z)
    var wheel_ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * .35, 1, [get_rid()])
    var hit := space.intersect_ray(wheel_ray)
    if hit.is_empty() or absf((hit.position as Vector3).y - candidate.y) > .25:
     supported = false
     break
   if supported:
    global_position = candidate
    return true
 return false

## Apply paint only to each model's identified exterior material slots. Texture
## albedo remains on liveries/badges and separate wheel materials are untouched.
func _apply_vehicle_finish() -> void:
 var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/vehicle_finishes.json"))
 if not catalog.has(vehicle_id):
  return
 var finish: Dictionary = catalog[vehicle_id]
 for child in get_node("Chassis").find_children("*", "MeshInstance3D", true, false):
  var instance := child as MeshInstance3D
  for surface in instance.mesh.get_surface_count():
   var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
   if source == null:
    continue
   for pattern: String in finish.get("paint_materials", []):
    if source.resource_name == pattern or (pattern.contains("Coloured_Material") and source.resource_name.contains(pattern)):
     var material := source.duplicate() as StandardMaterial3D
     material.albedo_color = Color(str(finish.paint_color))
     material.metallic = 0.0
     material.roughness = 0.26
     material.clearcoat_enabled = true
     material.clearcoat = 0.7
     material.clearcoat_roughness = 0.2
     instance.set_surface_override_material(surface, material)

func _apply_wheel_finish() -> void:
 for wheel: Node3D in wheels:
  for child in wheel.find_children("*", "MeshInstance3D", true, false):
   var instance := child as MeshInstance3D
   for surface in instance.mesh.get_surface_count():
    var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
    if source == null:continue
    var label := source.resource_name.to_lower()
    var color := source.albedo_color
    var placeholder := label.begins_with("wire_") or (maxf(color.r,maxf(color.g,color.b))-minf(color.r,minf(color.g,color.b))>.3 and not "caliper" in label and not "brake" in label and source.albedo_texture==null)
    if not placeholder:continue
    var material := source.duplicate() as StandardMaterial3D
    material.albedo_color=Color(.045,.05,.055)
    material.metallic=.15
    material.roughness=.55
    instance.set_surface_override_material(surface,material)

func _apply_glass_finish() -> void:
 var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/vehicle_finishes.json"))
 var explicit_glass: Array = []
 if catalog.has(vehicle_id) and catalog[vehicle_id].has("glass_materials"):
  explicit_glass = catalog[vehicle_id].glass_materials
 for child in get_node("Chassis").find_children("*", "MeshInstance3D", true, false):
  var instance := child as MeshInstance3D
  if instance.mesh == null:
   continue
  for surface in instance.mesh.get_surface_count():
   var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
   if source == null:
    continue
   var label := source.resource_name
   var label_low := label.to_lower()
   var is_glass := false
   if label in explicit_glass:
    is_glass = true
   elif "glass" in label_low or "window" in label_low or "wind" in label_low or "vitre" in label_low or "parabrisas" in label_low:
    is_glass = true
   elif source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and source.albedo_color.a < 0.95:
    is_glass = true
   if is_glass:
    var glass := StandardMaterial3D.new()
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.albedo_color = Color(0.20, 0.28, 0.35, 0.18)
    glass.metallic = 0.2
    glass.roughness = 0.05
    glass.cull_mode = BaseMaterial3D.CULL_BACK
    glass.clearcoat_enabled = true
    glass.clearcoat = 1.0
    glass.clearcoat_roughness = 0.05
    instance.set_surface_override_material(surface, glass)
    _glass_materials.append(glass)
