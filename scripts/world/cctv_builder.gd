class_name CctvBuilder
extends Node3D

## User-supplied low-poly CCTV units mounted only where they are useful:
## junction signals, the TGSRTC terminal and selected zebra crossings.  The
## compact placement budget keeps them legible without cluttering every road.

const CCTV_SCENE := preload("res://assets/models/cctv/gdk_cctv.glb")
const MAX_JUNCTION_CAMERAS := 10
const MAX_CROSSING_CAMERAS := 5
const PLACEMENT_RADIUS := 1800.0
const MIN_SPACING := 55.0

var camera_count := 0
var junction_camera_count := 0
var bus_station_camera_count := 0
var crossing_camera_count := 0
var _placed := PackedVector2Array()

func build(world: Node, data: MapData) -> void:
	name = "CCTV"
	for poi in data.pois:
		if str(poi.kind) == "bus_station":
			if _add_camera(world, poi.position):
				bus_station_camera_count += 1
			break
	var junctions := SignageBuilder.signal_junctions(data)
	for group in junctions:
		if junction_camera_count >= MAX_JUNCTION_CAMERAS:
			break
		var point := _cluster_center(group)
		if _add_camera(world, point):
			junction_camera_count += 1
	for crossing in data.crossings:
		if crossing_camera_count >= MAX_CROSSING_CAMERAS:
			break
		if _add_camera(world, crossing):
			crossing_camera_count += 1

func _cluster_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / maxf(float(points.size()), 1.0)

func _add_camera(world: Node, target: Vector2) -> bool:
	if target.length() > PLACEMENT_RADIUS:
		return false
	for other in _placed:
		if other.distance_to(target) < MIN_SPACING:
			return false
	var road: Dictionary = world.signage._nearest_road(target, 45.0)
	if road.is_empty():
		return false
	var side := 1.0 if (target - road.point).dot(road.normal) >= 0.0 else -1.0
	var spot: Vector2 = road.point + road.normal * side * (road.half_width + 0.75)
	var ground: float = world.ground_height(spot)
	var facing: Vector2 = -road.normal * side
	var pole := MeshInstance3D.new()
	pole.name = "CCTVMountPole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.055
	pole_mesh.bottom_radius = 0.075
	pole_mesh.height = 5.9
	pole.mesh = pole_mesh
	pole.position = Vector3(spot.x, ground + 2.95, spot.y)
	pole.material_override = _material(Color("#565d60"))
	add_child(pole)
	var camera := CCTV_SCENE.instantiate() as Node3D
	camera.name = "CCTV_%02d" % (camera_count + 1)
	camera.position = Vector3(spot.x, ground + 5.45, spot.y)
	camera.rotation.y = atan2(facing.x, facing.y)
	camera.scale = Vector3.ONE * 1.15
	add_child(camera)
	_placed.append(target)
	camera_count += 1
	return true

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.45
	material.roughness = 0.42
	return material
