extends StaticBody3D

## A practice-mode target: standing dummy with head and body zones that stands back up after a kill.
## Shots reach it through tdm_dummy_hit(), the same way a puppet gets tdm_claim_hit().

signal hit(headshot: bool, killed: bool)

const HEIGHT := 1.8
const HEAD_ZONE := 0.35
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
const RESPAWN_SECONDS := 2.0

var health := 100.0
var _visual: Node3D
var _collision: CollisionShape3D

func _ready() -> void:
	add_to_group("tdm_dummy")
	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = HEIGHT
	_collision.shape = capsule
	_collision.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(_collision)
	_visual = Node3D.new()
	add_child(_visual)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 1.3
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.85, 0.0)
	body.material_override = _flat(Color(0.85, 0.55, 0.15))
	_visual.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.48
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.62, 0.0)
	head.material_override = _flat(Color(0.95, 0.85, 0.25))
	_visual.add_child(head)

static func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func tdm_dummy_hit(hit_position: Vector3, weapon := Weapons.M416) -> void:
	if health <= 0.0:
		return
	var headshot := hit_position.y >= global_position.y + HEIGHT - HEAD_ZONE
	var stats := Weapons.stats(weapon)
	health = maxf(0.0, health - float(stats.head_damage if headshot else stats.body_damage))
	var killed := health <= 0.0
	hit.emit(headshot, killed)
	if killed:
		_visual.visible = false
		_collision.set_deferred("disabled", true)
		get_tree().create_timer(RESPAWN_SECONDS, false).timeout.connect(_stand_up)

func _stand_up() -> void:
	health = 100.0
	_visual.visible = true
	_collision.set_deferred("disabled", false)
