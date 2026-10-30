extends SceneTree

## The radial wheel on its own, driven by the events a phone or keyboard would send:
## slide and lift, tap then tap, cancel, unusable items and the held key.

const ActionWheel := preload("res://scripts/ui/action_wheel.gd")

var _failures := 0
var _viewport: SubViewport
var _wheel: Control
var _trigger: Button
var _picked: Array[StringName] = []

func _init() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	root.add_child(_viewport)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	_viewport.add_child(host)
	_trigger = Button.new()
	_trigger.position = Vector2(1160, 340)
	_trigger.size = Vector2(80, 80)
	host.add_child(_trigger)
	_wheel = ActionWheel.new()
	_wheel.trigger = _trigger
	_wheel.provider = func() -> Array[Dictionary]:
		var items: Array[Dictionary] = [
			{"id": &"up", "icon": &"medkit", "label": "Up"},
			{"id": &"right", "icon": &"talk", "label": "Right"},
			{"id": &"down", "icon": &"help", "label": "Down", "enabled": false},
			{"id": &"left", "icon": &"avatar", "label": "Left", "count": 2},
		]
		return items
	_wheel.chosen.connect(func(id: StringName) -> void: _picked.append(id))
	host.add_child(_wheel)
	await process_frame
	_check(_wheel.size == Vector2(1280, 720), "The wheel fills the screen (%s)" % _wheel.size)
	_test_directions()
	await _test_slide_and_lift()
	await _test_tap_then_tap()
	await _test_cancel()
	await _test_key()
	if _failures > 0:
		print("FAIL action wheel regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS action wheel regression: directions, slide and lift, tap then tap, tap outside, unusable items, cancelled touch, held key with virtual pointer")
	quit()

func _test_directions() -> void:
	_wheel.open()
	_check(_wheel.index_for(Vector2.UP) == 0, "Item 0 is straight up")
	_check(_wheel.index_for(Vector2.RIGHT) == 1, "Items run clockwise")
	_check(_wheel.index_for(Vector2.DOWN) == 2, "Item 2 is down")
	_check(_wheel.index_for(Vector2.LEFT) == 3, "Item 3 is left")
	_check(_wheel.index_for(Vector2(-1.0, -3.0)) == 0, "Just left of up is still up")
	_wheel.close()

func _test_slide_and_lift() -> void:
	var start := _trigger.get_global_rect().get_center()
	_touch(1, start, true)
	await process_frame
	_check(_wheel.is_open(), "Pressing the button opens the wheel")
	_drag(1, start + Vector2(10.0, 0.0))
	_check(_wheel.selected == -1, "A small slide picks nothing")
	_drag(1, start + Vector2(90.0, 0.0))
	_check(_wheel.selected == 1, "Sliding right highlights the right item")
	_touch(1, start + Vector2(90.0, 0.0), false)
	await process_frame
	_check(_picked == [&"right"], "Lifting chooses it (%s)" % [_picked])
	_check(not _wheel.is_open(), "Choosing closes the wheel")
	_picked.clear()
	_touch(1, start, true)
	_drag(1, start + Vector2(0.0, 90.0))
	_touch(1, start + Vector2(0.0, 90.0), false)
	await process_frame
	_check(_picked.is_empty() and not _wheel.is_open(), "An unusable item does nothing and the wheel closes")

func _test_tap_then_tap() -> void:
	var start := _trigger.get_global_rect().get_center()
	_touch(2, start, true)
	await process_frame
	_touch(2, start, false)
	await process_frame
	_check(_wheel.is_open() and _wheel.sticky, "A quick tap leaves the wheel open")
	var spot: Vector2 = _wheel.center() + Vector2.LEFT * (_wheel.inner_radius() + _wheel.outer_radius()) * 0.5
	_touch(3, spot, true)
	await process_frame
	_check(_picked == [&"left"] and not _wheel.is_open(), "Tapping an item chooses it (%s)" % [_picked])
	_touch(3, spot, false)
	_picked.clear()
	_touch(2, start, true)
	await process_frame
	_touch(2, start, false)
	await process_frame
	_touch(3, Vector2(8.0, 8.0), true)
	await process_frame
	_touch(3, Vector2(8.0, 8.0), false)
	_check(_picked.is_empty() and not _wheel.is_open(), "Tapping outside closes without choosing")
	_touch(2, start, true)
	await process_frame
	_touch(2, start, false)
	await process_frame
	_touch(3, _wheel.center(), true)
	_touch(3, _wheel.center(), false)
	_check(_picked.is_empty() and not _wheel.is_open(), "Tapping the centre closes without choosing")

func _test_cancel() -> void:
	var start := _trigger.get_global_rect().get_center()
	_touch(1, start, true)
	_drag(1, start + Vector2(90.0, 0.0))
	var event := InputEventScreenTouch.new()
	event.index = 1
	event.position = start
	event.canceled = true
	_viewport.push_input(event)
	await process_frame
	_check(_picked.is_empty() and not _wheel.is_open(), "A cancelled touch chooses nothing")

func _test_key() -> void:
	_wheel.key_down()
	_check(_wheel.is_open(), "Holding the key opens the wheel")
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(-60.0, 0.0)
	_viewport.push_input(move)
	_check(_wheel.selected == 3, "Mouse movement steers the pick while the mouse is captured")
	_wheel.key_up()
	_check(_picked == [&"left"], "Letting go chooses it (%s)" % [_picked])
	_picked.clear()
	_wheel.key_down()
	_wheel.key_up()
	_check(_picked.is_empty() and not _wheel.is_open(), "Tapping the key with no direction chooses nothing")
	_wheel.key_up()
	await process_frame

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_viewport.push_input(event)

func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	_viewport.push_input(event)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
