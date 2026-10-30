class_name CoalMine
extends Node3D

## An explorable underground coal-mine gallery (the user's "coal-mine-gallery" model)
## under a pit-top portal near the mapped "OCP 5 Incline" mine. Walking into the portal
## takes the person down into the gallery; walking to either end of the gallery brings
## them back up. Like GTA interiors, the gallery sits directly below the portal and the
## trip is a teleport.
##
## The portal location and the gallery are game content: Singareni's real underground
## workings are not mapped in open data.

const DISPLAY_NAME := "Coal Gallery"
const GALLERY_SCENE := "res://assets/models/coal_mine/coal_mine_gallery.glb"
const SIGN_WINDING_ROAD := preload("res://assets/models/city_props/road/sign_winding_road.glb")
const SIGN_SLIPPERY_ROAD := preload("res://assets/models/city_props/road/sign_slippery_road.glb")
const ELECTRICAL_PYLON := preload("res://assets/models/city_props/road/electrical_pylon.glb")
## Walkable floor cells of the gallery (from tools/export_coal_mine.py).
const FLOOR_DATA := "res://assets/models/coal_mine/coal_mine_floor.json"
const ROCK_HEIGHT := 6.0

const GALLERY_DEPTH := 60.0
## Gallery floor ends, measured in the exported model (origin at the middle of the floor).
const GALLERY_ENDS := [Vector3(-16.0, 0.57, 28.0), Vector3(18.0, 0.57, -28.0)]
const ENTRY_STEP_IN := 1.5
## Exit zones reach well into each end: the last metres hold mine clutter you cannot walk past.
const EXIT_TRIGGER_RADIUS := 4.5
const EXIT_TRIGGER_INSET := 2.0
const TRIP_COOLDOWN_MSEC := 1500
const LAMP_COUNT := 7

var person: CharacterBody3D
var gallery: Node3D
var _last_trip_msec := -TRIP_COOLDOWN_MSEC
var _lamp_points: Array[Vector3] = []

## Builds the portal at `portal_at` (ground level), facing `facing` (unit, map plane), and
## the gallery below it.
func build(portal_at: Vector3, facing: Vector2, who: CharacterBody3D) -> void:
	name = "CoalMine"
	person = who
	position = portal_at
	rotation.y = atan2(facing.x, facing.y)
	_build_portal()
	_build_gallery()

func _build_portal() -> void:
	var concrete := _material(Color("#8d8a82"))
	var dark := _material(Color("#0d0d0f"))
	var steel := _material(Color("#4a4f55"))
	# Concrete headwall with a dark adit opening, a corrugated shed roof and a headgear frame.
	for part in [
		[Vector3(-3.4, 2.4, 0), Vector3(1.6, 4.8, 3.0), concrete],
		[Vector3(3.4, 2.4, 0), Vector3(1.6, 4.8, 3.0), concrete],
		[Vector3(0, 4.3, 0), Vector3(8.4, 1.0, 3.0), concrete],
		[Vector3(0, 5.0, -2.5), Vector3(9.0, 0.25, 8.0), steel],
		[Vector3(-4.2, 8.0, -4.5), Vector3(0.4, 16.0, 0.4), steel],
		[Vector3(4.2, 8.0, -4.5), Vector3(0.4, 16.0, 0.4), steel],
		[Vector3(0, 15.8, -4.5), Vector3(8.8, 0.5, 0.6), steel],
	]:
		add_child(_solid(part[0], part[1], part[2]))
	var opening := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.2, 3.8, 0.2)
	opening.mesh = box
	opening.material_override = dark
	opening.position = Vector3(0, 1.9, -0.6)
	add_child(opening)
	var wheel := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.6
	torus.outer_radius = 1.9
	wheel.mesh = torus
	wheel.material_override = steel
	wheel.position = Vector3(0, 15.0, -4.5)
	wheel.rotation.x = PI * 0.5
	add_child(wheel)
	var sign := Label3D.new()
	sign.text = DISPLAY_NAME.to_upper() + "\n5 INCLINE"
	sign.font_size = 64
	sign.pixel_size = 0.008
	sign.modulate = Color("#ffd24a")
	sign.outline_size = 10
	sign.position = Vector3(0, 6.0, 1.6)
	add_child(sign)
	# Walk into the dark opening to go down.
	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	var shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(4.8, 3.0, 1.2)
	shape.shape = trigger_box
	shape.position = Vector3(0, 1.5, -0.2)
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_portal_entered)
	add_child(trigger)
	_place_mine_infrastructure_props()

func _place_mine_infrastructure_props() -> void:
	if SIGN_WINDING_ROAD:
		var sign_w := SIGN_WINDING_ROAD.instantiate() as Node3D
		sign_w.name = "SignWindingRoad"
		sign_w.position = Vector3(-5.8, 0.0, 7.5)
		sign_w.rotation.y = 0.0
		_setup_prop_collision(sign_w)
		add_child(sign_w)

	if SIGN_SLIPPERY_ROAD:
		var sign_s := SIGN_SLIPPERY_ROAD.instantiate() as Node3D
		sign_s.name = "SignSlipperyRoad"
		sign_s.position = Vector3(5.8, 0.0, 7.5)
		sign_s.rotation.y = 0.0
		_setup_prop_collision(sign_s)
		add_child(sign_s)

	if ELECTRICAL_PYLON:
		var pylon := ELECTRICAL_PYLON.instantiate() as Node3D
		pylon.name = "InclinePowerPylon"
		pylon.position = Vector3(-12.5, 0.0, 1.5)
		pylon.rotation.y = PI * 0.5
		_setup_prop_collision(pylon)
		add_child(pylon)

func _setup_prop_collision(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visibility_range_end = 250.0 if OS.has_feature("mobile") else 600.0
		if mesh.mesh != null:
			mesh.create_trimesh_collision()

func _build_gallery() -> void:
	if not ResourceLoader.exists(GALLERY_SCENE):
		return
	gallery = (load(GALLERY_SCENE) as PackedScene).instantiate()
	gallery.name = "Gallery"
	gallery.position = Vector3(0, -GALLERY_DEPTH, 0)
	add_child(gallery)
	# The SketchUp shell is single-sided and faces outwards; from inside it must still render.
	var body := StaticBody3D.new()
	gallery.add_child(body)
	for node in gallery.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if source:
				var copy := source.duplicate() as BaseMaterial3D
				copy.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_instance.set_surface_override_material(surface, copy)
		var collision := CollisionShape3D.new()
		var shape := mesh_instance.mesh.create_trimesh_shape()
		shape.backface_collision = true
		collision.shape = shape
		collision.transform = mesh_instance.transform
		body.add_child(collision)
	_build_rock_shell()

	# Mine lamps along the gallery, warm and short-range.
	for at in _lamp_points:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#ffd9a0")
		lamp.light_energy = 2.2
		lamp.omni_range = 16.0
		lamp.position = at + Vector3(0, 3.6, 0)
		gallery.add_child(lamp)
	for index in 2:
		var end: Vector3 = GALLERY_ENDS[index]
		var other: Vector3 = GALLERY_ENDS[1 - index]
		var inward := Vector3(other.x - end.x, 0.0, other.z - end.z).normalized()
		var exit := Area3D.new()
		exit.collision_layer = 0
		exit.collision_mask = 1
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = EXIT_TRIGGER_RADIUS
		shape.shape = sphere
		exit.add_child(shape)
		exit.position = end + inward * EXIT_TRIGGER_INSET + Vector3(0, 1.0, 0)
		exit.body_entered.connect(_on_gallery_exit_entered)
		gallery.add_child(exit)

## Underground there is no daylight: the sun is switched off while the person is down
## in the gallery (the Compatibility renderer has no per-object light masks), so it is
## lit only by its mine lamps.
func _set_daylight(on: bool) -> void:
	for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).visible = on

## The SketchUp gallery has arches and roof lagging but no side walls, so the tunnel is
## walled and roofed in rock along the edge of its walkable floor. This also hides the sky
## and the underside of the town above.
func _build_rock_shell() -> void:
	if not FileAccess.file_exists(FLOOR_DATA):
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FLOOR_DATA))
	var floor_cells: Dictionary = {}
	for cell in data.get("cells", []):
		floor_cells[Vector2i(int(cell[0]), int(cell[1]))] = true
	# Fill single-cell holes (rail gaps) so they don't become pillars of rock.
	for cell in floor_cells.keys():
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var gap: Vector2i = cell + offset
			if floor_cells.has(gap):
				continue
			var around := 0
			for other in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if floor_cells.has(gap + other):
					around += 1
			if around >= 3:
				floor_cells[gap] = true
	# Lamps spread evenly through the bends: farthest-point sampling over the floor cells.
	var cells: Array = floor_cells.keys()
	var chosen: Array[Vector2i] = [cells[0]]
	while chosen.size() < LAMP_COUNT:
		var best: Vector2i = cells[0]
		var best_distance := -1.0
		for cell: Vector2i in cells:
			var nearest := INF
			for picked in chosen:
				nearest = minf(nearest, Vector2(cell).distance_to(Vector2(picked)))
			if nearest > best_distance:
				best_distance = nearest
				best = cell
		chosen.append(best)
	for cell in chosen:
		_lamp_points.append(Vector3(cell.x, 0.6, cell.y))
	var rock := MeshSurface.new()
	var colour := Color("#2a2420")
	for cell: Vector2i in floor_cells:
		var x0 := cell.x - 0.5
		var z0 := cell.y - 0.5
		var roof := [Vector3(x0, ROCK_HEIGHT, z0), Vector3(x0 + 1, ROCK_HEIGHT, z0), Vector3(x0 + 1, ROCK_HEIGHT, z0 + 1), Vector3(x0, ROCK_HEIGHT, z0 + 1)]
		rock.quad(roof[0], roof[1], roof[2], roof[3], Vector3.DOWN, colour, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		for side in [[Vector2i(1, 0), Vector3(x0 + 1, 0, z0), Vector3(x0 + 1, 0, z0 + 1)], [Vector2i(-1, 0), Vector3(x0, 0, z0 + 1), Vector3(x0, 0, z0)],
				[Vector2i(0, 1), Vector3(x0 + 1, 0, z0 + 1), Vector3(x0, 0, z0 + 1)], [Vector2i(0, -1), Vector3(x0, 0, z0), Vector3(x0 + 1, 0, z0)]]:
			if floor_cells.has(cell + (side[0] as Vector2i)):
				continue
			var a: Vector3 = side[1] + Vector3.DOWN * 0.5
			var b: Vector3 = side[2] + Vector3.DOWN * 0.5
			var inward := -Vector3(side[0].x, 0, side[0].y)
			rock.quad(a, b, b + Vector3.UP * (ROCK_HEIGHT + 0.5), a + Vector3.UP * (ROCK_HEIGHT + 0.5), inward, colour,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
	var mesh := MeshInstance3D.new()
	mesh.name = "RockShell"
	mesh.mesh = rock.to_mesh()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	gallery.add_child(mesh)
	var walls := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(rock.collision)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	walls.add_child(collision)
	gallery.add_child(walls)

## Where the person arrives in the gallery: a few metres in from the first end, facing along it.
func gallery_entry() -> Transform3D:
	var first: Vector3 = GALLERY_ENDS[0]
	var second: Vector3 = GALLERY_ENDS[1]
	var inward := Vector3(second.x - first.x, 0.0, second.z - first.z).normalized()
	# Clear of the exit trigger at this end, so arriving does not send the person straight back.
	var local_at := first + inward * (EXIT_TRIGGER_INSET + EXIT_TRIGGER_RADIUS + ENTRY_STEP_IN) + Vector3.UP * 0.2
	var forward := gallery.global_transform.basis * inward
	return Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), gallery.global_transform * local_at)

func surface_exit() -> Transform3D:
	var at := global_transform * Vector3(0, 0.3, 4.0)
	return Transform3D(Basis(Vector3.UP, rotation.y), at)

func _on_portal_entered(body: Node3D) -> void:
	if body == person and gallery and _can_travel():
		_set_daylight(false)
		_travel(gallery_entry())

func _on_gallery_exit_entered(body: Node3D) -> void:
	if body == person and _can_travel():
		_travel(surface_exit())
		_set_daylight(true)

func _can_travel() -> bool:
	return Time.get_ticks_msec() - _last_trip_msec > TRIP_COOLDOWN_MSEC and person.visible

func _travel(target: Transform3D) -> void:
	_last_trip_msec = Time.get_ticks_msec()
	person.global_transform = target
	person.velocity = Vector3.ZERO
	person.reset_physics_interpolation()

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

static func _solid(at: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body
