extends SceneTree

var _failures := 0

func _init() -> void:
	run_verification.call_deferred()

func run_verification() -> void:
	print("--- BEGIN GODAVARIKHANI LIVING DISTRICT VERIFICATION ---")
	
	# 1. Test Camera Controller TPP/FPP & Viewing Settings
	var cam_script := load("res://scripts/camera/camera_controller.gd")
	var cam := cam_script.new() as Node3D
	root.add_child(cam)
	
	cam.set_view_mode(0) # TPP
	_check(not cam.is_first_person(), "Camera must be in Third Person (TPP)")
	cam.set_tpp_distance(6.5)
	_check(is_equal_approx(cam.camera_distance, 6.5), "Camera TPP distance set to 6.5m")
	cam.set_tpp_fov(75.0)
	_check(is_equal_approx(cam._base_fov, 75.0), "Camera TPP FOV set to 75.0°")
	
	cam.set_view_mode(1) # FPP
	_check(cam.is_first_person(), "Camera must toggle to First Person (FPP)")
	cam.set_fpp_fov(85.0)
	_check(is_equal_approx(cam.first_person_fov, 85.0), "Camera FPP FOV set to 85.0°")
	
	cam.queue_free()
	
	# 2. Test Traffic Vehicles: Auto Occupants & Triple-Rider Bike
	var tv_script = load("res://scripts/world/traffic_vehicle.gd")
	
	# Auto with occupants
	var auto = tv_script.new()
	auto.vehicle_kind = "auto"
	root.add_child(auto)
	await process_frame
	var tuk_tuk = auto.get_node_or_null("TukTukModel")
	_check(tuk_tuk != null, "Auto rickshaw model instantiated")
	if tuk_tuk:
		var driver = tuk_tuk.get_node_or_null("AutoDriver")
		var pass1 = tuk_tuk.get_node_or_null("AutoPassenger_01")
		var pass2 = tuk_tuk.get_node_or_null("AutoPassenger_02")
		_check(driver != null, "Auto must have seated khaki-uniform driver")
		_check(pass1 != null and pass2 != null, "Auto must have seated rear passengers")
	auto.queue_free()
	
	# Triple-rider teenager bike
	var bike = tv_script.new()
	bike.vehicle_kind = "triple_ride"
	root.add_child(bike)
	await process_frame
	var r1 = bike.get_node_or_null("TeenRiderFront")
	var r2 = bike.get_node_or_null("TeenRiderMiddle")
	var r3 = bike.get_node_or_null("TeenRiderRear")
	_check(r1 != null, "Triple-ride bike must have front rider")
	_check(r2 != null, "Triple-ride bike must have sandwiched middle rider")
	_check(r3 != null, "Triple-ride bike must have rear pillion rider")
	bike.queue_free()
	
	# 3. Test Full Game Scene for Traffic Routes, Billboards & Hotspot Crowds
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	
	for _frame in 15:
		await physics_frame
	
	var world := main_scene.get_node_or_null("World")
	_check(world != null, "Main world must be instantiated")
	
	if world:
		# Check Traffic & Bus Routes
		var traffic := world.get_node_or_null("Traffic") as TrafficBuilder
		_check(traffic != null, "Traffic node must exist in world")
		if traffic:
			_check(not traffic.lanes.is_empty(), "Mapped traffic lanes must exist")
			_check(traffic.profiles.size() == 6, "All six traffic profiles must be available")
			_check(traffic.vehicle_count <= 25, "Traffic must respect active vehicle cap")

		# Check Billboards across district
		var billboards := world.get_node_or_null("ChowrasthaBillboards") as BillboardBuilder
		_check(billboards != null, "Billboards node must exist")
		if billboards:
			_check(billboards.billboard_count >= 3, "Multiple regional billboards must be placed (%d built)" % billboards.billboard_count)
		
		# Check Hotspot Crowds
		var local_act := world.get_node_or_null("LocalActivity") as LocalActivityBuilder
		_check(local_act != null, "LocalActivity node must exist")
		if local_act:
			_check(local_act.hotspot_crowd_count >= 30, "Hotspot crowds must be populated across gathering hubs (%d spawned)" % local_act.hotspot_crowd_count)
	
	main_scene.queue_free()
	await process_frame
	
	if _failures == 0:
		print("PASS: ALL GODAVARIKHANI LIVING DISTRICT CHECKS PASSED SUCCESSFULLY (0 failures)")
		quit(0)
	else:
		push_error("FAIL: %d checks failed during living district verification" % _failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [OK] %s" % message)
	else:
		_failures += 1
		push_error("  [FAIL] %s" % message)
