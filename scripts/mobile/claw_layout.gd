extends RefCounted

## BGMI-style touch layout for phones and tablets held in landscape, following the
## reference arrangement Rahul supplied (2026-10-28): minimap top-right, compass
## top-centre, left FIRE + peeks over a floating joystick, the right thumb cluster
## (ADS, JUMP, FIRE, RELOAD, CROUCH, PRONE) and an item bar along the bottom centre.
##
## Pure geometry: from the canvas size, the display safe area and the screen density
## it returns non-overlapping rectangles in canvas units, so every device shape can
## be checked headless. Positions follow the reference proportions scaled to the
## safe-area height; sizes never drop below the touch minimum in millimetres, and
## every stack is built inwards from an edge so a grown button never lands on another.

## Apple's 44 pt and Android's 48 dp minimum touch targets are both ~7-7.6 mm.
const MIN_TARGET_MM := 7.5
const TABLET_DIAGONAL_INCHES := 7.0
## Density used when the platform reports none: a 6.5" 1080p phone held landscape.
const REFERENCE_UNITS_PER_MM := 10.5
## The minimum target never exceeds this share of the short side, so the layout always fits.
const MAX_UNIT_SHARE := 0.13
## Height of the reference mock-up; its pixel sizes are scaled from this.
const REF_HEIGHT := 1024.0
## Left share of the safe width where a finger landing spawns the floating joystick.
const JOYSTICK_ZONE_SHARE := 0.40
## Status rows (status, coins, speed, gear) use fixed-size fonts, so their box is fixed too.
const STATUS_SIZE := Vector2(260.0, 135.0)

## Slot for each button defined in hud.tscn's TouchControls. Vehicle and helicopter
## buttons reuse on-foot slots that are hidden while driving, so the thumb finds
## the same places in every control state (BRAKE/DESCEND where FIRE is, and so on).
const SCENE_BUTTON_SLOTS := {
	&"Run": &"Run",
	&"Jump": &"Jump",
	&"Reset": &"Reset",
	&"Enter": &"Vehicle",
	&"Exit": &"Vehicle",
	&"Handbrake": &"Fire",
	&"Camera": &"Scope",
	&"GearUp": &"Reload",
	&"GearDown": &"Crouch",
	&"GearMode": &"Prone",
}

## Canvas units per physical millimetre for the current window.
static func units_per_mm(visible_size: Vector2, window_pixels: Vector2, dpi: float) -> float:
	if dpi <= 0.0 or window_pixels.y <= 0.0 or visible_size.y <= 0.0:
		return REFERENCE_UNITS_PER_MM
	return dpi / 25.4 * visible_size.y / window_pixels.y

static func is_tablet(screen_pixels: Vector2, dpi: float) -> bool:
	return dpi > 0.0 and screen_pixels.length() / dpi >= TABLET_DIAGONAL_INCHES

## The display safe area (notch, punch-hole, rounded corners, gesture bar) in canvas units.
## Desktop windows report the work area instead, so only mobile builds use it.
static func canvas_safe_rect(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	if not OS.has_feature("mobile"):
		return visible
	var window := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	return safe_pixels_to_canvas(Rect2(DisplayServer.get_display_safe_area()), window, visible)

static func safe_pixels_to_canvas(safe_pixels: Rect2, window_pixels: Rect2, visible: Rect2) -> Rect2:
	if window_pixels.size.x <= 0.0 or window_pixels.size.y <= 0.0 or not safe_pixels.has_area():
		return visible
	var scale := visible.size / window_pixels.size
	var local := Rect2(visible.position + (safe_pixels.position - window_pixels.position) * scale, safe_pixels.size * scale)
	var clipped := local.intersection(visible)
	return clipped if clipped.has_area() else visible

## Smallest allowed button side for this screen, in canvas units.
static func min_target(safe: Rect2, units_mm: float) -> float:
	return minf(MIN_TARGET_MM * units_mm, minf(safe.size.x, safe.size.y) * MAX_UNIT_SHARE)

## Rectangles keyed by slot name. Contextual slots (Vehicle, Context) are always
## reserved so showing them never pushes other buttons around. `tablet` insets
## the controls inward for comfortable thumb reach on 4:3 and 16:10 aspect ratios.
static func compute(visible_size: Vector2, safe: Rect2, units_mm: float, tablet := false,
		button_scale := 1.0, left_handed := false) -> Dictionary:
	var short_side := minf(safe.size.x, safe.size.y)
	var min_target := minf(MIN_TARGET_MM * units_mm, short_side * MAX_UNIT_SHARE)
	var k := safe.size.y / REF_HEIGHT
	var s := button_scale
	var g := maxf(min_target * 0.18, 10.0 * k)
	var margin := maxf(g, short_side * 0.03)
	if tablet:
		var aspect := safe.size.x / maxf(1.0, safe.size.y)
		if aspect <= 1.65:
			margin += short_side * (0.018 / maxf(1.0, s))
	var t := maxf(min_target, 62.0 * k * s)
	var left := safe.position.x + margin
	var right := safe.end.x - margin
	var top := safe.position.y + margin
	var bottom := safe.end.y - margin
	var center_x := safe.get_center().x
	var rects := {}

	# Top right: minimap in the corner, then SQUAD, GYRO and RESET leftwards along the top.
	var minimap := clampf(185.0 * k, 120.0, 230.0)
	rects[&"Minimap"] = Rect2(right - minimap, top, minimap, minimap)
	var cursor := right - minimap - g
	for slot: StringName in [&"Squad", &"Gyro", &"Reset"]:
		var width := t * (1.2 if slot == &"Reset" else 1.4)
		rects[slot] = Rect2(cursor - width, top, width, t)
		cursor -= width + g
	# Second row under the minimap, right to left: auto-run, free look, FPP/TPP, drive, give up, help.
	var row_y := top + maxf(minimap, t) + g
	cursor = right
	for slot: StringName in [&"Run", &"FreeLook", &"View", &"Vehicle", &"Surrender", &"Help"]:
		var width := t * 1.5 if slot == &"Vehicle" else _size(95.0, k, s, min_target)
		var height := t if slot == &"Vehicle" else width
		rects[slot] = Rect2(cursor - width, row_y, width, height)
		cursor -= width + g

	# Right thumb: PRONE in the corner, JUMP and ADS stacked above it along the edge,
	# FIRE inboard of that column with CROUCH beneath it and RELOAD beside it.
	var prone := _size(125.0, k, s, min_target)
	var jump := _size(110.0, k, s, min_target)
	var scope := _size(130.0, k, s, min_target)
	rects[&"Prone"] = Rect2(right - prone, bottom - prone, prone, prone)
	rects[&"Jump"] = Rect2(right - jump, bottom - prone - g - jump, jump, jump)
	rects[&"Scope"] = Rect2(right - scope, rects[&"Jump"].position.y - g - scope, scope, scope)
	var column := maxf(prone, maxf(jump, scope))
	var fire := _size(190.0, k, s, min_target)
	var crouch := _size(125.0, k, s, min_target)
	var reload := _size(110.0, k, s, min_target)
	rects[&"Fire"] = Rect2(right - column - g - fire, bottom - crouch - g - fire, fire, fire)
	rects[&"Crouch"] = Rect2(rects[&"Fire"].get_center().x - crouch * 0.5, bottom - crouch, crouch, crouch)
	rects[&"Reload"] = Rect2(rects[&"Fire"].position.x - g - reload, rects[&"Fire"].end.y - reload, reload, reload)

	# Bottom centre item bar: medkit | weapon (tap to equip, shows ammo) | grenade,
	# fire mode above the weapon, contextual revive/loot above that.
	var weapon := Vector2(maxf(220.0 * k * s, t * 2.4), maxf(70.0 * k * s, t))
	rects[&"Equip"] = Rect2(center_x - weapon.x * 0.5, bottom - weapon.y, weapon.x, weapon.y)
	var item := _size(85.0, k, s, min_target)
	rects[&"Medkit"] = Rect2(rects[&"Equip"].position.x - g - item, bottom - item, item, item)
	rects[&"Grenade"] = Rect2(rects[&"Equip"].end.x + g, bottom - item, item, item)
	# Over the weapon slot: fire mode on the left half, the rifle swap (shown with two rifles) on the right.
	var half := (weapon.x - g) * 0.5
	rects[&"FireMode"] = Rect2(center_x - weapon.x * 0.5, rects[&"Equip"].position.y - g - t, half, t)
	# Large buttons on a 4:3 tablet bring RELOAD's corner over this row; the swap gives way.
	var swap_width := minf(half, rects[&"Reload"].position.x - g - (center_x + g * 0.5))
	rects[&"Swap"] = Rect2(center_x + g * 0.5, rects[&"FireMode"].position.y, swap_width, t)
	var context := Vector2(t * 2.2, t)
	rects[&"Context"] = Rect2(center_x - context.x * 0.5, rects[&"FireMode"].position.y - g - t, context.x, t)
	rects[&"ContextAlt"] = Rect2(center_x - context.x * 0.5, rects[&"Context"].position.y - g - t, context.x, t)

	# Left: compact status with the ACTION/PEACE and AVATAR toggles, then left FIRE with both peeks
	# beside it, the joystick zone below, and TALK in the bottom-left corner.
	rects[&"StatusPanel"] = Rect2(Vector2(left, top), STATUS_SIZE)
	rects[&"Mode"] = Rect2(left, rects[&"StatusPanel"].end.y + g, t * 1.6, t)
	rects[&"Character"] = Rect2(rects[&"Mode"].end.x + g, rects[&"Mode"].position.y, t * 1.6, t)
	var fire_left := _size(165.0, k, s, min_target)
	var fire_left_y: float = maxf(top + 435.0 * k - fire_left * 0.5, rects[&"Mode"].end.y + g)
	rects[&"FireLeft"] = Rect2(left, fire_left_y, fire_left, fire_left)
	var peek := _size(78.0, k, s, min_target)
	var peek_y: float = rects[&"FireLeft"].get_center().y - peek * 0.5
	rects[&"PeekLeft"] = Rect2(rects[&"FireLeft"].end.x + g, peek_y, peek, peek)
	rects[&"PeekRight"] = Rect2(rects[&"PeekLeft"].end.x + g, peek_y, peek, peek)
	var talk := _size(95.0, k, s, min_target)
	rects[&"Talk"] = Rect2(left, bottom - talk, talk, talk)
	var zone_top: float = maxf(rects[&"FireLeft"].end.y, rects[&"PeekRight"].end.y) + g
	var zone := Rect2(left, zone_top, safe.size.x * JOYSTICK_ZONE_SHARE - margin, rects[&"Talk"].position.y - g - zone_top)
	rects[&"JoystickZone"] = zone
	var stick := minf(260.0 * k * s, minf(zone.size.x, zone.size.y))
	var stick_x := clampf(left + 210.0 * k - stick * 0.5, zone.position.x, zone.end.x - stick)
	rects[&"Joystick"] = Rect2(stick_x, zone.get_center().y - stick * 0.5, stick, stick)

	# Compass fills whatever the top row leaves between the status box and RESET.
	var compass_half := minf(clampf(visible_size.x * 0.28, 200.0, 320.0) * 0.5,
		minf(rects[&"Reset"].position.x - g - center_x, center_x - rects[&"StatusPanel"].end.x - g))
	rects[&"Compass"] = Rect2(center_x - compass_half, top, compass_half * 2.0, minf(34.0, t))

	if left_handed:
		for slot in rects:
			var rect: Rect2 = rects[slot]
			rects[slot] = Rect2(safe.position.x + safe.end.x - rect.end.x, rect.position.y, rect.size.x, rect.size.y)
	return rects

## Slots that receive touches; Compass, StatusPanel, Minimap and the zone are excluded.
static func button_slots() -> Array[StringName]:
	return [&"Jump", &"Crouch", &"Prone", &"Fire", &"Scope", &"Reload", &"PeekRight", &"PeekLeft",
		&"Vehicle", &"Squad", &"Gyro", &"FireMode", &"Reset", &"FireLeft", &"Run", &"Context", &"ContextAlt",
		&"Equip", &"Swap", &"Medkit", &"Grenade", &"Talk", &"Surrender", &"Help", &"FreeLook", &"Mode", &"Character", &"View"]

## A reference-sized button scaled to this screen, never below the touch minimum.
static func _size(reference: float, k: float, button_scale: float, min_target: float) -> float:
	return maxf(reference * k * button_scale, min_target)
