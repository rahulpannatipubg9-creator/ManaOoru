extends SceneTree

## Custom layouts on the real HUD: the layout follows what the player is doing
## (walk -> ACTION -> drive), each layout's buttons and opacity apply, and a button
## moved onto the joystick zone still receives its own taps.

const Profiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const PLAYER := """extends CharacterBody3D
var is_running := false
var movement_enabled := true
var respawn_position := Vector3.ZERO
var touch_peek_input := 0.0
var camera_pivot: Node3D
func set_touch_move_input(_v: Vector2) -> void: pass
func set_touch_run_pressed(_v: bool) -> void: pass
func is_weapon_equipped() -> bool: return false
"""
const PIVOT := """extends Node3D
var touch_aim := false
var is_aiming := false
var gyro_mode := 0
func clear_touch_look() -> void: touch_aim = false
"""
const GAMEPLAY := """extends Node
var action_mode := false
var ammo := 24
var reserve := 120
var medkits := 0
var grenades := 3
var fire_mode := 0
var touch_fire_pressed := false
var shots := 0
func attack() -> bool:
	shots += 1
	return true
"""
const GAME := """extends Node
enum ControlState { ON_FOOT, DRIVING }
var control_state := ControlState.ON_FOOT
var gameplay: Node
var city_life: Node
var first_person_view := false
"""

var _failures := 0

func _init() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var game := Node.new()
	game.set_script(_script(GAME))
	viewport.add_child(game)
	var gameplay := Node.new()
	gameplay.set_script(_script(GAMEPLAY))
	game.add_child(gameplay)
	game.gameplay = gameplay
	var player := CharacterBody3D.new()
	player.set_script(_script(PLAYER))
	player.name = "Player"
	game.add_child(player)
	var pivot := Node3D.new()
	pivot.set_script(_script(PIVOT))
	player.add_child(pivot)
	player.camera_pivot = pivot
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	game.add_child(hud)
	await process_frame
	hud._game = game
	hud._touch_overlay_enabled = true
	hud.get_node("TouchControls").visible = true
	# Layouts arranged by the player (kept in memory; nothing is written to disk).
	hud.layout_profiles = Profiles.new()
	hud.layout_profiles.set_slot(Profiles.NORMAL, &"Run", Vector2(0.12, 0.78), 1.0)
	hud.layout_profiles.set_slot(Profiles.COMBAT, &"Fire", Vector2(0.5, 0.5), 1.2)
	hud.layout_profiles.set_slot(Profiles.VEHICLE, &"Fire", Vector2(0.9, 0.2), 1.0)
	hud.layout_profiles.set_opacity(Profiles.VEHICLE, 0.5)
	hud._layout_for_viewport()
	await process_frame

	var run: Button = hud.get_node("TouchControls/Run")
	var fire: Button = hud.btn_fire_right
	var zone: Rect2 = hud._stick.zone
	_check(hud._applied_profile == Profiles.NORMAL, "On foot in PEACE uses the NORMAL layout")
	_check(zone.has_point(run.get_global_rect().get_center()), "Setup: NORMAL puts RUN inside the joystick zone")
	var downs := [0]
	run.button_down.connect(func() -> void: downs[0] += 1)
	_tap(viewport, run.get_global_rect().get_center())
	await process_frame
	_check(downs[0] == 1 and not hud._stick.is_active(), "A button moved onto the joystick zone gets the tap, not the stick")
	_tap(viewport, zone.position + Vector2(8, 8))
	await process_frame

	gameplay.action_mode = true
	await process_frame
	await process_frame
	_check(hud._applied_profile == Profiles.COMBAT, "Switching to ACTION switches to the FIRING layout by itself")
	_check(fire.get_global_rect().get_center().distance_to(Vector2(640, 360)) < 1.0, "FIRING places FIRE where the player put it")

	game.control_state = game.ControlState.DRIVING
	await process_frame
	await process_frame
	var brake: Button = hud.get_node("TouchControls/Handbrake")
	_check(hud._applied_profile == Profiles.VEHICLE, "Driving switches to the VEHICLE layout")
	_check(brake.get_global_rect().get_center().distance_to(Vector2(1280 * 0.9, 720 * 0.2)) < 60.0, "VEHICLE places BRAKE where the player put it (%s)" % brake.get_global_rect().get_center())
	_check(is_equal_approx(hud.get_node("TouchControls").modulate.a, 0.5), "VEHICLE uses its own opacity")

	game.control_state = game.ControlState.ON_FOOT
	gameplay.action_mode = false
	await process_frame
	await process_frame
	_check(hud._applied_profile == Profiles.NORMAL and is_equal_approx(hud.get_node("TouchControls").modulate.a, hud.touch_settings.opacity),
		"Getting out returns to NORMAL with the global opacity")

	if _failures > 0:
		print("FAIL hud custom layout regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS hud custom layout regression: NORMAL/FIRING/VEHICLE follow the game state, custom positions and per-layout opacity apply, moved buttons win over the joystick zone")
	quit()

func _tap(viewport: SubViewport, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.pressed = pressed
		viewport.push_input(event)

func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
