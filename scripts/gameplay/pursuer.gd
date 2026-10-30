extends CharacterBody3D
## Bounded road-following pursuit; physics collisions prevent driving through buildings.
var game: Node
var controller: Node
var health := 100.0
var route := PackedVector2Array()
var route_index := 0
var route_timer := 0.0
var contact_timer := 0.0
var siren: AudioStreamPlayer3D
var lamps: Array[MeshInstance3D] = []
var phase := 0.0

func _ready() -> void:
	add_to_group("pursuers")
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.3, 3.8)
	collider.shape = shape
	collider.position.y = 0.8
	add_child(collider)
	preload("res://scripts/gameplay/city_assets.gd").vehicle(self, "police")
	for side in [-1.0, 1.0]:
		lamps.append(_box(Vector3(side * 0.45, 1.7, 0), Vector3(0.5, 0.15, 0.28), Color.RED if side < 0 else Color.BLUE))
	var label := Label3D.new()
	label.text = "POLICE"
	label.position.y = 2.1
	label.font_size = 30
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	siren = AudioStreamPlayer3D.new()
	siren.stream = load("res://assets/audio/gameplay/siren.wav")
	if siren.stream is AudioStreamWAV:
		siren.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	siren.max_distance = 100
	siren.unit_size = 12
	siren.volume_db = -18
	add_child(siren)
	siren.play()

func _box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	visual.position = at
	add_child(visual)
	return visual

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or controller.wanted_level == 0:
		queue_free()
		return
	phase += delta
	for i in lamps.size():
		lamps[i].visible = (int(phase * 6) + i) % 2 == 0
	route_timer -= delta
	contact_timer = maxf(0.0, contact_timer - delta)
	var target: Vector3 = game.tracked_body().global_position
	if route_timer <= 0.0:
		route_timer = 2.5
		var found: Dictionary = game.road_network.find_route(Vector2(global_position.x, global_position.z), Vector2(target.x, target.z), RoadNetwork.Mode.DRIVE)
		route = found.get("points", PackedVector2Array())
		route_index = mini(1, route.size() - 1)
	var aim := target
	if route_index >= 0 and route_index < route.size() and global_position.distance_to(target) > 14.0:
		var point := route[route_index]
		aim = Vector3(point.x, global_position.y, point.y)
		if Vector2(global_position.x, global_position.z).distance_to(point) < 5.0:
			route_index += 1
	var direction := (aim - global_position).slide(Vector3.UP).normalized()
	var speed: float = 10.0 + controller.wanted_level * 2.0
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 7.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 7.0)
	velocity.y -= 18.0 * delta
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 3.0)
	move_and_slide()
	if global_position.distance_to(target) < 4.0 and controller.visible_to_player(self) and contact_timer <= 0.0:
		contact_timer = 1.5
		if game.control_state == game.ControlState.DRIVING and game.active_vehicle.has_method("take_damage"):
			game.active_vehicle.take_damage(7.0)
		else:
			game.person.take_damage(8.0)
	if global_position.y < game.person.fall_limit:
		queue_free()

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		queue_free()
