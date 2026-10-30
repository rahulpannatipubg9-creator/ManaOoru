extends Node3D
## Animates the three-wheel meshes in the imported auto model from the same
## suspension and tyre state that drives the rigid-body contact simulation.

const MOUNT_HEIGHT := 0.9
const FRONT_Z := 1.204
const REAR_Z := -0.98

var _vehicle: RigidVehicle
var _front_wheel: Node3D
var _rear_wheels: Node3D
var _front_base: Basis
var _rear_base: Basis
var _handlebar: Node3D
const HANDLEBAR_PIVOT := Vector3(0, 1.15, 0.67)

func _ready() -> void:
	_vehicle = get_parent() as RigidVehicle
	_front_wheel = find_child("Rin", true, false) as Node3D
	_rear_wheels = find_child("Rin_001", true, false) as Node3D
	if _vehicle == null or _front_wheel == null or _rear_wheels == null:
		push_error("Tuk Tuk visual wheel nodes or RigidVehicle parent are missing")
		set_physics_process(false)
		return
	_build_handlebar()
	_front_base = _vehicle.global_basis.inverse() * _front_wheel.global_basis
	_rear_base = _vehicle.global_basis.inverse() * _rear_wheels.global_basis

func _physics_process(_delta: float) -> void:
	if _vehicle == null:
		return
	_handlebar.rotation.y = _vehicle._steer * 0.3
	var front_length := (_vehicle._lengths[0] + _vehicle._lengths[1]) * 0.5
	var rear_length := (_vehicle._lengths[2] + _vehicle._lengths[3]) * 0.5
	_front_wheel.global_position = _vehicle.to_global(Vector3(0.0, MOUNT_HEIGHT - front_length, FRONT_Z))
	_rear_wheels.global_position = _vehicle.to_global(Vector3(0.0, MOUNT_HEIGHT - rear_length, REAR_Z))
	_front_wheel.global_basis = _vehicle.global_basis * Basis(Vector3.UP, _vehicle._steer) \
		* _front_base * Basis(Vector3.RIGHT, _vehicle._spin[0])
	var rear_spin := (_vehicle._spin[2] + _vehicle._spin[3]) * 0.5
	_rear_wheels.global_basis = _vehicle.global_basis * _rear_base * Basis(Vector3.RIGHT, rear_spin)

## The imported exterior has no usable driver controls. Add a real bar and
## rubber grips at the measured contact points so the hands hold geometry.
func _build_handlebar() -> void:
	_handlebar = Node3D.new()
	_handlebar.name = "DriverHandlebar"
	add_child(_handlebar)
	_handlebar.position = HANDLEBAR_PIVOT - position
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("424548")
	metal.metallic = 0.7
	metal.roughness = 0.4
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("171819")
	rubber.roughness = 0.9
	_bar(Vector3(-0.33, 0, 0), Vector3(0.33, 0, 0), 0.015, metal)
	_bar(Vector3(0, -0.32, 0.17), Vector3.ZERO, 0.024, metal)
	for side: float in [-1, 1]:
		_bar(Vector3(side * 0.18, 0, 0), Vector3(side * 0.32, 0, 0), 0.025, rubber)

func _bar(a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 10
	node.mesh = mesh
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	node.material_override = material
	_handlebar.add_child(node)

func driver_grip_points() -> Array[Vector3]:
	var turn := Basis(Vector3.UP, _vehicle._steer * 0.3)
	return [HANDLEBAR_PIVOT + turn * (_vehicle.left_hand_grip - HANDLEBAR_PIVOT),
		HANDLEBAR_PIVOT + turn * (_vehicle.right_hand_grip - HANDLEBAR_PIVOT)]
