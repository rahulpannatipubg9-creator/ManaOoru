extends Control

## Hold-to-open radial wheel for everything that does not earn a permanent button.
##
## Touch: press the wheel button and slide towards an item, then lift to choose it. A quick
## tap leaves the wheel open so an item can be tapped; tapping the centre or outside closes
## it. Desktop: hold the wheel key, move the mouse towards an item and let go. The game keeps
## running behind it, so it is safe in multiplayer.
##
## Items are {id: StringName, icon: StringName, label: String, count: int (optional),
## enabled: bool (optional), active: bool (optional)}. `provider` builds them at each open
## so the wheel only ever offers what fits the moment.

signal chosen(id: StringName)

const Icons := preload("res://scripts/ui/hud_icons.gd")
## A press shorter than this, with no slide, leaves the wheel open.
const TAP_SECONDS := 0.25
## Distance from the press before a direction counts, in canvas units.
const DEAD_ZONE := 26.0

## func() -> Array[Dictionary]
var provider: Callable
## The on-screen button that opens the wheel; touches on it are claimed here.
var trigger: Control
var items: Array[Dictionary] = []
var selected := -1
var sticky := false

var _finger := -1
var _origin := Vector2.ZERO
var _pointer := Vector2.ZERO
var _held_for := 0.0
var _key_held := false
var _alpha := 0.0
var _closing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func is_open() -> bool:
	return visible and not _closing

## Fresh items, centred on the screen, nothing picked yet.
func open() -> void:
	if not provider.is_valid():
		return
	items.assign(provider.call())
	if items.is_empty():
		return
	selected = -1
	sticky = false
	_closing = false
	_held_for = 0.0
	_pointer = Vector2.ZERO
	visible = true
	queue_redraw()

## Stays open until an item or the outside is pressed: mouse clicks on the button end up here.
func open_sticky() -> void:
	open()
	sticky = is_open()

func close() -> void:
	_finger = -1
	_key_held = false
	sticky = false
	selected = -1
	_closing = true

## Desktop: the held key opens the wheel and letting go of it chooses.
func key_down() -> void:
	if not is_open():
		open()
		_key_held = is_open()

func key_up() -> void:
	if _key_held:
		commit()

## Chooses the highlighted item, if it can be used, and closes.
func commit() -> void:
	var pick := selected
	close()
	if pick < 0 or pick >= items.size() or not items[pick].get("enabled", true):
		return
	chosen.emit(items[pick].id)

## The wedge for a direction from the centre; item 0 is straight up, then clockwise.
func index_for(direction: Vector2) -> int:
	if items.is_empty():
		return -1
	var step := TAU / items.size()
	return posmod(roundi(fposmod(direction.angle() + PI * 0.5, TAU) / step), items.size())

## Geometry of the ring for this screen.
func center() -> Vector2:
	return size * 0.5

func outer_radius() -> float:
	return minf(size.x, size.y) * 0.46

func inner_radius() -> float:
	return outer_radius() * 0.42

func _process(delta: float) -> void:
	if not visible:
		return
	if _finger != -1 or _key_held:
		_held_for += delta
	var target := 0.0 if _closing else 1.0
	_alpha = move_toward(_alpha, target, delta / UiTheme.MOTION_FAST)
	modulate.a = _alpha
	if _closing and _alpha <= 0.0:
		visible = false
		_closing = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		if event.index == _finger:
			_set_slide(event.position - _origin)
			get_viewport().set_input_as_handled()
	elif is_open() and _key_held and event is InputEventMouseMotion:
		# The mouse is captured in play, so it steers a virtual pointer instead of the camera.
		_set_slide((_pointer + event.relative).limit_length(120.0))
		get_viewport().set_input_as_handled()
	elif is_open() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _key_held:
			commit()
		else:
			_press_at(event.position)
		get_viewport().set_input_as_handled()

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if get_tree().paused:
			return
		if is_open() and sticky:
			_press_at(event.position)
			get_viewport().set_input_as_handled()
		elif not is_open() and _finger == -1 and _on_trigger(event.position):
			open()
			_finger = event.index
			_origin = event.position
			get_viewport().set_input_as_handled()
	elif event.index == _finger:
		get_viewport().set_input_as_handled()
		if event.canceled:
			close()
		elif selected == -1 and _held_for < TAP_SECONDS:
			_finger = -1
			sticky = true
			queue_redraw()
		else:
			commit()

func _on_trigger(position: Vector2) -> bool:
	return is_instance_valid(trigger) and trigger.is_visible_in_tree() and trigger.get_global_rect().has_point(position)

func _set_slide(offset: Vector2) -> void:
	_pointer = offset
	var next := index_for(offset) if offset.length() >= DEAD_ZONE else -1
	if next != selected:
		selected = next
		queue_redraw()

## Sticky mode: a press on a wedge chooses it, anywhere else closes.
func _press_at(position: Vector2) -> void:
	var offset := position - center()
	var distance := offset.length()
	if distance >= inner_radius() and distance <= outer_radius() * 1.08:
		selected = index_for(offset)
		commit()
	else:
		close()

func _draw() -> void:
	if items.is_empty():
		return
	var at := center()
	var outer := outer_radius()
	var inner := inner_radius()
	var step := TAU / items.size()
	var middle := (outer + inner) * 0.5
	var font := UiTheme.font()
	draw_circle(at, outer + UiTheme.SPACE_S, Color(UiTheme.INK, 0.42), true, -1.0, true)
	for i in items.size():
		var item: Dictionary = items[i]
		var angle := -PI * 0.5 + step * i
		var usable: bool = item.get("enabled", true)
		var active: bool = item.get("active", false)
		var fill := UiTheme.SURFACE_SOLID
		if i == selected and usable:
			fill = Color(UiTheme.ACCENT, 0.92)
		elif active:
			fill = UiTheme.ACCENT.darkened(0.6)
		_wedge(at, inner, outer, angle - step * 0.5 + 0.012, angle + step * 0.5 - 0.012, fill)
		var ink := UiTheme.ACCENT_DARK if i == selected and usable else UiTheme.TEXT
		if not usable:
			ink = Color(UiTheme.TEXT_MUTED, 0.5)
		var spot := at + Vector2.from_angle(angle) * middle
		Icons.paint(self, item.icon, spot, outer * 0.15, ink)
		if item.has("count"):
			var count := str(item.count)
			var corner := spot + Vector2(outer * 0.085, outer * 0.095)
			draw_string(font, corner, count, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SMALL, ink)
	var title := ""
	if selected >= 0 and selected < items.size():
		title = items[selected].label
	var size_px: int = UiTheme.FONT_LABEL
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_circle(at, inner - 6.0, UiTheme.SURFACE_SOLID, true, -1.0, true)
	draw_string(font, at + Vector2(-width * 0.5, font.get_ascent(size_px) * 0.36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, UiTheme.TEXT)

func _wedge(at: Vector2, inner: float, outer: float, from: float, to: float, fill: Color) -> void:
	var points := PackedVector2Array()
	var segments := maxi(8, ceili((to - from) / 0.08))
	for i in segments + 1:
		points.append(at + Vector2.from_angle(lerpf(from, to, float(i) / segments)) * outer)
	for i in range(segments, -1, -1):
		points.append(at + Vector2.from_angle(lerpf(from, to, float(i) / segments)) * inner)
	draw_colored_polygon(points, fill)
