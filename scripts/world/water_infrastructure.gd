class_name WaterInfrastructure
extends Node3D

## Real OSM water-tower footprints receive a recognizable elevated municipal
## tank. A static water tanker is parked only at a nearby clear roadside spot.

const TOWER_PAINT := Color("#c8ced0")
const LEG_PAINT := Color("#aeb5b7")
const TANKER_BLUE := Color("#2d79b8")
const TANKER_CAB := Color("#f2f2ed")
const INDIAN_WATER_TANK_SCENE := preload("res://assets/models/indian_water_tank/gdk_indian_water_tank.glb")

var tower_count := 0
var tanker_count := 0

func build(world: Node, data: MapData) -> void:
	name = "WaterInfrastructure"
	for building in data.buildings:
		if building.tags.get("man_made") != "water_tower":
			continue
		var center := _centroid(building.points)
		_add_tower(world, center, building.points)
		if tanker_count < 2:
			_add_tanker(world, center)

func _add_tower(world: Node, center: Vector2, footprint: PackedVector2Array) -> void:
	# User-supplied water tower uses centimetres; 0.03 gives a realistic
	# 6–7m diameter tank at each real mapped water-tower footprint.
	var supplied_tower := INDIAN_WATER_TANK_SCENE.instantiate() as Node3D
	supplied_tower.name = "MappedIndianWaterTower"
	supplied_tower.position = Vector3(center.x, world.ground_height(center), center.y)
	supplied_tower.scale = Vector3.ONE * 0.03
	add_child(supplied_tower)
	tower_count += 1
	return
	# Retained fallback geometry below documents the original tower construction.
	var radius := 3.2
	for point in footprint:
		radius = maxf(radius, center.distance_to(point) * 0.8)
	radius = clampf(radius, 3.2, 7.0)
	var ground: float = world.ground_height(center)
	var tower := Node3D.new()
	tower.name = "MappedWaterTower"
	add_child(tower)
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var leg := center + Vector2(cos(angle), sin(angle)) * radius * 0.62
		_cylinder(tower, Vector3(leg.x, ground + 5.0, leg.y), 0.28, 10.0, LEG_PAINT)
	var tank := CylinderMesh.new()
	tank.top_radius = radius * 0.78
	tank.bottom_radius = radius * 0.82
	tank.height = 4.0
	tank.radial_segments = 16
	_add_mesh(tower, tank, Vector3(center.x, ground + 11.4, center.y), TOWER_PAINT)
	var roof := CylinderMesh.new()
	roof.top_radius = radius * 0.45
	roof.bottom_radius = radius * 0.80
	roof.height = 0.8
	roof.radial_segments = 16
	_add_mesh(tower, roof, Vector3(center.x, ground + 13.8, center.y), TOWER_PAINT.lightened(0.08))
	tower_count += 1

func _add_tanker(world: Node, near: Vector2) -> void:
	var road: Dictionary = world.signage._nearest_road(near, 90.0)
	if road.is_empty():
		return
	var normal: Vector2 = road.normal
	var spot: Vector2 = road.point + normal * (road.half_width + 3.0)
	if not world.buildings.is_clear(spot, 4.5):
		spot = road.point - normal * (road.half_width + 3.0)
	if not world.buildings.is_clear(spot, 4.5):
		return
	var ground: float = world.ground_height(spot)
	var yaw := atan2(road.direction.x, road.direction.y)
	var tanker := Node3D.new()
	tanker.name = "MunicipalWaterTanker"
	add_child(tanker)
	_box(tanker, Vector3(spot.x, ground + 0.65, spot.y), Vector3(2.25, 1.1, 7.2), yaw, Color("#43484b"))
	var cab: Vector2 = spot + road.direction * 2.6
	_box(tanker, Vector3(cab.x, ground + 1.15, cab.y), Vector3(2.15, 1.9, 1.9), yaw, TANKER_CAB)
	var tank := CylinderMesh.new()
	tank.top_radius = 1.0
	tank.bottom_radius = 1.0
	tank.height = 4.25
	tank.radial_segments = 14
	var mesh := _add_mesh(tanker, tank, Vector3(spot.x - road.direction.x * 0.65, ground + 1.75, spot.y - road.direction.y * 0.65), TANKER_BLUE)
	mesh.rotation = Vector3(0.0, yaw, PI * 0.5)
	for side in [-0.85, 0.85]:
		for along in [-2.25, 2.25]:
			var wheel: Vector2 = spot + road.direction * along + normal * side
			_cylinder(tanker, Vector3(wheel.x, ground + 0.42, wheel.y), 0.42, 0.28, Color("#222426"), Vector3(PI * 0.5, yaw, 0.0))
	tanker_count += 1

func _add_mesh(parent: Node3D, mesh: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, position: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _add_mesh(parent, mesh, position, color)
	instance.rotation.y = yaw

func _cylinder(parent: Node3D, position: Vector3, radius: float, height: float, color: Color, rotation := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var instance := _add_mesh(parent, mesh, position, color)
	instance.rotation = rotation

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	return material

static func _centroid(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / points.size()
