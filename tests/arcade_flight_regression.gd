extends SceneTree

func frames(count: int) -> void:
	for frame in roundi(count * Engine.physics_ticks_per_second / 60.0):
		await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--physics-rate="):
			Engine.physics_ticks_per_second = int(argument.get_slice("=", 1))
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var heli := (load("res://scenes/vehicles/gdk_helicopter.tscn") as PackedScene).instantiate() as GdkHelicopter
	heli.position = Vector3(0, 1.35, 0)
	root.add_child(heli)
	await frames(2)
	heli.set_driving_enabled(true)
	heli.set_input_authority(true)
	heli.set_keyboard_input_enabled(true)
	key(KEY_SPACE, true)
	await frames(180)
	key(KEY_SPACE, false)
	assert(heli.position.y > 8.0, "Space must take off vertically")
	assert(heli.linear_velocity.slide(Vector3.UP).length() < 0.1, "Vertical takeoff must not push sideways")
	assert(not heli.can_exit_safely(), "F must be blocked in flight")
	await frames(120)
	var height := heli.position.y
	key(KEY_W, true)
	await frames(360)
	key(KEY_W, false)
	var cruise := heli.current_speed * 3.6
	assert(cruise >= 60.0 and cruise <= 100.0, "Cruise speed must reach 60–100 km/h: %f" % cruise)
	assert(heli.position.z < -40.0, "W must fly toward the visual nose (-Z)")
	assert(absf(heli.position.y - height) < 1.0, "Forward flight must not automatically climb")
	assert(absf(heli.current_speed - heli.linear_velocity.slide(Vector3.UP).length()) < 0.5, "HUD speed must measure horizontal physics velocity")
	await frames(420)
	assert(heli.current_speed < 0.2 and absf(heli.position.y - height) < 1.0, "Released controls must stabilize horizontal drift and altitude")
	var reverse_z := heli.position.z
	key(KEY_S, true)
	await frames(90)
	key(KEY_S, false)
	assert(heli.position.z > reverse_z + 2.0, "S must fly backward, not command descent")
	await frames(180)
	key(KEY_W, true)
	key(KEY_S, true)
	await frames(90)
	key(KEY_W, false)
	key(KEY_S, false)
	assert(heli.current_speed < 0.2, "Opposing W/S inputs must cancel")
	var x := heli.position.x
	key(KEY_D, true)
	await frames(90)
	key(KEY_D, false)
	assert(heli.position.x > x + 2.0, "D must strafe right")
	assert(absf((heli.get_node("Model") as Node3D).rotation.z) > 0.05, "Strafe must visibly bank")
	await frames(180)
	key(KEY_Q, true)
	await frames(90)
	key(KEY_Q, false)
	assert(heli.global_rotation.y > 0.2, "Q must yaw left")
	key(KEY_E, true)
	await frames(180)
	key(KEY_E, false)
	assert(heli.global_rotation.y < 0.1, "E must yaw right without exiting")
	key(KEY_W, true)
	key(KEY_CTRL, true)
	await frames(480)
	key(KEY_W, false)
	key(KEY_CTRL, false)
	var fast_speed := heli.current_speed * 3.6
	assert(heli.current_speed * 3.6 >= 120.0 and heli.current_speed * 3.6 <= 160.0, "Fast flight must reach 120–160 km/h")
	key(KEY_SHIFT, true)
	await frames(90)
	key(KEY_SHIFT, false)
	assert(heli.position.y < height - 3.0, "Shift must descend, never also ascend")
	GameplayControls.blocked = true
	key(KEY_SPACE, true)
	var blocked_height := heli.position.y
	await frames(120)
	key(KEY_SPACE, false)
	assert(absf(heli.position.y - blocked_height) < 2.0, "Blocked controls must not climb or lose assisted hover")
	GameplayControls.blocked = false
	heli.set_touch_descend_pressed(true)
	await frames(360)
	heli.set_touch_descend_pressed(false)
	await frames(60)
	assert(heli.can_exit_safely(), "Landed helicopter must allow F")
	var platform := StaticBody3D.new()
	var platform_collision := CollisionShape3D.new()
	var platform_box := BoxShape3D.new()
	platform_box.size = Vector3(40, 6, 40)
	platform_collision.shape = platform_box
	platform_collision.position = Vector3(700, 3, 700)
	platform.add_child(platform_collision)
	root.add_child(platform)
	heli.set_driving_enabled(false)
	heli.position = Vector3(700, 18, 700)
	heli.set_driving_enabled(true)
	heli.set_touch_descend_pressed(true)
	await frames(360)
	heli.set_touch_descend_pressed(false)
	await frames(60)
	assert(heli.position.y > 5.0 and heli.can_exit_safely(), "Landing detection must work away from the original pad at a different elevation")
	print("PASS arcade flight: vertical takeoff, %.1f km/h cruise, %.1f km/h fast flight, hover, altitude, strafe/bank, Q/E yaw, Shift descent, HUD speed, physical landing at two elevations" % [cruise, fast_speed])
	quit()
