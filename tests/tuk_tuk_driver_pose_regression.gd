extends SceneTree
func _init() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	var car: RigidVehicle = load("res://scenes/vehicles/tuk_tuk.tscn").instantiate()
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)
	var person: CharacterBody3D = load("res://scenes/player/person.tscn").instantiate()
	root.add_child(person)
	person.set_physics_process(false)
	var entry: Node = load("res://scripts/vehicle/vehicle_entry.gd").new()
	root.add_child(entry)
	entry.person = person
	entry.vehicle = car
	entry.phase = entry.Phase.SEATED
	await process_frame
	var character: Node3D = person.get_node("TestCharacter")
	character.set_process(false)
	character.seated = true
	entry._follow_seat()
	for frame in 12:
		character._process(0.1)
	var rig: Skeleton3D = character.skeleton
	for pair in [["L", car.left_hand_grip], ["R", car.right_hand_grip]]:
		var hand := rig.find_bone("DEF-hand." + pair[0])
		var actual := car.to_local(rig.to_global(rig.get_bone_global_pose(hand).origin))
		var gap := actual.distance_to(pair[1])
		print("Hand ", pair[0], " at ", actual, " target ", pair[1], " gap ",gap)
		assert(gap < 0.055, "Driver wrist must contact its handlebar grip")
	for steering_lock: float in [-0.72, 0.72]:
		car._steer = steering_lock
		entry._follow_seat()
		character._process(0.1)
		var targets: Array[Vector3] = car.get_node("TukTukVisual").driver_grip_points()
		for side_index in 2:
			var side := "L" if side_index == 0 else "R"
			var wrist := car.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("DEF-hand." + side)).origin))
			assert(wrist.distance_to(targets[side_index]) < 0.055, "Hands must stay on grips while steering")
	car._steer = 0.0
	entry._follow_seat()
	character._process(0.1)
	var left_hip := rig.to_global(rig.get_bone_global_pose(rig.find_bone("DEF-thigh.L")).origin)
	var right_hip := rig.to_global(rig.get_bone_global_pose(rig.find_bone("DEF-thigh.R")).origin)
	var hips := car.to_local((left_hip + right_hip) * 0.5)
	print("Hips ", hips, " seat ", car.seat_hip)
	assert(absf(hips.x) < 0.06 and absf(hips.y - car.seat_hip.y) < 0.08, "Pelvis must be centered on driver's cushion")
	for side in ["L", "R"]:
		var foot := car.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("DEF-foot." + side)).origin))
		print("Foot ", side," ",foot)
		assert(foot.y > 0.42 and foot.y < 0.7 and absf(foot.x) < 0.4, "Feet must stay inside the footwell")
	if "--capture" in OS.get_cmdline_user_args():
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color("91a8b0")
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color.WHITE
		settings.ambient_light_energy = 0.8
		environment.environment = settings
		root.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40,-35,0)
		root.add_child(light)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(-2.8,1.55,-0.05)
		camera.look_at(Vector3(0,1.05,.2))
		camera.current = true
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_tuk_driver_pose.png")
	character.seated = false
	for frame in 8:
		character._process(0.1)
	for side in ["L", "R"]:
		var arm := rig.find_bone("DEF-upper_arm." + side)
		assert(rig.get_bone_pose_position(arm).distance_to(rig.get_bone_rest(arm).origin) < 0.001, "Arm roots must return to the standing pose after exit")
	person.queue_free()
	car.queue_free()
	entry.queue_free()
	await process_frame
	print("PASS tuk-tuk driver pose: both grip contacts, centered pelvis, feet inside footwell")
	quit()
