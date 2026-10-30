extends SceneTree
const Allocator := preload("res://scripts/world/storefront_allocator.gd")

func board(title: String, point: Vector2) -> Dictionary:
	var gps := GeoProjection.map_to_lon_lat(point)
	return {"name": title, "category": "shop=convenience", "lon": gps[0], "lat": gps[1], "source_id": title}

func run_case(tags: Dictionary, boards: Array, polygon := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(0, 10)])) -> RefCounted:
	var allocator := Allocator.new()
	var polygons: Array[PackedVector2Array] = [polygon]
	var metadata: Array[Dictionary] = [{"id": "source-building-42", "tags": tags, "base": 0.0, "floors": 5}]
	allocator.allocate(polygons, metadata, boards, func(_p: Vector2) -> Vector2: return Vector2(0, -1), func(_p: Vector2) -> float: return 8.0)
	return allocator

func _init() -> void:
	var crowded: Array = []
	for i in 15:
		crowded.append(board("Business %02d" % i, Vector2(7, 4)))
	var allocator := run_case({"building": "yes"}, crowded)
	assert(allocator.assignments.is_empty() and allocator.unplaced.size() == 15, "15 businesses must not be forced onto an unknown building")
	allocator = run_case({"building": "retail"}, crowded)
	assert(allocator.assignments.is_empty() and allocator.unplaced.size() == 15, "Conflicting real pins must not be relocated into empty units")
	allocator = run_case({"building": "house"}, [board("Shop", Vector2(4, 4))])
	assert(allocator.assignments.is_empty() and allocator.unplaced[0].reason == "residential_building", "Residential buildings must reject inferred shops")
	allocator = run_case({"building": "yes"}, [board("Nearby", Vector2(22, 4))])
	assert(allocator.assignments.is_empty(), "Nearest-building guesses must stay unplaced")
	allocator = run_case({"building": "retail"}, [board("West shop", Vector2(2, 4)), board("East shop", Vector2(18, 4))])
	assert(allocator.assignments.size() == 2, "Separated retail storefronts must support separate businesses")
	assert(allocator.assignments[0].storefront_id != allocator.assignments[1].storefront_id, "Two businesses must never share a unit")
	assert(is_equal_approx(allocator.assignments[0].bottom, allocator.assignments[1].bottom), "Signs must remain in one ground-floor band")
	assert(allocator.units.size() == floori((20.0 - 0.5) / Allocator.MIN_UNIT_WIDTH), "Capacity must derive from frontage geometry")
	var rotated := PackedVector2Array()
	for point: Vector2 in [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(0, 10)]:
		rotated.append(point.rotated(PI * 0.25))
	allocator = run_case({"building": "retail"}, [board("Rotated shop", Vector2(8, 4).rotated(PI * 0.25))], rotated)
	assert(allocator.assignments.size() == 1, "Rotated storefront allocation must work")
	var mount: Dictionary = allocator.assignments[0]
	assert(mount.normal.dot(Vector2(0, -1)) >= 0.5, "Rotated storefront sign must face its road")
	allocator = run_case({"building": "yes"}, [board("Only shop", Vector2(8, 4)), board("Only shop", Vector2(8, 4))])
	assert(allocator.assignments.size() == 1 and allocator.businesses[0].source_records.size() == 2, "Repeated source records must retain provenance without duplicate signs")
	var before: Array = allocator.assignments.duplicate(true)
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(0, 10)])]
	var metadata: Array[Dictionary] = [{"id": "source-building-42", "tags": {"building": "yes"}, "base": 0.0, "floors": 5}]
	allocator.allocate(polygons, metadata, [board("Only shop", Vector2(8, 4)), board("Only shop", Vector2(8, 4))], func(_p: Vector2) -> Vector2: return Vector2(0, -1), func(_p: Vector2) -> float: return 8.0)
	assert(before == allocator.assignments, "Repeated generation must replace state deterministically")
	for assignment: Dictionary in allocator.assignments:
		assert(assignment.bottom + assignment.height <= Allocator.GROUND_BAND_TOP + 0.001, "No sign may cover upper-floor windows")
	metadata[0]["wall_height"] = 2.7
	allocator.allocate(polygons, metadata, [board("Low shop", Vector2(8,4))], func(_p: Vector2) -> Vector2: return Vector2(0,-1), func(_p: Vector2) -> float: return 8.0)
	assert(allocator.assignments.is_empty(), "Explicit low roofs must reject signs instead of floating above the wall")
	print("PASS storefront allocation: crowding, residential use, no relocation, frontage capacity, ownership, source retention, regeneration")
	quit()
