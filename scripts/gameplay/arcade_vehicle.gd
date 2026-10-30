extends RigidVehicle
## Original blockout vehicles: stable motorcycle, displacement boat, fixed-wing aircraft.
var kind := "motorcycle"
var water: Node
var _visual: Node3D

func _ready() -> void:
	vehicle_mass = 250.0 if kind in ["motorcycle", "scooter"] else (750.0 if kind == "boat" else 1100.0)
	entry_half_width = 0.45 if kind in ["motorcycle", "scooter"] else 1.2
	seat_hip = Vector3(0, 0.95, -0.2)
	pedal_point = Vector3(0.25, 0.5, 0.5)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.7, 1.8) if kind in ["motorcycle", "scooter"] else Vector3(1.7, 1.0, 3.7)
	collider.shape = shape
	collider.position.y = 0.7
	add_child(collider)
	_visual = Node3D.new()
	add_child(_visual)
	if kind in ["motorcycle", "scooter"]:
		_box(Vector3(0, 0.8, 0), Vector3(0.42, 0.5, 1.5), Color("a71f36"))
		_box(Vector3(0, 1.08, -0.3), Vector3(0.45, 0.12, 0.75), Color("202329"))
		_box(Vector3(0, 1.25, 0.65), Vector3(0.85, 0.08, 0.1), Color("a2acb0"))
		if kind == "scooter":
			_box(Vector3(0,.85,.58),Vector3(.55,.16,.8),Color("2c6a87"))
			_box(Vector3(0,.47,0),Vector3(.5,.12,1.3),Color("4c555d"))
		for z in [-0.75, 0.75]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.32
			mesh.bottom_radius = 0.32
			mesh.height = 0.16
			wheel.mesh = mesh
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(0, 0.32, z)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("171a20")
			wheel.material_override = mat
			_visual.add_child(wheel)
	elif kind in ["police", "ambulance"]:
		preload("res://scripts/gameplay/city_assets.gd").vehicle(_visual, kind)
	else:
		_box(Vector3(0, 0.5, 0), Vector3(1.5, 0.65, 3.8), Color("d9e3e8"))
		_box(Vector3(0, 1.0, 0.2), Vector3(0.8, 0.6, 1.3), Color("30566c"))
		if kind == "plane":
			_box(Vector3(0, 0.7, 0), Vector3(8, 0.15, 1.1), Color("c83737"))
			_box(Vector3(0, 0.8, -1.7), Vector3(3.0, 0.12, 0.7), Color("c83737"))
			_box(Vector3(0, 1.3, -1.7), Vector3(0.12, 1.2, 0.6), Color("c83737"))
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position.y = 1.6
	pivot.set_script(load("res://scripts/camera/camera_controller.gd"))
	pivot.set("camera_distance", 9.0 if kind == "plane" else 6.0)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	arm.add_child(camera)
	pivot.add_child(arm)
	add_child(pivot)
	var engine := AudioStreamPlayer3D.new()
	engine.name = "EngineAudio"
	engine.set_script(load("res://scripts/player/engine_sound.gd"))
	add_child(engine)
	if kind in ["motorcycle", "scooter"]:
		drivetrain = load("res://scripts/player/drivetrain_profile.gd").new()
		drivetrain.idle_rpm = 1400.0
		drivetrain.redline_rpm = 8500.0
		drivetrain.cylinders = 1
		drivetrain.diesel_clatter = 0.0
		drivetrain.launch_rpm = 3500.0
		drivetrain.torque_curve.assign([Vector2(1400, 12), Vector2(4000, 24), Vector2(7000, 22), Vector2(8500, 16)])
	super._ready()
	if kind in ["motorcycle", "scooter"]:
		# Four suspension rays in a narrow footprint give arcade balance without auto-rotation.
		_mounts = [Vector3(-0.18, 0.9, 0.75), Vector3(0.18, 0.9, 0.75), Vector3(-0.18, 0.9, -0.75), Vector3(0.18, 0.9, -0.75)]
		center_of_mass.y = 0.4

func _box(at: Vector3, size: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	_visual.add_child(visual)

func _physics_process(delta: float) -> void:
	if kind == "boat":
		_boat_physics(delta)
		return
	super._physics_process(delta)
	var controlled := driving_enabled and input_authority and GameplayControls.allows(self)
	if kind in ["motorcycle", "scooter"]:
		_visual.rotation.z = lerpf(_visual.rotation.z, -_steer * clampf(absf(current_speed) / 8.0, 0, 1) * 0.6, delta * 6)
	if kind == "plane" and controlled:
		var speed := maxf(0.0, linear_velocity.dot(global_basis.z))
		var lift := clampf(speed * speed / 625.0, 0.0, 1.5)
		apply_central_force(global_basis.y * mass * _gravity * lift)
		var pitch := float(Input.is_key_pressed(KEY_K)) - float(Input.is_key_pressed(KEY_I))
		var roll := float(Input.is_key_pressed(KEY_Q)) - float(Input.is_key_pressed(KEY_E))
		var target_angular := global_basis.x * pitch * 0.5 + global_basis.z * roll * 0.7
		apply_torque((target_angular - angular_velocity) * mass * 2.0 * minf(speed / 15.0, 1.0))
		if Input.is_action_pressed("vehicle_throttle") and condition > 0.0:
			apply_central_force(global_basis.z * mass * 5.0)

func _boat_physics(delta: float) -> void:
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
	var height: float = water.surface_at(global_position) if water else -INF
	var controlled := driving_enabled and input_authority and GameplayControls.allows(self)
	if is_finite(height):
		var depth := height + 0.15 - global_position.y
		apply_central_force(Vector3.UP * mass * maxf(0.0, _gravity + depth * 25.0 - linear_velocity.y * 8.0))
		apply_torque((global_basis.y.cross(Vector3.UP) * 12.0 - angular_velocity * 4.0) * mass)
		apply_central_force(-linear_velocity * mass * 0.6)
		if controlled and condition > 0.0:
			var input := touch_move_input if touch_move_input.length_squared() > 0 else GameplayControls.movement()
			gearbox.update(current_speed, -input.y, wheel_radius, delta)
			apply_central_force(global_basis.z * -input.y * mass * 5.0)
			apply_torque(Vector3.UP * -input.x * mass * clampf(absf(current_speed) * 0.4, 0.2, 2.0))
	current_speed = linear_velocity.dot(global_basis.z)
	_pre_contact_velocity = linear_velocity
	_update_audio(controlled, float(Input.is_action_pressed("vehicle_throttle")), delta)
	if global_position.y < fall_limit:
		recover_vehicle()
