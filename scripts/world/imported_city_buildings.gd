extends Node3D
## User-created exterior models. Geographic positions come from the bundled place catalogue.
## Dimensions and appearance remain photo-based approximations.
const DEFINITIONS := [
	{"slug":"srinivasa_theatre", "place":"Srinivasa Theatre"},
	{"slug":"mythri_rajesh_theatre", "place":"rajesh theatre", "map_point": Vector2(-750.0, -665.0), "face_point": Vector2(-726.0, -679.9)},
	{"slug":"sai_leela_residency", "place":"Hotel Sai Leela Residency"},
	{"slug":"destination_dine_in", "place":"Destination Family Restaurant"},
	{"slug":"godavarikhani_bus_station", "place":"TGSRTC  Bus Station , Godavarikhani", "lon":79.5082894,"lat":18.7601255},
	{"slug":"stadium_with_swimming_pool", "place":"JAWAHARLAL NEHRU STADIUM STAGE", "lon":79.51853, "lat":18.7431, "scale":1.0}
]
const SOFA_SCENE := preload("res://assets/models/props/furniture/sofa_modular.glb")
const POOL_SCENE := preload("res://assets/models/environment/pool/swimming_pool_luxury.glb")
var placements: Array[Dictionary] = []
var instance_count := 0

func prepare(data: MapData) -> void:
	name = "ImportedCityBuildings"
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/places/godavarikhani_places.json"))
	for definition: Dictionary in DEFINITIONS:
		var location: Dictionary = definition if definition.has("lon") else {}
		for place: Dictionary in catalogue.places:
			if str(place.name).to_lower() == str(definition.place).to_lower():
				location = place
				break
		if location.is_empty(): continue
		var point := GeoProjection.lon_lat_to_map(float(location.lon), float(location.lat))
		var polygon := PackedVector2Array()
		var best := 45.0
		for building: Dictionary in data.buildings:
			var points: PackedVector2Array = building.points
			if Geometry2D.is_point_in_polygon(point, points):
				polygon = points
				break
			var center := Vector2.ZERO
			for p in points: center += p
			center /= points.size()
			var distance := center.distance_to(point)
			if distance < best:
				best = distance
				polygon = points
		# Never replace an arbitrary block when the mapped location has no nearby footprint.
		if polygon.is_empty():
			push_warning("No footprint match for " + str(definition.place))
			continue
		var center := Vector2.ZERO
		for p in polygon: center += p
		center /= polygon.size()
		var placement_point: Vector2 = definition.get("map_point", center)
		placements.append({
			"slug": definition.slug,
			"name": definition.place,
			"point": placement_point,
			"polygon": polygon,
			"face_point": definition.get("face_point", null),
			"scale": definition.get("scale", null)
		})

func excludes(points: PackedVector2Array) -> bool:
	for placement in placements:
		var polygon: PackedVector2Array = placement.polygon
		if points == polygon: return true
	return false

func build(world: Node) -> void:
	for placement in placements:
		var slug: String = placement.slug
		var path := "res://assets/models/city_buildings/" + slug + "/" + slug + ".glb"
		var packed := load(path) as PackedScene
		if packed == null: continue
		var model := packed.instantiate() as Node3D
		var anchor := Node3D.new()
		anchor.name = slug
		add_child(anchor)
		anchor.add_child(model)
		var bounds := _bounds(model)
		var center: Vector2 = placement.point
		var yaw := 0.0
		if placement.get("face_point") != null:
			var toward: Vector2 = (placement.face_point as Vector2) - center
			# Blender front -Y exports to Godot +Z.
			yaw = atan2(toward.x, toward.y)
		else:
			var road: Dictionary = world.signage._nearest_road(center, 150.0)
			if not road.is_empty():
				var toward: Vector2 = (road.point as Vector2) - center
				# Blender front -Y exports to Godot +Z.
				yaw = atan2(toward.x, toward.y)
		var local_min := Vector2(INF, INF)
		var local_max := Vector2(-INF, -INF)
		var poly_center := Vector2.ZERO
		for p: Vector2 in placement.polygon: poly_center += p
		poly_center /= maxf(float(placement.polygon.size()), 1.0)
		for p: Vector2 in placement.polygon:
			var local := (p - poly_center).rotated(yaw)
			local_min = local_min.min(local)
			local_max = local_max.max(local)
		var size := local_max - local_min
		var factor: float = float(placement.scale) if placement.get("scale") != null else clampf(minf(size.x / maxf(bounds.size.x, 0.1), size.y / maxf(bounds.size.z, 0.1)) * 0.94, 0.15, 2.5)
		model.scale = Vector3.ONE * factor
		model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
		anchor.rotation.y = yaw
		anchor.position = GeoProjection.map_to_world(center, world.ground_height(center))
		anchor.set_meta("placement_source", "Bundled OSM/Overture catalogue; nearest footprint fit")
		anchor.set_meta("photo_dimensions_estimated", true)
		_collision_and_visibility(model)
		if slug == "sai_leela_residency" or slug == "destination_dine_in":
			_place_lobby_sofas(anchor, factor)
		if slug == "sai_leela_residency":
			_place_courtyard_pool(anchor, factor)
		instance_count += 1
	print("Imported city buildings placed: ", instance_count)

func _place_lobby_sofas(parent: Node3D, factor: float) -> void:
	if SOFA_SCENE == null: return
	var sofa := SOFA_SCENE.instantiate() as Node3D
	sofa.name = "LobbySofaSet"
	sofa.position = Vector3(1.8 * factor, 0.05, 1.2 * factor)
	sofa.rotation.y = PI
	sofa.scale = Vector3.ONE * clampf(factor, 0.85, 1.05)
	_collision_and_visibility(sofa)
	parent.add_child(sofa)

func _place_courtyard_pool(parent: Node3D, factor: float) -> void:
	if POOL_SCENE == null: return
	var pool := POOL_SCENE.instantiate() as Node3D
	pool.name = "CourtyardSwimmingPool"
	# Position in the rear courtyard patio behind Hotel Sai Leela
	pool.position = Vector3(0.0, 0.02, -16.0 * factor)
	pool.rotation.y = 0.0
	pool.scale = Vector3.ONE * clampf(factor, 0.90, 1.10)
	_collision_and_visibility(pool)

	# Water volume Area3D for player swimming detection
	var water_area := Area3D.new()
	water_area.name = "PoolWaterVolume"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 1.4, 8.0) * pool.scale.x
	col.shape = box
	col.position = Vector3(0.0, -0.7, 0.0)
	water_area.add_child(col)
	pool.add_child(water_area)

	parent.add_child(pool)

func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var transform := root.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _collision_and_visibility(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visibility_range_end = 450.0 if OS.has_feature("mobile") else 900.0
		if mesh.mesh != null:
			mesh.create_trimesh_collision()
