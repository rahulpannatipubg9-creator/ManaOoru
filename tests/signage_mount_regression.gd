extends SceneTree

func _init() -> void:
	var probe := BuildingBuilder.new()
	probe.footprints.append(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]))
	assert(probe._sign_clear_of_buildings(Vector2(2, 0), Vector2(8, 0), Vector2(0, -1)), "Exterior wall mount must remain valid")
	assert(not probe._sign_clear_of_buildings(Vector2(2, 0), Vector2(8, 0), Vector2(0, 1)), "Inward mount must be rejected")
	probe.footprints.append(PackedVector2Array([Vector2(4, -2), Vector2(6, -2), Vector2(6, 2), Vector2(4, 2)]))
	assert(not probe._sign_clear_of_buildings(Vector2(2, 0), Vector2(8, 0), Vector2(0, -1)), "Neighbour crossing panel middle must be rejected")
	probe.free()
	var data := MapData.load_shared()
	var buildings := BuildingBuilder.new()
	root.add_child(buildings)
	buildings.setup(data, func(_points: PackedVector2Array) -> bool: return false)
	assert(not buildings.facade_mounts.is_empty(), "Facade mount planning failed")
	var cinema := false
	var reference_mount: Dictionary = {}
	var business_ids := {}
	var unit_ids := {}
	var valid_units := {}
	for unit: Dictionary in buildings.storefront_allocator.units:
		valid_units[unit.id] = unit
	for mount: Dictionary in buildings.facade_mounts:
		assert(buildings._sign_clear_of_buildings(mount.a, mount.b, mount.normal), "Rendered sign intersects a building footprint")
		var width: float = mount.a.distance_to(mount.b)
		assert(width >= 2.39 and width <= BuildingBuilder.BOARD_MAX_WIDTH + 0.01, "Unrealistic panel width: %f" % width)
		assert(absf(mount.height / width - BuildingBuilder.BOARD_ASPECT) < 0.001, "Panel/text aspect ratio distorted")
		assert(mount.has("business_id") and mount.has("storefront_id") and mount.has("building_id"), "Every sign must have business/storefront/building ownership")
		assert(not business_ids.has(mount.business_id) and not unit_ids.has(mount.storefront_id), "Business or storefront assigned twice")
		business_ids[mount.business_id] = true
		unit_ids[mount.storefront_id] = true
		assert(valid_units.has(mount.storefront_id) and valid_units[mount.storefront_id].business_id == mount.business_id,
			"Every rendered sign must reference its own valid business/unit assignment")
		assert(str(buildings.building_metadata[mount.building_index].tags.get("building", "")) not in buildings.StorefrontAllocator.RESIDENTIAL,
			"Residential building received commercial sign")
		assert(mount.bottom + mount.height <= buildings.building_metadata[mount.building_index].base + 3.151, "No upper-floor sign stacks")
		assert(mount.bottom + mount.height <= mount.roof - 0.14, "Sign floats above its building")
		for endpoint: Vector2 in [mount.a, mount.b]:
			assert(endpoint.distance_to(Geometry2D.get_closest_point_to_segment(endpoint, mount.wall_a, mount.wall_b)) < 0.001,
				"Sign not mounted on its assigned wall")
		var middle: Vector2 = (mount.a + mount.b) * 0.5
		assert(mount.normal.dot(buildings._direction_to_road(middle)) > 0.45, "Sign rotated away from road")
		var board: Dictionary = buildings._boards[mount.board_index]
		if BuildingBuilder._sign_name_key(board.name) == "new ashok theatre":
			cinema = true
			reference_mount = mount
		for other: Dictionary in buildings.facade_mounts:
			if other == mount or other.wall_a != mount.wall_a or other.wall_b != mount.wall_b:
				continue
			if absf(float(other.bottom) - float(mount.bottom)) < 0.01:
				assert(middle.distance_to((other.a + other.b) * 0.5) >= (width + other.a.distance_to(other.b)) * 0.5,
					"Facade panels overlap")
	assert(cinema, "NEW ASHOK THEATRE reference must have a facade mount")
	var prior := buildings.facade_mounts.duplicate(true)
	var prior_unplaced: Array = buildings.storefront_allocator.unplaced.duplicate(true)
	buildings.setup(data, func(_points: PackedVector2Array) -> bool: return false)
	assert(prior == buildings.facade_mounts and prior_unplaced == buildings.storefront_allocator.unplaced,
		"Regeneration must neither accumulate nor relocate businesses/signs")
	print("PASS signage mounts: %d panels; wall contact, road facing, dimensions, roof clearance, overlap, NEW ASHOK reference" % buildings.facade_mounts.size())
	if "--capture" in OS.get_cmdline_user_args():
		var middle: Vector2 = (reference_mount.a + reference_mount.b) * 0.5
		buildings.build_around(middle, 100.0)
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color.SKY_BLUE
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color.WHITE
		settings.ambient_light_energy = 0.8
		environment.environment = settings
		root.add_child(environment)
		var target := Vector3(middle.x, reference_mount.bottom + reference_mount.height * 0.5, middle.y)
		var normal := Vector3(reference_mount.normal.x, 0, reference_mount.normal.y)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = target + normal * 3.5 + Vector3.UP * 0.15
		await process_frame
		camera.look_at(target)
		camera.current = true
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_sign_reference.png")
	quit()
