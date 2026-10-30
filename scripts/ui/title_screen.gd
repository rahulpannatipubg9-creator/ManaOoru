extends Control

## The front door: MANA OORU, one Telugu line and a short menu over a drawn dusk.
## Settings shows graphics quality here, the one setting worth choosing before the town
## loads. The rest needs a running game, so All settings starts it and opens them.

const CreditsScreen := preload("res://scripts/ui/credits_screen.gd")
const LoadingScreen := preload("res://scripts/ui/loading_screen.gd")
const GraphicsSettings := preload("res://scripts/performance/graphics_settings.gd")
## Same file as CityLife.SAVE_PATH. Naming that constant would load the whole game here.
const SAVE_PATH := "user://city_life_v1.json"
const SKY_SHADER := preload("res://shaders/title_sky.gdshader")
const QUALITY := ["Auto", "Low", "Medium", "High"]

var _menu: VBoxContainer
var _first: Button
var _sky: ColorRect
var _sheet: Control

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_sky()
	_build_front()
	get_viewport().size_changed.connect(_fit_sky)
	_fit_sky()
	_first.grab_focus()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, UiTheme.MOTION_NORMAL)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_sheet):
		_close_sheet()
		get_viewport().set_input_as_handled()

func _build_sky() -> void:
	_sky = ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter("ink", UiTheme.INK)
	material.set_shader_parameter("marigold", UiTheme.ACCENT)
	_sky.material = material
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)

func _fit_sky() -> void:
	var view := get_viewport_rect().size
	(_sky.material as ShaderMaterial).set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))

func _build_front() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL * 2)
	for side: String in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	var title := Label.new()
	title.text = "MANA OORU"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_HERO * 2)
	title.add_theme_constant_override("line_spacing", 0)
	column.add_child(title)
	var telugu := Label.new()
	telugu.text = "మన ఊరు"
	telugu.add_theme_font_size_override("font_size", UiTheme.FONT_DISPLAY)
	telugu.add_theme_color_override("font_color", UiTheme.ACCENT)
	column.add_child(telugu)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(gap)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_menu)
	if has_save():
		_first = _add_item("Continue", func() -> void: _start())
		_add_item("New Game", _ask_new_game)
	else:
		_first = _add_item("New Game", func() -> void: _start())
	UiTheme.make_primary(_first)
	_add_item("Squad", func() -> void: _start(LoadingScreen.THEN_SQUAD))
	_add_item("Settings", _show_settings)
	_add_item("Credits", _show_credits)
	_add_item("Quit", func() -> void: get_tree().quit())

func _add_item(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET * 6.0, UiTheme.TOUCH_TARGET)
	button.add_theme_font_size_override("font_size", UiTheme.FONT_LABEL)
	var quiet := StyleBoxEmpty.new()
	quiet.set_content_margin_all(UiTheme.SPACE_M)
	button.add_theme_stylebox_override("normal", quiet)
	button.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.LINE))
	button.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	button.add_theme_color_override("font_focus_color", UiTheme.ACCENT)
	_menu.add_child(button)
	button.pressed.connect(action)
	return button

## Hands over to the loading screen, which outlives this scene.
func _start(then := "") -> void:
	var loading := LoadingScreen.new()
	loading.then = then
	get_tree().root.add_child(loading)
	_set_menu_enabled(false)

func _set_menu_enabled(value: bool) -> void:
	for button: Button in _menu.get_children():
		button.disabled = not value

## A small dialog over the title. Returns its column; Esc or the first button closes it.
func _open_sheet(heading: String) -> VBoxContainer:
	_close_sheet()
	_sheet = ColorRect.new()
	UiTheme.make_dim(_sheet)
	add_child(_sheet)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE_SOLID, UiTheme.RADIUS, UiTheme.LINE))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_M)
	panel.add_child(column)
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
	column.add_child(label)
	return column

func _close_sheet() -> void:
	if is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null
	_first.grab_focus()

func _sheet_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET * 3.0, UiTheme.TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _ask_new_game() -> void:
	var column := _open_sheet("Replace your saved game?")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_S)
	column.add_child(row)
	var keep := _sheet_button(row, "Keep it", _close_sheet)
	UiTheme.make_primary(keep)
	_sheet_button(row, "Start over", _start_over)
	keep.grab_focus()

func _start_over() -> void:
	erase_save()
	_close_sheet()
	_start()

static func erase_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _show_settings() -> void:
	var column := _open_sheet("Graphics")
	var graphics := GraphicsSettings.new()
	graphics.load_from()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	column.add_child(row)
	var group := ButtonGroup.new()
	var chosen: Button
	for preset: String in QUALITY:
		var option := Button.new()
		option.text = preset
		option.toggle_mode = true
		option.button_group = group
		option.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET * 2.0, UiTheme.TOUCH_TARGET)
		option.button_pressed = graphics.preset == preset
		option.add_theme_color_override("font_pressed_color", UiTheme.ACCENT)
		row.add_child(option)
		option.pressed.connect(func() -> void:
			graphics.select(preset)
			graphics.save_to())
		if option.button_pressed or chosen == null:
			chosen = option
	_sheet_button(column, "All settings", func() -> void:
		_close_sheet()
		_start(LoadingScreen.THEN_SETTINGS))
	var done := _sheet_button(column, "Done", _close_sheet)
	UiTheme.make_primary(done)
	chosen.grab_focus()

func _show_credits() -> void:
	var credits := CreditsScreen.new()
	add_child(credits)
	credits.closed.connect(func() -> void: _first.grab_focus())
