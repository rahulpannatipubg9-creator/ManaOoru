class_name MapData
extends RefCounted

## Parsed, projected view of all bundled geographic data. Parsed once per run and
## shared by the 3D world, minimap, full map and router. Sources:
## - OSM core extract: roads, OSM buildings, named amenities
## - OSM features extract: shops/amenities, crossings, signals, barriers, rail, parks, water
## - Microsoft Global ML Building Footprints: buildings missing from OSM
## - Optional local overrides for traffic signals not yet mapped in OSM

const DEFAULT_PATH := "res://data/osm/godavarikhani_core.json"
const FEATURES_PATH := "res://data/osm/godavarikhani_features.json"
const MS_BUILDINGS_PATH := "res://data/buildings/godavarikhani_ms_buildings.json"
const OVERTURE_BUILDINGS_PATH := "res://data/buildings/vidya_nagar_2_overture.geojson"
const LOCAL_SIGNALS_PATH := "res://data/local/traffic_signals.json"
## A curated, source-attributed place catalogue generated from OpenStreetMap and
## Overture Maps.  We expose its high-confidence entries around Chowrasta as
## playable labels/pins without guessing a business position from an address.
const REFERENCE_PLACES_PATH := "res://data/places/godavarikhani_places.json"
const LOCAL_REFERENCE_PINS_PATH := "res://data/local/chowrasta_exact_pins.json"
const USER_SHOPS_PATH := "res://data/local/user_shop_overpass.json"
const TOPOEXPORT_ROADS_PATH := "res://data/topoexport/roads.json"
const TOPOEXPORT_TREES_PATH := "res://data/topoexport/trees.json"
const CHOWRASTA_REFERENCE_RADIUS_METERS := 1000.0
const MIN_REFERENCE_CONFIDENCE := 0.95
const DESTINATION_AMENITIES := {
	"bus_station": "Bus station",
	"hospital": "Hospital",
	"police": "Police",
	"theatre": "Theatre",
	"college": "College",
	"school": "School",
	"place_of_worship": "Worship",
	"fuel": "Fuel",
	"bank": "Bank",
	"post_office": "Post office",
	"monument": "Monument",
	"clinic": "Health centre",
	"blood_bank": "Hospital",
}
const MAJOR_ROAD_KINDS := ["trunk", "primary", "secondary", "tertiary"]
## Area kinds drawn on the ground and on the maps.
const AREA_KINDS := {
	"park": "park", "playground": "park", "garden": "park", "pitch": "pitch",
	"stadium": "stadium", "recreation_ground": "park", "grassland": "grass", "water": "water",
	"swimming_pool": "water", "quarry": "quarry",
}
const LANDMARK_DEDUPE_DISTANCE := 60.0
const NAME_KEYWORDS := {
	"school": "school", "college": "college", "hospital": "hospital", "temple": "place_of_worship",
	"masjid": "place_of_worship", "church": "place_of_worship", "statue": "monument",
}

const LocationCatalogData := preload("res://scripts/map/location_catalog.gd")
const SegmentGrid := preload("res://scripts/map/segment_grid.gd")
var location_catalog: RefCounted
var _road_grid: RefCounted
var _osm_road_grid: RefCounted

static var _cache: Dictionary = {}

## Each road piece: {way_id:int, kind:String, name:String, oneway:int, node_ids:PackedInt64Array, points:PackedVector2Array}
## A way is split into pieces wherever it leaves the playable radius, so no piece jumps across the boundary.
var roads: Array[Dictionary] = []
## Supplemental TopoExport roads are kept separate from the named OSM graph.
## They can improve visual/service-lane coverage without creating duplicate GPS
## edges or changing the existing route network.
var topoexport_roads: Array[Dictionary] = []
var topoexport_trees: Array[Dictionary] = []
## Each building: {points:PackedVector2Array, tags:Dictionary, source:"osm"|"microsoft"}
var buildings: Array[Dictionary] = []
## Each landmark: {name:String, category:String, position:Vector2}
var landmarks: Array[Dictionary] = []
## Each POI: {name:String, kind:String, position:Vector2} — real shops/amenities for signboards.
var pois: Array[Dictionary] = []
var crossings := PackedVector2Array()
var level_crossings := PackedVector2Array()
## Named localities/colonies: {name:String, position:Vector2}
var places: Array[Dictionary] = []
## Each signal: {position:Vector2, source:"osm"|"local"}
var traffic_signals: Array[Dictionary] = []
## Polylines: {kind:String, points:PackedVector2Array}
var barriers: Array[Dictionary] = []
var railways: Array[PackedVector2Array] = []
## Polygons: {kind:String, name:String, points:PackedVector2Array}
var areas: Array[Dictionary] = []
## Ground heights (Copernicus DEM) and measured building heights (Google Open Buildings 2.5D).
var terrain: TerrainData
var building_heights: BuildingHeights
var source_road_way_count := 0
var osm_building_count := 0
var microsoft_building_count := 0
var overture_building_count := 0
var topoexport_road_count := 0
var topoexport_tree_count := 0
## High-confidence business pins within the one-kilometre Chowrasta zone.
var chowrasta_reference_pin_count := 0
var user_shop_import_stats: Dictionary = {}
var attribution := ""
var data_timestamp := ""
var is_valid := false

static func load_shared(path := DEFAULT_PATH) -> MapData:
	if not _cache.has(path):
		var data := MapData.new()
		data._load(path)
		_cache[path] = data
	return _cache[path]

## Every segment of every road, TopoExport included. Owners index roads, then topoexport_roads.
func road_grid() -> RefCounted:
	if _road_grid == null:
		_road_grid = SegmentGrid.new()
		_fill_road_grid(_road_grid, roads, 0)
		_fill_road_grid(_road_grid, topoexport_roads, roads.size())
	return _road_grid

## The OSM roads alone. Owners index roads.
func osm_road_grid() -> RefCounted:
	if _osm_road_grid == null:
		_osm_road_grid = SegmentGrid.new()
		_fill_road_grid(_osm_road_grid, roads, 0)
	return _osm_road_grid

static func _fill_road_grid(grid: RefCounted, source: Array[Dictionary], first_owner: int) -> void:
	for road_index in source.size():
		var road: Dictionary = source[road_index]
		var half := RoadStyle.width(road) * 0.5
		var points: PackedVector2Array = road.points
		for index in range(1, points.size()):
			grid.add(points[index - 1], points[index], half, first_owner + road_index)

func _load(path: String) -> void:
	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary:
		push_error("Godavarikhani map data is missing or invalid: %s" % path)
		return
	var osm3s: Dictionary = parsed.get("osm3s", {})
	attribution = str(osm3s.get("copyright", "© OpenStreetMap contributors, ODbL"))
	data_timestamp = str(osm3s.get("timestamp_osm_base", ""))
	var elements: Array = parsed.get("elements", [])
	var nodes := _project_nodes(elements)
	for element in elements:
		var tags: Dictionary = element.get("tags", {})
		match element.get("type"):
			"node":
				_add_landmark(tags, nodes[int(element.get("id"))])
			"way":
				var ids: Array = element.get("nodes", [])
				if tags.has("highway"):
					source_road_way_count += 1
					_add_road_pieces(int(element.get("id")), tags, ids, nodes)
					_add_named_road_landmark(int(element.get("id")), tags)
				elif tags.has("building"):
					var footprint := _ring(ids, nodes)
					if footprint.size() >= 3:
						buildings.append({"points": footprint, "tags": tags, "source": "osm", "osm_id": element.get("id")})
						_add_landmark(tags, _centroid(footprint))
	osm_building_count = buildings.size()
	_load_features()
	_load_chowrasta_reference_places()
	_load_local_chowrasta_pins()
	_load_user_shop_export()
	_load_user_shop_labels()
	_load_microsoft_buildings()
	_load_overture_buildings()
	_load_local_signals()
	_load_topoexport_layers()
	GodavariBridgeBuilder.add_to_map(self)
	location_catalog = LocationCatalogData.new()
	terrain = TerrainData.new()
	building_heights = BuildingHeights.new()
	is_valid = true

func _load_features() -> void:
	var parsed: Variant = _read_json(FEATURES_PATH)
	if not parsed is Dictionary:
		return
	var elements: Array = parsed.get("elements", [])
	var nodes := _project_nodes(elements)
	for element in elements:
		var tags: Dictionary = element.get("tags", {})
		if tags.is_empty():
			continue
		if element.get("type") == "node":
			var point: Vector2 = nodes[int(element.get("id"))]
			if not GeoProjection.is_playable(point):
				continue
			match str(tags.get("highway", "")):
				"crossing":
					crossings.append(point)
				"traffic_signals":
					traffic_signals.append({"position": point, "source": "osm"})
			if tags.get("railway") == "level_crossing":
				level_crossings.append(point)
			if tags.get("place") in ["locality", "neighbourhood", "suburb", "quarter"] and tags.has("name"):
				places.append({"name": _display_name(str(tags.name)), "position": point})
				_add_landmark_entry(_display_name(str(tags.name)), "Area", point)
			# The Singareni residential colonies are mapped as named nodes (for
			# example, "C-8 & C-9 Quarters") rather than formal place polygons.
			# Promote those verified map points into discoverable areas without
			# inventing a boundary around them.
			elif _is_quarters_name(str(tags.get("name", ""))):
				var quarter_name := _display_name(str(tags.name))
				places.append({"name": quarter_name, "position": point})
				_add_landmark_entry(quarter_name, "Area", point)
			_add_poi(tags, point)
			_add_landmark(tags, point)
			continue
		var ids: Array = element.get("nodes", [])
		var line := _line(ids, nodes)
		if line.size() < 2:
			continue
		if tags.get("railway") == "rail":
			railways.append(line)
		elif tags.has("barrier") and tags.barrier in ["jersey_barrier", "wall", "retaining_wall"]:
			barriers.append({"kind": str(tags.barrier), "points": line})
		var area_kind := str(AREA_KINDS.get(tags.get("leisure", tags.get("natural", tags.get("landuse", ""))), ""))
		var ring := _ring(ids, nodes)
		if not area_kind.is_empty() and ring.size() >= 3:
			areas.append({"kind": area_kind, "name": str(tags.get("name", "")), "points": ring})
		if ring.size() >= 3:
			_add_poi(tags, _centroid(ring))
			_add_landmark(tags, _centroid(ring))
			if tags.get("leisure") == "stadium" and tags.has("name"):
				_add_landmark_entry(_display_name(str(tags.name)), "Stadium", _centroid(ring))

## Overpass exports can supply nodes directly and polygon centres via `out
## center`. Keep source tags/IDs and retain existing nearby POIs to avoid signs
## duplicated by overlapping exports. Polygon centres are reference points,
## not measured storefront entrances.
func _load_user_shop_export() -> void:
	var parsed: Variant = _read_json(USER_SHOPS_PATH, false)
	if not parsed is Dictionary:
		return
	user_shop_import_stats = {"added": 0, "existing": 0, "outside": 0, "unsupported": 0}
	for element: Dictionary in parsed.get("elements", []):
		var coordinate: Dictionary = element if element.get("type") == "node" else element.get("center", {})
		var tags: Dictionary = element.get("tags", {})
		var kind := poi_kind(tags)
		if not coordinate.has("lat") or not coordinate.has("lon") or kind.is_empty():
			user_shop_import_stats.unsupported += 1
			continue
		var point := GeoProjection.lon_lat_to_map(float(coordinate.lon), float(coordinate.lat))
		if not GeoProjection.is_playable(point):
			user_shop_import_stats.outside += 1
			continue
		var name := str(tags.get("name", "")).strip_edges()
		var found := false
		for poi in pois:
			if poi.position.distance_to(point) < 40.0 and ((not name.is_empty() and str(poi.name).to_lower() == name.to_lower()) or (name.is_empty() and str(poi.name).is_empty() and poi.kind == kind)):
				found = true
				break
		if found:
			user_shop_import_stats.existing += 1
		else:
			pois.append({"name": name, "kind": kind, "position": point,
				"source": "OpenStreetMap user export", "osm_type": element.get("type"),
				"osm_id": element.get("id"), "tags": tags})
			user_shop_import_stats.added += 1
		if not name.is_empty():
			_add_landmark_entry(name, _reference_landmark_category(kind), point)

## Explicit directory pins approved by the user, across the playable map.
func _load_user_shop_labels() -> void:
	var parsed: Variant = _read_json("res://data/local/user_shop_labels.json", false)
	if not parsed is Dictionary:
		return
	for entry: Dictionary in parsed.get("shops", []):
		var name := str(entry.get("name", "")).strip_edges()
		var point := GeoProjection.lon_lat_to_map(float(entry.lon), float(entry.lat))
		if name.is_empty() or not GeoProjection.is_playable(point):
			continue
		var exists := false
		for poi in pois:
			if str(poi.name).to_lower() == name.to_lower() and poi.position.distance_to(point) < 40.0:
				exists = true
				break
		if not exists:
			pois.append({"name": name, "kind": str(entry.kind), "position": point,
				"source": str(entry.source), "position_verified": false})
		_add_landmark_entry(name, "Shop", point)

func _load_microsoft_buildings() -> void:
	var parsed: Variant = _read_json(MS_BUILDINGS_PATH)
	if not parsed is Dictionary:
		return
	for flat in parsed.get("buildings", []):
		var ring := PackedVector2Array()
		for index in range(0, flat.size() - 1, 2):
			ring.append(GeoProjection.lon_lat_to_map(float(flat[index]), float(flat[index + 1])))
		if ring.size() >= 3:
			buildings.append({"points": ring, "tags": {}, "source": "microsoft"})
	microsoft_building_count = buildings.size() - osm_building_count

## Build-time filtered ODbL supplement. Existing OSM/Microsoft footprints win.
## Height/facade inference remains unchanged; these records provide roof outlines only.
func _load_overture_buildings() -> void:
	var parsed: Variant = _read_json(OVERTURE_BUILDINGS_PATH, false)
	if not parsed is Dictionary:
		return
	for feature: Dictionary in parsed.get("features", []):
		var geometry: Dictionary = feature.get("geometry", {})
		var rings: Array = geometry.get("coordinates", [])
		if geometry.get("type") != "Polygon" or rings.size() != 1:
			continue
		var ring := PackedVector2Array()
		for coordinate: Array in rings[0]:
			ring.append(GeoProjection.lon_lat_to_map(float(coordinate[0]), float(coordinate[1])))
		if ring.size() > 1 and ring[0].is_equal_approx(ring[-1]):
			ring.resize(ring.size() - 1)
		if ring.size() < 3:
			continue
		var properties: Dictionary = feature.get("properties", {})
		buildings.append({"points": ring, "tags": {}, "source": "overture",
			"overture_id": properties.get("id", ""), "sources": properties.get("sources", [])})
		overture_building_count += 1

## Promote precise named businesses around the real Chowrasta into both the
## 3D-world signage layer and the full-map landmark list.  Existing OSM POIs
## win when they identify the same place at the same position.
func _load_chowrasta_reference_places() -> void:
	var parsed: Variant = _read_json(REFERENCE_PLACES_PATH, false)
	if not parsed is Dictionary:
		return
	for entry: Dictionary in parsed.get("places", []):
		var name := str(entry.get("name", "")).strip_edges()
		if name.is_empty() or float(entry.get("confidence", 0.0)) < MIN_REFERENCE_CONFIDENCE:
			continue
		var point := GeoProjection.lon_lat_to_map(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0)))
		if point.length() > CHOWRASTA_REFERENCE_RADIUS_METERS:
			continue
		_add_chowrasta_reference_pin(name, str(entry.get("category", "")), point)

## Exact user-requested locations whose coordinates are present in local OSM
## features but whose tags are too sparse to appear in the normal POI import.
func _load_local_chowrasta_pins() -> void:
	var parsed: Variant = _read_json(LOCAL_REFERENCE_PINS_PATH, false)
	if not parsed is Dictionary:
		return
	for entry: Dictionary in parsed.get("pins", []):
		var name := str(entry.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		var point := GeoProjection.lon_lat_to_map(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0)))
		_add_chowrasta_reference_pin(name, str(entry.get("category", "")), point)

func _add_chowrasta_reference_pin(name: String, category: String, point: Vector2) -> void:
	if point.length() > CHOWRASTA_REFERENCE_RADIUS_METERS:
		return
	var kind := _reference_place_kind(category)
	if kind.is_empty():
		return
	var already_mapped := false
	for poi in pois:
		if str(poi.name).to_lower() == name.to_lower() and poi.position.distance_to(point) < 40.0:
			already_mapped = true
			break
	if not already_mapped:
		pois.append({"name": name, "kind": kind, "position": point})
	_add_landmark_entry(name, _reference_landmark_category(kind), point)
	chowrasta_reference_pin_count += 1

## Overture category strings are mapped to the game’s existing sign/landmark
## vocabulary.  OpenStreetMap categories retain the value after `key=`.
static func _reference_place_kind(category: String) -> String:
	if "=" in category:
		return category.get_slice("=", 1)
	match category:
		"bank_or_credit_union": return "bank"
		"pharmacy_and_drug_store": return "pharmacy"
		"electronics_store", "telecommunications_service": return "electronics"
		"fashion_and_apparel_store": return "clothes"
		"food_and_beverage_store", "specialty_store", "shopping": return "general"
		"movie_theater", "theatre": return "theatre"
		"hospital": return "hospital"
		"college_university": return "college"
		"high_school", "education", "place_of_learning": return "school"
		"hindu_place_of_worship", "christian_place_of_worship", "muslim_place_of_worship": return "place_of_worship"
		"police_station": return "police"
		"gas_station": return "fuel"
		"restaurant", "cafe", "physical_medicine_and_rehabilitation", "financial_service", "atm": return category
	# Missing or unsupported categories are research records, not invented shops.
	return ""

static func _reference_landmark_category(kind: String) -> String:
	if DESTINATION_AMENITIES.has(kind):
		return DESTINATION_AMENITIES[kind]
	if kind in ["clinic", "physical_medicine_and_rehabilitation"]:
		return "Health centre"
	return "Shop"

## Optional, user-maintained list of signals that are real but not yet in OSM.
func _load_local_signals() -> void:
	var parsed: Variant = _read_json(LOCAL_SIGNALS_PATH, false)
	if not parsed is Dictionary:
		return
	for entry in parsed.get("traffic_signals", []):
		var point := GeoProjection.lon_lat_to_map(float(entry.get("lon")), float(entry.get("lat")))
		if GeoProjection.is_playable(point):
			traffic_signals.append({"position": point, "source": "local"})

## TopoExport is an optional, user-supplied offline supplement. Roads stay out
## of the navigation graph because the export has no reliable names, direction
## or connectivity metadata; the world renderer and tree placement use them as
## additional surveyed geometry.
func _load_topoexport_layers() -> void:
	var roads_doc: Variant = _read_json(TOPOEXPORT_ROADS_PATH, false)
	if roads_doc is Dictionary:
		for entry: Dictionary in roads_doc.get("roads", []):
			var points := PackedVector2Array()
			for raw_point: Array in entry.get("points", []):
				if raw_point.size() >= 2:
					points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
			if points.size() >= 2 and points.size() <= 1000:
				topoexport_roads.append({"points": points, "kind": str(entry.get("kind", "residential")),
					"width": maxf(float(entry.get("width", 3.5)), 1.0), "oneway": 0, "lanes": 0,
					"source": "topoexport", "source_id": str(entry.get("id", ""))})
		topoexport_road_count = topoexport_roads.size()
	var trees_doc: Variant = _read_json(TOPOEXPORT_TREES_PATH, false)
	if trees_doc is Dictionary:
		for entry: Dictionary in trees_doc.get("trees", []):
			var raw_point: Array = entry.get("point", [])
			if raw_point.size() >= 2:
				var point := Vector2(float(raw_point[0]), float(raw_point[1]))
				if GeoProjection.is_playable(point):
					topoexport_trees.append({"point": point, "height": maxf(float(entry.get("height", 8.0)), 1.0),
						"crown_diameter": maxf(float(entry.get("crown_diameter", 6.0)), 1.0),
						"source": "topoexport", "source_id": str(entry.get("id", ""))})
		topoexport_tree_count = topoexport_trees.size()

func _read_json(path: String, required := true) -> Variant:
	if not FileAccess.file_exists(path):
		if required:
			push_error("Map data file is missing: %s" % path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _project_nodes(elements: Array) -> Dictionary:
	var nodes: Dictionary = {}
	for element in elements:
		if element.get("type") == "node":
			nodes[int(element.get("id"))] = GeoProjection.lon_lat_to_map(float(element.get("lon")), float(element.get("lat")))
	return nodes

func _add_road_pieces(way_id: int, tags: Dictionary, ids: Array, nodes: Dictionary) -> void:
	var oneway := 0
	var oneway_tag := str(tags.get("oneway", ""))
	if oneway_tag in ["yes", "1", "true"] or tags.get("junction") == "roundabout":
		oneway = 1
	elif oneway_tag == "-1":
		oneway = -1
	var piece_ids := PackedInt64Array()
	var piece_points := PackedVector2Array()
	for raw_id in ids:
		var node_id := int(raw_id)
		var point: Variant = nodes.get(node_id)
		# The trunk road to the Godavari bridge runs past the playable radius; keep it whole to the bridge.
		if point == null or not (GeoProjection.is_playable(point) or way_id in GodavariBridgeBuilder.APPROACH_WAYS):
			_commit_road_piece(way_id, tags, oneway, piece_ids, piece_points)
			piece_ids = PackedInt64Array()
			piece_points = PackedVector2Array()
			continue
		piece_ids.append(node_id)
		piece_points.append(point)
	_commit_road_piece(way_id, tags, oneway, piece_ids, piece_points)

func _commit_road_piece(way_id: int, tags: Dictionary, oneway: int, ids: PackedInt64Array, points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	roads.append({
		"way_id": way_id,
		"kind": str(tags.get("highway")),
		"name": str(tags.get("name", "")),
		"oneway": oneway,
		"junction": str(tags.get("junction", "")),
		"lanes": int(str(tags.get("lanes", "0")).to_int()),
		"node_ids": ids,
		"points": points,
	})

## Closed polygon ring inside the playable area, without the repeated closing point.
func _ring(ids: Array, nodes: Dictionary) -> PackedVector2Array:
	var ring := _line(ids, nodes)
	if ring.size() >= 2 and ring[0].distance_to(ring[ring.size() - 1]) < 0.5:
		ring.remove_at(ring.size() - 1)
	return ring

func _line(ids: Array, nodes: Dictionary) -> PackedVector2Array:
	var line := PackedVector2Array()
	for raw_id in ids:
		var point: Variant = nodes.get(int(raw_id))
		if point != null and GeoProjection.is_playable(point):
			line.append(point)
	return line

func _add_poi(tags: Dictionary, position: Vector2) -> void:
	var name := str(tags.get("name", "")).strip_edges()
	var kind := poi_kind(tags)
	if kind.is_empty() or kind in ["childcare", "grave_yard", "drinking_water", "stadium"]:
		return
	if tags.has("building") and name.is_empty():
		return
	for existing in pois:
		if existing.position.distance_to(position) < 5.0 and existing.kind == kind:
			return
	pois.append({"name": name, "kind": kind, "position": position})

func _add_landmark(tags: Dictionary, position: Vector2) -> void:
	var name := str(tags.get("name", "")).strip_edges()
	var kind := poi_kind(tags)
	if name.is_empty() or not DESTINATION_AMENITIES.has(kind) or not GeoProjection.is_playable(position):
		return
	_add_landmark_entry(name, DESTINATION_AMENITIES[kind], position)

## Category of a mapped place. Name-only features (e.g. "SCCL SCHOOL", statues)
## are classified from their name so they still get signs and map entries.
static func poi_kind(tags: Dictionary) -> String:
	for key in ["shop", "amenity", "office", "tourism", "historic"]:
		if tags.has(key):
			return str(tags[key])
	if tags.has("healthcare"):
		return "clinic" if str(tags.healthcare) in ["centre", "yes"] else str(tags.healthcare)
	var name := str(tags.get("name", "")).to_lower()
	if name.is_empty() or tags.has("highway") or tags.has("railway") or tags.has("place") or tags.has("landuse"):
		return ""
	for keyword in NAME_KEYWORDS:
		if keyword in name:
			return NAME_KEYWORDS[keyword]
	return ""

static func _is_quarters_name(name: String) -> bool:
	return "quarter" in name.to_lower()

func _add_landmark_entry(name: String, category: String, position: Vector2) -> void:
	for landmark in landmarks:
		if landmark.name.to_lower() == name.to_lower() and landmark.position.distance_to(position) < LANDMARK_DEDUPE_DISTANCE:
			return
	landmarks.append({"name": name, "category": category, "position": position})

func _add_named_road_landmark(way_id: int, tags: Dictionary) -> void:
	var name := str(tags.get("name", "")).strip_edges()
	if name.is_empty() or not str(tags.get("highway")) in MAJOR_ROAD_KINDS:
		return
	if roads.is_empty() or roads[roads.size() - 1].way_id != way_id:
		return
	var points: PackedVector2Array = roads[roads.size() - 1].points
	for landmark in landmarks:
		if landmark.name == _display_name(name):
			return
	landmarks.append({"name": _display_name(name), "category": "Road", "position": points[points.size() / 2]})

static func _display_name(name: String) -> String:
	return name.capitalize() if name == name.to_upper() else name

func _centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())
