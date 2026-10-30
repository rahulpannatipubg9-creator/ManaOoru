class_name GodavariBridgeBuilder
extends Node3D

## Procedurally places the 1,100 m Godavari River Bridge digital twin across the
## Godavari River floodplain at the northern terminus of Rajiv Rahadari / 4-lane trunk highway.
##
## The bridge sits past the north edge of the city's terrain (z = -3,120 m), so this builder also makes
## the river valley around it: a land strip from the terrain edge to the south abutment, banks down to the
## river, the water, and a north landing with a turnaround. The model's own river terrain, water, bank trees
## and rock islands are dropped: they were laid out around the bridge, not the city, and buried the north
## of Godavarikhani under a sheet 5 m above the ground. add_to_map() puts the approach, deck and
## turnaround into the road network so the map, minimap and GPS route onto the bridge.

const BRIDGE_SCENE := "res://Godavarikhani_Bridge_3D/Godavarikhani_Bridge.glb"

## Surveyed highway junction terminus from OSM (Way 817699107 & Way 1320685007)
const ABUTMENT_X := 757.87
const ABUTMENT_Z := -3286.52
const HEADING_DEG := -4.57
const ROAD_LAYER := 2
## The two one-way trunk carriageways that lead to the bridge. They run past the 3 km playable radius,
## so MapData keeps them whole instead of clipping them at the radius.
const APPROACH_WAYS := [817699107, 1320685007]
const BRIDGE_LENGTH := 1100.0
## Road deck top in the model (Blender z / Godot y).
const DECK_LOCAL_TOP := 11.41
## Carriageway centres either side of the bridge axis (model decks span 1.5-12 m off the axis).
const LANE_OFFSET := 6.75
## River valley layout (map z, metres). The city terrain ends at TERRAIN_EDGE_Z; TerrainData.height_at
## clamps there, so every height north of it is the terrain's north-edge profile E(x).
const TERRAIN_EDGE_Z := -3120.0
const SOUTH_LAND_Z := -3292.0
const NORTH_LAND_Z := -4380.0
const NORTH_LIMIT_Z := -4700.0
const BANK_RUN := 60.0
const VALLEY_HALF_WIDTH := 3120.0
const VALLEY_STEP := 15.0

var bridge_instance: Node3D
var spawn_spot: Dictionary = {}

static func forward2() -> Vector2:
	var heading := deg_to_rad(HEADING_DEG)
	return Vector2(sin(heading), -cos(heading))

## Right of the direction of travel (east when heading north).
static func right2() -> Vector2:
	var f := forward2()
	return Vector2(-f.y, f.x)

static func south_end() -> Vector2:
	return Vector2(ABUTMENT_X, ABUTMENT_Z)

static func north_end() -> Vector2:
	return south_end() + forward2() * BRIDGE_LENGTH

## Approach, deck and turnaround roads, a closing barrier at the north edge and the river (for the map).
## Deck pieces carry "structure": "bridge": they route and draw on the map, but RoadBuilder does not
## pave them (the model is the road surface there).
static func add_to_map(data: MapData) -> void:
	var nb_end := {}
	var sb_start := {}
	for road: Dictionary in data.roads:
		if road.way_id == APPROACH_WAYS[0]:
			nb_end = {"id": road.node_ids[road.node_ids.size() - 1], "point": road.points[road.points.size() - 1]}
		elif road.way_id == APPROACH_WAYS[1]:
			sb_start = {"id": road.node_ids[0], "point": road.points[0]}
	if nb_end.is_empty() or sb_start.is_empty():
		push_warning("Godavari bridge approach roads are missing from the map data")
		return
	var f := forward2()
	var r := right2()
	var nb_s := south_end() - r * LANE_OFFSET
	var nb_n := nb_s + f * BRIDGE_LENGTH
	var sb_s := south_end() + r * LANE_OFFSET
	var sb_n := sb_s + f * BRIDGE_LENGTH
	# Left-hand traffic: northbound keeps to the west deck, southbound to the east one. The few metres from
	# where OSM ends to the deck are paved like the approach; the decks themselves are the model's surface.
	data.roads.append(_road(-904, "", 1, PackedInt64Array([nb_end.id, -9001]),
		PackedVector2Array([nb_end.point, nb_s]), ""))
	data.roads.append(_road(-901, "Godavari River Bridge", 1, PackedInt64Array([-9001, -9002]),
		PackedVector2Array([nb_s, nb_n]), "bridge"))
	data.roads.append(_road(-902, "Godavari River Bridge", 1, PackedInt64Array([-9003, -9004]),
		PackedVector2Array([sb_n, sb_s]), "bridge"))
	data.roads.append(_road(-905, "", 1, PackedInt64Array([-9004, sb_start.id]),
		PackedVector2Array([sb_s, sb_start.point]), ""))
	# A loop on the north landing joins the decks so traffic and GPS routes can turn back.
	var mid := (nb_n + sb_n) * 0.5
	var loop := PackedVector2Array([nb_n, nb_n + f * 25.0])
	for step in range(0, 9):
		var angle := PI - PI * step / 8.0
		loop.append(mid + f * 40.0 + r * cos(angle) * 16.0 + f * sin(angle) * 14.0)
	loop.append(sb_n + f * 25.0)
	loop.append(sb_n)
	var loop_ids := PackedInt64Array([-9002])
	for index in range(1, loop.size() - 1):
		loop_ids.append(-9100 - index)
	loop_ids.append(-9003)
	data.roads.append(_road(-903, "Godavari Bridge North Turnaround", 1, loop_ids, loop, ""))
	data.barriers.append({"kind": "jersey_barrier", "points": PackedVector2Array([
		Vector2(-VALLEY_HALF_WIDTH + 5.0, NORTH_LIMIT_Z + 3.0), Vector2(VALLEY_HALF_WIDTH - 5.0, NORTH_LIMIT_Z + 3.0)])})
	data.areas.append({"kind": "water", "name": "Godavari River", "structure": "river", "points": channel_ring()})

## Screenshot-guided dry-season outline; metres anchored to the existing OSM bridge.
## This is an approximate reconstruction, not surveyed shoreline geometry.
static func channel_south(x: float) -> float:
	return SOUTH_LAND_Z - 115.0 - 55.0 * sin((x - ABUTMENT_X) / 420.0)

static func channel_north(x: float) -> float:
	return channel_south(x) - 240.0 - 65.0 * sin((x - ABUTMENT_X) / 570.0 + 0.8)

static func channel_ring() -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in range(105):
		var x := -VALLEY_HALF_WIDTH + i * 60.0
		ring.append(Vector2(x, channel_south(x)))
	for i in range(104, -1, -1):
		var x := -VALLEY_HALF_WIDTH + i * 60.0
		ring.append(Vector2(x, channel_north(x)))
	return ring

static func _road(way_id: int, road_name: String, oneway: int, ids: PackedInt64Array, points: PackedVector2Array,
		structure: String) -> Dictionary:
	return {"way_id": way_id, "kind": "trunk", "name": road_name, "oneway": oneway, "junction": "", "lanes": 2,
		"node_ids": ids, "points": points, "structure": structure}

func build(world: Node, data: MapData) -> void:
	name = "GodavariBridge"
	if not ResourceLoader.exists(BRIDGE_SCENE):
		push_warning("Godavari bridge asset missing at: " + BRIDGE_SCENE)
		return

	var packed := load(BRIDGE_SCENE) as PackedScene
	if not packed:
		return
	bridge_instance = packed.instantiate() as Node3D
	# The .glb carries the Blender scene's sun lamps (Sun_KeyLight 3,551, Sun_FillLight 956 in Blender's W/m²).
	# In Godot a directional light lights the whole world, so they turned every surface white; the city's own
	# sun and environment light the bridge.
	for light in bridge_instance.find_children("*", "Light3D", true, false):
		light.get_parent().remove_child(light)
		light.free()
	for mesh in bridge_instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String(mesh.name)
		for dropped in ["Godavari_River_Terrain", "Godavari_River_WaterSurface", "BankTree", "RockIsland"]:
			if mesh_name.begins_with(dropped):
				mesh.queue_free()
		# The abutment blocks stood 0.8 m above the deck (12.2 m vs 11.41 m) with no collision, so cars drove
		# through a slab at each end; their top now meets the road.
		if mesh_name.begins_with("Abutment_"):
			mesh.scale.y *= (DECK_LOCAL_TOP - 0.03) / 12.2

	# Each end of the deck meets the road at the ground height there; the deck pitches the tiny difference
	# (about 1 m over 1.1 km) so neither end has a step.
	var south := south_end()
	var north := north_end()
	var south_h: float = world.ground_height(south)
	var north_h: float = world.ground_height(north)
	# The model's +X end is the Godavarikhani abutment: it faces the city (south), so -X points along the
	# heading. (rotation 90° + heading laid it 9° off the road and left the south end 88 m to the west.)
	var yaw := -PI * 0.5 - deg_to_rad(HEADING_DEG)
	var pitch := atan2(south_h - north_h, BRIDGE_LENGTH)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	var middle := (south + north) * 0.5
	var deck_middle := Vector3(middle.x, (south_h + north_h) * 0.5, middle.y)
	bridge_instance.transform = Transform3D(basis, deck_middle - basis * Vector3(0.0, DECK_LOCAL_TOP, 0.0))

	_apply_bridge_materials(bridge_instance)
	_setup_collisions(bridge_instance)
	add_child(bridge_instance)
	_build_river_valley(world, south_h - DECK_LOCAL_TOP)
	# The river area (add_to_map) is for the map and the swim/boat surface: give it the real water level,
	# or WaterSystem drapes a translucent sheet at ground height + 1.5 m, which is right over the deck.
	for area: Dictionary in data.areas:
		if area.get("structure", "") == "river":
			area["surface_y"] = south_h - DECK_LOCAL_TOP

	# Register landmark on minimap and GPS catalog
	data.landmarks.append({
		"name": "Godavari River Bridge",
		"category": "Bridge",
		"position": Vector2(ABUTMENT_X, ABUTMENT_Z)
	})

	# Pre-calculated spawn spot at the bridge approach (Northbound lane)
	var spawn_pos := Vector3(ABUTMENT_X - 6.7, south_h + 0.3, ABUTMENT_Z + 15.0)
	spawn_spot = {
		"position": spawn_pos,
		"yaw": deg_to_rad(HEADING_DEG),
		"name": "Godavari River Bridge"
	}

	print("Godavari River Bridge placed from ", south, " to ", north, " (deck ", south_h, " -> ", north_h, ")")

## Land north of the terrain edge: a strip from the edge to just under the south abutment, a bank down to
## the river, the river, a bank up to the north landing and the landing itself, across the whole width of the
## terrain. Heights follow the terrain's north-edge profile, which is what TerrainData.height_at returns
## north of the edge, so roads and barriers drape onto it exactly. Water sits where the model had it.
func _build_river_valley(world: Node, water_y: float) -> void:
	var valley := Node3D.new()
	valley.name = "GodavariRiverValley"
	add_child(valley)
	var land := MeshSurface.new()
	var bed_y := water_y - 1.5
	var x := -VALLEY_HALF_WIDTH
	while x < VALLEY_HALF_WIDTH - 0.01:
		var x2 := minf(x + VALLEY_STEP, VALLEY_HALF_WIDTH)
		var e1: float = world.ground_height(Vector2(x, TERRAIN_EDGE_Z))
		var e2: float = world.ground_height(Vector2(x2, TERRAIN_EDGE_Z))
		# rows from south to north: [z, height at x, height at x2]
		var sand_y := water_y + 0.35
		var rows := [[TERRAIN_EDGE_Z, e1, e2], [SOUTH_LAND_Z, e1, e2],
			[channel_south(x) + 25.0, sand_y, sand_y],
			[channel_south(x), bed_y, bed_y], [channel_north(x), bed_y, bed_y],
			[channel_north(x) - 25.0, sand_y, sand_y], [NORTH_LAND_Z + BANK_RUN, sand_y, sand_y],
			[NORTH_LAND_Z, e1, e2], [NORTH_LIMIT_Z, e1, e2]]
		for index in range(1, rows.size()):
			if index == 4:
				continue                                             # under the water: no ground needed
			var a: Array = rows[index - 1]
			var b: Array = rows[index]
			var p1 := Vector3(x, a[1], a[0])
			var za2: float = a[0]
			var zb2: float = b[0]
			if index - 1 in [2, 3]:
				za2 += channel_south(x2) - channel_south(x)
			elif index - 1 in [4, 5]:
				za2 += channel_north(x2) - channel_north(x)
			if index in [2, 3]:
				zb2 += channel_south(x2) - channel_south(x)
			elif index in [4, 5]:
				zb2 += channel_north(x2) - channel_north(x)
			var p2 := Vector3(x2, a[2], za2)
			var p3 := Vector3(x2, b[2], zb2)
			var p4 := Vector3(x, b[1], b[0])
			var normal := (p2 - p1).cross(p4 - p1).normalized()
			if normal.y < 0.0:
				normal = -normal
			land.quad(p1, p2, p3, p4, normal, Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
				Vector2.ZERO, true)
		x = x2
	var body := StaticBody3D.new()
	body.name = "ValleyGround"
	var mesh := MeshInstance3D.new()
	mesh.mesh = land.to_mesh()
	mesh.material_override = _plain(Color("#b2a087"), 1.0)
	# Same 0.2 m drop as the city terrain mesh so draped roads never z-fight with it.
	mesh.position.y = -0.2
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(land.collision)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	valley.add_child(body)
	var water := MeshInstance3D.new()
	water.name = "GodavariRiverWater"
	var ring := channel_ring()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(ring):
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3(ring[index].x, water_y, ring[index].y))
	water.mesh = surface.commit()
	var water_material := _plain(Color("#183d40"), 0.22)
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	valley.add_child(water)
	_build_ghat_and_fields(valley, world, water_y)

## Approximate ghat west of the south approach, as visible in the supplied satellite screenshot.
## No unverified temple/shop identities or building heights are inferred from the image.
func _build_ghat_and_fields(parent: Node3D, world: Node, water_y: float) -> void:
	var gx := ABUTMENT_X - 145.0
	var gz := SOUTH_LAND_Z + 10.0
	var top: float = world.ground_height(Vector2(gx, gz))
	var end_z := channel_south(gx) - 2.0
	var count := maxi(24, int(ceil((top - water_y) / 0.18)))
	var tread := (gz - end_z) / count
	for i in range(count):
		var y := lerpf(top, water_y + 0.08, float(i) / (count - 1))
		_box(parent, "GhatStep_%02d" % i, Vector3(gx, y - 0.3, gz - (i + 0.5) * tread),
			Vector3(65.0, 0.6, tread + 0.04), Color("#9c9486"), true)
	_box(parent, "GhatUpperPromenade", Vector3(gx, top - 0.25, gz + 6.0), Vector3(84, 0.5, 12), Color("#b0a393"), true)
	# Sparse visual parcels on the two land strips; keep clear of highway approaches.
	for bank_z in [TERRAIN_EDGE_Z - 65.0, NORTH_LIMIT_Z + 120.0]:
		for i in range(26):
			var x := -2300.0 + i * 180.0
			if absf(x - ABUTMENT_X) < 210.0:
				continue
			var y: float = world.ground_height(Vector2(x, bank_z))
			var color := Color("#344638") if i % 3 else Color("#676449")
			_box(parent, "FieldParcel", Vector3(x, y - 0.1, bank_z), Vector3(166, 0.12, 110), color, false)

func _box(parent: Node3D, label: String, center: Vector3, size: Vector3, color: Color, collide: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _plain(color, 0.95)
	visual.position = center
	parent.add_child(visual)
	if collide:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		visual.add_child(body)

## The city ground shader colours by the ESA land-cover raster, which ends with the terrain: north of the
## edge it smeared the edge row into stripes (river-blue among them). The valley uses the same shader and
## textures with a single class: cropland, the commonest cover along the north edge.
const VALLEY_LAND_COVER := 40

static func _valley_ground_material(world: Node) -> Material:
	var material: Material = world._ground_material() if world.has_method("_ground_material") else null
	if material is ShaderMaterial:
		var cover := Image.create_from_data(1, 1, false, Image.FORMAT_R8, PackedByteArray([VALLEY_LAND_COVER]))
		(material as ShaderMaterial).set_shader_parameter("landcover", ImageTexture.create_from_image(cover))
		return material
	return _plain(Color("#8f7f62"), 1.0)

static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _setup_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.name.begins_with("COL_"):
			var static_body := StaticBody3D.new()
			static_body.name = child.name + "_Static"
			static_body.transform = child.transform
			var is_road := child.name.begins_with("COL_Road")
			# Road surfaces collide on Layer 1 (vehicle/player) and Layer 2 (road surface query)
			static_body.collision_layer = 1 | (1 << (ROAD_LAYER - 1)) if is_road else 1
			static_body.collision_mask = 0
			var col_shape := CollisionShape3D.new()
			col_shape.shape = child.mesh.create_trimesh_shape()
			static_body.add_child(col_shape)
			child.get_parent().add_child(static_body)
			child.visible = false
		else:
			_setup_collisions(child)

func _apply_bridge_materials(root: Node) -> void:
	var mat_asphalt := StandardMaterial3D.new()
	mat_asphalt.resource_name = "Road_Asphalt"
	mat_asphalt.albedo_color = Color(0.11, 0.11, 0.12)
	mat_asphalt.roughness = 0.86
	mat_asphalt.metallic = 0.02

	var mat_marking := StandardMaterial3D.new()
	mat_marking.resource_name = "Road_Marking_White"
	mat_marking.albedo_color = Color(0.94, 0.94, 0.91)
	mat_marking.roughness = 0.42

	var mat_deck := StandardMaterial3D.new()
	mat_deck.resource_name = "Concrete_Deck"
	mat_deck.albedo_color = Color(0.62, 0.61, 0.58)
	mat_deck.roughness = 0.76

	var mat_pier := StandardMaterial3D.new()
	mat_pier.resource_name = "Concrete_Pier"
	mat_pier.albedo_color = Color(0.58, 0.57, 0.54)
	mat_pier.roughness = 0.82

	var mat_footing := StandardMaterial3D.new()
	mat_footing.resource_name = "Concrete_Footing"
	mat_footing.albedo_color = Color(0.46, 0.45, 0.40)
	mat_footing.roughness = 0.90

	var mat_steel := StandardMaterial3D.new()
	mat_steel.resource_name = "Steel_Galvanized"
	mat_steel.albedo_color = Color(0.76, 0.77, 0.78)
	mat_steel.metallic = 0.95
	mat_steel.roughness = 0.28

	var mat_water := StandardMaterial3D.new()
	mat_water.resource_name = "River_Water"
	mat_water.albedo_color = Color(0.04, 0.20, 0.24, 0.90)
	mat_water.roughness = 0.08
	mat_water.metallic = 0.05
	mat_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mat_sand := StandardMaterial3D.new()
	mat_sand.resource_name = "River_Sand"
	mat_sand.albedo_color = Color(0.69, 0.55, 0.38)
	mat_sand.roughness = 0.92

	var mat_rock := StandardMaterial3D.new()
	mat_rock.resource_name = "River_Rock"
	mat_rock.albedo_color = Color(0.40, 0.30, 0.24)
	mat_rock.roughness = 0.80

	var mat_foliage := StandardMaterial3D.new()
	mat_foliage.resource_name = "Foliage_Green"
	mat_foliage.albedo_color = Color(0.18, 0.34, 0.12)
	mat_foliage.roughness = 0.65

	var mat_pole := StandardMaterial3D.new()
	mat_pole.resource_name = "Streetlight_Paint"
	mat_pole.albedo_color = Color(0.22, 0.24, 0.26)
	mat_pole.metallic = 0.85
	mat_pole.roughness = 0.38

	var mat_led := StandardMaterial3D.new()
	mat_led.resource_name = "Streetlight_LED"
	mat_led.albedo_color = Color(1.0, 0.98, 0.92)
	mat_led.emission_enabled = true
	mat_led.emission = Color(1.0, 0.95, 0.88)
	mat_led.emission_energy_multiplier = 4.0

	var mat_bearing := StandardMaterial3D.new()
	mat_bearing.resource_name = "Neoprene_Bearing"
	mat_bearing.albedo_color = Color(0.10, 0.10, 0.10)
	mat_bearing.roughness = 0.85

	var mat_map: Dictionary = {
		"Road_Asphalt": mat_asphalt,
		"Road_Marking_White": mat_marking,
		"Road_Marking_Yellow": mat_marking,
		"Concrete_Deck": mat_deck,
		"Concrete_Pier": mat_pier,
		"Concrete_Footing": mat_footing,
		"Steel_Galvanized": mat_steel,
		"River_Water": mat_water,
		"River_Sand": mat_sand,
		"River_Rock": mat_rock,
		"Foliage_Green": mat_foliage,
		"Streetlight_Paint": mat_pole,
		"Streetlight_LED": mat_led,
		"Neoprene_Bearing": mat_bearing
	}
	_assign_surface_materials(root, mat_map)

func _assign_surface_materials(node: Node, mat_map: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for surface in mi.mesh.get_surface_count():
				var orig_mat := mi.mesh.surface_get_material(surface)
				var mat_name := ""
				if orig_mat:
					mat_name = orig_mat.resource_name
				if mat_map.has(mat_name):
					mi.set_surface_override_material(surface, mat_map[mat_name])
				else:
					var n := mi.name.to_lower()
					if n.contains("asphalt"):
						mi.set_surface_override_material(surface, mat_map["Road_Asphalt"])
					elif n.contains("line") or n.contains("dash"):
						mi.set_surface_override_material(surface, mat_map["Road_Marking_White"])
					elif n.contains("rail") or n.contains("joint"):
						mi.set_surface_override_material(surface, mat_map["Steel_Galvanized"])
					elif n.contains("pier") or n.contains("shaft"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Pier"])
					elif n.contains("footing"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Footing"])
					elif n.contains("water"):
						mi.set_surface_override_material(surface, mat_map["River_Water"])
					elif n.contains("terrain") or n.contains("sand"):
						mi.set_surface_override_material(surface, mat_map["River_Sand"])
					elif n.contains("rock"):
						mi.set_surface_override_material(surface, mat_map["River_Rock"])
					elif n.contains("tree") or n.contains("foliage"):
						mi.set_surface_override_material(surface, mat_map["Foliage_Green"])
					elif n.contains("pole"):
						mi.set_surface_override_material(surface, mat_map["Streetlight_Paint"])
					elif n.contains("lamp") or n.contains("head"):
						mi.set_surface_override_material(surface, mat_map["Streetlight_LED"])
					elif n.contains("bearing"):
						mi.set_surface_override_material(surface, mat_map["Neoprene_Bearing"])
					elif n.contains("deck") or n.contains("girder") or n.contains("barrier") or n.contains("diaphragm") or n.contains("cap") or n.contains("strut") or n.contains("abutment"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Deck"])

	for child in node.get_children():
		_assign_surface_materials(child, mat_map)
