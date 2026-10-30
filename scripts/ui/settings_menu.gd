extends CanvasLayer

const PRESETS := ["Low", "Medium", "High", "Seasoned Expert", "Custom"]
var hud: Node
var panel: PanelContainer
var preset: OptionButton
var controls: Dictionary = {}
var hint: Label
var graphics_controls: Dictionary = {}
var graphics_preset: OptionButton
var _graphics_sync := false
var _syncing := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE

func setup(owner_hud: Node) -> void:
	hud = owner_hud
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	var entry := Button.new()
	entry.text = "SETTINGS"
	entry.position = Vector2(570, 16)
	entry.custom_minimum_size = Vector2(180, 52)
	entry.visible = not hud._touch_overlay_enabled
	add_child(entry)
	entry.pressed.connect(open_menu)
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.065, 0.99)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	_button(header, "Save & Return", close_menu)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 22)
	column.add_child(tabs)
	var sensitivity := _page(tabs, "Controls & Sensitivity")
	var description := Label.new()
	description.text = "Game-specific presets. 100% = 1x sensitivity. Changes apply immediately and save on return."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sensitivity.add_child(description)
	# BGMI-style layout editor: separate NORMAL, FIRING and VEHICLE arrangements.
	_button(sensitivity, "Customize HUD layout  (Normal • Firing • Vehicle)", func() -> void:
		close_menu()
		if not panel.visible and hud.has_method("open_layout_editor"):
			hud.open_layout_editor())
	preset = _options(sensitivity, "Sensitivity preset", PRESETS)
	preset.item_selected.connect(func(index: int) -> void:
		if _syncing: return
		hud.touch_settings.apply_preset(PRESETS[index])
		_refresh()
		_apply())
	var mode := _options(sensitivity, "Gyroscope mode", ["Off", "Scope Only", "Always On"])
	controls["gyro_mode"] = mode
	mode.item_selected.connect(func(index: int) -> void:
		if _syncing: return
		hud.touch_settings.gyro_mode = index
		_apply())
	_slider(sensitivity, "Camera swipe / mouse", "look_sensitivity", 0.3, 3.0)
	_slider(sensitivity, "ADS swipe / mouse", "ads_sensitivity", 0.1, 4.0)
	_slider(sensitivity, "Gyroscope (hip fire)", "gyro_sensitivity", 0.2, 4.0)
	_slider(sensitivity, "ADS gyroscope", "ads_gyro_sensitivity", 0.2, 4.0)
	for item in [["Invert gyro horizontal", "gyro_invert_x"], ["Invert gyro vertical", "gyro_invert_y"]]:
		var check := CheckButton.new()
		check.text = item[0]
		check.custom_minimum_size.y = 52
		sensitivity.add_child(check)
		var key: String = item[1]
		controls[key] = check
		check.toggled.connect(func(value: bool) -> void:
			if _syncing: return
			hud.touch_settings.set(key, value)
			_apply())
	_button(sensitivity, "Reset sensitivity to Medium", func() -> void:
		hud.touch_settings.apply_preset("Medium")
		_refresh()
		_apply())
	hint = Label.new()
	sensitivity.add_child(hint)
	var weather := _page(tabs, "Time & Weather")
	var time := _options(weather, "Time of day", ["Automatic", "Morning", "Afternoon", "Night"])
	controls["time"] = time
	time.item_selected.connect(func(index: int) -> void:
		if not _syncing: hud._game.environment_controls.environment.set_time_mode(["Automatic", "Morning", "Afternoon", "Night"][index]))
	var sky := _options(weather, "Weather", ["Automatic", "Clear", "Rain", "Storm"])
	controls["weather"] = sky
	sky.item_selected.connect(func(index: int) -> void:
		if not _syncing: hud._game.environment_controls.environment.set_weather_mode(["Automatic", "Clear", "Rain", "Storm"][index]))
	var activities := _page(tabs, "Activities")
	_button(activities, "Open missions & activities", func() -> void:
		close_menu()
		hud._game.gameplay.open_board())
	var cities := _page(tabs, "Maps & Cities")
	var city_desc := Label.new()
	city_desc.text = "Select an exploration map. Chowrasta City is built directly from the crossroads sketch reference."
	city_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cities.add_child(city_desc)
	_button(cities, "Load Chowrasta City (Sketch Reference)", func() -> void:
		close_menu()
		get_tree().change_scene_to_file("res://scenes/world/chowrasta_city.tscn"))
	_button(cities, "Load Godavarikhani (Full District)", func() -> void:
		close_menu()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_button(activities, "Open city journal", func() -> void:
		close_menu()
		hud._game.city_life.open_journal())
	_build_graphics(tabs)
	panel.hide()

func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenDrag:
			scroll.scroll_vertical -= int(event.relative.y))
	tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	parent.add_child(button)
	button.pressed.connect(callback)

func _options(parent: Node, title: String, choices: Array) -> OptionButton:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.y = 52
	for choice: String in choices: option.add_item(choice)
	parent.add_child(option)
	return option

func _slider(parent: Node, title: String, key: String, lower: float, upper: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	row.add_child(value)
	var slider := HSlider.new()
	slider.min_value = lower
	slider.max_value = upper
	slider.step = 0.05
	slider.custom_minimum_size.y = 48
	parent.add_child(slider)
	controls[key] = slider
	slider.value_changed.connect(func(amount: float) -> void:
		value.text = "%d%%" % roundi(amount * 100.0)
		if _syncing: return
		hud.touch_settings.set(key, amount)
		hud.touch_settings.sensitivity_preset = "Custom"
		preset.select(4)
		_apply())

func _refresh() -> void:
	_syncing = true
	preset.select(maxi(0, PRESETS.find(hud.touch_settings.sensitivity_preset)))
	for key in controls:
		var control: Control = controls[key]
		if control is HSlider: control.value = hud.touch_settings.get(key)
		elif control is CheckButton: control.button_pressed = hud.touch_settings.get(key)
		elif key == "gyro_mode": control.select(hud.touch_settings.gyro_mode)
	var environment = hud._game.environment_controls.environment
	controls.time.select(maxi(0, ["Automatic", "Morning", "Afternoon", "Night"].find(environment.time_mode)))
	controls.weather.select(0 if environment.auto_weather else (3 if environment.storm else (2 if environment.rain_target > 0.5 else 1)))
	_syncing = false

func _apply() -> void:
	hud.touch_settings.sanitize()
	hud.touch_settings.apply_to_camera(hud.player.camera_pivot)

func open_menu() -> void:
	if panel.visible or get_tree().paused or not hud._game: return
	_mouse_before = Input.mouse_mode
	hud._game._clear_control_inputs()
	hud._game.pause_tree(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_refresh_graphics()
	hint.text = "Gyro affects aim only on devices with a gyroscope. Off ignores gyro sensitivity."
	panel.show()

func close_menu() -> void:
	if not panel.visible: return
	_apply()
	var result: Error = hud.touch_settings.save_to()
	if result != OK:
		hint.text = "Settings could not be saved. Try again."
		return
	if hud._game.performance_controller.settings.save_to() != OK:
		hint.text = "Graphics preferences could not be saved."
		return
	panel.hide()
	get_tree().paused = false
	hud._game._clear_control_inputs()
	Input.mouse_mode = _mouse_before
	hud._game._sync_input_context()

func _input(event: InputEvent) -> void:
	if panel and panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func _build_graphics(tabs: TabContainer) -> void:
	var page := _page(tabs, "Graphics & Performance")
	var note := Label.new()
	note.text = "Auto selects a conservative device profile. FPS is a target, not a guarantee. Lower quality reduces GPU and simulation work."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
	graphics_preset = _options(page, "Graphics preset", ["Auto", "Low", "Medium", "High", "Custom"])
	graphics_preset.item_selected.connect(func(index: int) -> void:
		if _graphics_sync: return
		var controller = hud._game.performance_controller
		controller.settings.select(["Auto", "Low", "Medium", "High", "Custom"][index])
		controller.apply_settings()
		_refresh_graphics())
	for item in [["3D resolution scale", "scale", 0.5, 1.0, 0.05], ["Building / prop distance (metres)", "distance", 250.0, 1000.0, 50.0], ["Active ambient residents / traffic", "actors", 6.0, 70.0, 1.0], ["Simulation distance (metres)", "simulation", 80.0, 450.0, 10.0], ["Weather effects", "effects", 0.0, 1.0, 0.05]]:
		var label := Label.new()
		page.add_child(label)
		var slider := HSlider.new()
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = item[4]
		slider.custom_minimum_size.y = 48
		page.add_child(slider)
		var key: String = item[1]
		var title: String = item[0]
		graphics_controls[key] = slider
		slider.value_changed.connect(func(value: float) -> void:
			label.text = title + ": " + ("%d%%" % roundi(value * 100) if key in ["scale", "effects"] else str(roundi(value)))
			if not _graphics_sync: _graphics_change(key, value))
	var shadows := CheckButton.new()
	shadows.text = "Shadows"
	shadows.custom_minimum_size.y = 52
	page.add_child(shadows)
	graphics_controls.shadows = shadows
	shadows.toggled.connect(func(value: bool) -> void:
		if not _graphics_sync: _graphics_change("shadows", value))
	var fps := _options(page, "Frame-rate target", ["30 FPS", "60 FPS"])
	graphics_controls.fps = fps
	fps.item_selected.connect(func(index: int) -> void:
		if not _graphics_sync: _graphics_change("fps", 30 if index == 0 else 60))

func _graphics_change(key: String, value: Variant) -> void:
	var controller = hud._game.performance_controller
	controller.settings.preset = "Custom"
	controller.settings.values[key] = value
	controller.apply_settings()
	graphics_preset.select(4)

func _refresh_graphics() -> void:
	if not hud._game.performance_controller: return
	_graphics_sync = true
	var settings = hud._game.performance_controller.settings
	graphics_preset.select(maxi(0, ["Auto", "Low", "Medium", "High", "Custom"].find(settings.preset)))
	for key: String in graphics_controls:
		var control: Control = graphics_controls[key]
		if control is HSlider:
			control.value = settings.values[key]
			control.value_changed.emit(control.value)
		elif control is CheckButton: control.button_pressed = settings.values[key]
		elif control is OptionButton: control.select(0 if settings.values.fps == 30 else 1)
	_graphics_sync = false
