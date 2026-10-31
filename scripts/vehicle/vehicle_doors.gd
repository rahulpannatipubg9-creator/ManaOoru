extends Node3D
## Driver-door geometry is removed from the closed body and reparented to a
## hinge, preserving each original surface's textures, UVs, normals and paint.
var fraction := 0.0
var style := "hinged"
var pivot: Node3D
var _side := 1.0
var triangle_count := 0
var _work: Array
var _to_car := Transform3D.IDENTITY
func build(car: PhysicsBody3D, seat: Vector3) -> void:
 name = "DriverDoorRig"
 car.add_child(self)
 _side = 1.0 if seat.x >= 0 else -1.0
 var width: float = float(car.get("entry_half_width")) if car.get("entry_half_width") != null else 0.0
 if width <= 0:
  var collision := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
  width = collision.shape.size.x*.5 if collision and collision.shape is BoxShape3D else .95
 var id := str(car.get("vehicle_id")) if car.get("vehicle_id") != null else car.scene_file_path
 if "aventador" in id or "diablo" in id:
  style = "scissor"
 elif "bmw_i8" in id:
  style = "butterfly"
 pivot = Node3D.new()
 pivot.name = "DriverDoorHinge"
 pivot.position = Vector3(width * _side, maxf(.3, seat.y-.1), seat.z+.62)
 add_child(pivot)
 var chassis := car.get_node_or_null("Chassis")
 if chassis == null:
  return
 for node in chassis.find_children("*", "MeshInstance3D", true, false):
  var source := node as MeshInstance3D
  if source.mesh == null:
   continue
  var to_car := car.global_transform.affine_inverse() * source.global_transform
  var body_mesh := ArrayMesh.new()
  var door_mesh := ArrayMesh.new()
  for surface in source.mesh.get_surface_count():
   if source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
    continue
   var arrays := source.mesh.surface_get_arrays(surface)
   var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
   var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
   if indices.is_empty():
    for i in vertices.size():indices.append(i)
   var body_indices := PackedInt32Array()
   var door_indices := PackedInt32Array()
   _work = arrays.duplicate()
   _to_car = to_car
   var planes := [[0,width*.65,_side>0], [2,seat.z-.6,true], [2,seat.z+.62,false], [1,maxf(.18,seat.y-.32),true], [1,seat.y+.86,false]]
   if _side<0:planes[0][1]=-width*.65
   for index in range(0,indices.size()-2,3):
    var polygon: Array[int] = [indices[index],indices[index+1],indices[index+2]]
    var rejected := false
    var fully_inside := true
    for plane: Array in planes:
     var inside_count := 0
     for vertex in polygon:
      var coordinate: float = (to_car * vertices[vertex])[int(plane[0])]
      if coordinate >= float(plane[1]) if bool(plane[2]) else coordinate <= float(plane[1]):
       inside_count += 1
     if inside_count == 0:
      rejected = true
      break
     if inside_count != 3:fully_inside = false
    if rejected:
     body_indices.append_array(PackedInt32Array(polygon))
     continue
    if fully_inside:
     door_indices.append_array(PackedInt32Array(polygon))
     continue
    # Peel away the exterior of each plane; only the remaining inside polygon
    # belongs to the door. Boundary vertices are interpolated exactly, avoiding
    # the long spikes created by selecting whole triangles by their centres.
    for plane: Array in planes:
     if polygon.is_empty():break
     var split := _clip_polygon(polygon,int(plane[0]),float(plane[1]),bool(plane[2]))
     body_indices.append_array(_fan_indices(split[1]))
     polygon.assign(split[0])
    door_indices.append_array(_fan_indices(polygon))
   arrays = _work
   var material := source.get_active_material(surface)
   if not body_indices.is_empty():
    var body_arrays := arrays.duplicate()
    body_arrays[Mesh.ARRAY_INDEX] = body_indices
    body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,body_arrays)
    body_mesh.surface_set_material(body_mesh.get_surface_count()-1,material)
   if not door_indices.is_empty():
    var door_arrays := arrays.duplicate()
    door_arrays[Mesh.ARRAY_INDEX] = door_indices
    door_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,door_arrays)
    var panel_material := material
    if material is StandardMaterial3D:
     panel_material = material.duplicate()
     panel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    door_mesh.surface_set_material(door_mesh.get_surface_count()-1,panel_material)
    triangle_count += door_indices.size()/3
  if door_mesh.get_surface_count()>0:
   source.mesh = body_mesh
   # Material overrides refer to old surface indices; rebuilt surfaces retain
   # their active materials directly, including vehicle-specific paint.
   for i in source.get_surface_override_material_count():source.set_surface_override_material(i,null)
   var panel := MeshInstance3D.new()
   panel.name = "DriverDoorPanel"
   panel.mesh = door_mesh
   panel.transform = pivot.transform.affine_inverse() * to_car
   panel.visibility_range_end = source.visibility_range_end
   pivot.add_child(panel)
func set_fraction(value: float) -> void:
 fraction = clampf(value,0,1)
 var weight := smoothstep(0.0,1.0,fraction)
 if pivot == null:return
 if style == "scissor":pivot.rotation = Vector3(weight*1.05, -_side*weight*.12,0)
 elif style == "butterfly":pivot.rotation = Vector3(weight*.7,-_side*weight*.65,_side*weight*.35)
 else:pivot.rotation = Vector3(0,-_side*weight*1.05,0)

func _fan_indices(polygon: Array) -> PackedInt32Array:
 var result := PackedInt32Array()
 for i in range(1,polygon.size()-1):
  result.append(polygon[0]);result.append(polygon[i]);result.append(polygon[i+1])
 return result

func _clip_polygon(polygon: Array[int], axis: int, boundary: float, greater: bool) -> Array:
 var inside: Array[int] = []
 var outside: Array[int] = []
 var positions: PackedVector3Array = _work[Mesh.ARRAY_VERTEX]
 for edge in polygon.size():
  var a := polygon[edge]
  var b := polygon[(edge+1)%polygon.size()]
  var da: float = (_to_car * positions[a])[axis] - boundary
  var db: float = (_to_car * positions[b])[axis] - boundary
  var a_inside := da >= -0.000001 if greater else da <= 0.000001
  var b_inside := db >= -0.000001 if greater else db <= 0.000001
  if a_inside:inside.append(a)
  else:outside.append(a)
  if a_inside != b_inside:
   var weight := clampf(da/(da-db),0.0,1.0)
   var added := _interpolate_vertex(a,b,weight)
   inside.append(added);outside.append(added)
 return [inside,outside]

func _interpolate_vertex(a:int,b:int,t:float)->int:
 var positions: PackedVector3Array = _work[Mesh.ARRAY_VERTEX]
 var added := positions.size()
 positions.append(positions[a].lerp(positions[b],t));_work[Mesh.ARRAY_VERTEX]=positions
 for slot in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR]:
  if _work[slot]==null:continue
  var values = _work[slot]
  if values.is_empty():continue
  var value = values[a].lerp(values[b],t)
  if slot==Mesh.ARRAY_NORMAL:value=value.normalized()
  values.append(value);_work[slot]=values
 if _work[Mesh.ARRAY_TANGENT]!=null:
  var tangents:PackedFloat32Array=_work[Mesh.ARRAY_TANGENT]
  if not tangents.is_empty():
   for component in 4:tangents.append(lerpf(tangents[a*4+component],tangents[b*4+component],t))
   _work[Mesh.ARRAY_TANGENT]=tangents
 return added
