class_name FullMap
extends Control

## Full-screen north-up map. Mouse: wheel zoom, drag pan, click waypoint,
## right-click clear. Touch: drag pan, pinch zoom, tap waypoint.
## The game tree is paused while this is open; this node keeps processing.

signal close_requested

const MIN_ZOOM := 0.1
const MAX_ZOOM := 4.0
const DEFAULT_ZOOM := 0.5
const TAP_MOVE_TOLERANCE := 12.0
const MAX_DESTINATIONS := 12

var canvas: MapCanvas
var _game: Node
var _navigator: GpsNavigator
var _landmarks: Array[Dictionary] = []
var _status: Label
var _attribution: Label
const Catalog := preload("res://scripts/map/location_catalog.gd")
var _catalog: RefCounted
var _search: LineEdit
var _results: VBoxContainer
var _destinations: VBoxContainer
var _buttons: Array[Button] = []
var _mouse_down := false
var _mouse_moved := 0.0
var _touches: Dictionary = {}
var _tap_index := -1
var _tap_moved := 0.0
var _pinch_distance := 0.0

func setup(game: Node, data: MapData, building_footprints: Array[PackedVector2Array],
		landmark_list: Array[Dictionary], navigator: GpsNavigator) -> void:
	_game = game
	_navigator = navigator
	_landmarks = landmark_list
	_catalog = data.location_catalog
	name = "FullMap"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = MapCanvas.new()
	canvas.name = "MapCanvas"
	canvas.show_labels = true
	canvas.road_width_scale = 1.2
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	canvas.setup(data, building_footprints, landmark_list)
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16.0
	top_bar.offset_right = -16.0
	top_bar.offset_top = 12.0
	top_bar.add_theme_constant_override("separation", 10)
	add_child(top_bar)
	var title := Label.new()
	title.text = "GODAVARIKHANI MAP"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)
	for spec in [["−", _zoom_by.bind(1.0 / 1.5)], ["+", _zoom_by.bind(1.5)], ["ME", center_on_player],
			["CLEAR ROUTE", _clear_route], ["✕  CLOSE", close_requested.emit]]:
		top_bar.add_child(_make_button(spec[0], spec[1], 20))
	var panel := PanelContainer.new()
	panel.name = "Destinations"
	panel.position = Vector2(16.0, 64.0)
	var panel_background := StyleBoxFlat.new()
	panel_background.bg_color = Color(0.06, 0.09, 0.08, 0.92)
	panel_background.set_content_margin_all(8.0)
	panel_background.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", panel_background)
	add_child(panel)
	_destinations = VBoxContainer.new()
	panel.add_child(_destinations)
	var heading := Label.new()
	heading.text = "Destinations"
	_destinations.add_child(heading)
	_search = LineEdit.new()
	_search.name = "LocationSearch"
	_search.placeholder_text = "Search place, road, colony or category"
	_search.custom_minimum_size = Vector2(370, 38)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_destinations.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 310)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_destinations.add_child(scroll)
	_results = VBoxContainer.new()
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_results)
	_status = Label.new()
	_status.name = "Status"
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = -110.0
	_status.offset_bottom = -80.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	var status_background := StyleBoxFlat.new()
	status_background.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	status_background.content_margin_left = 12.0
	status_background.content_margin_right = 12.0
	_status.add_theme_stylebox_override("normal", status_background)
	add_child(_status)
	_attribution = Label.new()
	_attribution.text = ("Map data © OpenStreetMap contributors (ODbL) • Building footprints © Microsoft (ODbL) • "
		+ "Building heights: Google Open Buildings 2.5D (CC BY 4.0) • Terrain: Copernicus DEM © DLR e.V., © Airbus DS, ESA\n"
		+ "Supplemental footprints: Overture Maps Foundation (ODbL), Google Open Buildings (CC BY 4.0)\n"
		+ "Shop and street names: © OpenStreetMap contributors, Overture Maps Foundation (CDLA-Permissive-2.0)\n"
		+ "Land cover: © ESA WorldCover project 2021, Copernicus Sentinel data (CC BY 4.0) • "
		+ "Trees: Meta and World Resources Institute canopy height maps (CC BY 4.0) • "
		+ "Supplemental roads/trees: TopoExport, Overture Maps Foundation (ODbL), Global Canopy Height Maps v2 (CC BY 4.0)")
	_attribution.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attribution.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_attribution.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_attribution.offset_right = -12.0
	_attribution.offset_bottom = -8.0
	_attribution.add_theme_font_size_override("font_size", 12)
	add_child(_attribution)
	navigator.route_changed.connect(refresh)

func open() -> void:
	_rebuild_destinations()
	center_on_player()
	canvas.pixels_per_meter = DEFAULT_ZOOM
	visible = true
	refresh()

func close() -> void:
	visible = false
	_search.release_focus()
	_touches.clear()
	_tap_index = -1
	_mouse_down = false

func center_on_player() -> void:
	canvas.view_center = GeoProjection.world_to_map(_game.tracked_body().global_position)
	refresh()

func refresh() -> void:
	if not visible or _game == null:
		return
	var tracked: Node3D = _game.tracked_body()
	canvas.player_position = GeoProjection.world_to_map(tracked.global_position)
	canvas.player_heading = MapCanvas.heading_of(tracked)
	canvas.vehicles = _game.vehicle_markers()
	canvas.route = _navigator.remaining_route
	canvas.destination = _navigator.marker_point()
	canvas.queue_redraw()
	var status := _navigator.status_text()
	_status.text = status if not status.is_empty() else "Click or tap the map to set a waypoint"
	_status.add_theme_color_override("font_color", Color("#ff8a80") if not _navigator.error_text.is_empty() else Color.WHITE)

## Places a waypoint at a viewport (global canvas) position on the map.
func place_waypoint_at_screen(screen_position: Vector2) -> void:
	_navigator.set_destination(canvas.screen_to_map(_to_canvas(screen_position)))
	refresh()

func _to_canvas(screen_position: Vector2) -> Vector2:
	return canvas.get_global_transform().affine_inverse() * screen_position

func _make_button(text: String, callback: Callable, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(callback)
	_buttons.append(button)
	return button

func _on_search_changed(_query: String) -> void:
	_rebuild_destinations()

func _rebuild_destinations() -> void:
	for child in _results.get_children():
		if child is Button:
			_buttons.erase(child)
		_results.remove_child(child)
		child.queue_free()
	var origin := GeoProjection.world_to_map(_game.tracked_body().global_position)
	if _catalog != null and not _search.text.strip_edges().is_empty():
		var matches: Array[Dictionary] = _catalog.search(_search.text, origin, MAX_DESTINATIONS)
		if matches.is_empty():
			var message := Label.new()
			message.text = "No source-backed location found."
			_results.add_child(message)
		for record: Dictionary in matches:
			var label := "%s · %s\n%s" % [record.category, record.name, Catalog.status_label(record)]
			var button := _make_button(label, _go_to_record.bind(record), 13)
			button.disabled = not record.canNavigate
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.tooltip_text = "%s\n%s\n%s" % [record.name, Catalog.status_label(record), str(record.get("sources", record.get("source", "")))]
			_results.add_child(button)
		return
	var sorted := _landmarks.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := 0 if a.category in ["Road", "Bus station", "Game area"] else 1
		var b_priority := 0 if b.category in ["Road", "Bus station", "Game area"] else 1
		if a_priority != b_priority:
			return a_priority < b_priority
		return origin.distance_to(a.position) < origin.distance_to(b.position))
	for landmark in sorted.slice(0, MAX_DESTINATIONS):
		var label := "%s · %s  (%s)" % [landmark.category, landmark.name,
			GpsNavigator.format_distance(origin.distance_to(landmark.position))]
		var button := _make_button(label, _go_to_landmark.bind(landmark), 14)
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_results.add_child(button)

func _go_to_record(record: Dictionary) -> void:
	if not record.get("canNavigate", false) or not record.has("position"):
		return
	_go_to_landmark(record)

func _go_to_landmark(landmark: Dictionary) -> void:
	_navigator.set_destination(landmark.position, landmark.name)
	canvas.view_center = landmark.position
	refresh()

func _clear_route() -> void:
	_navigator.clear()
	refresh()

func _zoom_by(factor: float, pivot := Vector2.INF) -> void:
	if pivot == Vector2.INF:
		pivot = canvas.size * 0.5
	var anchor := canvas.screen_to_map(pivot)
	canvas.pixels_per_meter = clampf(canvas.pixels_per_meter * factor, MIN_ZOOM, MAX_ZOOM)
	canvas.view_center += anchor - canvas.screen_to_map(pivot)
	refresh()

func _pan_by(screen_delta: Vector2) -> void:
	canvas.view_center -= screen_delta / canvas.pixels_per_meter
	refresh()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(1.15, _to_canvas(get_global_transform() * event.position))
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / 1.15, _to_canvas(get_global_transform() * event.position))
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_mouse_down = true
					_mouse_moved = 0.0
				elif _mouse_down:
					_mouse_down = false
					if _mouse_moved < TAP_MOVE_TOLERANCE:
						place_waypoint_at_screen(get_global_transform() * event.position)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_clear_route()
		accept_event()
	elif event is InputEventMouseMotion and _mouse_down:
		_mouse_moved += event.relative.length()
		_pan_by(event.relative)
		accept_event()

## Touch is handled directly because touch-to-mouse emulation is disabled in this project.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_tap_index = event.index
				_tap_moved = 0.0
			else:
				_tap_index = -1
				_pinch_distance = _pinch_span()
		else:
			_touches.erase(event.index)
			if event.index == _tap_index and not event.canceled and _tap_moved < TAP_MOVE_TOLERANCE:
				_handle_tap(event.position)
			if event.index == _tap_index:
				_tap_index = -1
			_pinch_distance = _pinch_span()
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if not _touches.has(event.index):
			return
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var span := _pinch_span()
			if _pinch_distance > 0.0 and span > 0.0:
				_zoom_by(span / _pinch_distance, _to_canvas(_pinch_center()))
			_pinch_distance = span
		else:
			_tap_moved += event.relative.length()
			if _tap_moved >= TAP_MOVE_TOLERANCE:
				_pan_by(event.relative)

func _handle_tap(screen_position: Vector2) -> void:
	for button in _buttons:
		if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(screen_position):
			button.pressed.emit()
			return
	place_waypoint_at_screen(screen_position)

func _pinch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])

func _pinch_center() -> Vector2:
	var points: Array = _touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
