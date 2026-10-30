extends SceneTree

func _init() -> void:
	var vehicle_scene := load("res://scenes/vehicles/tuk_tuk.tscn") as PackedScene
	assert(vehicle_scene != null, "Enterable tuk-tuk scene did not load")
	var vehicle := vehicle_scene.instantiate() as RigidVehicle
	root.add_child(vehicle)
	await process_frame
	var model := vehicle.get_node_or_null("TukTukVisual") as Node3D
	assert(model != null, "Enterable tuk-tuk visual missing")
	assert(is_equal_approx(model.scale.x, 1.0), "Tuk-tuk must retain metre scale")
	assert(is_equal_approx(model.position.y, 1.4), "Tuk-tuk wheels must align with the body origin")
	var collision := vehicle.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert(collision != null and collision.shape is BoxShape3D, "Tuk-tuk must have a real ground collision shape")
	assert(is_equal_approx(collision.position.y, 1.375), "Tuk-tuk collision must rest on the road, not hover")
	assert(is_equal_approx(vehicle.entry_half_width, 0.68), "Tuk-tuk entry door width must match its cabin")
	assert(vehicle.seat_hip != Vector3.ZERO and vehicle.pedal_point != Vector3.ZERO,
		"Tuk-tuk must supply a usable driver seat and pedals")
	print("PASS tuk-tuk regression: grounded collision, seat and entry measurements")
	quit()
