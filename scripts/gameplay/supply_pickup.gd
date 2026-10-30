extends Area3D
var kind := "health"
var gameplay: Node
var _used := false
func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	collision.shape = shape
	add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d94e4e") if kind == "health" else (Color("638bd9") if kind == "armour" else Color("d7b94b"))
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.3
	visual.material_override = material
	add_child(visual)
	body_entered.connect(_collect)
func _collect(body: Node) -> void:
	if _used or body != gameplay.game.person:
		return
	match kind:
		"health":
			if body.health >= body.max_health: return
			body.heal_full()
		"armour":
			if gameplay.armour >= 100: return
			gameplay.armour = 100.0
		"ammo":
			if gameplay.reserve >= 999: return
			gameplay.reserve = mini(999, gameplay.reserve + 24)
	_used = true
	hide()
	set_deferred("monitoring", false)
	gameplay.life.toast(kind.capitalize() + " collected")
	get_tree().create_timer(120.0, false).timeout.connect(func() -> void:
		_used = false
		show()
		set_deferred("monitoring", true))
