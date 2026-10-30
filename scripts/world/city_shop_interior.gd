class_name CityShopInterior
extends Node3D
## One reusable, original walkable room below the active shop. Its X/Z matches
## the entrance so the minimap stays geographically aligned. Inactive collision
## is disabled; no city building is hollowed out or moved.
var _bodies: Array[StaticBody3D] = []
var title: Label3D

func build() -> void:
	name = "LocalShopInterior"
	position.y = -1000.0
	_box(Vector3(0, -0.15, 0), Vector3(6.6, 0.3, 7.0), Color("#89735c"), true)
	for piece in [[Vector3(-3.3, 1.8, 0), Vector3(0.2, 3.6, 7)], [Vector3(3.3, 1.8, 0), Vector3(0.2, 3.6, 7)], [Vector3(0, 1.8, -3.4), Vector3(6.6, 3.6, 0.2)], [Vector3(-2.2, 1.8, 3.4), Vector3(2.2, 3.6, 0.2)], [Vector3(2.2, 1.8, 3.4), Vector3(2.2, 3.6, 0.2)]]:
		_box(piece[0], piece[1], Color("#c5bb94"), true)
	_box(Vector3(0, 3.6, 0), Vector3(6.6, 0.2, 7.0), Color("#d8d0af"), false)
	_box(Vector3(0, 0.6, -1.3), Vector3(3.7, 1.2, 0.8), Color("#76513c"), true)
	for row in 3:
		_box(Vector3(0, 0.65 + row * 0.7, -3.15), Vector3(5.6, 0.10, 0.45), Color("#5f4332"), false)
		for column in 9:
			_box(Vector3(-2.5 + column * 0.62, 0.87 + row * 0.7, -3.12), Vector3(0.27, 0.34, 0.25), [Color("#c18a36"), Color("#77905c"), Color("#b85f49")][(row + column) % 3], false)
	for i in 4:
		_box(Vector3(-1.2 + i * 0.65, 1.25, -1.25), Vector3(0.18, 0.22, 0.18), Color("#d7c8a1"), false)
	title = Label3D.new()
	title.position = Vector3(0, 2.8, -3.1)
	title.pixel_size = 0.006
	title.font_size = 40
	title.modulate = Color("#693d27")
	add_child(title)
	var exit := Label3D.new()
	exit.text = "EXIT"
	exit.position = Vector3(0, 2.7, 3.2)
	exit.rotation.y = PI
	exit.font_size = 32
	exit.pixel_size = 0.007
	add_child(exit)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.9, 0)
	lamp.omni_range = 8.0
	lamp.light_color = Color("#ffe6b5")
	lamp.light_energy = 2.0
	lamp.shadow_enabled = false
	add_child(lamp)
	var keeper: Node3D = preload("res://scenes/world/pedestrian.tscn").instantiate()
	keeper.position = Vector3(0.9, -0.07, -2.25)
	keeper.idle_mode = true
	keeper.talking_mode = true
	keeper.walk_direction = Vector3.BACK
	add_child(keeper)
	set_active(false)

func set_active(value: bool) -> void:
	visible = value
	for body in _bodies:
		body.collision_layer = 1 if value else 0

func _box(at: Vector3, size: Vector3, color: Color, collide: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	add_child(mesh)
	if collide:
		var body := StaticBody3D.new()
		body.position = at
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		_bodies.append(body)
