extends SceneTree

func _init() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var scene := load("res://scenes/vehicles/gdk_helicopter.tscn") as PackedScene
	assert(scene != null, "Helicopter scene must load")
	var helicopter := scene.instantiate() as RigidBody3D
	helicopter.position = Vector3(0.0, 1.35, 0.0)
	root.add_child(helicopter)
	await physics_frame
	assert(absf((helicopter.get_node("Model") as Node3D).rotation.x - PI * 0.5) < 0.01,
		"Helicopter visual model must be aligned horizontally with its collision body")
	assert(absf(angle_difference((helicopter.get_node("Model") as Node3D).rotation.y, PI)) < 0.01,
		"Visual fuselage must retain its 180-degree heading correction independently of controls")
	assert(helicopter.get_node_or_null("AnimatedMainRotor") != null, "Animated main rotor missing")
	assert(helicopter.get_node_or_null("RotorEngineAudio") != null, "Helicopter engine audio missing")
	assert((helicopter.get_node("RotorEngineAudio") as AudioStreamPlayer3D).volume_db >= 0.0,
		"Helicopter engine audio must be audible while driving")
	helicopter.set_driving_enabled(true)
	helicopter.set_input_authority(true)
	helicopter.set_keyboard_input_enabled(false)
	helicopter.set_touch_run_pressed(true)
	helicopter.set_touch_move_input(Vector2(0.0, -1.0))
	var start_y: float = helicopter.global_position.y
	var start_z: float = helicopter.global_position.z
	for _frame in 120:
		await physics_frame
	assert(helicopter.global_position.y > start_y + 2.0, "Collective input must lift the helicopter")
	assert(absf(helicopter.global_position.z - start_z) > 0.25, "Cyclic pitch must produce forward flight")
	assert((helicopter.get_node("AnimatedMainRotor") as Node3D).rotation.y != 0.0, "Rotor must spin after engine start")
	helicopter.set_touch_run_pressed(false)
	assert(not helicopter.can_exit_safely(), "Airborne helicopter must reject vehicle exit")
	print("PASS helicopter regression: takeoff and airborne exit safety")
	quit()
