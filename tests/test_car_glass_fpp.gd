extends SceneTree

var failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	for car_id in ["ford_mustang_mach_40", "toyota_supra_gr", "roush_mustang_96"]:
		var scene_path: String = "res://scenes/vehicles/imported/" + str(car_id) + ".tscn"
		var scene: PackedScene = load(scene_path)
		var car = scene.instantiate()
		root.add_child(car)
		for i in 2:
			await physics_frame
		
		print("VERIFYING: ", car_id)
		print("  seat_hip: ", car.seat_hip)
		print("  glass materials count: ", car._glass_materials.size())
		check(car._glass_materials.size() > 0, "No glass materials configured for " + car_id)
		
		for gm in car._glass_materials:
			check(gm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Glass must have TRANSPARENCY_ALPHA")
		
		# In TPP mode (default)
		car.set_driving_enabled(true)
		var pivot = car.get_node("CameraPivot")
		pivot.view_mode = 0 # THIRD_PERSON
		car._update_visuals()
		print("  TPP glass alpha: ", car._glass_materials[0].albedo_color.a)
		check(car._glass_materials[0].albedo_color.a > 0.1, "TPP glass must be tinted")
		
		# In FPP mode
		pivot.view_mode = 1 # FIRST_PERSON
		car._update_visuals()
		print("  FPP glass alpha: ", car._glass_materials[0].albedo_color.a)
		check(car._glass_materials[0].albedo_color.a == 0.0, "FPP glass must be completely clear (alpha = 0.0)")
		
		car.queue_free()
		for i in 2:
			await physics_frame
			
	print("PASS Car glass and FPP transparency verification" if failures == 0 else "FAIL Car glass verification")
	quit(0 if failures == 0 else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
