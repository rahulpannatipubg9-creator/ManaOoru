extends SceneTree

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
const FloatingJoystick := preload("res://scripts/mobile/floating_joystick.gd")
const GyroLook := preload("res://scripts/mobile/gyro_look.gd")
const MobileControlsSettings := preload("res://scripts/mobile/mobile_controls_settings.gd")
const SETTINGS_PATH := "user://test_mobile_controls.cfg"

## Canvas size, window pixels, dpi, and safe-area insets in pixels (left, top, right, bottom).
const DEVICES := [
	{"name": "16:9 phone", "visible": Vector2(1280, 720), "pixels": Vector2(1920, 1080), "dpi": 401.0, "insets": Vector4(0, 0, 0, 0)},
	{"name": "20:9 notch phone", "visible": Vector2(1600, 720), "pixels": Vector2(2400, 1080), "dpi": 405.0, "insets": Vector4(110, 0, 0, 63)},
	{"name": "19.5:9 notch phone (rotated)", "visible": Vector2(1560, 720), "pixels": Vector2(2532, 1170), "dpi": 460.0, "insets": Vector4(0, 0, 141, 63)},
	{"name": "small 5in phone", "visible": Vector2(1280, 720), "pixels": Vector2(1280, 720), "dpi": 294.0, "insets": Vector4(0, 0, 0, 0)},
	{"name": "16:10 tablet (Xiaomi Pad class)", "visible": Vector2(1280, 800), "pixels": Vector2(3200, 2000), "dpi": 344.0, "insets": Vector4(0, 0, 0, 0)},
	{"name": "4:3 tablet", "visible": Vector2(1280, 960), "pixels": Vector2(2048, 1536), "dpi": 264.0, "insets": Vector4(0, 0, 0, 40)},
	{"name": "unknown density", "visible": Vector2(1280, 720), "pixels": Vector2(1920, 1080), "dpi": 0.0, "insets": Vector4(0, 0, 0, 0)},
]

var _failures := 0

func _init() -> void:
	# A script that fails to compile still lets this runner reach PASS, so prove the modules load.
	for module: GDScript in [ClawLayout, FloatingJoystick, GyroLook, MobileControlsSettings]:
		if not module.can_instantiate():
			print("FAIL mobile controls regression: %s does not compile" % module.resource_path)
			quit(1)
			return
	_test_layouts()
	_test_safe_area_conversion()
	_test_joystick()
	_test_gyro()
	_test_settings()
	if _failures > 0:
		print("FAIL mobile controls regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS mobile controls regression: claw layout on %d device shapes x 3 scales x both hands (no overlap, inside safe area, >= %.1f mm targets), safe-area mapping, single-finger joystick ownership, radial deadzone, sprint latch, gyro sign/deadzone/invert, settings round-trip and clamping" % [DEVICES.size(), ClawLayout.MIN_TARGET_MM])
	quit()

func _test_layouts() -> void:
	for device: Dictionary in DEVICES:
		var visible: Vector2 = device.visible
		var pixels: Vector2 = device.pixels
		var insets: Vector4 = device.insets
		var safe_pixels := Rect2(insets.x, insets.y, pixels.x - insets.x - insets.z, pixels.y - insets.y - insets.w)
		var safe := ClawLayout.safe_pixels_to_canvas(safe_pixels, Rect2(Vector2.ZERO, pixels), Rect2(Vector2.ZERO, visible))
		var upm := ClawLayout.units_per_mm(visible, pixels, device.dpi)
		var tablet := ClawLayout.is_tablet(pixels, device.dpi)
		if String(device.name).contains("tablet"):
			_check(tablet, "%s must be detected as a tablet" % device.name)
		elif device.dpi > 0.0:
			_check(not tablet, "%s must be detected as a phone" % device.name)
		for scale in [0.8, 1.0, 1.25]:
			for left_handed in [false, true]:
				var label := "%s scale %.2f %s" % [device.name, scale, "left" if left_handed else "right"]
				_check_layout(label, ClawLayout.compute(visible, safe, upm, tablet, scale, left_handed), safe, upm)

func _check_layout(label: String, rects: Dictionary, safe: Rect2, upm: float) -> void:
	var occupied: Array[StringName] = ClawLayout.button_slots()
	occupied.append_array([&"Compass", &"StatusPanel", &"Minimap", &"JoystickZone"])
	for slot in occupied:
		_check(rects.has(slot), "%s: slot %s missing" % [label, slot])
	for slot in rects:
		var rect: Rect2 = rects[slot]
		_check(rect.has_area() and rect.is_finite(), "%s: %s must have area" % [label, slot])
		_check(safe.grow(0.5).encloses(rect), "%s: %s %s must stay inside safe area %s" % [label, slot, rect, safe])
	for slot in ClawLayout.button_slots():
		var rect: Rect2 = rects[slot]
		var smallest_mm := minf(rect.size.x, rect.size.y) / upm
		_check(smallest_mm >= ClawLayout.MIN_TARGET_MM - 0.05,
			"%s: %s is %.1f mm, below the %.1f mm touch minimum" % [label, slot, smallest_mm, ClawLayout.MIN_TARGET_MM])
	for i in occupied.size():
		for j in range(i + 1, occupied.size()):
			var a: Rect2 = rects[occupied[i]]
			var b: Rect2 = rects[occupied[j]]
			_check(not a.intersects(b), "%s: %s %s overlaps %s %s" % [label, occupied[i], a, occupied[j], b])
	# The stick's resting base belongs inside its zone; nothing else may be.
	_check(rects[&"JoystickZone"].grow(0.5).encloses(rects[&"Joystick"]), "%s: joystick must rest inside its zone" % label)
	var fire: Rect2 = rects[&"Fire"]
	_check(fire.size.x >= rects[&"Jump"].size.x and fire.size.x >= rects[&"Crouch"].size.x,
		"%s: FIRE must be the largest thumb target" % label)

func _test_safe_area_conversion() -> void:
	var visible := Rect2(0, 0, 1600, 720)
	var window := Rect2(0, 0, 2400, 1080)
	var safe := ClawLayout.safe_pixels_to_canvas(Rect2(120, 0, 2280, 1017), window, visible)
	_check(safe.position.is_equal_approx(Vector2(80, 0)) and safe.size.is_equal_approx(Vector2(1520, 678)),
		"Notch and gesture-bar insets must scale into canvas units (%s)" % safe)
	_check(ClawLayout.safe_pixels_to_canvas(Rect2(), window, visible) == visible, "An empty safe area must fall back to the full canvas")
	_check(ClawLayout.safe_pixels_to_canvas(Rect2(0, 0, 100, 100), Rect2(), visible) == visible, "A zero window must fall back to the full canvas")
	_check(ClawLayout.units_per_mm(Vector2(1280, 720), Vector2(1920, 1080), 0.0) == ClawLayout.REFERENCE_UNITS_PER_MM,
		"Unknown density must use the reference phone")

func _test_joystick() -> void:
	var stick := FloatingJoystick.new()
	stick.zone = Rect2(0, 300, 480, 420)
	stick.radius = 100.0
	_check(not stick.press(0, Vector2(900, 600)), "A touch outside the zone must not claim the stick")
	_check(stick.press(2, Vector2(200, 600)), "A touch in the zone must claim the stick")
	_check(not stick.press(3, Vector2(210, 610)), "A second finger in the zone must not steal the stick")
	_check(not stick.drag(3, Vector2(400, 400)), "Another finger's drag must be ignored")
	_check(stick.value == Vector2.ZERO, "Another finger must not move the stick")
	stick.drag(2, Vector2(200 + 10, 600))
	_check(stick.value == Vector2.ZERO, "Inside the deadzone the stick must read zero")
	stick.drag(2, Vector2(200 + 20, 600))
	_check(stick.value.x > 0.0 and stick.value.x < 0.15, "Just past the deadzone the output must start near zero, not jump (%.3f)" % stick.value.x)
	stick.drag(2, Vector2(200 + 300, 600))
	_check(is_equal_approx(stick.value.length(), 1.0), "Full deflection must clamp to 1")
	_check(not stick.wants_sprint(), "Sideways deflection must not arm sprint")
	_check(not stick.release(3), "Another finger's release must not free the stick")
	_check(stick.is_active(), "The stick must stay owned until its own finger lifts")
	stick.drag(2, Vector2(205, 600 - 160))
	_check(stick.wants_sprint() and stick.value.y < -0.9, "Pushing far ahead must arm sprint")
	stick.release(2)
	_check(stick.sprint_latched and stick.value == Vector2(0, -1), "Releasing while armed must latch forward sprint")
	stick.press(0, Vector2(100, 650))
	_check(not stick.sprint_latched and stick.value == Vector2.ZERO, "A new press must clear the latch")
	stick.drag(0, Vector2(100, 400))
	stick.cancel()
	_check(not stick.is_active() and stick.value == Vector2.ZERO and not stick.sprint_latched,
		"Cancel (focus loss) must drop the finger and any latch")
	stick.sprint_lock_enabled = false
	stick.press(1, Vector2(100, 650))
	stick.drag(1, Vector2(100, 400))
	stick.release(1)
	_check(not stick.sprint_latched and stick.value == Vector2.ZERO, "Sprint latch must respect the setting")
	_check(FloatingJoystick.shape(Vector2(0.5, 0), 0.0).is_equal_approx(Vector2(0.5, 0)), "Zero deadzone must pass input through")

func _test_gyro() -> void:
	var gyro := GyroLook.new()
	gyro.smoothing = 1000.0
	gyro.sensitivity = 1.0
	# +y is the device turning left about the screen's up axis: look left (mouse-left, -x).
	var turn_left := gyro.step(Vector3(0, 1.0, 0), 0.05)
	_check(turn_left.x < 0.0 and is_zero_approx(turn_left.y), "Turning the device left must look left (%s)" % turn_left)
	gyro.reset()
	# +x tilts the top edge towards the player, which points the rear camera up (mouse-up, -y).
	var tilt_back := gyro.step(Vector3(1.0, 0, 0), 0.05)
	_check(tilt_back.y < 0.0 and is_zero_approx(tilt_back.x), "Tilting the top edge towards you must look up (%s)" % tilt_back)
	gyro.reset()
	_check(absf(turn_left.x + 0.05) < 0.002, "At sensitivity 1 a rotation must map 1:1 to look radians (%.4f)" % turn_left.x)
	_check(gyro.step(Vector3(0.01, 0.0, 0.005), 0.016) == Vector2.ZERO, "Tremor below the deadzone must not move the camera")
	_check(gyro.step(Vector3(NAN, 0, 0), 0.016) == Vector2.ZERO, "Non-finite samples must be ignored")
	_check(gyro.step(Vector3(0, 1, 0), 0.0) == Vector2.ZERO, "A zero frame time must not move the camera")
	gyro.reset()
	gyro.invert_x = true
	gyro.invert_y = true
	var inverted := gyro.step(Vector3(1.0, 1.0, 0), 0.05)
	_check(inverted.x > 0.0 and inverted.y > 0.0, "Invert options must flip both axes (%s)" % inverted)
	var slow := GyroLook.new()
	slow.sensitivity = 1.0
	var first := slow.step(Vector3(0, 1.0, 0), 0.016)
	_check(absf(first.x) < 0.016 * 0.5, "Smoothing must ease into a sudden rate change")

func _test_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	var settings := MobileControlsSettings.new()
	_check(not settings.load_from(SETTINGS_PATH), "A missing settings file must keep defaults")
	settings.button_scale = 1.1
	settings.left_handed = true
	settings.gyro_mode = 2
	settings.gyro_invert_y = true
	_check(settings.save_to(SETTINGS_PATH) == OK, "Settings must save to user://")
	var loaded := MobileControlsSettings.new()
	_check(loaded.load_from(SETTINGS_PATH), "Saved settings must load")
	_check(is_equal_approx(loaded.button_scale, 1.1) and loaded.left_handed and loaded.gyro_mode == 2 and loaded.gyro_invert_y,
		"Settings must round-trip")
	var tampered := ConfigFile.new()
	tampered.set_value(MobileControlsSettings.SECTION, "button_scale", 9.0)
	tampered.set_value(MobileControlsSettings.SECTION, "opacity", "opaque")
	tampered.set_value(MobileControlsSettings.SECTION, "gyro_mode", 7)
	tampered.set_value(MobileControlsSettings.SECTION, "left_handed", "yes")
	tampered.set_value(MobileControlsSettings.SECTION, "joystick_deadzone", INF)
	tampered.save(SETTINGS_PATH)
	var clamped := MobileControlsSettings.new()
	clamped.load_from(SETTINGS_PATH)
	_check(clamped.button_scale == MobileControlsSettings.BUTTON_SCALE_RANGE.y, "Out-of-range scale must clamp")
	_check(is_equal_approx(clamped.opacity, 0.85), "A wrong-typed value must fall back to the default")
	_check(clamped.gyro_mode == 1, "An unknown gyro mode must wrap into range")
	_check(not clamped.left_handed, "A non-bool flag must fall back to the default")
	_check(is_equal_approx(clamped.joystick_deadzone, 0.12), "A non-finite deadzone must fall back to the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
