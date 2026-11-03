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
const PANEL_WIDTH := 320.0
const LIST_HEIGHT := 300.0
const SOURCES_WIDTH := 460.0
const LEGEND_SWATCH := 12.0
const LABEL_ZOOM := 1.0
const KEY_PAN_STEP := 80.0
const ATTRIBUTION := ("Map data © OpenStreetMap contributors (ODbL) • Building footprints © Microsoft (ODbL) • "
	+ "Building heights: Google Open Buildings 2.5D (CC BY 4.0) • Terrain: Copernicus DEM © DLR e.V., © Airbus DS, ESA\n"
	+ "Supplemental footprints: Overture Maps Foundation (ODbL), Google Open Buildings (CC BY 4.0)\n"
	+ "Shop and street names: © OpenStreetMap contributors, Overture Maps Foundation (CDLA-Permissive-2.0)\n"
	+ "Land cover: © ESA WorldCover project 2021, Copernicus Sentinel data (CC BY 4.0) • "
	+ "Trees: Meta and World Resources Institute canopy height maps (CC BY 4.0) • "
	+ "Supplemental roads/trees: TopoExport, Overture Maps Foundation (ODbL), Global Canopy Height Maps v2 (CC BY 4.0)")

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
var _destinations: PanelContainer
var _clear_button: Button
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
	theme = UiTheme.theme()
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, UiTheme.SPACE_M)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_bar.add_theme_constant_override("separation", UiTheme.SPACE_S)
	add_child(top_bar)
	for spec: Array in [["-", _zoom_by.bind(1.0 / 1.5)], ["+", _zoom_by.bind(1.5)], ["Me", center_on_player]]:
		var button := _make_button(spec[0], spec[1])
		button.custom_minimum_size.x = UiTheme.TOUCH_TARGET
		top_bar.add_child(button)
	_clear_button = _make_button("Clear route", _clear_route)
	top_bar.add_child(_clear_button)
	top_bar.add_child(_make_button("Back", close_requested.emit))
	var panel := VBoxContainer.new()
	panel.name = "Destinations"
	panel.position = Vector2(UiTheme.SPACE_M, UiTheme.SPACE_M)
	panel.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	add_child(panel)
	_search = LineEdit.new()
	_search.name = "LocationSearch"
	_search.placeholder_text = "Search"
	_search.custom_minimum_size = Vector2(PANEL_WIDTH, UiTheme.TOUCH_TARGET)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_search.focus_entered.connect(_sync_list)
	_search.focus_exited.connect(_sync_list, CONNECT_DEFERRED)
	panel.add_child(_search)
	_destinations = PanelContainer.new()
	_destinations.visible = false
	panel.add_child(_destinations)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - UiTheme.SPACE_L, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_destinations.add_child(scroll)
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_results)
	_status = Label.new()
	_status.name = "Status"
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, UiTheme.SPACE_M)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE, UiTheme.RADIUS_PILL))
	add_child(_status)
	_build_legend()
	var sources_column := VBoxContainer.new()
	sources_column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, UiTheme.SPACE_M)
	sources_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sources_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sources_column.alignment = BoxContainer.ALIGNMENT_END
	add_child(sources_column)
	_attribution = Label.new()
	_attribution.visible = false
	_attribution.text = ATTRIBUTION
	_attribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attribution.custom_minimum_size.x = SOURCES_WIDTH
	_attribution.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_attribution.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE_SOLID))
	sources_column.add_child(_attribution)
	var sources := _make_button("© Sources", func() -> void: _attribution.visible = not _attribution.visible)
	sources.size_flags_horizontal = Control.SIZE_SHRINK_END
	sources_column.add_child(sources)
	navigator.route_changed.connect(refresh)

## You, the goal, the route and other vehicles, in the colours the map draws them.
func _build_legend() -> void:
	var legend := PanelContainer.new()
	legend.name = "Legend"
	legend.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE))
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, UiTheme.SPACE_M)
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(legend)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_S)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_child(row)
	for item: Array in [["You", MapCanvas.PLAYER_COLOR], ["Goal", MapCanvas.DESTINATION_COLOR],
			["Route", MapCanvas.ROUTE_COLOR], ["Vehicle", MapCanvas.VEHICLE_COLOR]]:
		var swatch := ColorRect.new()
		swatch.color = item[1]
		swatch.custom_minimum_size = Vector2.ONE * LEGEND_SWATCH
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = item[0]
		label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		row.add_child(label)

func open() -> void:
	_rebuild_destinations()
	center_on_player()
	canvas.pixels_per_meter = DEFAULT_ZOOM
	visible = true
	refresh()

func close() -> void:
	visible = false
	_search.release_focus()
	_search.clear()
	_destinations.visible = false
	_attribution.visible = false
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
	# Labels stay off until the player zooms in, so the roads read first.
	canvas.show_labels = canvas.pixels_per_meter >= LABEL_ZOOM
	var status := _navigator.status_text()
	_status.text = status
	_status.visible = not status.is_empty()
	_status.add_theme_color_override("font_color", UiTheme.DANGER if not _navigator.error_text.is_empty() else UiTheme.TEXT)
	_clear_button.visible = not status.is_empty()

## Places a waypoint at a viewport (global canvas) position on the map.
func place_waypoint_at_screen(screen_position: Vector2) -> void:
	_navigator.set_destination(canvas.screen_to_map(_to_canvas(screen_position)))
	refresh()

func _to_canvas(screen_position: Vector2) -> Vector2:
	return canvas.get_global_transform().affine_inverse() * screen_position

func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	button.pressed.connect(callback)
	_buttons.append(button)
	return button

func _on_search_changed(_query: String) -> void:
	_rebuild_destinations()
	_sync_list()

## The place list shows only while the player is using it.
func _sync_list() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_destinations.visible = visible and (focused == _search or (focused != null and _results.is_ancestor_of(focused)))

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
			message.text = "No match"
			_results.add_child(message)
		for record: Dictionary in matches:
			var button := _result_button(str(record.name), _go_to_record.bind(record))
			button.disabled = not record.canNavigate
			button.tooltip_text = "%s\n%s\n%s\n%s" % [record.name, record.category, Catalog.status_label(record), str(record.get("sources", record.get("source", "")))]
		return
	var sorted := _landmarks.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := 0 if a.category in ["Road", "Bus station", "Game area"] else 1
		var b_priority := 0 if b.category in ["Road", "Bus station", "Game area"] else 1
		if a_priority != b_priority:
			return a_priority < b_priority
		return origin.distance_to(a.position) < origin.distance_to(b.position))
	for landmark in sorted.slice(0, MAX_DESTINATIONS):
		var label := "%s  %s" % [landmark.name, GpsNavigator.format_distance(origin.distance_to(landmark.position))]
		_result_button(label, _go_to_landmark.bind(landmark))

func _result_button(text: String, callback: Callable) -> Button:
	var button := _make_button(text, callback)
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_results.add_child(button)
	return button

func _go_to_record(record: Dictionary) -> void:
	if not record.get("canNavigate", false) or not record.has("position"):
		return
	_go_to_landmark(record)

func _go_to_landmark(landmark: Dictionary) -> void:
	_navigator.set_destination(landmark.position, landmark.name)
	canvas.view_center = landmark.position
	_search.release_focus()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_destinations.visible = false
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
					_search.release_focus()
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
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventScreenTouch:
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

## Keyboard: arrows pan, plus and minus zoom, Tab enters the search and the buttons.
func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or get_viewport().gui_get_focus_owner() != null:
		return
	var step := KEY_PAN_STEP
	match event.keycode:
		KEY_LEFT: _pan_by(Vector2(step, 0.0))
		KEY_RIGHT: _pan_by(Vector2(-step, 0.0))
		KEY_UP: _pan_by(Vector2(0.0, step))
		KEY_DOWN: _pan_by(Vector2(0.0, -step))
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _zoom_by(1.5)
		KEY_MINUS, KEY_KP_SUBTRACT: _zoom_by(1.0 / 1.5)
		KEY_TAB: _search.grab_focus()
		_: return
	get_viewport().set_input_as_handled()

func _handle_tap(screen_position: Vector2) -> void:
	for button in _buttons:
		if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(screen_position):
			button.pressed.emit()
			return
	if _search.get_global_rect().has_point(screen_position):
		_search.grab_focus()
		return
	_search.release_focus()
	place_waypoint_at_screen(screen_position)

func _pinch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])

func _pinch_center() -> Vector2:
	var points: Array = _touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
