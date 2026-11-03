extends RefCounted

## Player-customised touch layouts, BGMI/PUBG style: one layout for walking around
## (NORMAL), one for fighting (FIRING, i.e. ACTION mode) and one for driving
## (VEHICLE). Each stores, per button, a centre in safe-area fractions and a size
## multiplier on top of the ClawLayout default, plus the layout's opacity, so
## layouts survive any screen size, notch or rotation. Saved offline in user://.
##
## Everything read from disk is untrusted: unknown layouts or buttons are dropped,
## numbers are clamped, and a corrupt file falls back to the defaults.

const DEFAULT_PATH := "user://hud_layouts.cfg"
const VERSION := 1
const NORMAL := &"normal"
const COMBAT := &"combat"
const VEHICLE := &"vehicle"
const PROFILES: Array[StringName] = [NORMAL, COMBAT, VEHICLE]
const PROFILE_TITLES := {NORMAL: "NORMAL", COMBAT: "FIRING", VEHICLE: "VEHICLE"}
const SCALE_RANGE := Vector2(0.6, 1.8)
const OPACITY_RANGE := Vector2(0.35, 1.0)
## The stick's spawn zone around a moved joystick, as a multiple of the stick size.
const MOVED_ZONE_SCALE := 2.2

## Walking only ever shows these. Slots no longer in a list are dropped when an old file loads.
const NORMAL_SLOTS: Array[StringName] = [&"Joystick", &"Jump", &"Run", &"Vehicle", &"Wheel", &"Menu",
	&"Context", &"ContextAlt"]
const ON_FOOT_SLOTS: Array[StringName] = [&"Joystick", &"Jump", &"Run", &"Vehicle", &"Wheel", &"Menu",
	&"Context", &"ContextAlt", &"Fire", &"Scope", &"Reload", &"Crouch", &"Swap"]
## Driving reuses on-foot slots for its own buttons (see ClawLayout.SCENE_BUTTON_SLOTS),
## so moving BRAKE in VEHICLE never moves FIRE in FIRING.
const VEHICLE_SLOTS: Array[StringName] = [&"Joystick", &"Fire", &"Scope", &"Reload", &"Crouch",
	&"Vehicle", &"Run", &"Wheel", &"Menu"]

## profile -> {slot: {"center": Vector2 (0..1 of the safe area), "scale": float}}
var overrides := {}
## profile -> opacity; a missing entry means "use the global touch opacity".
var opacity := {}

func _init() -> void:
	for profile in PROFILES:
		overrides[profile] = {}

static func slots_for(profile: StringName) -> Array[StringName]:
	match profile:
		VEHICLE: return VEHICLE_SLOTS
		NORMAL: return NORMAL_SLOTS
		_: return ON_FOOT_SLOTS

## Driving wins over everything; on foot, ACTION mode means the FIRING layout.
static func profile_for(driving: bool, action_mode: bool) -> StringName:
	if driving:
		return VEHICLE
	return COMBAT if action_mode else NORMAL

func has_custom(profile: StringName) -> bool:
	return not overrides.get(profile, {}).is_empty() or opacity.has(profile)

func set_slot(profile: StringName, slot: StringName, center: Vector2, scale: float) -> void:
	if profile not in PROFILES or slot not in slots_for(profile) or not center.is_finite() or not is_finite(scale):
		return
	overrides[profile][slot] = {
		"center": Vector2(clampf(center.x, 0.0, 1.0), clampf(center.y, 0.0, 1.0)),
		"scale": clampf(scale, SCALE_RANGE.x, SCALE_RANGE.y),
	}

func slot_scale(profile: StringName, slot: StringName) -> float:
	return float(overrides.get(profile, {}).get(slot, {}).get("scale", 1.0))

func set_opacity(profile: StringName, value: float) -> void:
	if profile in PROFILES and is_finite(value):
		opacity[profile] = clampf(value, OPACITY_RANGE.x, OPACITY_RANGE.y)

func opacity_for(profile: StringName, fallback: float) -> float:
	return float(opacity.get(profile, fallback))

func reset(profile: StringName) -> void:
	if profile in PROFILES:
		overrides[profile] = {}
		opacity.erase(profile)

## Default rects with this layout's overrides applied. Moved and resized buttons keep
## their default aspect, never drop below `min_target` on their short side, and are
## pushed back inside `safe`. A moved joystick takes its spawn zone with it.
func apply(profile: StringName, defaults: Dictionary, safe: Rect2, min_target: float) -> Dictionary:
	var rects := defaults.duplicate()
	var custom: Dictionary = overrides.get(profile, {})
	for slot in custom:
		if not rects.has(slot):
			continue
		var base: Rect2 = rects[slot]
		var size := base.size * float(custom[slot].scale)
		var short_side := minf(size.x, size.y)
		if short_side < min_target and short_side > 0.0:
			size *= min_target / short_side
		size = Vector2(minf(size.x, safe.size.x), minf(size.y, safe.size.y))
		var center := safe.position + safe.size * (custom[slot].center as Vector2)
		rects[slot] = _inside(Rect2(center - size * 0.5, size), safe)
	if custom.has(&"Joystick") and rects.has(&"Joystick"):
		var stick: Rect2 = rects[&"Joystick"]
		var zone_size := stick.size * MOVED_ZONE_SCALE
		rects[&"JoystickZone"] = _inside(Rect2(stick.get_center() - zone_size * 0.5, zone_size), safe).merge(stick)
	return rects

## Inverse of apply's positioning: the stored centre for a button drawn at `rect`.
static func center_fraction(rect: Rect2, safe: Rect2) -> Vector2:
	if not safe.has_area():
		return Vector2(0.5, 0.5)
	return ((rect.get_center() - safe.position) / safe.size).clamp(Vector2.ZERO, Vector2.ONE)

static func _inside(rect: Rect2, bounds: Rect2) -> Rect2:
	var size := Vector2(minf(rect.size.x, bounds.size.x), minf(rect.size.y, bounds.size.y))
	var position := rect.position.clamp(bounds.position, bounds.end - size)
	return Rect2(position, size)

func save_to(path := DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	for profile in PROFILES:
		if opacity.has(profile):
			config.set_value(String(profile), "_opacity", opacity[profile])
		var custom: Dictionary = overrides[profile]
		for slot in custom:
			config.set_value(String(profile), String(slot), [custom[slot].center.x, custom[slot].center.y, custom[slot].scale])
	return config.save(path)

func load_from(path := DEFAULT_PATH) -> bool:
	for profile in PROFILES:
		reset(profile)
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	if config.get_value("meta", "version", 0) != VERSION:
		return false
	for profile in PROFILES:
		var section := String(profile)
		if not config.has_section(section):
			continue
		for key in config.get_section_keys(section):
			var value: Variant = config.get_value(section, key)
			if key == "_opacity":
				if value is float or value is int:
					set_opacity(profile, float(value))
			elif value is Array and value.size() == 3 and value.all(func(n: Variant) -> bool: return n is float or n is int):
				set_slot(profile, StringName(key), Vector2(float(value[0]), float(value[1])), float(value[2]))
	return true
