class_name BusStationBuilder
extends Node3D

## A compact TGSRTC-style terminal placed at the real OSM bus-station point.
## The downloaded legacy .3ds model cannot be converted locally, so this uses
## lightweight native geometry and remains aligned to the mapped inner road.

const ROOF_COLOR := Color("#b62d31")
const COLUMN_COLOR := Color("#d8d6cf")
const PLATFORM_COLOR := Color("#9d9b93")

var terminal_count := 0
## Ground-level positions used by the local-life builder for waiting passengers.
var passenger_spots := PackedVector3Array()
## Mapped terminal interaction points, queried by the player controller.
var terminal_entries: Array[Dictionary] = []

func build(world: Node, data: MapData) -> void:
	name = "BusStations"
	for poi in data.pois:
		if str(poi.kind) == "bus_station":
			_add_terminal(world, poi.position, str(poi.name))

func _add_terminal(world: Node, point: Vector2, station_name: String) -> void:
	var road: Dictionary = world.signage._nearest_road(point, 100.0)
	if road.is_empty():
		return
	var direction: Vector2 = road.direction
	var normal: Vector2 = road.normal if (point - road.point).dot(road.normal) >= 0.0 else -road.normal
	var center: Vector2 = road.point + normal * (road.half_width + 3.0)
	var ground: float = world.ground_height(center)
	var yaw := atan2(direction.x, direction.y)
	var terminal := Node3D.new()
	terminal.name = "TGSRTCBusStation"
	add_child(terminal)
	_box(terminal, Vector3(center.x, ground + 0.18, center.y), Vector3(17.0, 0.36, 5.0), yaw, PLATFORM_COLOR)
	for along in [-7.4, -2.5, 2.5, 7.4]:
		var post: Vector2 = center + direction * along - normal * 1.7
		_box(terminal, Vector3(post.x, ground + 2.15, post.y), Vector3(0.24, 4.3, 0.24), yaw, COLUMN_COLOR)
	var roof_center := center - normal * 0.55
	_box(terminal, Vector3(roof_center.x, ground + 4.45, roof_center.y), Vector3(18.0, 0.22, 4.3), yaw, ROOF_COLOR)
	var sign := Label3D.new()
	sign.text = station_name.to_upper()
	sign.font_size = 42
	sign.pixel_size = 0.006
	sign.width = 16.0 / sign.pixel_size
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.modulate = Color.WHITE
	sign.outline_size = 4
	sign.position = Vector3(center.x + normal.x * 2.18, ground + 4.0, center.y + normal.y * 2.18)
	sign.rotation.y = yaw
	terminal.add_child(sign)
	for bay in [-5.2, 0.0, 5.2]:
		var seat: Vector2 = center + direction * bay + normal * 0.6
		_box(terminal, Vector3(seat.x, ground + 0.62, seat.y), Vector3(2.7, 0.45, 0.7), yaw, Color("#527a92"))
		passenger_spots.append(Vector3(seat.x - direction.x * 0.65, ground, seat.y - direction.y * 0.65))
		passenger_spots.append(Vector3(seat.x + direction.x * 0.65, ground, seat.y + direction.y * 0.65))
	_add_direction_board(terminal, center + direction * 8.7 + normal * 1.1, ground, yaw)
	terminal_entries.append({"position": Vector3(center.x, ground, center.y), "name": station_name})
	terminal_count += 1

func nearest_terminal(world_position: Vector3, radius: float = 8.0) -> Dictionary:
	var nearest: Dictionary = {}
	var best := radius * radius
	for entry in terminal_entries:
		var distance: float = world_position.distance_squared_to(entry.position)
		if distance < best:
			best = distance
			nearest = entry
	return nearest

func _add_direction_board(parent: Node3D, point: Vector2, ground: float, yaw: float) -> void:
	_box(parent, Vector3(point.x, ground + 2.35, point.y), Vector3(5.7, 2.0, 0.15), yaw, Color("#17633c"))
	for sideways in [-2.25, 2.25]:
		_box(parent, Vector3(point.x, ground + 1.1, point.y), Vector3(0.14, 2.2, 0.14), yaw + PI * 0.5, Color("#5f6564"))
		# `_box` aligns its long axis with its local X, so turn the support into
		# the board's plane and offset it on the board width.
	var text := Label3D.new()
	text.text = "TGSRTC ROUTES\\nMANCHERIAL  →\\nRAMAGUNDAM  →\\nKARIMNAGAR  ←"
	text.font_size = 28
	text.pixel_size = 0.006
	text.outline_size = 3
	text.modulate = Color.WHITE
	text.position = Vector3(point.x, ground + 2.4, point.y + 0.1)
	text.rotation.y = yaw
	parent.add_child(text)

func _box(parent: Node3D, position: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = yaw
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	instance.material_override = material
	parent.add_child(instance)
