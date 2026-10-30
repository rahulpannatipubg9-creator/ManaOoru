class_name BirdFlock
extends Node3D

## Lightweight ambient birds: small high-altitude flocks with offset circular
## paths, gentle height variation and wing beats. They are deliberately visual
## only, so they never distract from driving or block roads.

const FLOCK_CENTERS := [
	Vector2(-160.0, -120.0), Vector2(180.0, -240.0), Vector2(315.6, -334.6),
	Vector2(-300.0, 160.0), Vector2(420.0, 80.0), Vector2(40.0, 360.0),
]
const BIRDS_PER_FLOCK := 6
const FLOCK_RADIUS := 20.0
const MIN_HEIGHT := 28.0

var _world: Node
var _birds: Array[Dictionary] = []
var _elapsed := 0.0

func setup(world: Node) -> void:
	name = "BirdFlocks"
	_world = world
	for flock_index in FLOCK_CENTERS.size():
		var center: Vector2 = FLOCK_CENTERS[flock_index]
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xB1AD + flock_index * 7919
		for bird_index in BIRDS_PER_FLOCK:
			var bird := _make_bird(rng)
			add_child(bird.root)
			_birds.append({
				"root": bird.root, "left_wing": bird.left_wing, "right_wing": bird.right_wing,
				"center": center, "phase": rng.randf_range(0.0, TAU),
				"radius": FLOCK_RADIUS + rng.randf_range(-8.0, 8.0),
				"speed": rng.randf_range(0.14, 0.23), "height": MIN_HEIGHT + rng.randf_range(0.0, 22.0),
				"wing_speed": rng.randf_range(6.0, 9.0),
			})

func bird_count() -> int:
	return _birds.size()

func _process(delta: float) -> void:
	_elapsed += delta
	for bird: Dictionary in _birds:
		var angle: float = _elapsed * bird.speed + bird.phase
		var center: Vector2 = bird.center
		var radius: float = bird.radius
		var point := center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.62)
		var ground: float = _world.ground_height(point)
		var root: Node3D = bird.root
		root.position = Vector3(point.x, ground + bird.height + sin(_elapsed * 0.7 + bird.phase) * 2.0, point.y)
		# Tangent orientation: birds face the way their flock is travelling.
		root.rotation.y = atan2(cos(angle), -sin(angle) * 0.62)
		var beat := sin(_elapsed * bird.wing_speed + bird.phase) * 0.65
		(bird.left_wing as Node3D).rotation.z = beat
		(bird.right_wing as Node3D).rotation.z = -beat

func _make_bird(rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Bird"
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.16
	body_mesh.height = 0.38
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	body.mesh = body_mesh
	body.material_override = _material(Color("#2e3335").lerp(Color("#5f6668"), rng.randf() * 0.35))
	root.add_child(body)
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.52, 0.025, 0.16)
	var left := MeshInstance3D.new()
	left.name = "LeftWing"
	left.mesh = wing_mesh
	left.position = Vector3(-0.28, 0.04, 0.0)
	left.material_override = _material(Color("#383d3f"))
	root.add_child(left)
	var right := MeshInstance3D.new()
	right.name = "RightWing"
	right.mesh = wing_mesh
	right.position = Vector3(0.28, 0.04, 0.0)
	right.material_override = _material(Color("#383d3f"))
	root.add_child(right)
	return {"root": root, "left_wing": left, "right_wing": right}

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
