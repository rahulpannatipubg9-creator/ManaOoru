extends SceneTree

const Catalog := preload("res://scripts/map/location_catalog.gd")

func _init() -> void:
	var catalog := Catalog.new()
	_check(catalog.records.size() == 547, "Source catalog record count must match the generated inventory")
	_check(catalog.candidates.size() == 114, "Candidate names must remain separate from mapped source records")
	var entrance := catalog.search("Vidya Nagar 2", Vector2.ZERO, 12)
	_check(not entrance.is_empty(), "Search must find the mapped Vidya Nagar 2 entrance")
	var found_entrance := false
	for record in entrance:
		if record.id == "osm/node/3384160142":
			found_entrance = true
			_check(record.canNavigate, "Mapped entrance inside the playable area should be navigable")
			_check(record.coordinateStatus == "source_point", "Entrance must retain its source point role")
	_check(found_entrance, "Search result must preserve the original OSM node identity")
	var laxmi := catalog.search("Laxmi Nagar", Vector2.ZERO, 12)
	var found_laxmi := false
	for record in laxmi:
		if record.id == "osm/node/2891164206":
			found_laxmi = true
			_check(record.canNavigate, "Mapped Laxmi Nagar locality should be selectable")
			var map_data := MapData.load_shared()
			var network := RoadNetwork.new(map_data)
			var route := network.find_route(Vector2.ZERO, record.position, RoadNetwork.Mode.WALK)
			_check(route.ok and route.points.size() >= 2, "Laxmi Nagar search result should route on connected mapped roads")
	_check(found_laxmi, "Search must find the mapped Laxmi Nagar locality point")
	var leads := catalog.search("SS Mobiles", Vector2.ZERO, 12)
	var found_unlocated_candidate := false
	for record in leads:
		if str(record.id).begins_with("candidate/"):
			found_unlocated_candidate = true
			_check(not record.canNavigate and not record.has("position"), "Candidate names must never become routeable pins")
	_check(found_unlocated_candidate, "Candidate-only shop names must be searchable as unverified leads")
	var fixme_count := 0
	for record in catalog.records:
		if record.verificationStatus == "needs_review":
			fixme_count += 1
			_check(not record.canNavigate, "OSM fixme locations must not be used as destinations")
	_check(fixme_count > 0, "Source review warnings should be retained")
	if _failures > 0:
		push_error("FAIL location catalog regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS location catalog regression: source records, candidate separation, projection eligibility, source warnings")
	quit()

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
