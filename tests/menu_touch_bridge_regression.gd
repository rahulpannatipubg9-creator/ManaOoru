extends SceneTree

## The bridge must turn touch-to-mouse emulation on only while a menu is open over a
## paused game, swallow raw touches only then, and always leave gameplay with true
## multi-touch. (Headless runs cannot deliver OS-level emulated events, so the
## controls' response to the emulated pointer is verified on the device.)

const MenuTouchBridge := preload("res://scripts/mobile/menu_touch_bridge.gd")

var _failures := 0
var _menu_open := false

func _init() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var bridge := MenuTouchBridge.new()
	bridge.is_menu_open = func() -> bool: return _menu_open
	viewport.add_child(bridge)
	var button := Button.new()
	button.position = Vector2(100, 100)
	button.size = Vector2(200, 60)
	viewport.add_child(button)
	var downs := [0]
	button.button_down.connect(func() -> void: downs[0] += 1)
	await process_frame

	await _settle()
	_check(not Input.emulate_mouse_from_touch, "Gameplay must keep emulation off")
	await _tap(viewport, button.get_global_rect().get_center())
	_check(downs[0] == 1, "With no menu open a touch must reach the button directly (%d)" % downs[0])

	_menu_open = true
	await _settle()
	_check(not Input.emulate_mouse_from_touch, "A menu over a running game must not enable emulation (it could fire the rifle)")

	paused = true
	await _settle()
	_check(Input.emulate_mouse_from_touch, "A menu over a paused game must enable emulation")
	downs[0] = 0
	await _tap(viewport, button.get_global_rect().get_center())
	_check(downs[0] == 0, "Raw touches must be swallowed while emulation is on, so buttons are not pressed twice (%d)" % downs[0])

	# "Save & Return" closes the menu on the finger's lift: that lift must not fall
	# through onto whatever sits under the button (the minimap, on the tablet).
	var below := Control.new()
	below.position = Vector2(700, 100)
	below.size = Vector2(200, 200)
	below.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.add_child(below)
	var touches := [0]
	below.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch: touches[0] += 1)
	var spot := below.get_global_rect().get_center()
	_touch(viewport, 0, spot, true)
	await process_frame
	_menu_open = false
	paused = false
	await process_frame
	_touch(viewport, 0, spot, false)
	await _settle()
	_check(touches[0] == 0, "The lift that closes a menu must not reach the control under it (%d touches)" % touches[0])
	paused = true
	_menu_open = false
	await _settle()
	_check(not Input.emulate_mouse_from_touch, "Closing the menu must restore true multi-touch")
	paused = false
	bridge.queue_free()
	await process_frame
	_check(not Input.emulate_mouse_from_touch, "Removing the bridge must leave emulation off")

	if _failures > 0:
		print("FAIL menu touch bridge regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS menu touch bridge regression: emulation only while a menu is open over a paused game, raw touches swallowed then, closing lift never falls through, multi-touch restored on close")
	quit()

func _settle() -> void:
	await process_frame
	await process_frame

func _tap(viewport: SubViewport, position: Vector2) -> void:
	for pressed in [true, false]:
		_touch(viewport, 0, position, pressed)
		await process_frame

func _touch(viewport: SubViewport, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	viewport.push_input(event)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
