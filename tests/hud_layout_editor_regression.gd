extends SceneTree

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
const Profiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const Editor := preload("res://scripts/mobile/hud_layout_editor.gd")
const PATH := "user://test_hud_layout_editor.cfg"

var _failures := 0
var _viewport: SubViewport
var _closed: Array = []

func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	root.add_child(_viewport)
	var profiles := Profiles.new()
	var editor := Editor.new()
	editor.profiles = profiles
	editor.save_path = PATH
	editor.layout_provider = func(profile: StringName) -> Dictionary:
		var safe := Rect2(Vector2.ZERO, Vector2(_viewport.size))
		return {"rects": ClawLayout.compute(safe.size, safe, ClawLayout.REFERENCE_UNITS_PER_MM), "safe": safe,
			"min_target": ClawLayout.min_target(safe, ClawLayout.REFERENCE_UNITS_PER_MM),
			"labels": {&"Fire": "BRAKE" if profile == Profiles.VEHICLE else "FIRE"}, "opacity": 0.85}
	editor.closed.connect(func(saved: bool) -> void: _closed.append(saved))
	_viewport.add_child(editor)
	await process_frame

	editor.open(Profiles.COMBAT)
	await process_frame
	_check(paused and editor.is_open(), "Opening the editor pauses the game")
	_check(editor._tile_nodes.size() == Profiles.ON_FOOT_SLOTS.size(), "FIRING shows every on-foot button (%d tiles)" % editor._tile_nodes.size())

	# Drag FIRE to the centre with the pointer.
	var fire: Control = editor._tile_nodes[&"Fire"]
	var start := fire.get_global_rect().get_center()
	await _drag(start, Vector2(640, 360))
	var fire_center: Vector2 = profiles.overrides[Profiles.COMBAT][&"Fire"].center
	_check(fire_center.distance_to(Vector2(0.5, 0.5)) < 0.01, "Dragging FIRE moves it where the finger lifts (%s)" % fire_center)
	_check(editor.selected == &"Fire", "The dragged button becomes the selection")

	# Off-screen drag stays on screen.
	await _drag(Vector2(640, 360), Vector2(5000, -300))
	var rect: Rect2 = editor._context.rects[&"Fire"]
	_check(Rect2(0, 0, 1280, 720).encloses(rect), "A button dragged off screen stays fully visible (%s)" % rect)

	# Resize with the toolbar, including both limits.
	await _click_button(editor, "SIZE +")
	_check(is_equal_approx(profiles.slot_scale(Profiles.COMBAT, &"Fire"), 1.1), "SIZE + grows the selected button")
	for _i in 20:
		editor.change_size(-1.0)
	_check(profiles.slot_scale(Profiles.COMBAT, &"Fire") == Profiles.SCALE_RANGE.x, "SIZE − stops at the smallest size")
	var shrunk: Rect2 = editor._context.rects[&"Fire"]
	_check(minf(shrunk.size.x, shrunk.size.y) >= ClawLayout.min_target(Rect2(0, 0, 1280, 720), ClawLayout.REFERENCE_UNITS_PER_MM) - 0.01,
		"Even the smallest size stays a usable touch target")
	for _i in 20:
		editor.change_size(1.0)
	_check(profiles.slot_scale(Profiles.COMBAT, &"Fire") == Profiles.SCALE_RANGE.y, "SIZE + stops at the largest size")
	_check(Rect2(0, 0, 1280, 720).encloses(editor._context.rects[&"Fire"]), "A maximum-size button near the edge stays on screen")

	# Switching layout mid-edit: VEHICLE is independent and labelled for driving.
	_touch_down(editor._tile_nodes[&"Jump"].get_global_rect().get_center())
	await process_frame
	await _click_button(editor, "VEHICLE")
	_release(Vector2(10, 10))
	await process_frame
	_check(editor.profile == Profiles.VEHICLE and editor._drag_slot.is_empty(), "Switching layout ends any drag in progress")
	_check(editor._tile_nodes.size() == Profiles.VEHICLE_SLOTS.size() and not editor._tile_nodes.has(&"Talk"), "VEHICLE shows only driving buttons")
	_check((editor._tile_nodes[&"Fire"].get_child(0) as Label).text == "BRAKE", "In VEHICLE the FIRE slot is labelled BRAKE")
	_check(profiles.overrides[Profiles.VEHICLE].is_empty(), "FIRING edits did not leak into VEHICLE")
	await _click_button(editor, "OPACITY −")
	_check(is_equal_approx(profiles.opacity_for(Profiles.VEHICLE, 0.85), 0.75), "OPACITY − lowers this layout's opacity only")
	_check(not profiles.opacity.has(Profiles.COMBAT), "Other layouts keep their opacity")

	# Screen change while editing (rotation, split screen, notch change).
	_viewport.size = Vector2i(1600, 720)
	await process_frame
	await process_frame
	var wide := Rect2(0, 0, 1600, 720)
	var all_inside: bool = editor._context.rects.values().all(func(r: Rect2) -> bool: return wide.encloses(r))
	_check(all_inside and editor._context.safe == wide, "A screen size change while editing re-lays every tile inside the new screen")

	# SAVE writes, closes and unpauses.
	await _click_button(editor, "SAVE")
	_check(not editor.is_open() and not paused and _closed == [true], "SAVE closes the editor and resumes the game")
	var reloaded := Profiles.new()
	_check(reloaded.load_from(PATH) and reloaded.overrides[Profiles.COMBAT].has(&"Fire"), "SAVE writes the layouts to disk")

	# CANCEL throws away unsaved changes.
	editor.open(Profiles.COMBAT)
	await process_frame
	editor.drag_to(&"Jump", Vector2(300, 300))
	await _click_button(editor, "CANCEL")
	_check(not profiles.overrides[Profiles.COMBAT].has(&"Jump"), "CANCEL discards unsaved moves")
	_check(profiles.overrides[Profiles.COMBAT].has(&"Fire"), "CANCEL keeps what was saved before")
	_check(_closed == [true, false], "CANCEL reports an unsaved close")

	# RESET returns a layout to the defaults (and saving keeps it reset).
	editor.open(Profiles.COMBAT)
	await process_frame
	await _click_button(editor, "RESET")
	_check(not profiles.has_custom(Profiles.COMBAT), "RESET clears this layout")
	_check(profiles.has_custom(Profiles.VEHICLE), "RESET leaves other layouts alone")
	editor.save()

	# Size buttons with nothing selected do nothing harmful.
	editor.open(Profiles.NORMAL)
	await process_frame
	editor.change_size(1.0)
	_check(profiles.overrides[Profiles.NORMAL].is_empty(), "SIZE with nothing selected changes nothing")
	editor.cancel()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if _failures > 0:
		print("FAIL hud layout editor regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS hud layout editor regression: pause, drag, off-screen clamp, size limits and touch minimum, layout switch mid-drag, independent VEHICLE + opacity, screen resize while editing, save/cancel/reset")
	quit()

func _drag(from: Vector2, to: Vector2) -> void:
	_touch_down(from)
	await process_frame
	for step in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, step / 8.0)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		_viewport.push_input(motion, true)
		await process_frame
	_release(to)
	await process_frame

func _touch_down(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	_viewport.push_input(press, true)

func _release(position: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.global_position = position
	_viewport.push_input(release, true)

func _click_button(editor: Node, text: String) -> void:
	for button in editor.find_children("*", "Button", true, false):
		if button.text == text:
			var center: Vector2 = button.get_global_rect().get_center()
			var move := InputEventMouseMotion.new()
			move.position = center
			move.global_position = center
			_viewport.push_input(move, true)
			_touch_down(center)
			await process_frame
			_release(center)
			await process_frame
			return
	_check(false, "Toolbar button %s exists" % text)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
