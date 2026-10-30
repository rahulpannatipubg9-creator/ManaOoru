extends RefCounted

## Touch layout for phones and tablets held in landscape, following
## docs/reference/UI_DESIGN.md: minimap and vitals top-left, compass top-centre, objective and
## menu top-right, a floating joystick on the left, one column of everyday buttons down the
## right edge with the rifle buttons inboard of it, and the ammo or speed readout at the
## bottom centre.
##
## Pure geometry: from the canvas size, the display safe area and the screen density
## it returns non-overlapping rectangles in canvas units, so every device shape can
## be checked headless. Every slot is reserved even while its button is hidden, so a
## button appearing never pushes another one, and every stack is built inwards from an
## edge so a grown button never lands on a neighbour.

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
## Boxes holding fixed-size text, so their size does not follow the screen.
const VITALS_SIZE := Vector2(150.0, 36.0)
const WANTED_HEIGHT := 24.0
const COINS_HEIGHT := 28.0
const OBJECTIVE_WIDTH := 240.0
const OBJECTIVE_HEIGHT := 72.0
const READOUT_SIZE := Vector2(280.0, 64.0)
const PROMPT_HEIGHT := 44.0

## Slot for each button defined in hud.tscn's TouchControls. Vehicle and helicopter
## buttons reuse on-foot slots that are hidden while driving, so the thumb finds
## the same places in every control state (BRAKE/DESCEND where FIRE is, and so on).
const SCENE_BUTTON_SLOTS := {
	&"Run": &"Run",
	&"Jump": &"Jump",
	&"Enter": &"Vehicle",
	&"Exit": &"Vehicle",
	&"Handbrake": &"Fire",
	&"Camera": &"Scope",
	&"GearUp": &"Reload",
	&"GearDown": &"Crouch",
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
	return minf(maxf(MIN_TARGET_MM * units_mm, UiTheme.TOUCH_TARGET), minf(safe.size.x, safe.size.y) * MAX_UNIT_SHARE)

## Rectangles keyed by slot name. `tablet` is kept for callers; the reference proportions
## already suit both, the mm floor handles phones.
static func compute(visible_size: Vector2, safe: Rect2, units_mm: float, _tablet := false,
		button_scale := 1.0, left_handed := false) -> Dictionary:
	var short_side := minf(safe.size.x, safe.size.y)
	var target_floor := min_target(safe, units_mm)
	var k := safe.size.y / REF_HEIGHT
	var s := button_scale
	var g := maxf(target_floor * 0.18, 10.0 * k)
	var margin := maxf(g, short_side * 0.03)
	var left := safe.position.x + margin
	var right := safe.end.x - margin
	var top := safe.position.y + margin
	var bottom := safe.end.y - margin
	var center_x := safe.get_center().x
	var rects := {}

	# Top left: the map, with vitals, wanted stars and coin pop-ups beside it.
	var minimap := clampf(215.0 * k, 130.0, 240.0)
	rects[&"Minimap"] = Rect2(left, top, minimap, minimap)
	rects[&"Vitals"] = Rect2(Vector2(left + minimap + g, top), VITALS_SIZE)
	rects[&"Wanted"] = Rect2(rects[&"Vitals"].position.x, rects[&"Vitals"].end.y + g, VITALS_SIZE.x, WANTED_HEIGHT)
	rects[&"Coins"] = Rect2(rects[&"Vitals"].position.x, rects[&"Wanted"].end.y + UiTheme.SPACE_XS, VITALS_SIZE.x, COINS_HEIGHT)

	# Top right: the menu in the corner, the objective beside it.
	var menu := _size(80.0, k, 1.0, target_floor)
	rects[&"Menu"] = Rect2(right - menu, top, menu, menu)
	rects[&"Objective"] = Rect2(rects[&"Menu"].position.x - g - OBJECTIVE_WIDTH, top, OBJECTIVE_WIDTH, OBJECTIVE_HEIGHT)
	var compass_half := minf(clampf(visible_size.x * 0.28, 200.0, 320.0) * 0.5,
		minf(rects[&"Objective"].position.x - g - center_x, center_x - rects[&"Vitals"].end.x - g))
	rects[&"Compass"] = Rect2(center_x - compass_half, top, compass_half * 2.0, minf(30.0, target_floor))

	# Right edge, bottom to top: what is always useful on foot. The same slots serve driving.
	var everyday := _size(110.0, k, s, target_floor)
	var cursor := bottom
	for slot: StringName in [&"Jump", &"Run", &"Vehicle", &"Wheel"]:
		cursor -= everyday
		rects[slot] = Rect2(right - everyday, cursor, everyday, everyday)
		cursor -= g

	# Inboard of it, the buttons that appear with a rifle out: FIRE big and low, the sight
	# over it, then CROUCH, RELOAD and the rifle swap in a third column.
	var fire := _size(190.0, k, s, target_floor)
	var fire_x := right - everyday - g - fire
	rects[&"Fire"] = Rect2(fire_x, bottom - fire, fire, fire)
	var scope := _size(125.0, k, s, target_floor)
	rects[&"Scope"] = Rect2(fire_x + (fire - scope) * 0.5, bottom - fire - g - scope, scope, scope)
	var side := _size(110.0, k, s, target_floor)
	var side_x := fire_x - g - side
	rects[&"Crouch"] = Rect2(side_x, bottom - side, side, side)
	rects[&"Reload"] = Rect2(side_x, bottom - side * 2.0 - g, side, side)
	rects[&"Swap"] = Rect2(side_x, bottom - side * 3.0 - g * 2.0, side, side)

	# Bottom centre: the ammo or speed readout, contextual revive and loot above it, then the prompt.
	var readout := Vector2(minf(READOUT_SIZE.x, (side_x - g - center_x) * 2.0), READOUT_SIZE.y)
	rects[&"Readout"] = Rect2(center_x - readout.x * 0.5, bottom - readout.y, readout.x, readout.y)
	var context := Vector2(target_floor * 2.0, target_floor)
	var context_y: float = rects[&"Readout"].position.y - g - context.y
	rects[&"Context"] = Rect2(center_x - g * 0.5 - context.x, context_y, context.x, context.y)
	rects[&"ContextAlt"] = Rect2(center_x + g * 0.5, context_y, context.x, context.y)
	rects[&"Prompt"] = Rect2(safe.position.x + safe.size.x * 0.25, context_y - g - PROMPT_HEIGHT, safe.size.x * 0.5, PROMPT_HEIGHT)

	# Left: the stick rests low; a finger landing anywhere in its zone brings it there.
	var zone_top: float = maxf(rects[&"Minimap"].end.y, rects[&"Coins"].end.y) + g
	var zone_width: float = minf(safe.size.x * JOYSTICK_ZONE_SHARE - margin,
		minf(rects[&"Context"].position.x, rects[&"Readout"].position.x) - g - left)
	var zone := Rect2(left, zone_top, zone_width, bottom - zone_top)
	rects[&"JoystickZone"] = zone
	var stick := minf(260.0 * k * s, minf(zone.size.x, zone.size.y))
	rects[&"Joystick"] = Rect2(left + 30.0 * k, bottom - stick, stick, stick)

	if left_handed:
		for slot in rects:
			var rect: Rect2 = rects[slot]
			rects[slot] = Rect2(safe.position.x + safe.end.x - rect.end.x, rect.position.y, rect.size.x, rect.size.y)
	return rects

## Slots that receive touches; the map, readouts and the stick's zone are excluded.
static func button_slots() -> Array[StringName]:
	return [&"Jump", &"Run", &"Vehicle", &"Wheel", &"Menu", &"Fire", &"Scope", &"Reload", &"Crouch", &"Swap",
		&"Context", &"ContextAlt"]

## Rectangles holding information only; they must not sit under a button either.
static func display_slots() -> Array[StringName]:
	return [&"Compass", &"Vitals", &"Objective", &"Minimap", &"JoystickZone", &"Readout"]

## A reference-sized button scaled to this screen, never below the touch minimum.
static func _size(reference: float, k: float, button_scale: float, min_target: float) -> float:
	return maxf(reference * k * button_scale, min_target)
