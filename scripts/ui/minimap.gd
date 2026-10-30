class_name Minimap
extends Control

## Real-time minimap. Follows the person on foot and the occupied vehicle while
## driving. Redraws at a capped rate, and only when something it shows changed.
## A plain map until asked: tap for the full map, hold for zoom and north-up controls.
## The GPS destination and distance show in the HUD's objective block.

signal open_full_map_requested

const ZOOM_LEVELS := [0.35, 0.6, 1.0, 1.6, 2.4]
const DEFAULT_ZOOM_INDEX := 2
const DESKTOP_REFRESH_HZ := 30.0
const MOBILE_REFRESH_HZ := 15.0
const LOW_FPS_REFRESH_HZ := 8.0
const LOW_FPS_THRESHOLD := 40.0
## Holding a finger this long brings up the zoom and orientation buttons...
const HOLD_SECONDS := 0.4
## ...for this long.
const CONTROLS_SECONDS := 4.0

var heading_up := false
var zoom_index := DEFAULT_ZOOM_INDEX
var canvas: MapCanvas
var _game: Node
var _navigator: GpsNavigator
var _overlay: Control
var _buttons: Dictionary = {}
var _refresh_timer := 0.0
var _dirty := true
var _last_position := Vector2.INF
var _last_heading := Vector2.ZERO
var _touch_index := -1
var _touch_held := 0.0
var _controls_left := 0.0
## Optional: func() -> Array of [map point (Vector2), Color, radius px]. Team Deathmatch draws team-mates,
## enemies who just fired and pings with it.
var markers: Callable

func setup(game: Node, data: MapData, building_footprints: Array[PackedVector2Array],
		landmark_list: Array[Dictionary], navigator: GpsNavigator) -> void:
	_game = game
	_navigator = navigator
	name = "Minimap"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	canvas = MapCanvas.new()
	canvas.name = "MapCanvas"
	canvas.clamp_destination_to_edge = true
	add_child(canvas)
	canvas.setup(data, building_footprints, landmark_list)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	for button_name in ["ZoomIn", "ZoomOut", "Orientation"]:
		var button := Button.new()
		button.name = button_name
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
		button.visible = false
		add_child(button)
		_buttons[button_name] = button
	_buttons.ZoomIn.text = "+"
	_buttons.ZoomOut.text = "−"
	_buttons.ZoomIn.pressed.connect(change_zoom.bind(1))
	_buttons.ZoomOut.pressed.connect(change_zoom.bind(-1))
	_buttons.Orientation.pressed.connect(toggle_orientation)
	navigator.route_changed.connect(mark_dirty)
	resized.connect(_layout)
	_update_orientation_button()
	_layout()

func mark_dirty() -> void:
	_dirty = true

func change_zoom(step: int) -> void:
	zoom_index = clampi(zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	_dirty = true

func toggle_orientation() -> void:
	heading_up = not heading_up
	_update_orientation_button()
	_dirty = true

func refresh_hz() -> float:
	if Engine.get_frames_per_second() > 0.0 and Engine.get_frames_per_second() < LOW_FPS_THRESHOLD:
		return LOW_FPS_REFRESH_HZ
	return MOBILE_REFRESH_HZ if OS.has_feature("mobile") else DESKTOP_REFRESH_HZ

func _process(delta: float) -> void:
	_tick_controls(delta)
	_refresh_timer += delta
	if _refresh_timer < 1.0 / refresh_hz():
		return
	_refresh_timer = 0.0
	refresh()
	if markers.is_valid():
		_overlay.queue_redraw()

## Pulls the latest tracked position/heading and redraws if anything visible changed.
func refresh() -> void:
	if _game == null:
		return
	var tracked: Node3D = _game.tracked_body()
	var position := GeoProjection.world_to_map(tracked.global_position)
	var heading := MapCanvas.heading_of(tracked)
	if not _dirty and position.distance_squared_to(_last_position) < 0.01 and heading.dot(_last_heading) > 0.9999:
		return
	_dirty = false
	_last_position = position
	_last_heading = heading
	canvas.view_center = position
	canvas.pixels_per_meter = ZOOM_LEVELS[zoom_index]
	canvas.view_rotation = (-PI * 0.5 - heading.angle()) if heading_up else 0.0
	canvas.player_position = position
	canvas.player_heading = heading
	canvas.vehicles = _game.vehicle_markers()
	canvas.route = _navigator.remaining_route
	canvas.destination = _navigator.marker_point()
	canvas.queue_redraw()
	_overlay.queue_redraw()

func _layout() -> void:
	if canvas == null:
		return
	canvas.position = Vector2.ZERO
	canvas.size = size
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	# Fingers need the full size, even if three buttons then fill a small map's edge.
	var button_size := clampf(size.y / 3.0 - 6.0, 32.0, UiTheme.TOUCH_TARGET)
	var x := size.x - button_size - 4.0
	_place_button(_buttons.ZoomIn, Vector2(x, 4.0), Vector2(button_size, button_size))
	_place_button(_buttons.ZoomOut, Vector2(x, 8.0 + button_size), Vector2(button_size, button_size))
	_place_button(_buttons.Orientation, Vector2(x, 12.0 + button_size * 2.0), Vector2(button_size, button_size))
	_dirty = true

func _place_button(button: Button, at: Vector2, button_size: Vector2) -> void:
	button.position = at
	button.size = button_size

func _update_orientation_button() -> void:
	if _buttons.has("Orientation"):
		_buttons.Orientation.text = "H" if heading_up else "N"
		_buttons.Orientation.tooltip_text = "Heading-up (N to switch)" if heading_up else "North-up (N to switch)"

func _draw_overlay() -> void:
	_overlay.draw_rect(Rect2(Vector2.ONE, size - Vector2(2.0, 2.0)), UiTheme.LINE, false, 2.0)
	if markers.is_valid():
		var transform := canvas.map_transform()
		var area := Rect2(Vector2.ZERO, size)
		for marker: Array in markers.call():
			var at: Vector2 = transform * (marker[0] as Vector2)
			if area.has_point(at):
				_overlay.draw_circle(at, float(marker[2]) + 1.5, Color(0.0, 0.0, 0.0, 0.8))
				_overlay.draw_circle(at, float(marker[2]), marker[1])
	if not heading_up:
		return
	var north := canvas.map_transform().basis_xform(Vector2(0.0, -1.0)).normalized()
	var radius := minf(size.x, size.y) * 0.5 - 14.0
	var at := size * 0.5 + north * radius
	_overlay.draw_circle(at, 11.0, UiTheme.SURFACE_SOLID)
	_overlay.draw_string(UiTheme.font(), at + Vector2(-5.0, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SMALL, UiTheme.ACCENT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				open_full_map_requested.emit()
			MOUSE_BUTTON_WHEEL_UP:
				change_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				change_zoom(-1)
		accept_event()

## Touch is handled directly because touch-to-mouse emulation is disabled in this project.
## _input sees touches before any menu drawn over the minimap, so a paused game (a menu
## is up) must not open the map through it.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_tree().paused:
		_touch_index = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed and get_global_rect().has_point(event.position):
			_touch_index = event.index
			_touch_held = 0.0
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			var was_hold := _touch_held >= HOLD_SECONDS
			_touch_index = -1
			get_viewport().set_input_as_handled()
			if not event.canceled and not was_hold and get_global_rect().has_point(event.position):
				_handle_tap(event.position)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		get_viewport().set_input_as_handled()

func _handle_tap(screen_position: Vector2) -> void:
	for button: Button in _buttons.values():
		if button.visible and button.get_global_rect().has_point(screen_position):
			button.pressed.emit()
			_show_controls(true)
			return
	open_full_map_requested.emit()

func controls_visible() -> bool:
	return _controls_left > 0.0

func _show_controls(value: bool) -> void:
	_controls_left = CONTROLS_SECONDS if value else 0.0
	for button: Button in _buttons.values():
		button.visible = value

func _tick_controls(delta: float) -> void:
	if _touch_index != -1:
		_touch_held += delta
		if _touch_held >= HOLD_SECONDS and _controls_left <= 0.0:
			_show_controls(true)
	elif _controls_left > 0.0:
		_controls_left -= delta
		if _controls_left <= 0.0:
			_show_controls(false)
