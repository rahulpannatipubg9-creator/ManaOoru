class_name World
extends Node3D

## Builds Godavarikhani from the bundled map data. Roads, buildings, parks,
## barriers, railways and signage all come from real data (see MapData); the
## gameplay pieces (spawn, parked cars, pedestrians, coins) are placed on real
## roadsides around the Chowrastha junction at start-up.

## Fraction 0 to 1 of a staged build, with a short label when the work changes.
signal progress(fraction: float, label: String)
signal built

## Set before the world enters the tree to build in stages with frames free between them.
## Off by default: tests and tools expect a finished world when _ready returns.
static var async_build := false
## True from the start of a staged build until `built`.
var building := false

const TERRAIN_CHUNK_CELLS := 32
## ESA WorldCover land cover (see tools/import_landcover.py) that picks each spot's ground texture.
const LANDCOVER_PATH := "res://data/landcover/godavarikhani_landcover"
const SPAWN_CENTER := Vector2.ZERO
## Preload the first reconstruction target as well as the player spawn. The
## source data contains its house footprints, but background streaming could
## leave the district looking empty while a player arrives there.
const VIDYA_NAGAR_2_CENTER := Vector2(315.60, -334.57)
const VIDYA_NAGAR_2_PRELOAD_RADIUS := 450.0
const PARKED_VEHICLE_SPACING := 30.0
const COIN_COUNT := 10
const SPOT_SEARCH_RADIUS := 600.0
const FOUNTAIN_SCENE := "res://assets/models/fountain/fountain_jets.glb"
const FOUNTAIN_PARK := "Dr.B.R. Ambedkar Park"
## The mapped "OCP 5 Incline" mine point (OSM), map coordinates.
const COAL_GALLERY_NEAR := Vector2(1543.0, 1388.0)

const ImportedCityBuildings := preload("res://scripts/world/imported_city_buildings.gd")
var imported_city_buildings: Node3D

var map_data: MapData
var roads: RoadBuilder
var buildings: BuildingBuilder
var signage: SignageBuilder
## Footprints of the buildings that exist in 3D, so the minimap shows exactly what exists.
var rendered_building_footprints: Array[PackedVector2Array] = []
## Roadside placements chosen at start-up. Each: {position: Vector3, yaw: float}
var player_spawn: Dictionary = {}
var vehicle_spawns: Array[Dictionary] = []
## Clear ground beside, never on, the Chowrastha road network for the helicopter.
var helicopter_spawn: Dictionary = {}
var _coin_material: StandardMaterial3D
var fountain_jets: Node3D
var coal_mine: CoalMine
var trees: TreeBuilder
var street_life: StreetLifeBuilder
var birds: BirdFlock
var water_infrastructure: WaterInfrastructure
var bus_station: BusStationBuilder
var billboards: BillboardBuilder
var cctv: CctvBuilder
var traffic: TrafficBuilder
var local_activity: LocalActivityBuilder
var godavari_bridge: GodavariBridgeBuilder
const RoadsideDrainage := preload("res://scripts/world/roadside_drainage_builder.gd")
var drainage: Node3D

func _ready() -> void:
	if async_build:
		_begin_staged_build()
	await _stage(0.01, "Reading the map")
	map_data = MapData.load_shared()
	if not map_data.is_valid:
		_finish_build()
		return
	await _stage(0.05, "Shaping the ground")
	_create_ground()
	await _stage(0.15, "Laying roads")
	roads = RoadBuilder.new()
	add_child(roads)
	roads.build(map_data)
	await _stage(0.25, "Placing buildings")
	buildings = BuildingBuilder.new()
	add_child(buildings)
	imported_city_buildings = ImportedCityBuildings.new()
	add_child(imported_city_buildings)
	imported_city_buildings.prepare(map_data)
	var lane_clearance := preload("res://scripts/world/vidya_lane_clearance.gd").new()
	lane_clearance.prepare(map_data)
	await _stage(0.3)
	buildings.setup(map_data, func(points: PackedVector2Array) -> bool: return imported_city_buildings.excludes(points) or lane_clearance.excludes(points))
	print("Vidyanagar 2 road clearance: %d conflicting building footprints omitted from rendering/collision" % lane_clearance.excluded_count)
	rendered_building_footprints = buildings.footprints
	var graphics = preload("res://scripts/performance/graphics_settings.gd").new()
	graphics.load_from()
	buildings.stream_radius = graphics.values.distance
	await _stage(0.35)
	buildings.build_around(SPAWN_CENTER, minf(300.0, graphics.values.distance))
	await _stage(0.45, "Putting up signs")
	signage = SignageBuilder.new()
	add_child(signage)
	signage.build(map_data, buildings)
	await _stage(0.5, "Raising landmarks")
	imported_city_buildings.build(self)
	await _stage(0.55)
	_create_water_infrastructure()
	await _stage(0.57)
	_create_bus_station()
	await _stage(0.59)
	_create_billboards()
	await _stage(0.6)
	_create_cctv()
	await _stage(0.61)
	_create_fountain()
	await _stage(0.62)
	_create_coal_gallery()
	await _stage(0.64)
	_create_godavari_bridge()
	await _stage(0.68, "Opening the streets")
	_choose_spawns()
	await _stage(0.7)
	street_life = StreetLifeBuilder.new()
	add_child(street_life)
	street_life.build(self, map_data)
	await _stage(0.76)
	add_child(preload("res://scripts/world/vidya_nagar_one_entrance.gd").build(self))
	add_child(preload("res://scripts/world/vidya_nagar_one_entrance.gd").build(self, 2, Vector2(79.5163817,18.7549674), Vector2(79.5151192,18.7559943)))
	await _stage(0.78)
	var vn2_street := preload("res://scripts/world/vidya_nagar_two_street_builder.gd").new()
	add_child(vn2_street)
	vn2_street.build(self, map_data)
	await _stage(0.82, "Planting trees")
	_create_trees()
	await _stage(0.88, "Waking the town")
	_create_birds()
	_create_pedestrians()
	await _stage(0.9)
	_create_local_activity()
	await _stage(0.93)
	_create_traffic()
	await _stage(0.97)
	_create_collectibles()
	# Representative scenery is planned after existing assets/spawns so it yields
	# to gameplay and source-backed placement. No GIS drainage geometry is loaded.
	if "--representative-drainage" in OS.get_cmdline_user_args() and "--no-drainage" not in OS.get_cmdline_user_args():
		drainage = RoadsideDrainage.new()
		add_child(drainage)
		drainage.setup(self, map_data)
		drainage.focus = func() -> Vector2:
			return buildings.focus.call() if buildings.focus.is_valid() else SPAWN_CENTER
	print("Godavarikhani district: %d/%d source roads rendered, %d roads skipped, %d TopoExport roads added (%d duplicates), %d buildings (%d OSM + %d Microsoft + %d Overture), %d signs, %d signals, %d legacy drain segments" %
		[roads.source_rendered_way_count, map_data.source_road_way_count,
		map_data.source_road_way_count - roads.source_rendered_way_count, roads.topoexport_rendered_count,
		roads.topoexport_duplicate_count, rendered_building_footprints.size(),
		map_data.osm_building_count, map_data.microsoft_building_count, map_data.overture_building_count, signage.board_count, signage.signal_count,
		roads.drain_segment_count])
	_finish_build()

## The tree stays paused and the 3D view off, so nothing falls through unbuilt ground and
## the loading screen is all that draws in the frames between stages.
func _begin_staged_build() -> void:
	building = true
	visible = false
	get_tree().paused = true
	get_tree().root.disable_3d = true

## Reports a stage and, in a staged build only, leaves a frame free to draw it. In the
## synchronous path this returns without suspending, so _ready still finishes in one go.
func _stage(fraction: float, label := "") -> void:
	if not building:
		return
	progress.emit(fraction, label)
	await get_tree().process_frame

func _finish_build() -> void:
	if not building:
		return
	building = false
	visible = true
	get_tree().paused = false
	get_tree().root.disable_3d = false
	progress.emit(1.0, "")
	built.emit()

## Real ground relief from the Copernicus DEM: one mesh + trimesh collision per
## chunk of terrain cells, covering the whole district.
func _create_ground() -> void:
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var material := _ground_material()
	var terrain := map_data.terrain
	if not terrain.is_valid:
		push_warning("Terrain data missing; ground will be empty")
		return
	var cells := terrain.size - 1
	for chunk_row in range(0, cells, TERRAIN_CHUNK_CELLS):
		for chunk_col in range(0, cells, TERRAIN_CHUNK_CELLS):
			var surface := MeshSurface.new()
			for row in range(chunk_row, mini(chunk_row + TERRAIN_CHUNK_CELLS, cells)):
				for col in range(chunk_col, mini(chunk_col + TERRAIN_CHUNK_CELLS, cells)):
					# Same diagonal as TerrainData.height_at so placed objects sit exactly on it.
					var v00 := terrain.vertex(row, col)
					var v10 := terrain.vertex(row, col + 1)
					var v01 := terrain.vertex(row + 1, col)
					var v11 := terrain.vertex(row + 1, col + 1)
					for triangle in [[v00, v10, v01], [v11, v01, v10]]:
						var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
						if normal.y < 0.0:
							normal = -normal
						surface.triangle(triangle[0], triangle[1], triangle[2], normal, Color.WHITE,
							Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
			var chunk := StaticBody3D.new()
			chunk.name = "Terrain_%d_%d" % [chunk_row, chunk_col]
			var mesh := MeshInstance3D.new()
			mesh.mesh = surface.to_mesh()
			mesh.material_override = material
			# The visible ground sits 0.2 m below the collision surface so draped roads never z-fight with it.
			mesh.position.y = -0.2
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mesh)
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(surface.collision)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			chunk.add_child(collision)
			ground.add_child(chunk)

## Real ground cover: the land-cover raster goes to the shader as an 8-bit class texture.
func _ground_material() -> Material:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDCOVER_PATH + ".json")) if FileAccess.file_exists(LANDCOVER_PATH + ".json") else null
	var codes := FileAccess.get_file_as_bytes(LANDCOVER_PATH + ".bin")
	if not meta is Dictionary or codes.size() != int(meta.size) * int(meta.size):
		push_warning("Land cover missing; ground drawn in one colour")
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color("#8f7f62")
		plain.roughness = 1.0
		return plain
	var image := Image.create_from_data(int(meta.size), int(meta.size), false, Image.FORMAT_R8, codes)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/ground.gdshader")
	material.set_shader_parameter("landcover", ImageTexture.create_from_image(image))
	material.set_shader_parameter("landcover_origin", Vector2(float(meta.origin_x), float(meta.origin_z)))
	material.set_shader_parameter("landcover_extent", float(meta.size) * float(meta.cell_size))
	material.set_shader_parameter("ground_albedo", preload("res://assets/textures/ground/ground_albedo.jpg"))
	material.set_shader_parameter("ground_normal", preload("res://assets/textures/ground/ground_normal.jpg"))
	material.set_shader_parameter("ground_arm", preload("res://assets/textures/ground/ground_arm.jpg"))
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.generate_mipmaps = true
	noise.normalize = true
	var generator := FastNoiseLite.new()
	generator.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	generator.frequency = 0.02
	generator.fractal_octaves = 3
	noise.noise = generator
	material.set_shader_parameter("noise", noise)
	return material

func ground_height(point: Vector2) -> float:
	return map_data.terrain.height_at(point)

## Roadside points near a centre: just off the carriageway edge, clear of buildings
## and of every other road, spaced apart. Each: {position: Vector2, direction: Vector2}
func roadside_spots(center: Vector2, count: int, edge_offset: float, spacing: float, kinds: Array) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for road in map_data.roads:
		if not road.kind in kinds:
			continue
		var half := RoadStyle.width(road) * 0.5
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			var a := points[index - 1]
			var b := points[index]
			var length := a.distance_to(b)
			if length < 12.0 or a.distance_to(center) > SPOT_SEARCH_RADIUS:
				continue
			var direction := (b - a) / length
			var step := 6.0
			while step < length - 6.0:
				# Left kerb: traffic keeps left in India.
				var spot := a + direction * step - direction.orthogonal() * (half + edge_offset)
				candidates.append({"position": spot, "direction": direction, "distance": spot.distance_to(center)})
				step += 8.0
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.distance < y.distance)
	var chosen: Array[Dictionary] = []
	for candidate in candidates:
		if chosen.size() >= count:
			break
		var position: Vector2 = candidate.position
		var too_close := false
		for existing in chosen:
			if existing.position.distance_to(position) < spacing:
				too_close = true
		# Must stay off every carriageway (including other roads at junctions), not just its own.
		if too_close or not buildings.is_clear(position, 2.4) or _is_on_any_road(position, edge_offset - 0.4):
			continue
		chosen.append(candidate)
	return chosen

func _is_on_any_road(point: Vector2, margin: float) -> bool:
	for road in map_data.roads:
		var half := RoadStyle.width(road) * 0.5 + margin
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			if Geometry2D.get_closest_point_to_segment(point, points[index - 1], points[index]).distance_to(point) < half:
				return true
	for road in map_data.topoexport_roads:
		var half := RoadStyle.width(road) * 0.5 + margin
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			if Geometry2D.get_closest_point_to_segment(point, points[index - 1], points[index]).distance_to(point) < half:
				return true
	return false

func _choose_spawns() -> void:
	var main_kinds := ["secondary", "tertiary", "trunk", "primary", "secondary_link", "unclassified"]
	var spots := roadside_spots(SPAWN_CENTER, 6, 1.4, PARKED_VEHICLE_SPACING, main_kinds)
	if spots.is_empty():
		return
	var first: Dictionary = spots[0]
	var player_point: Vector2 = first.position - first.direction * 6.0
	player_spawn = {"position": GeoProjection.map_to_world(player_point, ground_height(player_point) + 1.2), "yaw": atan2(first.direction.x, first.direction.y)}
	for spot in spots:
		vehicle_spawns.append({"position": GeoProjection.map_to_world(spot.position, ground_height(spot.position) + 1.2), "yaw": atan2(spot.direction.x, spot.direction.y)})
	var aircraft_spots := roadside_spots(SPAWN_CENTER, 1, 14.0, 1.0, main_kinds)
	if not aircraft_spots.is_empty():
		var aircraft: Dictionary = aircraft_spots[0]
		helicopter_spawn = {"position": GeoProjection.map_to_world(aircraft.position, ground_height(aircraft.position) + 1.3), "yaw": atan2(aircraft.direction.x, aircraft.direction.y)}

## The "Singing Fountains" jets from the user's model pack, in a stone pool at the
## centre of Dr. B.R. Ambedkar Park (a mapped park). The fountain itself is decorative:
## no open data says there is one there.
func _create_fountain() -> void:
	if not ResourceLoader.exists(FOUNTAIN_SCENE):
		return
	var park: Dictionary = {}
	for area in map_data.areas:
		if area.name == FOUNTAIN_PARK:
			park = area
	if park.is_empty():
		return
	var ring: PackedVector2Array = park.points
	var center := Vector2.ZERO
	for point in ring:
		center += point
	center /= ring.size()
	var box := BuildingBuilder._oriented_box(ring)
	var axis: Vector2 = box.axis if not box.is_empty() else Vector2.RIGHT
	var fountain := Node3D.new()
	fountain.name = "SingingFountain"
	fountain.position = GeoProjection.map_to_world(center, ground_height(center))
	fountain.rotation.y = -axis.angle()
	add_child(fountain)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#c9c1b0")
	stone.roughness = 0.9
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.25, 0.5, 0.65, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic = 0.2
	var pool := Vector2(12.0, 4.0)
	for wall in [[Vector3(0, 0.3, pool.y * 0.5), Vector3(pool.x + 0.6, 0.6, 0.3)], [Vector3(0, 0.3, -pool.y * 0.5), Vector3(pool.x + 0.6, 0.6, 0.3)],
			[Vector3(pool.x * 0.5, 0.3, 0), Vector3(0.3, 0.6, pool.y)], [Vector3(-pool.x * 0.5, 0.3, 0), Vector3(0.3, 0.6, pool.y)]]:
		fountain.add_child(_solid_box(wall[0], wall[1], stone))
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = pool
	surface.mesh = plane
	surface.material_override = water
	surface.position.y = 0.4
	fountain.add_child(surface)
	var jets: Node3D = (load(FOUNTAIN_SCENE) as PackedScene).instantiate()
	jets.name = "Jets"
	# Bright, slightly glowing spray so the thin decimated jets read from a distance.
	var spray := StandardMaterial3D.new()
	spray.albedo_color = Color(0.9, 0.96, 1.0, 0.85)
	spray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray.emission_enabled = true
	spray.emission = Color(0.55, 0.7, 0.85)
	spray.emission_energy_multiplier = 0.6
	spray.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh in jets.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = spray
	jets.position.y = 0.4
	fountain.add_child(jets)
	fountain_jets = jets

## The user's coal-gallery model as an underground mine below a pit-top portal on the
## nearest road to the mapped "OCP 5 Incline" mine.
func _create_coal_gallery() -> void:
	var person := get_parent().get_node_or_null("Player") as CharacterBody3D if get_parent() else null
	for spot in roadside_spots(COAL_GALLERY_NEAR, 12, 7.0, 10.0, ["secondary", "tertiary", "residential", "unclassified", "service", "track"]):
		var toward_road: Vector2 = (spot.direction as Vector2).orthogonal()
		var behind: Vector2 = spot.position - toward_road * 3.0
		if not buildings.is_clear(behind, 6.5):
			continue
		coal_mine = CoalMine.new()
		add_child(coal_mine)
		coal_mine.build(GeoProjection.map_to_world(spot.position, ground_height(spot.position)), toward_road, person)
		map_data.landmarks.append({"name": CoalMine.DISPLAY_NAME, "category": "Area", "position": spot.position})
		return

func _create_godavari_bridge() -> void:
	godavari_bridge = GodavariBridgeBuilder.new()
	add_child(godavari_bridge)
	godavari_bridge.build(self, map_data)

## Real trees from the canopy-height map, kept off spawns and the coal-gallery portal.
func _create_trees() -> void:
	trees = TreeBuilder.new()
	add_child(trees)
	trees.setup(self, map_data)
	if coal_mine:
		trees.keep_clear(coal_mine.global_position, TreeBuilder.MINE_CLEARANCE)
	if not player_spawn.is_empty():
		trees.keep_clear(player_spawn.position, TreeBuilder.SPAWN_CLEARANCE)
	for spawn in vehicle_spawns:
		trees.keep_clear(spawn.position, TreeBuilder.SPAWN_CLEARANCE)
	for spot in street_life.occupied():
		trees.keep_clear(Vector3(spot.x, 0.0, spot.y), spot.z)
	trees.build_around(SPAWN_CENTER, 250.0)

func _create_birds() -> void:
	birds = BirdFlock.new()
	add_child(birds)
	birds.setup(self)

func _create_water_infrastructure() -> void:
	water_infrastructure = WaterInfrastructure.new()
	add_child(water_infrastructure)
	water_infrastructure.build(self, map_data)

func _create_bus_station() -> void:
	bus_station = BusStationBuilder.new()
	add_child(bus_station)
	bus_station.build(self, map_data)

func _create_billboards() -> void:
	billboards = BillboardBuilder.new()
	add_child(billboards)
	billboards.build(self, map_data)

## Jets rise and fall gently, like a fountain playing to music.
func _process(_delta: float) -> void:
	if fountain_jets:
		var time := Time.get_ticks_msec() * 0.001
		fountain_jets.scale.y = 0.85 + 0.15 * sin(time * 1.3) * sin(time * 0.37 + 1.0)

func _solid_box(at: Vector3, size: Vector3, material: Material) -> StaticBody3D:
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

func _create_pedestrians() -> void:
	var pedestrian_scene: PackedScene = preload("res://scenes/world/pedestrian.tscn")
	var spots := roadside_spots(SPAWN_CENTER, 12, 2.6, 20.0, ["secondary", "tertiary", "residential", "unclassified"])
	for index in spots.size():
		var pedestrian := pedestrian_scene.instantiate()
		pedestrian.name = "Pedestrian_%02d" % (index + 1)
		pedestrian.position = GeoProjection.map_to_world(spots[index].position, ground_height(spots[index].position))
		pedestrian.ground_sampler = pedestrian.sample_world_surface.bind(self)
		pedestrian.sway_offset = float(index) * 0.7
		pedestrian.walk_direction = Vector3(spots[index].direction.x, 0.0, spots[index].direction.y)
		pedestrian.patrol_distance = 8.0 + float(index % 4) * 3.5
		pedestrian.walk_speed = 0.95 + float(index % 3) * 0.12
		var shirts := [Color("#256c4b"), Color("#315c9a"), Color("#a34231"), Color("#79522e"), Color("#5a397d")]
		var skins := [Color("#7d4733"), Color("#a96b4a"), Color("#c98a64"), Color("#6d3f2d")]
		pedestrian.shirt_color = shirts[index % shirts.size()]
		pedestrian.skin_color = skins[index % skins.size()]
		add_child(pedestrian)

func _create_traffic() -> void:
	traffic = TrafficBuilder.new()
	add_child(traffic)
	traffic.build(self, map_data)

func _create_cctv() -> void:
	cctv = CctvBuilder.new()
	add_child(cctv)
	cctv.build(self, map_data)

func _create_local_activity() -> void:
	local_activity = LocalActivityBuilder.new()
	add_child(local_activity)
	local_activity.build(self, map_data, bus_station)

func _create_collectibles() -> void:
	_coin_material = StandardMaterial3D.new()
	_coin_material.albedo_color = Color("#e3b341")
	_coin_material.metallic = 0.6
	_coin_material.roughness = 0.3
	var coin_script := load("res://scripts/world/coin.gd")
	var spots := roadside_spots(SPAWN_CENTER + Vector2(0.0, -150.0), COIN_COUNT, 1.0, 40.0, ["secondary", "tertiary", "residential"])
	for index in spots.size():
		var coin := Area3D.new()
		coin.name = "Coin_%02d" % (index + 1)
		coin.position = GeoProjection.map_to_world(spots[index].position, ground_height(spots[index].position) + 1.0)
		coin.script = coin_script
		coin.collision_layer = 0
		coin.collision_mask = 1
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.55
		cylinder.bottom_radius = 0.55
		cylinder.height = 0.12
		mesh.mesh = cylinder
		mesh.material_override = _coin_material
		coin.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.75
		shape.height = 1.5
		collision.shape = shape
		coin.add_child(collision)
		coin.collected.connect(_on_coin_collected)
		add_child(coin)

func _on_coin_collected() -> void:
	var hud := get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("register_coin_collected"):
		hud.register_coin_collected()
