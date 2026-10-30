extends SceneTree

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
const Profiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const PATH := "user://test_hud_layouts.cfg"

var _failures := 0

func _init() -> void:
	var module: GDScript = Profiles
	if not module.can_instantiate():
		print("FAIL hud layout profiles regression: module does not compile")
		quit(1)
		return
	_test_profile_choice()
	_test_apply()
	_test_independence()
	_test_bad_input()
	_test_persistence()
	if _failures > 0:
		print("FAIL hud layout profiles regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS hud layout profiles regression: profile choice, move/resize/clamp inside safe area, touch minimum, moved joystick zone, notch-safe fractions, independent NORMAL/FIRING/VEHICLE, bad values, corrupt/old files, round-trip")
	quit()

func _defaults(safe: Rect2, units_mm := ClawLayout.REFERENCE_UNITS_PER_MM) -> Dictionary:
	return ClawLayout.compute(Vector2(1280, 720), safe, units_mm)

func _test_profile_choice() -> void:
	_check(Profiles.profile_for(false, false) == Profiles.NORMAL, "On foot in PEACE uses NORMAL")
	_check(Profiles.profile_for(false, true) == Profiles.COMBAT, "On foot in ACTION uses FIRING")
	_check(Profiles.profile_for(true, true) == Profiles.VEHICLE and Profiles.profile_for(true, false) == Profiles.VEHICLE,
		"Driving always uses VEHICLE, whatever the mode")

func _test_apply() -> void:
	var safe := Rect2(0, 0, 1280, 720)
	var min_target := ClawLayout.MIN_TARGET_MM * ClawLayout.REFERENCE_UNITS_PER_MM
	var defaults := _defaults(safe)
	var profiles := Profiles.new()
	var untouched := profiles.apply(Profiles.COMBAT, defaults, safe, min_target)
	_check(untouched == defaults, "With no overrides the default layout is returned unchanged")

	profiles.set_slot(Profiles.COMBAT, &"Fire", Vector2(0.5, 0.5), 1.5)
	var moved := profiles.apply(Profiles.COMBAT, defaults, safe, min_target)
	var fire: Rect2 = moved[&"Fire"]
	_check(fire.get_center().distance_to(Vector2(640, 360)) < 0.5, "A moved button is centred where it was dropped (%s)" % fire.get_center())
	_check(is_equal_approx(fire.size.x, defaults[&"Fire"].size.x * 1.5), "Size multiplies the default size")
	_check(defaults[&"Fire"] == _defaults(safe)[&"Fire"], "Applying must not modify the defaults")

	profiles.set_slot(Profiles.COMBAT, &"Jump", Vector2(1.0, 1.0), 1.8)
	var corner: Rect2 = profiles.apply(Profiles.COMBAT, defaults, safe, min_target)[&"Jump"]
	_check(safe.encloses(corner), "A button dropped in the corner stays fully on screen (%s)" % corner)

	profiles.set_slot(Profiles.COMBAT, &"PeekLeft", Vector2(0.3, 0.3), 0.6)
	var small: Rect2 = profiles.apply(Profiles.COMBAT, defaults, safe, min_target)[&"PeekLeft"]
	_check(minf(small.size.x, small.size.y) >= min_target - 0.01, "Shrinking never goes below the touch minimum (%.1f)" % minf(small.size.x, small.size.y))

	profiles.set_slot(Profiles.COMBAT, &"Joystick", Vector2(0.75, 0.6), 1.0)
	var with_stick := profiles.apply(Profiles.COMBAT, defaults, safe, min_target)
	_check(with_stick[&"JoystickZone"].encloses(with_stick[&"Joystick"]), "A moved joystick takes its spawn zone with it")
	_check(safe.encloses(with_stick[&"JoystickZone"]), "The moved zone stays on screen")

	# Fractions of the safe area, so a notch or a different screen keeps the arrangement.
	var notch := Rect2(80, 0, 1440, 680)
	var on_notch: Rect2 = profiles.apply(Profiles.COMBAT, _defaults(notch), notch, min_target)[&"Fire"]
	_check(on_notch.get_center().distance_to(notch.get_center()) < 0.5 and notch.encloses(on_notch),
		"Layouts are stored relative to the safe area, so they carry over to notched/wider screens")
	_check(Profiles.center_fraction(Rect2(630, 350, 20, 20), safe).is_equal_approx(Vector2(0.5, 0.5)), "center_fraction inverts apply")
	_check(Profiles.center_fraction(Rect2(5000, -40, 10, 10), safe) == Vector2(1, 0), "center_fraction clamps a rect dragged off screen")
	_check(Profiles.center_fraction(Rect2(0, 0, 10, 10), Rect2()) == Vector2(0.5, 0.5), "An empty safe area cannot divide by zero")

func _test_independence() -> void:
	var profiles := Profiles.new()
	profiles.set_slot(Profiles.VEHICLE, &"Fire", Vector2(0.2, 0.2), 1.2)
	profiles.set_opacity(Profiles.VEHICLE, 0.5)
	_check(profiles.overrides[Profiles.COMBAT].is_empty() and profiles.overrides[Profiles.NORMAL].is_empty(),
		"Moving BRAKE (VEHICLE) must not move FIRE in FIRING or NORMAL")
	_check(profiles.opacity_for(Profiles.COMBAT, 0.85) == 0.85 and profiles.opacity_for(Profiles.VEHICLE, 0.85) == 0.5,
		"Opacity is per layout, with the global setting as fallback")
	profiles.reset(Profiles.VEHICLE)
	_check(not profiles.has_custom(Profiles.VEHICLE), "Reset clears one layout completely")

func _test_bad_input() -> void:
	var profiles := Profiles.new()
	profiles.set_slot(Profiles.COMBAT, &"Fire", Vector2(NAN, 0.5), 1.0)
	profiles.set_slot(Profiles.COMBAT, &"Jump", Vector2(0.5, 0.5), INF)
	profiles.set_slot(&"bogus", &"Fire", Vector2(0.5, 0.5), 1.0)
	profiles.set_slot(Profiles.VEHICLE, &"Talk", Vector2(0.5, 0.5), 1.0)
	_check(profiles.overrides[Profiles.COMBAT].is_empty() and profiles.overrides[Profiles.VEHICLE].is_empty(),
		"Non-finite values, unknown layouts and buttons that don't exist in a layout are ignored")
	profiles.set_slot(Profiles.COMBAT, &"Fire", Vector2(3.0, -2.0), 9.0)
	var entry: Dictionary = profiles.overrides[Profiles.COMBAT][&"Fire"]
	_check(entry.center == Vector2(1, 0) and entry.scale == Profiles.SCALE_RANGE.y, "Out-of-range positions and sizes are clamped")
	profiles.set_opacity(Profiles.COMBAT, 0.0)
	_check(profiles.opacity_for(Profiles.COMBAT, 1.0) == Profiles.OPACITY_RANGE.x, "Opacity cannot hide the controls completely")

func _test_persistence() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var fresh := Profiles.new()
	_check(not fresh.load_from(PATH), "A missing file keeps the defaults")
	var profiles := Profiles.new()
	profiles.set_slot(Profiles.COMBAT, &"Fire", Vector2(0.25, 0.75), 1.3)
	profiles.set_slot(Profiles.VEHICLE, &"Fire", Vector2(0.8, 0.2), 0.9)
	profiles.set_opacity(Profiles.NORMAL, 0.6)
	_check(profiles.save_to(PATH) == OK, "Layouts save to user://")
	var loaded := Profiles.new()
	_check(loaded.load_from(PATH), "Saved layouts load")
	_check(loaded.overrides[Profiles.COMBAT][&"Fire"].center.is_equal_approx(Vector2(0.25, 0.75))
		and is_equal_approx(loaded.slot_scale(Profiles.VEHICLE, &"Fire"), 0.9)
		and is_equal_approx(loaded.opacity_for(Profiles.NORMAL, 1.0), 0.6), "Layouts round-trip exactly")

	var tampered := ConfigFile.new()
	tampered.set_value("meta", "version", Profiles.VERSION)
	tampered.set_value("combat", "Fire", [0.5, "x", 1.0])
	tampered.set_value("combat", "Jump", [0.5, 0.5])
	tampered.set_value("combat", "NotAButton", [0.5, 0.5, 1.0])
	tampered.set_value("combat", "Scope", [2.0, 2.0, 50.0])
	tampered.set_value("combat", "_opacity", "solid")
	tampered.set_value("hacker", "Fire", [0.1, 0.1, 1.0])
	tampered.save(PATH)
	var cleaned := Profiles.new()
	cleaned.load_from(PATH)
	_check(cleaned.overrides[Profiles.COMBAT].keys() == [&"Scope"], "Malformed entries and unknown buttons are dropped (%s)" % [cleaned.overrides[Profiles.COMBAT].keys()])
	_check(cleaned.overrides[Profiles.COMBAT][&"Scope"].center == Vector2(1, 1) and cleaned.slot_scale(Profiles.COMBAT, &"Scope") == Profiles.SCALE_RANGE.y,
		"Out-of-range saved values are clamped")
	_check(not cleaned.opacity.has(Profiles.COMBAT), "A non-number opacity is ignored")

	var old := ConfigFile.new()
	old.set_value("meta", "version", 999)
	old.set_value("combat", "Fire", [0.1, 0.1, 1.0])
	old.save(PATH)
	var newer := Profiles.new()
	_check(not newer.load_from(PATH) and newer.overrides[Profiles.COMBAT].is_empty(), "A file from another version falls back to defaults")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("\u0000garbage[[[")
	file.close()
	var corrupt := Profiles.new()
	_check(not corrupt.load_from(PATH) and not corrupt.has_custom(Profiles.COMBAT), "A corrupt file falls back to defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
