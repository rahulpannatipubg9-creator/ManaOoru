extends SceneTree
var _game: Node

func frames(count: int) -> void:
	for frame in count:
		# A render-only test window can be behind the user's app. Supply a
		# synthetic focus event for capture; real OS focus remains a manual check.
		if "--capture" in OS.get_cmdline_user_args() and is_instance_valid(_game) and _game.is_inside_tree():
			_game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
			_game._sync_input_context()
		await physics_frame

func wait_driving(game: Node) -> void:
	for frame in 360:
		if game.control_state == game.ControlState.DRIVING:
			return
		await physics_frame
	assert(false, "Vehicle entry timed out")

func _init() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_game = game
	root.add_child(game)
	await frames(90)
	var person: CharacterBody3D = game.person
	Input.action_press("crouch")
	await frames(5)
	Input.action_release("crouch")
	assert(person.crouching, "C must toggle crouch on foot")
	await frames(5)
	Input.action_press("crouch")
	await frames(5)
	Input.action_release("crouch")
	assert(not person.crouching, "C must toggle standing when headroom is clear")
	var field := LineEdit.new()
	game.add_child(field)
	field.grab_focus()
	game._sync_input_context()
	assert(GameplayControls.blocked, "Text fields must suspend gameplay")
	assert(not GameplayControls.allows(person), "Typing must not control the person")
	field.release_focus()
	field.queue_free()
	game._sync_input_context()
	assert(not GameplayControls.blocked, "Leaving text UI must restore gameplay")
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(GameplayControls.blocked and person.touch_move_input == Vector2.ZERO, "Window blur must clear held controls")
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	game._sync_input_context()
	var heli := game.get_node("Chowrastha Helicopter") as GdkHelicopter
	person.global_position = game._door_position(heli, -1.0)
	game.enter_vehicle(heli)
	await wait_driving(game)
	assert(GameplayControls.owner_id == heli.get_instance_id() and not person.input_authority, "Only occupied helicopter may receive movement")
	heli.set_touch_run_pressed(true)
	await frames(480)
	heli.set_touch_run_pressed(false)
	await frames(120)
	assert(heli.position.y > heli.respawn_position.y + 20.0, "Helicopter must take off in the actual city")
	assert(not person.visible, "Helicopter pilot must not render above the rotor using the generic car-seat pose")
	game.exit_vehicle()
	assert(game.control_state == game.ControlState.DRIVING, "F must not eject an airborne player")
	heli.set_touch_move_input(Vector2(0, -1))
	var start := heli.position
	await frames(300)
	heli.set_touch_move_input(Vector2.ZERO)
	assert(heli.position.distance_to(start) > 40.0, "Helicopter must explore real city geometry")
	assert(game.tracked_body() == heli, "Minimap must track occupied helicopter")
	assert(MapCanvas.heading_of(heli).dot(Vector2(heli.forward_direction().x, heli.forward_direction().z)) > 0.99,
		"Minimap helicopter heading must match its visual nose")
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_arcade_flight.png")
		print("PASS rendered city flight: entry, takeoff, flight camera, hidden pilot, HUD and minimap capture")
		quit()
		return
	heli.recover_vehicle()
	await frames(60)
	assert(heli.can_exit_safely(), "Helicopter recovery must return to its landed safe point")
	game.exit_vehicle()
	for frame in 360:
		if game.control_state == game.ControlState.ON_FOOT:
			break
		await physics_frame
	assert(game.control_state == game.ControlState.ON_FOOT and person.input_authority, "Landed exit must restore on-foot control")
	var car: PhysicsBody3D = game.get_node("Vehicle")
	person.global_position = game._door_position(car, -1.0)
	game.enter_vehicle(car)
	await wait_driving(game)
	assert(GameplayControls.owner_id == car.get_instance_id() and not heli.input_authority, "Vehicle switching must remove previous flight authority")
	car.set_touch_move_input(Vector2(0, -1))
	var car_start := car.position
	await frames(90)
	assert(car.position.distance_to(car_start) > 1.0, "Switched-to car must drive without mouse-button input")
	print("PASS exploration flow: text focus, blur, helicopter entry/takeoff/city flight/recovery/exit, minimap heading, switch to car and drive")
	quit()
