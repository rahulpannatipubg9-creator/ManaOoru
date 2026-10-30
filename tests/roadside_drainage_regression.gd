extends SceneTree

const Drainage := preload("res://scripts/world/roadside_drainage_builder.gd")

class Buildings extends RefCounted:
	var footprints: Array[PackedVector2Array] = []
	var storefront_allocator := {"units": []}

class Furniture extends RefCounted:
	func occupied() -> Array[Vector3]:
		return []

class Fixture extends Node:
	var buildings := Buildings.new()
	var street_life := Furniture.new()
	var vehicle_spawns: Array[Dictionary] = []
	var player_spawn: Dictionary = {}
	var helicopter_spawn: Dictionary = {}
	var bus_station := {"terminal_entries": []}
	var local_activity := {"shop_entries": []}

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var data := MapData.new()
	data.terrain = TerrainData.new()
	data.terrain.is_valid = false
	data.roads = [{"way_id": 1, "kind": "residential", "lanes": 0, "oneway": 0, "points": PackedVector2Array([Vector2(-80, 0), Vector2(80, 0)])},
		{"way_id": 2, "kind": "secondary", "lanes": 0, "oneway": 0, "points": PackedVector2Array([Vector2(0, -80), Vector2(0, 80)])}]
	var fixture := Fixture.new()
	root.add_child(fixture)
	# A foundation on the verge, one inferred entrance and a protected parked car.
	fixture.buildings.footprints.append(PackedVector2Array([Vector2(35, 3), Vector2(65, 3), Vector2(65, 12), Vector2(35, 12)]))
	fixture.buildings.storefront_allocator.units.append({"entrance": Vector2(-35, 4)})
	fixture.vehicle_spawns.append({"position": Vector3(-60, 0, -4)})
	var builder := Drainage.new()
	root.add_child(builder)
	builder.setup(fixture, data)
	builder.build_all()
	_check(builder.open_count > 0 and builder.covered_count > 0, "Both open residential and covered access sections must be generated")
	_check(builder.rejected_count > 0, "Junctions, foundations and parked cars must exclude unsafe candidates")
	_check(not builder.placement_clear(Vector2(-5, 0), Vector2(5, 0)), "Reject carriageway overlap")
	_check(not builder.placement_clear(Vector2(40, 4), Vector2(60, 4)), "Reject foundations, including segment interiors")
	_check(not builder.placement_clear(Vector2(40, 2), Vector2(60, 2)), "Reject existing shopfront apron space outside the footprint")
	_check(not builder.placement_clear(Vector2(2999.9, 0), Vector2(3001, 0)), "Keep full channel width inside playable area")
	for section: Dictionary in builder.segments:
		_check(section.provenance == "representative_procedural", "Never claim inferred geometry is surveyed")
		for road: Dictionary in data.roads:
			_check(Drainage._segment_distance(section.a, section.b, road.points[0], road.points[1]) >= RoadStyle.width(road) * 0.5 + 1.08 + 0.32 - 0.001, "Full width must clear every road, including intersection approaches")
		if not section.covered:
			_check(Drainage._point_distance(Vector2(-35, 4), section.a, section.b) >= 9.0, "Inferred entrances require covered approaches")
		_check(Drainage._point_distance(Vector2(-60, -4), section.a, section.b) >= 5.32, "Existing vehicle/entry space must remain clear")
	_check(_physics_count(builder) == 0, "Drainage must add no bodies, areas or invisible collision barriers")
	var vertices := _vertex_count(builder)
	var snapshot := builder.segments.duplicate(true)
	builder.setup(fixture, data)
	builder.build_all()
	_check(snapshot == builder.segments and vertices == _vertex_count(builder), "Rebuilding must replace, not duplicate or relocate, generated scenery")
	builder.water_enabled = false
	for child in builder.get_children():
		if child.name.begins_with("Water_"):
			_check(not child.visible, "Water quality switch must hide water meshes")
	builder.enabled = false
	_check(not builder.visible, "Drainage quality switch must hide the complete system")
	builder.free()
	fixture.free()
	if "--full-world" in OS.get_cmdline_user_args():
		await _full_world()
	print("%s roadside drainage: clearance, junctions, access covers, boundaries, no collision, deterministic rebuild, quality switches" % ("PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures else 0)

func _physics_count(node: Node) -> int:
	var result := 1 if node is CollisionObject3D else 0
	for child in node.get_children():
		result += _physics_count(child)
	return result

func _vertex_count(builder: Node) -> int:
	var count := 0
	for child in builder.get_children():
		if child is MeshInstance3D:
			count += child.mesh.surface_get_array_len(0)
	return count

func _full_world() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	var road_snapshot: Array = world.map_data.roads.duplicate(true)
	var footprint_snapshot: Array = world.buildings.footprints.duplicate(true)
	var road_count: int = world.map_data.roads.size()
	var building_count: int = world.buildings.footprints.size()
	var started := Time.get_ticks_msec()
	world.drainage.build_all()
	_check(world.drainage.covered_count > 0 and world.drainage.open_count > 0, "Actual city needs both drainage types")
	_check(world.map_data.roads.size() == road_count and world.buildings.footprints.size() == building_count, "Drainage must preserve road/building data")
	_check(world.map_data.roads == road_snapshot and world.buildings.footprints == footprint_snapshot, "Road and building coordinates must remain byte-for-byte equivalent")
	_check(_physics_count(world.drainage) == 0, "Full world must retain original physics")
	var farthest := 0.0
	for section: Dictionary in world.drainage.segments:
		farthest = maxf(farthest, section.a.length())
	_check(farthest > 2500.0, "Budgeted drainage must reach distant districts, not only the spawn neighbourhood")
	_check(world.drainage.segments.size() <= 12000, "Geometry must respect the desktop section budget")
	print("City drainage: %d sections, %d meshes, %d triangles, generation %d ms (forced build; not FPS)" % [world.drainage.segments.size(), world.drainage.get_child_count(), _vertex_count(world.drainage) / 3, Time.get_ticks_msec() - started])
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(world)
	world.free()

func _capture(world: Node3D) -> void:
	var section: Dictionary = {}
	for candidate: Dictionary in world.drainage.segments:
		if not candidate.covered and candidate.a.length() < 900.0:
			section = candidate
			break
	if section.is_empty():
		section = world.drainage.segments[0]
	var point: Vector2 = (section.a + section.b) * 0.5
	world.buildings.build_around(point, 90.0)
	var camera := Camera3D.new()
	world.add_child(camera)
	var target := Vector3(point.x, world.ground_height(point), point.y)
	var n := Vector3(section.normal.x, 0, section.normal.y)
	var direction := Vector3(section.b.x - section.a.x, 0, section.b.y - section.a.y).normalized()
	camera.position = target - n * 4.5 + direction * 5.0 + Vector3.UP * 4.0
	camera.look_at(target)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#b6d3e0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.85
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -30, 0)
	world.add_child(light)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/mana_ooru_city_drainage.png")
