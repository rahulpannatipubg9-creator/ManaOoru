class_name TrafficVehicle
extends CharacterBody3D

const TrafficStopPoint := preload("res://scripts/world/traffic_stop_point.gd")

const TUK_TUK_SCENE := preload("res://assets/models/tuk_tuk/gdk_tuk_tuk.glb")
const SUV_SCENE := preload("res://assets/models/suv_4x4/suv_4x4_complete.glb")
const BUS_SCENE := preload("res://assets/models/vehicles/indian_tgsrtc_bus/indian_tgsrtc_bus.glb")
const BULLET_SCENE := preload("res://assets/models/vehicles/royal_enfield_bullet/bullet_motorcycle.scn")
const AVENGER_SCENE := preload("res://assets/models/vehicles/bajaj_avenger_cruise/bajaj_avenger_cruise.glb")

signal route_finished(vehicle: TrafficVehicle)
@export var safe_gap: float = 3.0
@export var braking: float = 6.0
var route := PackedVector3Array() # Legacy visual fixtures only.
var ground_sampler: Callable
var speed: float = 7.0
var acceleration: float = 2.0
var current_speed: float = 0.0
var vehicle_length: float = 4.1
var night_factor: float = 0.0
var night_active: bool = true
var vehicle_kind: String = "car"
var body_color := Color("#b6382b")
var active: bool = false
var lane: Path3D
var progress: float = 0.0
var manager: Node3D
var _bike_wheels: Array[MeshInstance3D] = []
var _front: RayCast3D
var _shape: CollisionShape3D
var _committed_stop: TrafficStopPoint

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 8
	_front = get_node_or_null("FrontRayCast3D") as RayCast3D
	if _front == null:
		_front = RayCast3D.new()
		_front.name = "FrontRayCast3D"
		add_child(_front)
	_front.collision_mask = 1 | 8
	_front.add_exception(self)
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "CollisionShape3D"
		add_child(_shape)
	var box := BoxShape3D.new()
	box.size = Vector3(0.65 if vehicle_kind == "bike" else 1.8, 1.2, vehicle_length)
	_shape.shape = box
	_shape.position.y = 0.8
	_build_visual()
	set_active(false)

func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value)
	collision_layer = 8 if value else 0
	if _shape != null:
		_shape.set_deferred("disabled", not value)
	current_speed = 0.0
	velocity = Vector3.ZERO
	_committed_stop = null

func activate(path: Path3D, offset: float) -> void:
	lane = path
	progress = offset
	set_active(true)
	global_position = lane.to_global(lane.curve.sample_baked(progress))
	rotation.y = atan2(_heading().x, _heading().z)
	reset_physics_interpolation()

func _heading() -> Vector3:
	var end := minf(progress + 1.0, lane.curve.get_baked_length())
	var start := maxf(0.0, end - 1.0)
	return (lane.curve.sample_baked(end) - lane.curve.sample_baked(start)).normalized()

func _physics_process(delta: float) -> void:
	if not active or lane == null:
		return
	var heading := _heading()
	var limit := speed * float(lane.get_meta("speed_scale", 1.0))
	var remaining := lane.curve.get_baked_length() - progress
	var successors: Array = lane.get_meta("next")
	if successors.is_empty():
		limit = minf(limit, sqrt(2.0 * braking * maxf(0.0, remaining - vehicle_length)))
	var stop: TrafficStopPoint = lane.get_meta("stop") as TrafficStopPoint if lane.has_meta("stop") else null
	var stop_offset := float(lane.get_meta("stop_offset", stop.progress)) if stop != null else INF
	if stop != null:
		var distance := stop_offset - progress - vehicle_length * 0.5
		if distance < 0.0:
			_committed_stop = stop
		if _committed_stop != stop and stop.must_stop():
			limit = minf(limit, sqrt(2.0 * braking * maxf(0.0, distance - 0.5)))
	# Collider is ahead of the bumper and rotates with the body (+Z forward).
	_front.position = Vector3(0.0, 0.8, vehicle_length * 0.5)
	_front.target_position = Vector3(0.0, 0.0, safe_gap + current_speed * 1.5 + current_speed * current_speed / (2.0 * braking))
	_front.force_raycast_update()
	if _front.is_colliding():
		var gap := _front.global_position.distance_to(_front.get_collision_point())
		limit = minf(limit, sqrt(2.0 * braking * maxf(0.0, gap - safe_gap)))
		# Do not travel farther than the measured free space this tick.
		limit = minf(limit, maxf(0.0, gap - safe_gap) / maxf(delta, 0.001))
	if manager != null:
		limit = minf(limit, manager.following_limit(self, heading, delta))
	# Slow before corners; a bounded lookahead uses the cached curve.
	var ahead := lane.curve.sample_baked(minf(progress + 8.0, lane.curve.get_baked_length())) - lane.curve.sample_baked(progress)
	if ahead.length_squared() > 0.01:
		limit *= clampf(heading.dot(ahead.normalized()), 0.25, 1.0)
	current_speed = move_toward(current_speed, limit, (acceleration if limit > current_speed else braking) * delta)
	var step := current_speed * delta
	if stop != null and _committed_stop != stop and stop.must_stop():
		step = minf(step, maxf(0.0, stop_offset - progress - vehicle_length * 0.5 - 0.5))
	if _front.is_colliding():
		step = minf(step, maxf(0.0, _front.global_position.distance_to(_front.get_collision_point()) - safe_gap))
	if manager != null:
		step = minf(step, manager.free_distance(self, heading))
	var next_progress := minf(progress + step, lane.curve.get_baked_length())
	var target := lane.to_global(lane.curve.sample_baked(next_progress))
	velocity = (target - global_position) / maxf(delta, 0.001)
	move_and_slide()
	# Advance only by actual horizontal travel, never through a blocking body.
	var offset := lane.curve.get_closest_offset(lane.to_local(global_position))
	progress = clampf(offset, progress, next_progress)
	rotation.y = atan2(heading.x, heading.z)
	for wheel in _bike_wheels:
		wheel.rotate_x(-step / 0.335)
	if successors.is_empty() and remaining <= vehicle_length + 0.2 and current_speed < 0.1:
		route_finished.emit(self)
	elif remaining < 0.2:
		if not successors.is_empty():
			lane = successors[0] as Path3D
			progress = 0.0
			_committed_stop = null
		else:
			route_finished.emit(self)

func _build_visual() -> void:
	if vehicle_kind == "scooter":
		_build_scooter()
		return
	if vehicle_kind in ["triple_ride", "triple_rider_bike"]:
		_build_triple_rider_bike()
		return
	if vehicle_kind == "tuk_tuk" or vehicle_kind == "auto":
		var tuk_tuk := TUK_TUK_SCENE.instantiate() as Node3D
		tuk_tuk.name = "TukTukModel"
		# The converted GLB already imports in metres.  Its mesh is centred on
		# the source origin, so lift it by half its 2.89m height to rest wheels on
		# the mapped road instead of shrinking it to a centimetre.
		tuk_tuk.position.y = 1.40
		add_child(tuk_tuk)
		_add_auto_occupants(tuk_tuk)
		return
	if vehicle_kind == "bus":
		var bus := BUS_SCENE.instantiate() as Node3D
		bus.name = "TGSRTCBusModel"
		bus.rotation.y = PI
		add_child(bus)
		return
	if vehicle_kind in ["bullet", "bike"]:
		var bullet := BULLET_SCENE.instantiate() as Node3D
		bullet.name = "BulletModel"
		var fw := bullet.get_node_or_null("FrontWheelMesh") as MeshInstance3D
		var rw := bullet.get_node_or_null("RearWheelMesh") as MeshInstance3D
		var hb := bullet.get_node_or_null("Handlebars") as MeshInstance3D
		if fw:
			fw.position = Vector3(0.0, 0.335, 0.695)
			_bike_wheels.append(fw)
		if rw:
			rw.position = Vector3(0.0, 0.335, -0.695)
			_bike_wheels.append(rw)
		if hb:
			hb.position = Vector3(0.0, 0.75, 0.35)
		add_child(bullet)
		return
	if vehicle_kind == "avenger":
		var avenger := AVENGER_SCENE.instantiate() as Node3D
		avenger.name = "AvengerModel"
		add_child(avenger)
		return
	if vehicle_kind == "suv":
		var suv := SUV_SCENE.instantiate() as Node3D
		suv.name = "SUV4x4Model"
		suv.position.y = 0.02
		add_child(suv)
		return
	var length := vehicle_length
	var is_truck := vehicle_kind == "coal_truck"
	var is_tractor := vehicle_kind == "tractor"
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
	if is_truck:
		_scooter_box("CoalBed", Vector3(0, 1.3, -1.1), Vector3(2.1, 1.0, length * 0.55), Color("795a3a"))
		_scooter_box("CoalLoad", Vector3(0, 1.9, -1.1), Vector3(1.9, 0.25, length * 0.5), Color("242424"))
	elif is_tractor:
		_scooter_box("TractorHood", Vector3(0, 1.2, 1.1), Vector3(1.0, 0.5, 1.5), Color("356e35"))
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

func _build_bike_rider() -> void:
	var rider := Node3D.new()
	rider.name = "BikeRider"
	rider.position.z = -0.15
	add_child(rider)
	_scooter_box("Torso", Vector3(0, 1.15, -0.05), Vector3(0.38, 0.52, 0.22), Color("#2e3d48"), rider)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	head.mesh = sphere
	head.position = Vector3(0, 1.52, -0.05)
	head.material_override = _material(Color("#d8b08c"))
	rider.add_child(head)
	var helmet := MeshInstance3D.new()
	var hmesh := SphereMesh.new()
	hmesh.radius = 0.155
	hmesh.height = 0.26
	helmet.mesh = hmesh
	helmet.position = Vector3(0, 1.55, -0.05)
	helmet.material_override = _material(Color("#1a1a1a"))
	rider.add_child(helmet)
	for side in [-1, 1]:
		_scooter_box("Thigh", Vector3(side * 0.16, 0.85, 0.08), Vector3(0.14, 0.14, 0.35), Color("#1b252e"), rider)
		_scooter_box("Leg", Vector3(side * 0.18, 0.55, 0.18), Vector3(0.12, 0.42, 0.14), Color("#1b252e"), rider)
		_scooter_box("Arm", Vector3(side * 0.24, 1.08, 0.18), Vector3(0.11, 0.11, 0.44), Color("#2e3d48"), rider)

func _add_auto_occupants(tuk_tuk: Node3D) -> void:
	# Front Driver in khaki uniform
	var driver := Node3D.new()
	driver.name = "AutoDriver"
	driver.position = Vector3(0.0, -0.42, 0.22)
	tuk_tuk.add_child(driver)
	_scooter_box("DriverTorso", Vector3(0, 0.40, 0), Vector3(0.38, 0.48, 0.22), Color("#c29d5b"), driver)
	var d_head := MeshInstance3D.new()
	var d_sph := SphereMesh.new()
	d_sph.radius = 0.13
	d_sph.height = 0.26
	d_head.mesh = d_sph
	d_head.position = Vector3(0, 0.72, 0)
	d_head.material_override = _material(Color("#935f43"))
	driver.add_child(d_head)
	for side in [-1, 1]:
		_scooter_box("Arm", Vector3(side * 0.22, 0.38, 0.24), Vector3(0.10, 0.10, 0.42), Color("#c29d5b"), driver)

	# Seated rear passengers on the passenger bench
	var p_colors := [Color("#2a688a"), Color("#c95a28"), Color("#3b823b")]
	for p_idx in 2:
		var side_x := -0.32 if p_idx == 0 else 0.32
		var pass_node := Node3D.new()
		pass_node.name = "AutoPassenger_%02d" % (p_idx + 1)
		pass_node.position = Vector3(side_x, -0.42, -0.55)
		tuk_tuk.add_child(pass_node)
		_scooter_box("PassTorso", Vector3(0, 0.40, 0), Vector3(0.34, 0.46, 0.20), p_colors[p_idx % p_colors.size()], pass_node)
		var p_head := MeshInstance3D.new()
		var p_sph := SphereMesh.new()
		p_sph.radius = 0.125
		p_sph.height = 0.25
		p_head.mesh = p_sph
		p_head.position = Vector3(0, 0.70, 0)
		p_head.material_override = _material(Color("#a0694a") if p_idx == 0 else Color("#824d32"))
		pass_node.add_child(p_head)

func _build_triple_rider_bike() -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	bullet.name = "TripleRiderBikeModel"
	var fw := bullet.get_node_or_null("FrontWheelMesh") as MeshInstance3D
	var rw := bullet.get_node_or_null("RearWheelMesh") as MeshInstance3D
	var hb := bullet.get_node_or_null("Handlebars") as MeshInstance3D
	if fw:
		fw.position = Vector3(0.0, 0.335, 0.695)
		_bike_wheels.append(fw)
	if rw:
		rw.position = Vector3(0.0, 0.335, -0.695)
		_bike_wheels.append(rw)
	if hb:
		hb.position = Vector3(0.0, 0.75, 0.35)
	add_child(bullet)

	# 1. Front Rider
	var r1 := Node3D.new()
	r1.name = "TeenRiderFront"
	r1.position = Vector3(0.0, 0.0, 0.12)
	add_child(r1)
	_scooter_box("Torso1", Vector3(0, 1.12, 0), Vector3(0.36, 0.50, 0.22), Color("#2979ff"), r1)
	var h1 := MeshInstance3D.new()
	var s1 := SphereMesh.new()
	s1.radius = 0.135
	s1.height = 0.27
	h1.mesh = s1
	h1.position = Vector3(0, 1.48, 0.04)
	h1.material_override = _material(Color("#a97155"))
	r1.add_child(h1)
	for side in [-1, 1]:
		_scooter_box("Leg1", Vector3(side * 0.18, 0.58, 0.08), Vector3(0.12, 0.44, 0.14), Color("#1b252e"), r1)
		_scooter_box("Arm1", Vector3(side * 0.24, 1.05, 0.18), Vector3(0.10, 0.10, 0.40), Color("#2979ff"), r1)

	# 2. Middle Rider (Sandwiched)
	var r2 := Node3D.new()
	r2.name = "TeenRiderMiddle"
	r2.position = Vector3(0.0, 0.0, -0.16)
	add_child(r2)
	_scooter_box("Torso2", Vector3(0, 1.18, 0), Vector3(0.34, 0.50, 0.20), Color("#d50000"), r2)
	var h2 := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = 0.13
	s2.height = 0.26
	h2.mesh = s2
	h2.position = Vector3(0, 1.54, 0.0)
	h2.material_override = _material(Color("#8d5338"))
	r2.add_child(h2)
	for side in [-1, 1]:
		_scooter_box("Leg2", Vector3(side * 0.22, 0.62, -0.04), Vector3(0.12, 0.44, 0.14), Color("#37474f"), r2)
		_scooter_box("Arm2", Vector3(side * 0.20, 1.08, 0.14), Vector3(0.09, 0.09, 0.32), Color("#d50000"), r2)

	# 3. Rear Pillion Rider
	var r3 := Node3D.new()
	r3.name = "TeenRiderRear"
	r3.position = Vector3(0.0, 0.0, -0.45)
	add_child(r3)
	_scooter_box("Torso3", Vector3(0, 1.15, -0.04), Vector3(0.36, 0.50, 0.22), Color("#ffab00"), r3)
	var h3 := MeshInstance3D.new()
	var s3 := SphereMesh.new()
	s3.radius = 0.135
	s3.height = 0.27
	h3.mesh = s3
	h3.position = Vector3(0, 1.50, -0.05)
	h3.material_override = _material(Color("#a97155"))
	r3.add_child(h3)
	for side in [-1, 1]:
		_scooter_box("Leg3", Vector3(side * 0.24, 0.58, -0.06), Vector3(0.12, 0.44, 0.14), Color("#212121"), r3)
		_scooter_box("Arm3", Vector3(side * 0.20, 0.98, -0.08), Vector3(0.09, 0.09, 0.28), Color("#ffab00"), r3)

func configure(profile: Dictionary) -> void:
	var changed := vehicle_kind != str(profile.kind)
	vehicle_kind = str(profile.kind)
	speed = float(profile.max_speed)
	acceleration = float(profile.acceleration)
	vehicle_length = float(profile.length)
	if changed and is_node_ready():
		_bike_wheels.clear()
		for child in get_children():
			if child != _shape and child != _front and child.name != "VisualRoot":
				remove_child(child)
				child.queue_free()
		_build_visual()
	if _shape != null:
		(_shape.shape as BoxShape3D).size = Vector3(0.65 if vehicle_kind == "bike" else 1.8, 1.2, vehicle_length)
