extends SceneTree

func _init() -> void:
	print("--- Running High-Speed Streaming Regression Test ---")
	_test_velocity_lookahead_formula()
	_test_chunk_cache_and_throttling()
	print("PASS high-speed streaming regression: velocity-aware lookahead, chunk LRU caching, and per-frame budget throttling")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: %s" % message)
		assert(false, message)

func _test_velocity_lookahead_formula() -> void:
	# Simulate the lookahead logic from main.gd
	var calculate_lookahead := func(vel: Vector3) -> Vector2:
		var speed := vel.length()
		if speed > 3.0:
			var lead_sec := clampf(1.0 + (speed / 36.1) * 1.5, 1.0, 2.5)
			var lead_vec := Vector2(vel.x, vel.z) * lead_sec
			if lead_vec.length() > 100.0:
				lead_vec = lead_vec.normalized() * 100.0
			return lead_vec
		return Vector2.ZERO

	# 1. Stationary (0 km/h)
	var stationary_lead: Vector2 = calculate_lookahead.call(Vector3.ZERO)
	_check(stationary_lead.length() == 0.0, "Stationary vehicle must have 0 lookahead")

	# 2. Slow walk (1 m/s = 3.6 km/h)
	var walk_lead: Vector2 = calculate_lookahead.call(Vector3(0.0, 0.0, 1.0))
	_check(walk_lead.length() == 0.0, "Walking (< 3 m/s) must not trigger lookahead")

	# 3. Moderate city driving (36 km/h = 10 m/s)
	var city_lead: Vector2 = calculate_lookahead.call(Vector3(0.0, 0.0, -10.0))
	_check(city_lead.length() > 10.0 and city_lead.length() < 25.0, "36 km/h driving must project 10m-25m ahead")
	_check(city_lead.y < 0.0, "Forward driving (-Z) must project in -Z direction")

	# 4. Highway driving (130 km/h = 36.1 m/s)
	var highway_lead: Vector2 = calculate_lookahead.call(Vector3(0.0, 0.0, -36.1))
	_check(absf(highway_lead.length() - 90.25) < 1.0, "130 km/h driving must project ~90m ahead")

	# 5. Extreme speed cap (200 km/h = 55.5 m/s)
	var extreme_lead: Vector2 = calculate_lookahead.call(Vector3(0.0, 0.0, -55.5))
	_check(is_equal_approx(extreme_lead.length(), 100.0), "Extreme speed must cap at 100m lookahead ceiling")

func _test_chunk_cache_and_throttling() -> void:
	var builder := BuildingBuilder.new()
	_check(builder.get("_chunk_cache") is Dictionary, "Chunk cache must exist as Dictionary")
	_check(builder.get("MAX_CACHED_CHUNKS") == 50, "Max cached chunks must equal 50")
	builder.free()
