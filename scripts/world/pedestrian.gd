extends Node3D

@export var sway_offset := 0.0
@export var walk_direction := Vector3.FORWARD
@export var patrol_distance := 13.0
@export var walk_speed := 1.15
@export var shirt_color := Color("#276b45")
@export var pants_color := Color("#1c2630")
@export var skin_color := Color("#8f563b")
## Crossing residents wait at the kerb, cross on the corresponding traffic-red
## phase, then wait on the opposite pavement before returning.
@export var crossing_mode := false
@export var crossing_target := Vector3.ZERO
@export var crossing_wait_seconds := 2.4
@export var traffic_signal: SignageBuilder
@export var traffic_group := 0
@export var idle_mode := false
@export var simulation_distance := 420.0

@onready var body: MeshInstance3D = $Body
@onready var head: MeshInstance3D = $Head
@onready var left_arm: Node3D = $LeftArmPivot
@onready var right_arm: Node3D = $RightArmPivot
@onready var left_leg: Node3D = $LeftLegPivot
@onready var right_leg: Node3D = $RightLegPivot

var health := 100.0
var _panic_time := 0.0
var _danger := Vector3.ZERO

func react_to_danger(at: Vector3) -> void:
	_danger = at
	_panic_time = 4.0

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(amount, 0.0))
	react_to_danger(global_position - walk_direction)
	if health <= 0.0:
		hide()
		set_process(false)
		get_tree().create_timer(30.0, false).timeout.connect(func() -> void:
			health = 100.0
			show()
			set_process(true))

var ground_sampler: Callable
var crossing_guard: Callable
var talking_mode := false
var activity_route := PackedVector3Array()
var activity_wait_seconds := 5.0
var hide_at_destination := false
var _activity_index := 1
var _activity_wait := 0.0
var _activity_hidden := false
var _crossing_active := false
var _ground_timer := 0.0
var _surface_y := 0.0
var _has_surface := false
var _phase := 0.0
var _travelled := 0.0
var _direction_sign := 1.0
var _crossing_wait := 0.0
var _crossing_start := Vector3.ZERO

func _ready() -> void:
	add_to_group("performance_ambient")
	add_to_group("city_residents")
	walk_direction.y = 0.0
	walk_direction = walk_direction.normalized() if walk_direction.length_squared() > 0.001 else Vector3.FORWARD
	rotation.y = atan2(walk_direction.x, walk_direction.z)
	_set_color(body, shirt_color)
	_set_color(head, skin_color)
	for mesh: MeshInstance3D in [$LeftArmPivot/Arm, $RightArmPivot/Arm]:
		_set_color(mesh, shirt_color)
	for mesh: MeshInstance3D in [$LeftLegPivot/Leg, $RightLegPivot/Leg]:
		_set_color(mesh, pants_color)
	preload("res://scripts/gameplay/resident_details.gd").dress(self, int(absf(sway_offset) * 10) + int(get_index()))
	if crossing_mode:
		_crossing_start = position
		_crossing_wait = crossing_wait_seconds * (0.45 + fmod(sway_offset, 0.7))
		_face(crossing_target - position)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and global_position.distance_squared_to(camera.global_position) > simulation_distance * simulation_distance:
		visible = false
		return
	visible = true
	if _panic_time > 0.0:
		_panic_time = maxf(0.0, _panic_time - delta)
		var away := (global_position - _danger).slide(Vector3.UP).normalized()
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.UP + away * 2.0, 3)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			global_position += away * 3.5 * delta
		_face(away)
		_phase += delta * 12.0
		_set_gait(sin(_phase) * 0.7)
	else:
		_animate(delta)
	_update_ground_contact(delta)

func _animate(delta: float) -> void:
	if activity_route.size() >= 2:
		_process_activity(delta)
		return
	if idle_mode:
		_phase += delta * 1.4
		_set_gait(0.0)
		body.rotation.z = sin(_phase + sway_offset) * 0.018
		head.rotation.z = body.rotation.z * 0.5
		if talking_mode:
			left_arm.rotation.x = -0.35 + sin(_phase * 2.0 + sway_offset) * 0.18
			right_arm.rotation.x = -0.15 + sin(_phase * 1.3) * 0.12
			head.rotation.x = sin(_phase * 1.6) * 0.06
		return
	if crossing_mode:
		_process_crossing(delta)
		return
	_phase += delta * walk_speed * 5.4
	_travelled += delta * walk_speed * _direction_sign
	if absf(_travelled) >= patrol_distance:
		_direction_sign *= -1.0
		_travelled = clampf(_travelled, -patrol_distance, patrol_distance)
		_face(walk_direction * _direction_sign)
	position += walk_direction * walk_speed * _direction_sign * delta
	var stride := sin(_phase) * 0.62
	left_arm.rotation.x = stride
	right_arm.rotation.x = -stride
	left_leg.rotation.x = -stride * 0.72
	right_leg.rotation.x = stride * 0.72
	body.rotation.z = sin(_phase * 0.5 + sway_offset) * 0.025
	head.rotation.z = body.rotation.z * 0.5

## Default surface sampler for residents even when CityCommunity is not enabled.
## Terrain visuals sit 20 cm below terrain collision; the road-only layer gives
## the actual draped carriageway height without placing feet on invisible ground.
func sample_world_surface(point: Vector2, world: Node3D) -> float:
	var terrain_y: float = world.ground_height(point)
	var height := terrain_y - 0.2
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, terrain_y + 1.0, point.y),
		Vector3(point.x, terrain_y - 0.3, point.y), RoadBuilder.ROAD_LAYER)
	var road_hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if not road_hit.is_empty():
		height = float(road_hit.position.y)
	else:
		var road: Dictionary = world.signage._nearest_road(point, 12.0)
		if not road.is_empty() and point.distance_to(road.point) <= float(road.half_width) + 1.0:
			height = terrain_y + RoadBuilder.SHOULDER_HEIGHT
	for unit: Dictionary in world.buildings.storefront_allocator.units:
		var delta: Vector2 = point - Vector2(unit.entrance)
		var normal: Vector2 = unit.normal
		var outward := delta.dot(normal)
		if outward >= 0.0 and outward <= BuildingBuilder.APRON_DEPTH and absf(delta.dot(normal.orthogonal())) < float(unit.width) * 0.5:
			var metadata: Dictionary = world.buildings.building_metadata[unit.building_index]
			height = maxf(height, float(metadata.base) + BuildingBuilder.APRON_HEIGHT)
	return height

## Anchor the lowest animated capsule sole, rather than the neutral-pose origin.
## The other foot can lift naturally; neither animation nor a slope can make both hover.
func _update_ground_contact(delta: float) -> void:
	if not ground_sampler.is_valid():
		return
	_ground_timer -= delta
	if not _has_surface or _ground_timer <= 0.0:
		_ground_timer = 0.08
		_surface_y = float(ground_sampler.call(Vector2(position.x, position.z)))
		_has_surface = true
	var lowest := INF
	for pivot: Node3D in [left_leg, right_leg]:
		var leg := pivot.get_node("Leg") as MeshInstance3D
		var capsule := leg.mesh as CapsuleMesh
		var foot_transform := pivot.transform * leg.transform
		var half_stem := capsule.height * 0.5 - capsule.radius
		var sole := foot_transform.origin.y - absf(foot_transform.basis.y.y) * half_stem - capsule.radius
		lowest = minf(lowest, sole)
	position.y = _surface_y - lowest * scale.y

func _process_crossing(delta: float) -> void:
	_phase += delta * walk_speed * 5.4
	if _crossing_wait > 0.0:
		_crossing_wait -= delta
		_set_gait(0.0)
		return
	if not _crossing_active and ((traffic_signal != null and traffic_signal.traffic_phase_for_group(traffic_group) != "red") or (crossing_guard.is_valid() and not crossing_guard.call(position, crossing_target))):
		_set_gait(0.0)
		return
	_crossing_active = true
	var toward := crossing_target - position
	toward.y = 0.0
	if toward.length() <= 0.10:
		var previous_start := _crossing_start
		_crossing_start = crossing_target
		crossing_target = previous_start
		_crossing_wait = crossing_wait_seconds
		_crossing_active = false
		_set_gait(0.0)
		return
	var direction := toward.normalized()
	position += direction * walk_speed * delta
	_face(direction)
	_set_gait(sin(_phase) * 0.62)

func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		rotation.y = atan2(direction.x, direction.z)

func _set_gait(stride: float) -> void:
	left_arm.rotation.x = stride
	right_arm.rotation.x = -stride
	left_leg.rotation.x = -stride * 0.72
	right_leg.rotation.x = stride * 0.72
	body.rotation.z = sin(_phase * 0.5 + sway_offset) * 0.025 if absf(stride) > 0.01 else 0.0
	head.rotation.z = body.rotation.z * 0.5

func _set_color(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	mesh.material_override = material

func _process_activity(delta: float) -> void:
	_phase += delta * walk_speed * 5.4
	if _activity_wait > 0.0:
		_activity_wait = maxf(0.0, _activity_wait - delta)
		visible = not _activity_hidden
		_set_gait(0.0)
		if _activity_wait == 0.0:
			_activity_hidden = false
			_activity_index = 0 if _activity_index == activity_route.size() - 1 else _activity_index + 1
		return
	var toward := activity_route[_activity_index] - position
	toward.y = 0.0
	if toward.length() < 0.12:
		_activity_wait = activity_wait_seconds
		_activity_hidden = hide_at_destination and _activity_index == activity_route.size() - 1
		_set_gait(0.0)
		return
	var direction := toward.normalized()
	position += direction * minf(toward.length(), walk_speed * delta)
	_face(direction)
	_set_gait(sin(_phase) * 0.55)
