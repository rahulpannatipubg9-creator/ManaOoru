extends RefCounted
## Offline source evidence and separate research candidates. No runtime geocoding.
const SOURCE_PATH := "res://data/locations/source_locations.json"
const CANDIDATE_PATH := "res://data/locations/candidate_locations.json"
var records: Array[Dictionary] = []
var candidates: Array[Dictionary] = []

func _init() -> void:
	records = _load_records(SOURCE_PATH, true)
	candidates = _load_records(CANDIDATE_PATH, false)

func _load_records(path: String, allow_position: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return result
	for raw: Dictionary in parsed.get("locations", []):
		var record := raw.duplicate(true)
		# Candidate files never get navigation coordinates, even if accidentally populated.
		if allow_position and record.get("latitude") != null and record.get("longitude") != null:
			record["position"] = GeoProjection.lon_lat_to_map(float(record.longitude), float(record.latitude))
			record["canNavigate"] = GeoProjection.is_playable(record.position) and record.get("verificationStatus") != "needs_review"
		else:
			record["canNavigate"] = false
		record["searchText"] = _search_text(record)
		result.append(record)
	return result

static func _normalize(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("-", "").replace("_", "").replace("'", "").replace(".", "")

func _search_text(record: Dictionary) -> String:
	var text := "%s %s %s %s %s" % [record.get("name", ""),record.get("category", ""),record.get("subcategory", ""),record.get("locality", ""),record.get("street", "")]
	for alias: String in record.get("aliases", []):
		text += " " + alias
	return _normalize(text)

func search(query: String, origin: Vector2, limit := 12) -> Array[Dictionary]:
	var key := _normalize(query.strip_edges())
	var matches: Array[Dictionary] = []
	if key.is_empty():
		return matches
	for record in records + candidates:
		if key in str(record.searchText):
			matches.append(record)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.canNavigate) != bool(b.canNavigate):
			return bool(a.canNavigate)
		var a_exact := _normalize(str(a.name)) == key
		var b_exact := _normalize(str(b.name)) == key
		if a_exact != b_exact:
			return a_exact
		if a.has("position") and b.has("position"):
			return origin.distance_squared_to(a.position) < origin.distance_squared_to(b.position)
		return str(a.name) < str(b.name))
	var result: Array[Dictionary] = []
	for match_record in matches.slice(0, limit):
		result.append(match_record)
	return result

static func status_label(record: Dictionary) -> String:
	if record.get("verificationStatus") == "needs_review":
		return "Source warns: position needs review"
	if record.get("coordinateStatus") == "unverified":
		return "Unverified — no mapped position"
	if not record.get("canNavigate", false):
		return "Outside playable area"
	if record.get("coordinateStatus") == "source_geometry_representative":
		return "Map outline center"
	if record.get("coordinateStatus") == "local_source_assertion":
		return "Local pin — needs review"
	return "Mapped source — not field verified"
