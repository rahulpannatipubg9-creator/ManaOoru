extends Node3D

## The Team Deathmatch arena: a 125 m circle around the Chowrastha junction (world origin).
## It places spawn zones on the side lanes beside the NW-SE highway, puts cover on the road so the
## highway cannot be sniped end to end, marks the boundary, and trims the view to the arena
## with fog and a short far plane (docs/TDM_DESIGN.md, section 3). Same result on every device:
## every position comes from constants plus the shared world data.

const RADIUS := 125.0
const RED := 0
## Red holds the NW arm of the highway, Blue the SE arm (bearings clockwise from north).
const TEAM_BEARINGS: Array[float] = [313.0, 133.0]
const SPAWN_DISTANCES: Array[float] = [80.0, 72.0, 88.0, 64.0, 96.0, 56.0]
const SPAWN_LATERALS: Array[float] = [16.0, -16.0, 24.0, -24.0, 10.0, -10.0, 34.0, -34.0]
const ZONES_PER_TEAM := 6
const CLEARANCE := 1.6
## Beyond this camera distance nothing is drawn: the culling that keeps phones at frame rate.
const VIEW_FAR := 260.0
const FOG_DENSITY := 0.0065
const FOG_COLOR := Color("#a7b4ba")
const COVER_SPACING := 18.0
const COVER_PROPS: Array[String] = [
	"res://assets/models/market_street/tea_stall.glb",
	"res://assets/models/market_street/vegetable_cart.glb",
	"res://assets/models/market_street/parked_scooter.glb",
]

var zones: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var cover_count := 0
var _world: Node
var _environment: Environment
var _saved_fog := {}
var _cameras_trimmed: Dictionary = {}

## Unit vector along the highway pointing out toward the team's side.
static func axis(team: int) -> Vector3:
	var bearing := deg_to_rad(TEAM_BEARINGS[team])
	return Vector3(sin(bearing), 0.0, -cos(bearing))

static func lateral(team: int) -> Vector3:
	var along := axis(team)
	return Vector3(-along.z, 0.0, along.x)

func build(world: Node, environment: Environment) -> void:
	_world = world
	_environment = environment
	name = "TdmArena"
	_pick_spawn_zones()
	_build_cover()
	_build_boundary()
	if _environment != null:
		_saved_fog = {"enabled": _environment.fog_enabled, "density": _environment.fog_density,
			"light_color": _environment.fog_light_color, "sky_affect": _environment.fog_sky_affect}

func ground_at(point: Vector2) -> float:
	return _world.ground_height(point) if _world != null else 0.0

func is_inside(point: Vector3) -> bool:
	return Vector2(point.x, point.z).length() <= RADIUS

func _is_free(point: Vector2, radius: float) -> bool:
	if _world == null or _world.get("buildings") == null:
		return true
	return _world.buildings.is_clear(point, radius)

## Up to four clear spots per team, preferring the side lanes beside the highway.
func _pick_spawn_zones() -> void:
	for team in 2:
		var found := PackedVector3Array()
		for distance in SPAWN_DISTANCES:
			for side in SPAWN_LATERALS:
				if found.size() >= ZONES_PER_TEAM:
					break
				var flat := axis(team) * distance + lateral(team) * side
				var point := Vector2(flat.x, flat.z)
				if point.length() >= RADIUS - 8.0 or not _is_free(point, CLEARANCE):
					continue
				var spaced := true
				for other in found:
					if Vector2(other.x, other.z).distance_to(point) < 8.0:
						spaced = false
				if spaced:
					found.append(Vector3(point.x, ground_at(point) + 0.1, point.y))
		zones[team] = found

## Barriers across the highway and market props beside it, so no straight line runs from one spawn to the other.
func _build_cover() -> void:
	var cover := Node3D.new()
	cover.name = "Cover"
	add_child(cover)
	var along := axis(RED)
	var side := lateral(RED)
	var step := 0
	var offset := -60.0
	while offset <= 60.0:
		var swing := 4.5 if step % 2 == 0 else -4.5
		_add_barrier(cover, along * offset + side * swing, along)
		var prop_side := 13.0 if step % 2 == 0 else -13.0
		_add_prop(cover, along * (offset + 9.0) + side * prop_side, step)
		offset += COVER_SPACING
		step += 1
	# The junction itself gets a few low walls so the centre is contested, not a plaza.
	for corner in [Vector3(8, 0, 8), Vector3(-8, 0, 8), Vector3(8, 0, -8), Vector3(-8, 0, -8)]:
		_add_barrier(cover, corner, Vector3.RIGHT)

func _add_barrier(parent: Node3D, flat: Vector3, facing: Vector3) -> void:
	var point := Vector2(flat.x, flat.z)
	if _in_spawn_zone(flat) or not _is_free(point, 1.2):
		return
	var size := Vector3(3.2, 1.15, 0.55)
	var body := StaticBody3D.new()
	body.name = "Barrier%d" % cover_count
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.58, 0.57, 0.54)
	material.roughness = 0.95
	mesh.material_override = material
	body.add_child(mesh)
	parent.add_child(body)
	# Barriers lie across the road: perpendicular to the highway axis.
	body.global_position = Vector3(flat.x, ground_at(point) + size.y * 0.5, flat.z)
	body.rotation.y = atan2(facing.x, facing.z)
	cover_count += 1

func _add_prop(parent: Node3D, flat: Vector3, index: int) -> void:
	var point := Vector2(flat.x, flat.z)
	if _in_spawn_zone(flat) or not _is_free(point, 1.8):
		return
	var scene := load(COVER_PROPS[index % COVER_PROPS.size()]) as PackedScene
	if scene == null:
		return
	var prop := scene.instantiate() as Node3D
	var body := StaticBody3D.new()
	body.name = "Prop%d" % cover_count
	parent.add_child(body)
	body.add_child(prop)
	var bounds := _bounds_of(prop)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3(0.6, 0.6, 0.6))
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	body.global_position = Vector3(flat.x, ground_at(point), flat.z)
	body.rotation.y = float(index) * 0.7
	cover_count += 1

func _in_spawn_zone(flat: Vector3) -> bool:
	for team in 2:
		for zone in zones[team]:
			if Vector2(zone.x, zone.z).distance_to(Vector2(flat.x, flat.z)) < 7.0:
				return true
	return false

static func _bounds_of(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var box := mesh_node.global_transform * mesh_node.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged

## A faint red wall and base ring along the 125 m boundary.
func _build_boundary() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "BoundaryShell"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = 40.0
	cylinder.radial_segments = 96
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	shell.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.25, 0.2, 0.07)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3(0.0, ground_at(Vector2.ZERO) + 12.0, 0.0)
	add_child(shell)

## Drops spawn zones that an enemy zone can see along a straight line at head height. Uses real physics,
## so call it a few physics frames after build(), once the cover colliders are in the space. Keeps at
## least two zones per team (the least exposed ones). Returns how many zones were dropped.
func prune_exposed_zones(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> int:
	var exposure: Array[Dictionary] = [{}, {}]
	for red_index in zones[0].size():
		for blue_index in zones[1].size():
			var from: Vector3 = zones[0][red_index] + Vector3.UP * 1.6
			var to: Vector3 = zones[1][blue_index] + Vector3.UP * 1.6
			var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
			if space.intersect_ray(query).is_empty():
				exposure[0][red_index] = int(exposure[0].get(red_index, 0)) + 1
				exposure[1][blue_index] = int(exposure[1].get(blue_index, 0)) + 1
	var dropped := 0
	for team in 2:
		var order: Array[int] = []
		for index in zones[team].size():
			order.append(index)
		order.sort_custom(func(a: int, b: int) -> bool: return int(exposure[team].get(a, 0)) < int(exposure[team].get(b, 0)))
		var kept := PackedVector3Array()
		for index in order:
			if int(exposure[team].get(index, 0)) == 0 or kept.size() < 2:
				kept.append(zones[team][index])
		dropped += zones[team].size() - kept.size()
		zones[team] = kept
	return dropped

func _process(_delta: float) -> void:
	# Re-applied every frame: the weather controller rewrites the fog density.
	if _environment != null:
		_environment.fog_enabled = true
		_environment.fog_density = FOG_DENSITY
		_environment.fog_light_color = FOG_COLOR
		_environment.fog_sky_affect = 1.0
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.far > VIEW_FAR:
		_cameras_trimmed[camera.get_instance_id()] = camera.far
		camera.far = VIEW_FAR

## Undoes the fog and far-plane trim when the match ends or the player leaves.
func restore() -> void:
	set_process(false)
	if _environment != null and not _saved_fog.is_empty():
		_environment.fog_enabled = _saved_fog.enabled
		_environment.fog_density = _saved_fog.density
		_environment.fog_light_color = _saved_fog.light_color
		_environment.fog_sky_affect = _saved_fog.sky_affect
	for id: int in _cameras_trimmed:
		var camera := instance_from_id(id) as Camera3D
		if camera != null:
			camera.far = _cameras_trimmed[id]
	_cameras_trimmed.clear()
