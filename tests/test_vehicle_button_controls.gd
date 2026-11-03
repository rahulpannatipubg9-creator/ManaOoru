extends SceneTree

const MobileControlsSettings := preload("res://scripts/mobile/mobile_controls_settings.gd")
const TEST_SETTINGS_PATH := "user://test_vehicle_controls_settings.cfg"

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: %s" % message)
		_failures += 1

func _init() -> void:
	_test_settings_serialization()
	_test_hud_vehicle_controls()

func _test_settings_serialization() -> void:
	var settings := MobileControlsSettings.new()
	settings.swap_vehicle_controls = true
	var err := settings.save_to(TEST_SETTINGS_PATH)
	_check(err == OK, "Settings saved successfully")

	var loaded := MobileControlsSettings.new()
	_check(loaded.load_from(TEST_SETTINGS_PATH), "Settings loaded successfully")
	_check(loaded.swap_vehicle_controls == true, "swap_vehicle_controls persisted as true")

	loaded.swap_vehicle_controls = false
	err = loaded.save_to(TEST_SETTINGS_PATH)
	_check(err == OK, "Settings re-saved with false")

	var reloaded := MobileControlsSettings.new()
	_check(reloaded.load_from(TEST_SETTINGS_PATH), "Settings re-loaded")
	_check(reloaded.swap_vehicle_controls == false, "swap_vehicle_controls persisted as false")

	DirAccess.remove_absolute(TEST_SETTINGS_PATH)

func _test_hud_vehicle_controls() -> void:
	var tree_root := get_root()
	var game := Node.new()
	game.name = "Game"
	var MockGame := GDScript.new()
	MockGame.source_code = """
extends Node
enum ControlState { ON_FOOT, DRIVING }
var control_state: int = 0
var gameplay: Node = null
"""
	MockGame.reload()
	game.set_script(MockGame)
	tree_root.add_child(game)

	var MockPlayer := GDScript.new()
	MockPlayer.source_code = """extends CharacterBody3D
var camera_pivot: Node3D
var crouching := false
var prone := false
var equipped := false
var touch_peek_input: float = 0.0
func set_touch_move_input(_v: Vector2) -> void: pass
func set_touch_run_pressed(_v: bool) -> void: pass
func is_weapon_equipped() -> bool: return equipped
"""
	MockPlayer.reload()

	var MockPivot := GDScript.new()
	MockPivot.source_code = """extends Node3D
var look_sensitivity := 1.0
var ads_sensitivity := 0.75
var touch_aim := false
var is_aiming := false
var gyro_mode := 0
func clear_touch_look() -> void: touch_aim = false
"""
	MockPivot.reload()

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(MockPlayer)
	var cam_pivot := Node3D.new()
	cam_pivot.name = "CameraPivot"
	cam_pivot.set_script(MockPivot)
	player.add_child(cam_pivot)
	player.camera_pivot = cam_pivot
	tree_root.add_child(player)

	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	tree_root.add_child(hud)
	await process_frame

	var mock_vehicle := RigidBody3D.new()
	mock_vehicle.set_script(load("res://scripts/vehicle/rigid_vehicle.gd"))
	tree_root.add_child(mock_vehicle)

	hud._game = game
	hud._vehicle = mock_vehicle
	hud._touch_overlay_enabled = true
	hud.get_node("TouchControls").visible = true
	hud._layout_for_viewport()

	# 1. On foot state
	game.control_state = 0 # ON_FOOT
	hud._refresh_touch()
	await process_frame

	var fwd: Button = hud.get_node("TouchControls/DriveForward")
	var back: Button = hud.get_node("TouchControls/DriveBack")
	var left: Button = hud.get_node("TouchControls/DriveLeft")
	var right: Button = hud.get_node("TouchControls/DriveRight")
	var stick_base: Control = hud.get_node("TouchControls/JoystickBase")

	_check(stick_base.visible, "On foot: JoystickBase is visible")
	_check(not fwd.visible, "On foot: DriveForward is hidden")
	_check(not back.visible, "On foot: DriveBack is hidden")
	_check(not left.visible, "On foot: DriveLeft is hidden")
	_check(not right.visible, "On foot: DriveRight is hidden")

	# 2. Driving state
	game.control_state = 1 # DRIVING
	hud._refresh_touch()
	await process_frame

	_check(not stick_base.visible, "Driving: JoystickBase is hidden")
	_check(fwd.visible, "Driving: DriveForward is visible")
	_check(back.visible, "Driving: DriveBack is visible")
	_check(left.visible, "Driving: DriveLeft is visible")
	_check(right.visible, "Driving: DriveRight is visible")

	# 3. Position check: default (Forward/Back on left, Left/Right on right)
	_check(fwd.position.x < left.position.x, "Default: Forward/Back is on left side of Left/Right")
	_check(fwd.position.y < back.position.y, "Forward is above Back")
	_check(left.position.x < right.position.x, "Left is to the left of Right")

	# 4. Swapped controls check
	hud.touch_settings.swap_vehicle_controls = true
	hud._layout_for_viewport()
	await process_frame

	_check(left.position.x < fwd.position.x, "Swapped: Left/Right is on left side of Forward/Back")

	# Restore default
	hud.touch_settings.swap_vehicle_controls = false
	hud._layout_for_viewport()
	await process_frame

	# 5. Input testing via touch handlers
	# Tap forward
	var touch_fwd := InputEventScreenTouch.new()
	touch_fwd.index = 0
	touch_fwd.pressed = true
	touch_fwd.position = fwd.get_global_rect().get_center()
	_check(hud._handle_drive_screen_touch(touch_fwd), "Touch on Forward handled")
	_check(mock_vehicle.touch_move_input.y == -1.0, "Forward sets throttle_y to -1.0 (got %s)" % mock_vehicle.touch_move_input.y)

	# Drag to back
	var drag_back := InputEventScreenDrag.new()
	drag_back.index = 0
	drag_back.position = back.get_global_rect().get_center()
	_check(hud._handle_drive_screen_drag(drag_back), "Drag to Back handled")
	_check(mock_vehicle.touch_move_input.y == 1.0, "Drag sets throttle_y to 1.0 (got %s)" % mock_vehicle.touch_move_input.y)

	# Release vertical
	var release_vert := InputEventScreenTouch.new()
	release_vert.index = 0
	release_vert.pressed = false
	_check(hud._handle_drive_screen_touch(release_vert), "Release vertical handled")
	_check(mock_vehicle.touch_move_input.y == 0.0, "Release sets throttle_y to 0.0")

	# Multi-touch: Tap right with finger 1 while steering
	var touch_right := InputEventScreenTouch.new()
	touch_right.index = 1
	touch_right.pressed = true
	touch_right.position = right.get_global_rect().get_center()
	_check(hud._handle_drive_screen_touch(touch_right), "Touch on Right handled")
	_check(mock_vehicle.touch_move_input.x == 1.0, "Right sets steer to 1.0")

	# Tap forward at the same time with finger 0
	touch_fwd.index = 0
	touch_fwd.pressed = true
	touch_fwd.position = fwd.get_global_rect().get_center()
	_check(hud._handle_drive_screen_touch(touch_fwd), "Simultaneous touch on Forward handled")
	_check(mock_vehicle.touch_move_input.is_equal_approx(Vector2(1.0, -1.0).normalized()), "Simultaneous input matches normalized diagonal Vector2(1, -1) (got %s)" % mock_vehicle.touch_move_input)

	# Clear inputs
	hud.clear_touch_inputs()
	_check(mock_vehicle.touch_move_input == Vector2.ZERO, "clear_touch_inputs resets vehicle touch input")

	hud.queue_free()
	mock_vehicle.queue_free()
	player.queue_free()
	game.queue_free()

	if _failures > 0:
		print("FAIL test_vehicle_button_controls: %d check(s) failed" % _failures)
		quit(1)
		return

	print("PASS test_vehicle_button_controls: Button controls layout, visibility, swap toggle, multi-touch forward/reverse/steer inputs, and settings persistence verified.")
	quit(0)
