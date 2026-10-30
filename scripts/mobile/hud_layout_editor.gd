extends CanvasLayer

## BGMI/PUBG-style "Customize HUD": the game pauses, every button of the chosen
## layout (NORMAL, FIRING or VEHICLE) becomes a tile you drag into place, and the
## toolbar resizes the selected tile and sets the layout's opacity. Saving writes
## the layouts offline; Cancel restores what was saved. Works with mouse and touch
## (the HUD's menu bridge turns a finger into the mouse while this is open).

signal closed(saved: bool)

const Profiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const SCALE_STEP := 0.1
const OPACITY_STEP := 0.1
const BAR_BUTTON := Vector2(132.0, 56.0)

var profiles: Profiles
## Where SAVE writes and CANCEL restores from (tests use a scratch file).
var save_path := Profiles.DEFAULT_PATH
## profile -> {"rects": Dictionary, "safe": Rect2, "min_target": float, "labels": Dictionary, "opacity": float}
var layout_provider: Callable
var profile := Profiles.NORMAL
var selected := &""

var _root: Control
var _tiles: Control
var _bar: PanelContainer
var _bar_at_top := true
var _profile_buttons := {}
var _selected_label: Label
var _size_label: Label
var _opacity_label: Label
var _status: Label
var _context := {}
var _tile_nodes := {}
var _drag_slot := &""
var _drag_offset := Vector2.ZERO
var _was_paused := false

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_tiles = Control.new()
	_tiles.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tiles.draw.connect(_draw_safe_area)
	_root.add_child(_tiles)
	_build_bar()
	_root.get_viewport().size_changed.connect(func() -> void:
		if visible: _rebuild())
	visible = false

func is_open() -> bool:
	return visible

func open(start_profile: StringName) -> void:
	profile = start_profile if start_profile in Profiles.PROFILES else Profiles.NORMAL
	selected = &""
	_drag_slot = &""
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_status.text = "Drag a button to move it. Select one to resize."
	_rebuild()

## Leaves without saving: the layouts go back to what is on disk.
func cancel() -> void:
	profiles.load_from(save_path)
	_close(false)

func save() -> void:
	if profiles.save_to(save_path) != OK:
		_status.text = "Could not save the layout. Try again."
		return
	_close(true)

func _close(saved: bool) -> void:
	_drag_slot = &""
	visible = false
	get_tree().paused = _was_paused
	closed.emit(saved)

func switch_profile(next: StringName) -> void:
	if next not in Profiles.PROFILES:
		return
	_drag_slot = &""
	selected = &""
	profile = next
	_rebuild()

func change_size(direction: float) -> void:
	if selected.is_empty():
		_status.text = "Select a button first."
		return
	var rect: Rect2 = _context.rects[selected]
	var scale := clampf(profiles.slot_scale(profile, selected) + direction * SCALE_STEP, Profiles.SCALE_RANGE.x, Profiles.SCALE_RANGE.y)
	profiles.set_slot(profile, selected, Profiles.center_fraction(rect, _context.safe), scale)
	_rebuild()

func change_opacity(direction: float) -> void:
	profiles.set_opacity(profile, profiles.opacity_for(profile, _context.get("opacity", 0.85)) + direction * OPACITY_STEP)
	_rebuild()

func reset_profile() -> void:
	profiles.reset(profile)
	selected = &""
	_status.text = "%s reset to the default layout." % Profiles.PROFILE_TITLES[profile]
	_rebuild()

## Moves a tile so its centre follows the finger, kept fully on screen.
func drag_to(slot: StringName, center: Vector2) -> void:
	if not _context.rects.has(slot):
		return
	var rect: Rect2 = _context.rects[slot]
	var moved := Profiles._inside(Rect2(center - rect.size * 0.5, rect.size), _context.safe)
	profiles.set_slot(profile, slot, Profiles.center_fraction(moved, _context.safe), profiles.slot_scale(profile, slot))
	# Only the dragged tile moves while the finger is down; the full refresh (overlap
	# warnings included) waits for the lift, so dragging stays smooth on a tablet.
	_context.rects[slot] = moved
	if _tile_nodes.has(slot):
		_tile_nodes[slot].position = moved.position

func _rebuild() -> void:
	if not layout_provider.is_valid():
		return
	var context: Dictionary = layout_provider.call(profile)
	context.rects = profiles.apply(profile, context.rects, context.safe, context.min_target)
	_context = context
	for child in _tiles.get_children():
		child.queue_free()
	_tile_nodes.clear()
	var slots := Profiles.slots_for(profile)
	var overlapping := {}
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			if context.rects.has(slots[i]) and context.rects.has(slots[j]) and context.rects[slots[i]].intersects(context.rects[slots[j]]):
				overlapping[slots[i]] = true
				overlapping[slots[j]] = true
	for slot in slots:
		if context.rects.has(slot):
			var tile := _make_tile(slot, context.rects[slot], context.labels.get(slot, String(slot)), overlapping.has(slot))
			_tile_nodes[slot] = tile
			_tiles.add_child(tile)
	# The selected button draws (and takes touches) on top, so after dropping it onto
	# another button it can still be grabbed again.
	if _tile_nodes.has(selected):
		_tiles.move_child(_tile_nodes[selected], -1)
	_tiles.queue_redraw()
	_refresh_bar()
	if not overlapping.is_empty():
		_status.text = "Orange buttons overlap: a tap there may hit the wrong one."
	_place_bar()

func _end_drag() -> void:
	var dragged := not _drag_slot.is_empty()
	_drag_slot = &""
	if dragged:
		_rebuild()

func _refresh_bar() -> void:
	for key in _profile_buttons:
		_profile_buttons[key].button_pressed = key == profile
	_selected_label.text = "Selected: %s" % (_context.labels.get(selected, String(selected)) if not selected.is_empty() else "none")
	_size_label.text = "%d%%" % roundi(profiles.slot_scale(profile, selected) * 100.0) if not selected.is_empty() else "—"
	_opacity_label.text = "%d%%" % roundi(profiles.opacity_for(profile, _context.get("opacity", 0.85)) * 100.0)

## Selection only changes borders, so the tile under the finger is never replaced mid-press.
func _restyle() -> void:
	for slot in _tile_nodes:
		var style := _tile_nodes[slot].get_theme_stylebox("panel") as StyleBoxFlat
		style.set_border_width_all(4 if slot == selected else 2)
		if slot == selected:
			style.border_color = Color("ffd45a")
		elif style.border_color == Color("ffd45a"):
			style.border_color = Color(1, 1, 1, 0.7)

func _make_tile(slot: StringName, rect: Rect2, text: String, overlaps: bool) -> Control:
	var tile := Panel.new()
	tile.name = String(slot)
	tile.position = rect.position
	tile.size = rect.size
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.18, profiles.opacity_for(profile, _context.get("opacity", 0.85)))
	style.set_corner_radius_all(roundi(minf(rect.size.x, rect.size.y) * 0.5))
	style.set_border_width_all(4 if slot == selected else 2)
	style.border_color = Color("ffd45a") if slot == selected else (Color(1.0, 0.55, 0.15) if overlaps else Color(1, 1, 1, 0.7))
	tile.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", clampi(roundi(minf(rect.size.y * 0.24, rect.size.x * 0.9 / maxf(text.length() * 0.6, 3.0))), 11, 24))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(label)
	tile.gui_input.connect(_on_tile_input.bind(slot, tile))
	return tile

func _on_tile_input(event: InputEvent, slot: StringName, tile: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_slot = slot
			_drag_offset = tile.get_global_rect().get_center() - (event as InputEventMouseButton).global_position
			if selected != slot:
				selected = slot
				_refresh_bar()
				_restyle()
				_tiles.move_child(tile, -1)
		else:
			_end_drag()
		tile.accept_event()
	elif event is InputEventMouseMotion and _drag_slot == slot and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		drag_to(slot, (event as InputEventMouseMotion).global_position + _drag_offset)
		tile.accept_event()

## Tiles are rebuilt while dragging, so motion is also followed here once the
## tile under the finger has been replaced.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion and not _drag_slot.is_empty() and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		drag_to(_drag_slot, (event as InputEventMouseMotion).global_position + _drag_offset)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _drag_slot.is_empty():
		_end_drag()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()

func _draw_safe_area() -> void:
	if _context.has("safe"):
		_tiles.draw_rect(_context.safe, Color(1, 1, 1, 0.25), false, 2.0)

func _build_bar() -> void:
	_bar = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.95)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	_bar.add_theme_stylebox_override("panel", style)
	_root.add_child(_bar)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_bar.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	for key in Profiles.PROFILES:
		var choice := _bar_button(top, Profiles.PROFILE_TITLES[key], switch_profile.bind(key))
		choice.toggle_mode = true
		_profile_buttons[key] = choice
	_bar_button(top, "RESET", reset_profile)
	_bar_button(top, "CANCEL", cancel)
	_bar_button(top, "SAVE", save)
	_bar_button(top, "MOVE BAR", func() -> void:
		_bar_at_top = not _bar_at_top
		_place_bar())
	var second := HBoxContainer.new()
	second.add_theme_constant_override("separation", 8)
	rows.add_child(second)
	_selected_label = Label.new()
	_selected_label.custom_minimum_size.x = 260.0
	second.add_child(_selected_label)
	_bar_button(second, "SIZE −", change_size.bind(-1.0))
	_size_label = Label.new()
	_size_label.custom_minimum_size.x = 70.0
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	second.add_child(_size_label)
	_bar_button(second, "SIZE +", change_size.bind(1.0))
	_bar_button(second, "OPACITY −", change_opacity.bind(-1.0))
	_opacity_label = Label.new()
	_opacity_label.custom_minimum_size.x = 70.0
	_opacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	second.add_child(_opacity_label)
	_bar_button(second, "OPACITY +", change_opacity.bind(1.0))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status)

func _bar_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BAR_BUTTON
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## The toolbar sits at the top or bottom centre of the safe area; MOVE BAR flips it
## so it never hides the buttons being arranged underneath.
func _place_bar() -> void:
	if not _context.has("safe"):
		return
	var safe: Rect2 = _context.safe
	var size := _bar.get_combined_minimum_size()
	_bar.size = size
	var x := safe.get_center().x - size.x * 0.5
	var y := safe.position.y + 8.0 if _bar_at_top else safe.end.y - size.y - 8.0
	_bar.position = Vector2(clampf(x, safe.position.x, maxf(safe.position.x, safe.end.x - size.x)), y)
