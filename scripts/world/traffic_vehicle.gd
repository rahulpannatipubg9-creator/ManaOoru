class_name TrafficVehicle
extends Node3D

const TUK_TUK_SCENE := preload("res://assets/models/tuk_tuk/gdk_tuk_tuk.glb")
const SUV_SCENE := preload("res://assets/models/suv_4x4/suv_4x4_complete.glb")

## Lightweight ambient traffic. It follows map-derived lanes without a rigid
## body, so dozens of cars can run on local/mobile hardware without disturbing
## the player-controlled vehicles.

var route := PackedVector3Array()
## Surface height under the current lane position; route endpoints alone miss terrain relief.
var ground_sampler: Callable
var speed := 7.0
var night_factor := 0.0
var night_active := true
var vehicle_kind := "car"
var body_color := Color("#b6382b")
var signal_positions := PackedVector3Array()
var signal_group := 0
var signal_controller: SignageBuilder
## Simulation is paused outside the active camera neighbourhood.  Routes are
## map-derived and resume seamlessly when the player returns, avoiding townwide
## per-frame work on laptops and phones.
@export var simulation_distance := 650.0
var _segment := 0
var _target_index := 1
var _route_direction := 1
var _distance := 0.0

func _ready() -> void:
	add_to_group("performance_ambient")
	_build_visual()
	if route.size() >= 2:
		position = route[0]
		_ground_on_surface()

func _process(delta: float) -> void:
	if route.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and global_position.distance_squared_to(camera.global_position) > simulation_distance * simulation_distance:
		visible = false
		return
	if night_factor > 0.75 and not night_active:
		visible = false
		return
	visible = true
	if _must_wait_at_signal():
		return
	if vehicle_kind == "scooter" and _scooter_obstructed():
		return
	_distance += speed * lerpf(1.0, 0.68, night_factor) * delta
	while _distance >= _segment_length():
		_distance -= _segment_length()
		_segment = _target_index
		if _segment == route.size() - 1:
			_route_direction = -1
		elif _segment == 0:
			_route_direction = 1
		_target_index = _segment + _route_direction
	var a := route[_segment]
	var b := route[_target_index]
	position = a.lerp(b, _distance / maxf(_segment_length(), 0.01))
	_ground_on_surface()
	var facing := b - a
	facing.y = 0.0
	if facing.length_squared() > 0.001:
		rotation.y = atan2(facing.x, facing.z)

func _ground_on_surface() -> void:
	if ground_sampler.is_valid():
		position.y = float(ground_sampler.call(Vector2(position.x, position.z)))

func _segment_length() -> float:
	return route[_segment].distance_to(route[_target_index])

func _must_wait_at_signal() -> bool:
	if signal_controller == null or signal_positions.is_empty():
		return false
	if signal_controller.traffic_phase_for_group(signal_group) != "red":
		return false
	var target := route[_target_index]
	for signal_position in signal_positions:
		# Only hold the vehicle when it is approaching a mapped junction, not
		# after it has passed it or when the junction belongs to another road.
		var distance := position.distance_to(signal_position)
		if distance > 9.0:
			continue
		var toward_signal := signal_position - position
		var direction := target - position
		toward_signal.y = 0.0
		direction.y = 0.0
		if direction.length_squared() > 0.01 and toward_signal.dot(direction) > 0.0:
			return true
	return false

func _build_visual() -> void:
	if vehicle_kind == "scooter":
		_build_scooter()
		return
	if vehicle_kind == "tuk_tuk":
		var tuk_tuk := TUK_TUK_SCENE.instantiate() as Node3D
		tuk_tuk.name = "TukTukModel"
		# The converted GLB already imports in metres.  Its mesh is centred on
		# the source origin, so lift it by half its 2.89m height to rest wheels on
		# the mapped road instead of shrinking it to a centimetre.
		tuk_tuk.position.y = 1.40
		add_child(tuk_tuk)
		return
	if vehicle_kind == "suv":
		var suv := SUV_SCENE.instantiate() as Node3D
		suv.name = "SUV4x4Model"
		suv.position.y = 0.02
		add_child(suv)
		return
	var length := 4.1 if vehicle_kind == "car" else 2.8
	var width := 1.75 if vehicle_kind == "car" else 1.45
	if vehicle_kind == "bus":
		length = 8.5
		width = 2.25
	elif vehicle_kind == "municipal":
		length = 6.2
		width = 2.05
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.75, length)
	body.mesh = mesh
	body.position.y = 0.55
	body.material_override = _material(body_color)
	add_child(body)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(width * 0.86, 0.55, length * 0.48)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 1.08, -length * 0.08)
	cabin.material_override = _material(Color("#273a48"))
	add_child(cabin)
	for x in [-width * 0.42, width * 0.42]:
		for z in [-length * 0.31, length * 0.31]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.30
			wheel_mesh.bottom_radius = 0.30
			wheel_mesh.height = 0.18
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(x, 0.30, z)
			wheel.rotation.z = PI * 0.5
			wheel.material_override = _material(Color("#1c2022"))
			add_child(wheel)
	if vehicle_kind == "auto":
		var roof := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(width * 0.9, 0.1, length * 0.58)
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, 1.62, 0.16)
		roof.material_override = _material(Color("#202d23"))
		add_child(roof)
	elif vehicle_kind == "municipal":
		var tank := MeshInstance3D.new()
		var tank_mesh := CylinderMesh.new()
		tank_mesh.top_radius = 0.92
		tank_mesh.bottom_radius = 0.92
		tank_mesh.height = 3.25
		tank.mesh = tank_mesh
		tank.position = Vector3(0.0, 1.25, 0.65)
		tank.rotation.x = PI * 0.5
		tank.material_override = _material(Color("#d8e1e4"))
		add_child(tank)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.22
	material.roughness = 0.55
	return material

func _scooter_obstructed() -> bool:
	var forward := (route[_target_index]-position).normalized()
	var shape := SphereShape3D.new()
	shape.radius = .55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = global_position + forward*2.0 + Vector3.UP*.9
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		return true
	# Ambient pedestrians/vehicles are lightweight nodes, not all physics bodies.
	var world := get_parent().get_parent()
	for container in world.get_children():
		for actor in container.get_children():
			if actor == self or not actor is Node3D:
				continue
			if not (actor is TrafficVehicle or actor.get_script() == preload("res://scripts/world/pedestrian.gd")):
				continue
			var offset: Vector3 = actor.global_position-global_position
			offset.y = 0
			if offset.dot(forward)>0 and offset.dot(forward)<3.0 and absf(offset.cross(forward).y)<1.0:
				return true
	return false

func _scooter_box(title: String,at: Vector3,size: Vector3,color: Color,parent: Node3D = self) -> void:
	var item := MeshInstance3D.new()
	item.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = at
	item.material_override = _material(color)
	parent.add_child(item)

func _build_scooter() -> void:
	_scooter_box("BlueBody",Vector3(0,.62,0),Vector3(.58,.48,1.45),Color("243e64"))
	_scooter_box("Seat",Vector3(0,.96,-.12),Vector3(.48,.12,.95),Color("202124"))
	_scooter_box("FrontShield",Vector3(0,.92,.67),Vector3(.55,.63,.18),Color("304e78"))
	_scooter_box("Headlamp",Vector3(0,1.13,.78),Vector3(.35,.14,.04),Color("f5edce"))
	_scooter_box("Handlebar",Vector3(0,1.25,.58),Vector3(.82,.055,.06),Color("272727"))
	for z in [-.62,.62]:
		var wheel := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .27
		mesh.bottom_radius = .27
		mesh.height = .12
		wheel.mesh = mesh
		wheel.position = Vector3(0,.27,z)
		wheel.rotation.z = PI*.5
		wheel.material_override = _material(Color("151515"))
		add_child(wheel)
	for index in 2:
		var rider := Node3D.new()
		rider.name = "Driver" if index == 0 else "Passenger"
		rider.position.z = .18 if index == 0 else -.42
		add_child(rider)
		_scooter_box("Torso",Vector3(0,1.36,0),Vector3(.40,.57,.24),Color("d5cb67") if index==0 else Color("25323a"),rider)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .145
		sphere.height = .29
		head.mesh = sphere
		head.position = Vector3(0,1.79,0)
		head.material_override = _material(Color("935f43"))
		rider.add_child(head)
		for side in [-1,1]:
			_scooter_box("Thigh",Vector3(side*.23,1.0,.12),Vector3(.17,.17,.42),Color("263345"),rider)
			_scooter_box("Leg",Vector3(side*.26,.70,.27),Vector3(.14,.48,.16),Color("263345"),rider)
			_scooter_box("Arm",Vector3(side*.26,1.28,.22),Vector3(.12,.13,.53),Color("935f43"),rider)
