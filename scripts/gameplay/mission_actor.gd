extends CharacterBody3D
var kind := "suspect"
var game: Node
var health := 100.0
var attack_timer := 0.0

func _ready() -> void:
	add_to_group("hostiles")
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.5
	visual.mesh = mesh
	visual.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("87342f")
	visual.material_override = material
	add_child(visual)
	var label := Label3D.new()
	label.text = "GANG MEMBER" if kind == "gang" else "SUSPECT"
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	var target: Vector3 = game.person.global_position
	var distance := target.distance_to(global_position)
	attack_timer = maxf(0.0, attack_timer - delta)
	velocity.y -= 18.0 * delta
	var toward := (target - global_position).slide(Vector3.UP).normalized()
	velocity.x = toward.x * 2.0 if distance > 8.0 and distance < 40.0 else 0.0
	velocity.z = toward.z * 2.0 if distance > 8.0 and distance < 40.0 else 0.0
	move_and_slide()
	if distance < 25.0 and attack_timer <= 0.0 and game.person.combat_mode:
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, target + Vector3.UP, 0xFFFFFFFF, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == game.person:
			attack_timer = 1.6
			game.person.take_damage(6.0)

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		rotation.z = PI * 0.5
		collision_layer = 0
		set_physics_process(false)
