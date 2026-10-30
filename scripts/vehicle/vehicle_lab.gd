class_name VehicleLab
extends Node3D

## Isolated test track for vehicle physics: flat pad, a 15% ramp, speed bumps,
## a wall, five parked cars and one drivable car. Run scenes/tests/vehicle_lab.tscn
## to drive it (W/A/S/D, Space handbrake, R recover), or use it from tests.

const CAR_SCENE := preload("res://scenes/vehicles/rigid_thar.tscn")
const RAMP_GRADE := 0.15
const PARKED_POSITIONS := [Vector3(0, 0, 30), Vector3(3, 0, 30), Vector3(-3, 0, 30), Vector3(0, 0, 36), Vector3(10, 0, 20)]

@export var interactive := true
var driven: RigidVehicle
var parked: Array[RigidVehicle] = []

func _ready() -> void:
	if not interactive:
		return
	build_arena()
	for spot in PARKED_POSITIONS:
		parked.append(spawn_car(spot, 0.0, false))
	driven = spawn_car(Vector3(0, 0, 0), 0.0, true)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#8fd3ef")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#b9d9e8")
	add_child(environment)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and driven:
		driven.recover_vehicle()

func build_arena() -> void:
	_box("Ground", Vector3(0, -0.5, 0), Vector3(600, 1, 600), Basis(), Color("#7d7461"))
	# 15% ramp rising along -Z, starting at z = -20.
	var angle := atan(RAMP_GRADE)
	var length := 40.0
	var ramp_basis := Basis(Vector3.RIGHT, angle)
	_box("Ramp", Vector3(-20, length * 0.5 * sin(angle) - 0.25, -20 - length * 0.5 * cos(angle)),
		Vector3(8, 0.5, length), ramp_basis, Color("#5d5f62"))
	for index in 3:
		_box("SpeedBump_%d" % index, Vector3(20, 0.0, -10 - index * 8), Vector3(8, 0.24, 0.6), Basis(), Color("#d9c24a"))
	_box("Wall", Vector3(0, 1.5, 80), Vector3(30, 3, 1), Basis(), Color("#b9b3a5"))

func spawn_car(position: Vector3, yaw: float, drivable: bool) -> RigidVehicle:
	var car: RigidVehicle = CAR_SCENE.instantiate()
	car.position = position + Vector3.UP * 0.05
	car.rotation.y = yaw
	add_child(car)
	car.respawn_position = car.global_position
	car.set_driving_enabled(drivable)
	car.set_input_authority(drivable)
	car.set_keyboard_input_enabled(drivable)
	var camera := car.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera:
		camera.current = drivable
	return car

func _box(box_name: String, at: Vector3, size: Vector3, basis: Basis, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.transform = Transform3D(basis, at)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body
