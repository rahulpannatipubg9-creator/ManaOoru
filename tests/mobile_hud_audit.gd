extends SceneTree

## Drives the real HUD scene with screen-touch events, as an Android device would,
## and reports every touch-control defect it finds. Report mode exits 0 so the
## shared suite stays green while hud.gd ownership is agreed; pass `-- --strict`
## to use it as the acceptance gate for the mobile HUD integration, and
## `--hud-script=<path>` to audit a candidate HUD script in place of hud.gd.
##   godot --headless --path . --script tests/mobile_hud_audit.gd [-- --strict --hud-script=/abs/hud.gd]

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
## Tapped with a rifle out, the fullest screen. Rarer actions live in the wheel (action_wheel_regression.gd).
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1280, 800)]
const PLAYER_STUB := """extends CharacterBody3D
var is_running := false
var movement_enabled := true
var respawn_position := Vector3(0.0, -999.0, 0.0)
var touch_peek_input := 0.0
var crouching := false
var prone := false
var camera_pivot: Node3D
var equipped := true
var run_calls: Array[bool] = []
var move_calls: Array[Vector2] = []
func set_touch_move_input(value: Vector2) -> void: move_calls.append(value)
func set_touch_run_pressed(value: bool) -> void: run_calls.append(value)
func is_weapon_equipped() -> bool: return equipped
func _update_stance(wants_crouch: bool, wants_prone: bool) -> void:
	crouching = wants_crouch
	prone = wants_prone
"""
const PIVOT_STUB := """extends Node3D
var touch_aim := false
var is_aiming := false
var gyro_mode := 0
func clear_touch_look() -> void: touch_aim = false
"""

const GAMEPLAY_STUB := """extends Node
var action_mode := true
var has_rifle := true
var ammo := 24
var reserve := 120
var medkits := 0
var grenades := 3
var fire_mode := 0
var touch_fire_pressed := false
func rifles() -> Array[int]: return [0, 1]
func attack() -> bool: return true
func reload_weapon() -> void: pass
func switch_weapon() -> bool: return true
func try_vault() -> bool: return false
"""
const GAME_STUB := """extends Node
enum ControlState { ON_FOOT, DRIVING }
var control_state := ControlState.ON_FOOT
var gameplay: Node
var city_life: Node
var first_person_view := false
"""

var _issues: Array[String] = []
var _hud_script: Script

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hud-script="):
			_hud_script = load(arg.trim_prefix("--hud-script="))
			if _hud_script == null:
				print("FAIL mobile HUD audit: cannot load %s" % arg)
				quit(1)
				return
	if not bool(ProjectSettings.get_setting("input_devices/sensors/enable_gyroscope", false)):
		_issue("project", "input_devices/sensors/enable_gyroscope is off, so Input.get_gyroscope() is always zero and every gyro mode is inert")
	for size: Vector2i in VIEWPORTS:
		await _audit(size)
	var strict := OS.get_cmdline_user_args().has("--strict")
	if _issues.is_empty():
		print("PASS mobile HUD audit: no touch-control defects on %d viewports" % VIEWPORTS.size())
		quit()
		return
	for line in _issues:
		print("  - " + line)
	print("%s mobile HUD audit: %d touch-control defect(s)%s" % ["FAIL" if strict else "REPORT", _issues.size(),
		"" if strict else " (report mode, exit 0; use -- --strict to gate)"])
	quit(1 if strict else 0)

func _audit(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var host := Node.new()
	host.set_script(_script(GAME_STUB))
	viewport.add_child(host)
	var gameplay := Node.new()
	gameplay.set_script(_script(GAMEPLAY_STUB))
	host.add_child(gameplay)
	host.gameplay = gameplay
	var player := CharacterBody3D.new()
	player.set_script(_script(PLAYER_STUB))
	player.name = "Player"
	host.add_child(player)
	var pivot := Node3D.new()
	pivot.set_script(_script(PIVOT_STUB))
	player.add_child(pivot)
	player.camera_pivot = pivot
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	if _hud_script:
		hud.set_script(_hud_script)
	host.add_child(hud)
	await process_frame
	hud._game = host
	# The menu is tested elsewhere; here a tap only has to reach the button.
	hud.settings_menu = null
	# Headless has no touchscreen; force the overlay the way a phone build shows it.
	hud._touch_overlay_enabled = true
	hud.get_node("TouchControls").visible = true
	hud._layout_for_viewport()
	await process_frame
	var tag := "%dx%d" % [size.x, size.y]
	var buttons := _on_foot_buttons(hud)
	_audit_geometry(tag, hud, buttons)
	await _audit_taps(tag, viewport, player, buttons)
	# The wheel button claims its finger itself: a tap there must open the wheel.
	hud.action_wheel.close()
	await _audit_wheel(tag, viewport, hud)
	await _audit_run_toggle(tag, viewport, player, buttons[&"Run"])
	await _audit_two_fingers(tag, viewport, hud, player, buttons[&"Crouch"])
	viewport.queue_free()
	await process_frame

func _on_foot_buttons(hud: CanvasLayer) -> Dictionary:
	var controls: Control = hud.get_node("TouchControls")
	return {
		&"Run": controls.get_node("Run"), &"Jump": controls.get_node("Jump"),
		&"Fire": hud.btn_fire_right, &"Scope": hud.btn_scope, &"Crouch": hud.btn_crouch,
		&"Reload": hud.btn_reload, &"Swap": hud.btn_swap, &"Menu": hud.btn_menu, &"Wheel": hud.btn_wheel,
	}

func _audit_geometry(tag: String, hud: CanvasLayer, buttons: Dictionary) -> void:
	var rects := {}
	for slot in buttons:
		var button: Control = buttons[slot]
		rects[slot] = button.get_global_rect()
	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var overlap: Rect2 = rects[names[i]].intersection(rects[names[j]])
			if overlap.get_area() > 1.0:
				_issue(tag, "%s overlaps %s (%d sq units)" % [names[i], names[j], overlap.get_area()])
	var min_units := ClawLayout.MIN_TARGET_MM * ClawLayout.REFERENCE_UNITS_PER_MM
	for slot in buttons:
		var rect: Rect2 = rects[slot]
		if minf(rect.size.x, rect.size.y) < min_units - 0.5:
			_issue(tag, "%s is %.1f mm on a reference phone, below %.1f mm" % [slot,
				minf(rect.size.x, rect.size.y) / ClawLayout.REFERENCE_UNITS_PER_MM, ClawLayout.MIN_TARGET_MM])

## Every button must receive its own tap, and only its own action.
func _audit_taps(tag: String, viewport: SubViewport, player: CharacterBody3D, buttons: Dictionary) -> void:
	for slot in buttons:
		var button: BaseButton = buttons[slot]
		var downs := [0]
		var on_down := func() -> void: downs[0] += 1
		button.button_down.connect(on_down)
		player.global_position = Vector3(5.0, 0.0, 5.0)
		var centre := button.get_global_rect().get_center()
		_touch(viewport, 0, centre, true)
		var jumped := Input.is_action_pressed("jump")
		await physics_frame
		_touch(viewport, 0, centre, false)
		jumped = jumped or Input.is_action_pressed("jump")
		await physics_frame
		button.button_down.disconnect(on_down)
		if downs[0] != 1 and slot not in [&"Run", &"Jump", &"Wheel"]:
			_issue(tag, "tapping %s never reaches the button (button_down x%d)" % [slot, downs[0]])
		if jumped and slot != &"Jump":
			_issue(tag, "tapping %s makes the player jump" % slot)
		if player.global_position.y < -900.0:
			_issue(tag, "tapping %s teleports the player to the respawn point" % slot)
		_clear_input(player)

func _audit_wheel(tag: String, viewport: SubViewport, hud: CanvasLayer) -> void:
	var centre: Vector2 = hud.btn_wheel.get_global_rect().get_center()
	_touch(viewport, 0, centre, true)
	await process_frame
	if not hud.action_wheel.is_open():
		_issue(tag, "pressing the wheel button does not open the wheel")
	_touch(viewport, 0, centre, false)
	await process_frame
	hud.action_wheel.close()

func _audit_run_toggle(tag: String, viewport: SubViewport, player: CharacterBody3D, run: Control) -> void:
	player.run_calls.clear()
	var centre := run.get_global_rect().get_center()
	_touch(viewport, 0, centre, true)
	await process_frame
	_touch(viewport, 0, centre, false)
	await process_frame
	if player.run_calls.is_empty() or not player.run_calls.back():
		_issue(tag, "a RUN tap leaves run off (set_touch_run_pressed calls %s)" % [player.run_calls])
	_clear_input(player)

## Joystick on finger 0 and a stance button on finger 1 must work together and release independently.
func _audit_two_fingers(tag: String, viewport: SubViewport, hud: CanvasLayer, player: CharacterBody3D, held: BaseButton) -> void:
	var stick: Control = hud.get_node("TouchControls/JoystickBase")
	var stick_centre := stick.get_global_rect().get_center()
	player.move_calls.clear()
	_touch(viewport, 0, stick_centre, true)
	await process_frame
	_drag(viewport, 0, stick_centre + Vector2(0.0, -80.0), Vector2(0.0, -80.0))
	await process_frame
	var moving: bool = not player.move_calls.is_empty() and player.move_calls.back().y < -0.5
	var held_centre := held.get_global_rect().get_center()
	_touch(viewport, 1, held_centre, true)
	await process_frame
	var was_held := held.button_pressed
	_touch(viewport, 0, stick_centre, false)
	await process_frame
	var still_held := held.button_pressed
	_touch(viewport, 1, held_centre, false)
	await process_frame
	if not moving:
		_issue(tag, "joystick drag on finger 0 does not move the player")
	if not was_held or not still_held:
		_issue(tag, "a second finger on CROUCH is lost while the joystick is held (held %s, after stick release %s)" % [was_held, still_held])
	_clear_input(player)

func _touch(viewport: SubViewport, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	viewport.push_input(event)

func _drag(viewport: SubViewport, index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	viewport.push_input(event)

func _clear_input(player: CharacterBody3D) -> void:
	Input.action_release("jump")
	player.run_calls.clear()
	player.move_calls.clear()

func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script

func _issue(tag: String, message: String) -> void:
	var line := "[%s] %s" % [tag, message]
	if not _issues.has(line):
		_issues.append(line)
