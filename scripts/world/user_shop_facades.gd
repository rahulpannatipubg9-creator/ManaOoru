extends RefCounted
## Physical signs on building facades for named commercial and institutional
## places from real map data (shops, hospitals, clinics, theatres, schools, colleges,
## banks, offices, and verified directories).
## Colony pins and outdoor amenities are excluded from building lettering.

static func build(builder: Node3D, data: MapData) -> void:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}

	# 1. User-requested directory coordinates
	var path := "res://data/local/user_shop_labels.json"
	if FileAccess.file_exists(path):
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for shop: Dictionary in document.get("shops", []):
			var point := GeoProjection.lon_lat_to_map(float(shop.lon), float(shop.lat))
			if GeoProjection.is_playable(point):
				_try_add_record(records, seen, builder, str(shop.name), point, true)

	# 2. Retain verified facade boards; fill missing building lettering
	for board: Dictionary in builder._boards:
		var name := str(board.name).strip_edges()
		if not _business_category(str(board.get("category", "")), name): continue
		var point := GeoProjection.lon_lat_to_map(float(board.lon), float(board.lat))
		if not GeoProjection.is_playable(point): continue
		_try_add_record(records, seen, builder, name, point, false)

	# 3. Godavarikhani map places (commercial, medical, educational, hospitality)
	var places_path := "res://data/places/godavarikhani_places.json"
	if FileAccess.file_exists(places_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(places_path))
		if parsed is Dictionary:
			for place: Dictionary in parsed.get("places", []):
				var name := str(place.name).strip_edges()
				if not _business_category(str(place.get("category", "")), name): continue
				var point := GeoProjection.lon_lat_to_map(float(place.lon), float(place.lat))
				if not GeoProjection.is_playable(point): continue
				_try_add_record(records, seen, builder, name, point, false)

	# 4. Map POIs
	for poi in data.pois:
		var name := str(poi.name).strip_edges()
		if name.is_empty(): continue
		if not _business_category(str(poi.kind), name): continue
		_try_add_record(records, seen, builder, name, poi.position, false)

	# Spatially index footprint bounds to keep bulk placement inexpensive.
	var grid: Dictionary = {}
	const CELL := 100.0
	for index in builder.footprints.size():
		var ring: PackedVector2Array = builder.footprints[index]
		var low := ring[0]
		var high := low
		for point in ring:
			low = low.min(point)
			high = high.max(point)
		for x in range(floori(low.x / CELL), floori(high.x / CELL) + 1):
			for y in range(floori(low.y / CELL), floori(high.y / CELL) + 1):
				var cell := Vector2i(x, y)
				if not grid.has(cell): grid[cell] = []
				grid[cell].append(index)

	var groups: Dictionary = {}
	var unplaced: Array = []
	var slot_cache: Dictionary = {}
	var generated_centers: Array[Vector2] = []

	for shop: Dictionary in records:
		var pin: Vector2 = shop.point
		var cell := Vector2i(floori(pin.x / CELL), floori(pin.y / CELL))
		var candidates: Dictionary = {}
		for x in range(-3, 4):
			for y in range(-3, 4):
				for index: int in grid.get(cell + Vector2i(x, y), []): candidates[index] = true
		var ranked: Array[Dictionary] = []
		for index: int in candidates:
			var ring: PackedVector2Array = builder.footprints[index]
			var distance := 0.0 if Geometry2D.is_point_in_polygon(pin, ring) else INF
			for edge in ring.size():
				distance = minf(distance, pin.distance_to(Geometry2D.get_closest_point_to_segment(pin, ring[edge], ring[(edge + 1) % ring.size()])))
			ranked.append({"index": index, "distance": distance})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)

		var placed := false
		for candidate: Dictionary in ranked:
			var index: int = candidate.index
			if float(candidate.distance) > 75.0: break
			if not slot_cache.has(index): slot_cache[index] = _safe_slots(builder, data, index, grid)
			var slots: Array = slot_cache[index]
			if slots.is_empty(): continue
			var slot: Dictionary = slots.pop_front()
			if not groups.has(index): groups[index] = []
			groups[index].append({"shop": shop, "distance": candidate.distance, "slot": slot})
			placed = true
			break
		if not placed:
			var fallback := _infill_shop(builder, data, shop, generated_centers)
			if not fallback.is_empty():
				if not groups.has(-1): groups[-1] = []
				groups[-1].append({"shop": shop, "distance": pin.distance_to(fallback.center), "slot": fallback})
			else:
				unplaced.append(str(shop.name))

	var colors := [Color("164e70"), Color("7b252d"), Color("224b38"), Color("613c18"), Color("493561"), Color("2b4c6f"), Color("6a3528")]
	var count := 0
	var report: Array = []
	for index: int in groups:
		for entry: Dictionary in groups[index]:
			var shop: Dictionary = entry.shop
			var slot: Dictionary = entry.slot
			var building_id := str(builder.building_metadata[index].id) if index >= 0 else str(slot.infill_id)
			var center: Vector2 = slot.center
			var normal := Vector3(slot.normal.x, 0, slot.normal.y)
			var width: float = slot.width
			var height: float = slot.height
			var mount := Node3D.new()
			mount.name = "UserShopFacade%d" % count
			builder.add_child(mount)
			mount.position = Vector3(center.x, slot.bottom + height * 0.5, center.y) + normal * 0.24
			mount.basis = Basis(Vector3.UP.cross(normal), Vector3.UP, normal)
			mount.set_meta("shop_name", str(shop.name))
			mount.set_meta("placement", "approximate user-requested frontage")
			mount.set_meta("building_id", building_id)
			mount.set_meta("pin_distance_m", entry.distance)
			mount.set_meta("board_width", width)

			var panel := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(width, height, 0.15)
			panel.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[count % colors.size()]
			material.roughness = 0.8
			panel.material_override = material
			panel.visibility_range_end = 160.0
			mount.add_child(panel)

			var label := Label3D.new()
			var text := _format_sign_text(str(shop.name))
			label.text = text
			label.font_size = 64
			var font := ThemeDB.fallback_font
			var max_text := 1.0
			for line in text.split("\n"):
				max_text = maxf(max_text, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x)
			label.pixel_size = minf((width - 0.3) / max_text, (height - 0.15) / (76.0 * text.split("\n").size()))
			label.position.z = 0.12
			label.outline_size = 4
			label.modulate = Color("fff1cc")
			label.no_depth_test = false
			label.visibility_range_end = 160.0
			mount.add_child(label)

			builder._board_names[str(shop.name).to_upper()] = true
			report.append({"name": shop.name, "building_id": building_id, "pin_distance_m": entry.distance, "placement": "generated shopfront near source pin" if index < 0 else "approximate user-requested frontage", "requested_five": shop.requested, "wall_a": [slot.a.x, slot.a.y], "wall_b": [slot.b.x, slot.b.y], "bottom": slot.bottom, "height": height, "width": width})
			count += 1

	var file := FileAccess.open("user://user_shop_facade_report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"mounted": count, "signs": report, "unplaced": unplaced}, "  "))
	print("User-requested building signs mounted: ", count, "; unplaced: ", unplaced.size())

static func _try_add_record(records: Array[Dictionary], seen: Dictionary, builder: Node3D, name: String, point: Vector2, requested: bool) -> bool:
	var key: String = builder._sign_name_key(name)
	if key.is_empty() or seen.has(key) or builder.has_facade_board(name):
		return false
	for prior in records:
		var pkey: String = builder._sign_name_key(str(prior.name))
		if pkey == key or ((pkey in key or key in pkey) and prior.point.distance_to(point) < 35.0):
			return false
	records.append({"name": name, "point": point, "requested": requested})
	seen[key] = true
	return true

static func _format_sign_text(raw_name: String) -> String:
	var text := raw_name.replace("`", "'").strip_edges()
	for suffix in [", Godavarikhani", ", godavarikhani", " - Godavarikhani", ", Markandeya Colony", ", Ramagundam", " Godavarikhani", " Godavari Khani"]:
		text = text.replace(suffix, "")
	text = text.strip_edges().to_upper()
	if "SAGARIKA" in text:
		return "SAGARIKA FURNITURE\nSHOWROOM"
	if "\n" not in text and text.length() > 22:
		var words := text.split(" ")
		if words.size() >= 2:
			var half := ceili(words.size() * 0.5)
			var line1 := " ".join(words.slice(0, half))
			var line2 := " ".join(words.slice(half))
			text = line1 + "\n" + line2
	return text

## Frontage slots must fit the wall, clear nearby footprints, existing signs,
## raised approach terrain and the facade's sunshade bands.
static func _safe_slots(builder: Node3D, data: MapData, index: int, grid: Dictionary) -> Array:
	var ring: PackedVector2Array = builder.footprints[index]
	var meta: Dictionary = builder.building_metadata[index]
	var roof: float = float(meta.base) + float(meta.wall_height) + 0.9
	var output: Array = []
	for edge in ring.size():
		var a := ring[edge]
		var b := ring[(edge + 1) % ring.size()]
		var length := a.distance_to(b)
		if length < 3.0: continue
		var tangent := (b - a).normalized()
		var normal := Vector2(tangent.y, -tangent.x)
		var middle := (a + b) * 0.5
		var road_direction: Vector2 = builder._direction_to_road(middle)
		var facing: float = normal.dot(road_direction) if road_direction.length_squared() > 0.01 else 0.5
		if facing < 0.25: continue
		var columns := maxi(1, floori((length - 0.5) / 6.0))
		var span := (length - 0.5) / columns
		for column in columns:
			var center := a + tangent * (0.25 + span * (column + 0.5))
			var width := minf(span - 0.2, 8.5)
			var aa := center - tangent * width * 0.5
			var bb := center + tangent * width * 0.5
			if not _outside_footprints(aa, bb, normal, grid, builder.footprints): continue
			var ground: float = float(meta.base)
			for offset in [0.0, 3.0, 6.0, 9.0]:
				for side in [-0.5, 0.0, 0.5]:
					ground = maxf(ground, data.terrain.height_at(center + normal * offset + tangent * width * side))
			# Each band sits above the sunshade of its storey.
			for floor_index in mini(3, maxi(1, int(meta.floors))):
				var bottom: float = float(meta.base) + floor_index * 3.0 + 2.62
				bottom = maxf(bottom, ground + 1.9)
				# Move above any higher sunshade the raised approach would cross.
				for ledge_floor in maxi(1, int(meta.floors)):
					var ledge: float = float(meta.base) + ledge_floor * 3.0 + 2.36
					if bottom < ledge + 0.15 and bottom + 0.9 > ledge - 0.05:
						bottom = ledge + 0.26
				var height := minf(0.9, roof - 0.2 - bottom)
				if height < 0.48: continue
				var overlaps := false
				for mount: Dictionary in builder.facade_mounts:
					if int(mount.building_index) != index: continue
					if float(mount.bottom) + float(mount.height) + 0.12 < bottom or float(mount.bottom) > bottom + height + 0.12: continue
					var ma: Vector2 = mount.a
					var mb: Vector2 = mount.b
					if absf((ma - center).dot(normal)) > 0.2 or absf((mb - center).dot(normal)) > 0.2: continue
					var left := minf((ma - center).dot(tangent), (mb - center).dot(tangent))
					var right := maxf((ma - center).dot(tangent), (mb - center).dot(tangent))
					if left < width * 0.5 + 0.12 and right > -width * 0.5 - 0.12: overlaps = true
				if overlaps: continue
				output.append({"a": aa, "b": bb, "center": center, "normal": normal, "width": width, "height": height, "bottom": bottom, "score": facing * 100.0 - float(builder._distance_to_road(center)) - floor_index * 50.0})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var distinct: Array = []
	for slot: Dictionary in output:
		var overlaps := false
		for kept: Dictionary in distinct:
			if slot.center.distance_to(kept.center) < 0.1 and slot.normal.dot(kept.normal) > 0.99:
				if float(slot.bottom) < float(kept.bottom) + float(kept.height) + 0.12 and float(kept.bottom) < float(slot.bottom) + float(slot.height) + 0.12:
					overlaps = true
					break
		if not overlaps: distinct.append(slot)
	return distinct

static func _outside_footprints(a: Vector2, b: Vector2, normal: Vector2, grid: Dictionary, footprints: Array[PackedVector2Array]) -> bool:
	var aa := a + normal * 0.24
	var bb := b + normal * 0.24
	var cell := Vector2i(floori(((a + b) * 0.5).x / 100.0), floori(((a + b) * 0.5).y / 100.0))
	var checked: Dictionary = {}
	for x in range(-1, 2):
		for y in range(-1, 2):
			for index: int in grid.get(cell + Vector2i(x, y), []):
				if checked.has(index): continue
				checked[index] = true
				var polygon := footprints[index]
				if Geometry2D.is_point_in_polygon(aa, polygon) or Geometry2D.is_point_in_polygon(bb, polygon): return false
				for edge in polygon.size():
					if Geometry2D.segment_intersects_segment(aa, bb, polygon[edge], polygon[(edge + 1) % polygon.size()]) != null: return false
	return true

static func _business_category(category: String, name: String = "") -> bool:
	var cat := category.to_lower()
	var n := name.to_lower()
	if cat in ["childcare", "monument", "bus_stop", "bus_station", "parking", "grave_yard", "cemetery", "park", "playground", "stadium", "pitch", "water", "fountain", "crossing", "traffic_signals", "drinking_water", "toilets", "waste_disposal", "recycling", "bench", "shelter", "animal_attraction"]:
		return false
	if "statue" in n or "monument" in n:
		return false
	if cat in ["locality", "neighbourhood", "suburb", "quarter", "area"]:
		return false
	if n.ends_with(" colony") or n.ends_with(" quarters") or n.ends_with(" chowk") or n.ends_with(" centre") or n.ends_with(" nagar"):
		var has_facility := false
		for fac in ["hospital", "clinic", "school", "college", "bank", "pharmacy", "medical", "hotel", "restaurant", "theatre", "temple", "church", "masjid", "dargah", "store", "shop", "electronics", "gadgets", "mobiles", "jewel"]:
			if fac in n:
				has_facility = true
				break
		if not has_facility:
			return false
	if cat.begins_with("shop=") or cat.begins_with("office=") or cat.begins_with("amenity=") or cat.begins_with("healthcare="):
		var sub := cat.get_slice("=", 1)
		if sub in ["waste_disposal", "bench", "shelter", "toilets", "drinking_water", "parking", "grave_yard"]:
			return false
		return true
	if "store" in cat or "service" in cat or "dealer" in cat or "shop" in cat:
		return true
	var allowed := [
		"shop", "yes", "general", "convenience", "supermarket", "department_store",
		"clothes", "shoes", "jewelry", "jewellery", "furniture", "mobile_phone",
		"electronics", "electrical", "hardware", "tailor", "photo", "medical_supply",
		"greengrocer", "confectionery", "sweets", "tea", "bakery", "butcher",
		"hairdresser", "beauty", "chemist", "optician", "car_repair", "motorcycle",
		"bicycle", "books", "stationery", "restaurant", "cafe", "bar", "fast_food",
		"food_and_drink", "food_and_beverage_store", "casual_eatery",
		"non_alcoholic_beverage_venue", "shopping", "shopping_mall", "pharmacy",
		"pharmacy_and_drug_store", "hotel", "lodging", "motel", "bank",
		"bank_or_credit_union", "atm", "financial_service", "fuel", "gas_station", "gym",
		"hospital", "clinic", "doctors", "dentist", "dental_clinic", "health_care",
		"health_post", "blood_bank", "physical_medicine_and_rehabilitation",
		"theatre", "movie_theater", "theatre_venue",
		"school", "college", "college_university", "high_school", "elementary_school",
		"place_of_learning", "specialty_school", "education", "university",
		"library", "post_office", "police", "police_station", "government_office",
		"place_of_worship", "hindu_place_of_worship", "christian_place_of_worship",
		"muslim_place_of_worship", "religious_organization", "sport_or_recreation_club",
		"supplier_or_distributor"
	]
	return cat in allowed or cat.is_empty()

## A small original shopfront fills missing footprint coverage; it is game
## geometry, never claimed as surveyed real architecture. Keep it off roads.
static func _infill_shop(builder: Node3D, data: MapData, shop: Dictionary, reserved: Array[Vector2]) -> Dictionary:
	var pin: Vector2 = shop.point
	var road_point := pin
	var normal := Vector2(0, -1)
	var nearest := INF
	var grid: RefCounted = data.osm_road_grid()
	var reach := 200.0
	# Widen until a road is found: anything nearer than it is already inside the search.
	while nearest == INF and reach < 20000.0:
		for segment in grid.near(pin, reach):
			var a: Vector2 = grid.starts[segment]
			var b: Vector2 = grid.ends[segment]
			var point := Geometry2D.get_closest_point_to_segment(pin, a, b)
			var distance := pin.distance_to(point)
			if distance < nearest:
				nearest = distance
				road_point = point
				normal = (point - pin).normalized() if distance > 0.1 else (b - a).normalized().orthogonal()
		if nearest > reach:
			nearest = INF
		reach *= 4.0
	var tangent := Vector2(normal.y, -normal.x)
	var anchor := pin
	if nearest < 14.0: anchor = road_point - normal * 14.0
	var center := Vector2.ZERO
	var found := false
	for back in [0.0, 8.0, 16.0, 24.0, 32.0]:
		for side in [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0]:
			var candidate: Vector2 = anchor - normal * float(back) + tangent * float(side)
			if candidate.distance_to(pin) > 80.0 or not GeoProjection.is_playable(candidate): continue
			if not builder.is_clear(candidate, 6.0): continue
			var conflict := false
			for prior in reserved:
				if candidate.distance_to(prior) < 12.0: conflict = true
			if conflict: continue
			var corners := PackedVector2Array([candidate - tangent * 4 - normal * 3, candidate + tangent * 4 - normal * 3, candidate + tangent * 4 + normal * 3, candidate - tangent * 4 + normal * 3])
			var safe := true
			for edge in 4:
				var a := corners[edge]
				var b := corners[(edge + 1) % 4]
				if not builder._sign_clear_of_roads(a, b, Vector2.ZERO): safe = false
			if not safe: continue
			center = candidate
			found = true
			break
		if found: break
	if not found: return {}
	reserved.append(center)
	var base: float = data.terrain.height_at(center)
	var low := base
	for x in [-4.0, 4.0]:
		for z in [-3.0, 3.0]:
			var height: float = data.terrain.height_at(center + tangent * x + normal * z)
			low = minf(low, height)
			base = maxf(base, height)
	var root := Node3D.new()
	root.name = "GeneratedShopfront%d" % reserved.size()
	builder.add_child(root)
	root.position = Vector3(center.x, base, center.y)
	var forward := Vector3(normal.x, 0, normal.y)
	root.basis = Basis(Vector3.UP.cross(forward), Vector3.UP, forward)
	root.set_meta("shop_name", shop.name)
	root.set_meta("generated_geometry", true)
	_infill_box(root, Vector3(0, -(base - low) * 0.5, 0), Vector3(8, base - low + 0.2, 6), Color("68645c"))
	_infill_box(root, Vector3(0, 2.1, 0), Vector3(8, 4.2, 6), Color("d5c29d"))
	_infill_box(root, Vector3(0, 4.25, 0), Vector3(8.3, .16, 6.3), Color("59666a"))
	_infill_box(root, Vector3(0, 1.15, 3.035), Vector3(5.8, 2.25, .06), Color("344b54"))
	for x in [-3.3, 3.3]:
		_infill_box(root, Vector3(x, 1.15, 3.05), Vector3(.35, 2.3, .15), Color("9d7650"))
	_infill_box(root, Vector3(0, .1, 3.45), Vector3(7.6, .2, .9), Color("888379"))
	var body := StaticBody3D.new()
	root.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 4.2 + base - low, 6)
	collision.shape = shape
	collision.position.y = 2.1 - (base - low) * 0.5
	body.add_child(collision)
	var front := center + normal * 3.0
	return {"center": front, "normal": normal, "a": front - tangent * 3.6, "b": front + tangent * 3.6, "width": 7.2, "height": 1.15, "bottom": base + 2.65, "infill_id": "generated/shopfront/" + str(shop.name)}

static func _infill_box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	instance.material_override = material
	instance.visibility_range_end = 200.0
	parent.add_child(instance)
