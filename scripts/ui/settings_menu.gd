extends CanvasLayer
## Settings pages: Controls, Camera, Graphics, Audio, Time & Weather, Animations, and Developer.
## Opens from the pause menu or directly, and closes back to whatever was underneath.

signal closed

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const PRESETS := ["Low", "Medium", "High", "Seasoned Expert", "Custom"]
const GRAPHICS_PRESETS := ["Auto", "Low", "Medium", "High", "Custom"]
const TIME_MODES := ["Automatic", "Morning", "Afternoon", "Night"]
const WEATHER_MODES := ["Automatic", "Clear", "Rain", "Storm"]
const SKIP_HOURS := [8, 17, 21]
const MENU_SETTINGS_PATH := "user://menu_settings.cfg"
const CARD_WIDTH := 960.0
const OPTION_WIDTH := 260.0
const VALUE_WIDTH := 64.0
const KEY_COLUMNS := 3
const KEYS := [["WASD", "Move"], ["Shift", "Run"], ["Space", "Jump"], ["C", "Crouch"], ["E", "Interact"], ["F", "Exit vehicle"],
	["V", "Camera"], ["B", "Look behind"], ["M", "Map"], ["F5", "Journal"], ["F6", "Time & weather"], ["F7", "Activities"],
	["1", "Equip"], ["2", "Switch rifle"], ["Click", "Fire"], ["Right-click", "Aim"], ["R", "Reload"], ["X", "Fire mode"],
	["G", "Grenade"], ["K", "Medkit"], ["O", "Help (hold)"], ["J", "Talk"], ["U", "Vault"], ["L", "Loot"],
	["F8", "Radio"], ["P", "Action mode"], ["Shift+P", "Surrender"], ["Home", "Recover"], ["Esc", "Menu"]]

var hud: Node
var panel: PanelContainer
var pause_menu: CanvasLayer
var tabs: TabContainer
var preset: OptionButton
var controls: Dictionary = {}
var audio_controls: Dictionary = {}
var hint: Label
var graphics_controls: Dictionary = {}
var camera_controls: Dictionary = {}
var graphics_preset: OptionButton
## The front door sets this to its credits screen; the button stays hidden until then.
var credits_action: Callable:
	set(value):
		credits_action = value
		if is_instance_valid(_credits):
			_credits.visible = value.is_valid()
var _credits: Button
var _developer_toggle: CheckButton
var _developer_enabled := false
var _master_volume := 1.0
var _ambience_volume := 0.65
var _touch_only: Array[Control] = []
var _graphics_sync := false
var _syncing := false
var _was_paused := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE

func setup(owner_hud: Node) -> void:
	hud = owner_hud
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_menu_settings()
	panel = PanelContainer.new()
	panel.theme = UiTheme.theme()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DIM, 0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size.x = CARD_WIDTH
	panel.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_S)
	card.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_S)
	column.add_child(header)
	var title := Label.new()
	title.text = "Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
	header.add_child(title)
	hint = Label.new()
	hint.add_theme_color_override("font_color", UiTheme.DANGER)
	header.add_child(hint)
	_credits = _button(header, "Credits", func() -> void: credits_action.call())
	_credits.visible = credits_action.is_valid()
	_button(header, "Back", close_menu)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	column.add_child(tabs)
	_build_controls(_page("Controls"))
	_build_graphics(_page("Graphics"))
	_build_audio(_page("Audio"))
	_build_time(_page("Time & Weather"))
	_build_camera(_page("Camera"))
	_build_animations_guide(_page("Animations"))
	_build_developer(_page("Developer"))
	_refresh_developer()
	for control: Control in _touch_only:
		control.visible = hud._touch_overlay_enabled
	panel.hide()
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.setup(hud, self)

## --dev always shows the tools; a debug build shows them once the setting is on.
func developer_visible() -> bool:
	return "--dev" in OS.get_cmdline_user_args() or (OS.is_debug_build() and _developer_enabled)

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_S)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_S)
	margin.add_child(column)
	return column

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	row.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = 0.7
	row.add_child(label)
	return row

func _options(parent: Node, title: String, choices: Array) -> OptionButton:
	var row := _row(parent, title)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(OPTION_WIDTH, UiTheme.TOUCH_TARGET)
	for choice: String in choices: option.add_item(choice)
	row.add_child(option)
	return option

## A titled slider. Returns [slider, value label].
func _range(parent: Node, title: String, lower: float, upper: float, step: float) -> Array:
	var row := _row(parent, title)
	var slider := HSlider.new()
	slider.min_value = lower
	slider.max_value = upper
	slider.step = step
	slider.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = VALUE_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	row.add_child(value)
	return [slider, value]

func _slider(parent: Node, title: String, key: String, lower: float, upper: float) -> Control:
	var parts := _range(parent, title, lower, upper, 0.05)
	var slider: HSlider = parts[0]
	var value: Label = parts[1]
	controls[key] = slider
	slider.value_changed.connect(func(amount: float) -> void:
		value.text = "%d%%" % roundi(amount * 100.0)
		if _syncing: return
		hud.touch_settings.set(key, amount)
		hud.touch_settings.sensitivity_preset = "Custom"
		preset.select(4)
		_apply())
	return slider.get_parent()

func _toggle(parent: Node, title: String, callback: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.custom_minimum_size.y = UiTheme.TOUCH_TARGET
	parent.add_child(check)
	check.toggled.connect(callback)
	return check

func _input(event: InputEvent) -> void:
	if panel and panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func set_driving(_driving: bool) -> void:
	pass

func _get_camera_pivot() -> Node:
	if hud and hud.player and "camera_pivot" in hud.player:
		return hud.player.camera_pivot
	elif hud and hud._game and hud._game.person and "camera_pivot" in hud._game.person:
		return hud._game.person.camera_pivot
	return null

func _build_camera(page: VBoxContainer) -> void:
	var desc := Label.new()
	desc.text = "Switch between TPP and FPP, scale view distances, adjust field of view (FOV), and tune shoulder offset."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	page.add_child(desc)

	var mode_opt := _options(page, "Perspective mode", ["Third Person (TPP)", "First Person (FPP)"])
	camera_controls["view_mode"] = mode_opt
	mode_opt.item_selected.connect(func(index: int) -> void:
		if _syncing: return
		var cam = _get_camera_pivot()
		if cam != null:
			cam.set_view_mode(index)
	)

	_add_camera_range(page, "TPP Camera Distance", "tpp_dist", 3.0, 9.0, 0.25, "m", func(val: float) -> void:
		var cam = _get_camera_pivot()
		if cam != null:
			cam.set_tpp_distance(val)
	)
	_add_camera_range(page, "TPP Field of View (FOV)", "tpp_fov", 55.0, 95.0, 1.0, "°", func(val: float) -> void:
		var cam = _get_camera_pivot()
		if cam != null:
			cam.set_tpp_fov(val)
	)
	_add_camera_range(page, "FPP Field of View (FOV)", "fpp_fov", 65.0, 110.0, 1.0, "°", func(val: float) -> void:
		var cam = _get_camera_pivot()
		if cam != null:
			cam.set_fpp_fov(val)
	)
	_add_camera_range(page, "Shoulder View Offset", "shoulder", 0.35, 0.95, 0.05, "m", func(val: float) -> void:
		var cam = _get_camera_pivot()
		if cam != null:
			cam.set_shoulder_offset(val)
	)
	_add_camera_range(page, "Camera Shake & Bobbing", "shake", 0.0, 2.0, 0.1, "x", func(val: float) -> void:
		var cam = _get_camera_pivot()
		if cam != null:
			cam.camera_shake_scale = val
	)

func _add_camera_range(parent: Node, title: String, key: String, min_val: float, max_val: float, step: float, unit: String, callback: Callable) -> void:
	var parts := _range(parent, title, min_val, max_val, step)
	var slider: HSlider = parts[0]
	var val_label: Label = parts[1]
	camera_controls[key] = slider
	slider.value_changed.connect(func(v: float) -> void:
		val_label.text = ("%.2f " if step < 1.0 else "%.0f ") % v + unit
		if not _syncing:
			callback.call(v)
	)

func _build_controls(page: VBoxContainer) -> void:
	preset = _options(page, "Sensitivity", PRESETS)
	preset.item_selected.connect(func(index: int) -> void:
		if _syncing: return
		hud.touch_settings.apply_preset(PRESETS[index])
		_refresh()
		_apply())
	_slider(page, "Look", "look_sensitivity", 0.3, 3.0)
	_slider(page, "Aim", "ads_sensitivity", 0.1, 4.0)
	var mode := _options(page, "Gyroscope", ["Off", "Scope Only", "Always On"])
	controls["gyro_mode"] = mode
	mode.item_selected.connect(func(index: int) -> void:
		if _syncing: return
		hud.touch_settings.gyro_mode = index
		_apply())
	_touch_only.append(mode.get_parent())
	_touch_only.append(_slider(page, "Gyro look", "gyro_sensitivity", 0.2, 4.0))
	_touch_only.append(_slider(page, "Gyro aim", "ads_gyro_sensitivity", 0.2, 4.0))
	for item: Array in [["Invert gyro horizontal", "gyro_invert_x"], ["Invert gyro vertical", "gyro_invert_y"], ["Swap left and right controls", "swap_vehicle_controls"]]:
		var key: String = item[1]
		var check := _toggle(page, item[0], func(value: bool) -> void:
			if _syncing: return
			hud.touch_settings.set(key, value)
			_apply()
			if key == "swap_vehicle_controls":
				hud._layout_for_viewport())
		controls[key] = check
		_touch_only.append(check)
	_button(page, "Reset sensitivity", func() -> void:
		hud.touch_settings.apply_preset("Medium")
		_refresh()
		_apply())
	# Touch players place their buttons here; keyboard players get the key list instead.
	_touch_only.append(_button(page, "Customize HUD", func() -> void:
		close_menu()
		if not panel.visible and hud.has_method("open_layout_editor"):
			hud.open_layout_editor()))
	if not hud._touch_overlay_enabled:
		_build_keys(page)

func _build_keys(page: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = KEY_COLUMNS * 2
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_M)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	page.add_child(grid)
	for item: Array in KEYS:
		var key := Label.new()
		key.text = item[0]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		var chip := UiTheme.box(UiTheme.SURFACE_RAISED)
		chip.set_content_margin(SIDE_TOP, UiTheme.SPACE_XS)
		chip.set_content_margin(SIDE_BOTTOM, UiTheme.SPACE_XS)
		key.add_theme_stylebox_override("normal", chip)
		grid.add_child(key)
		var action := Label.new()
		action.text = item[1]
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		action.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		grid.add_child(action)

func _build_time(page: VBoxContainer) -> void:
	var time := _options(page, "Time of day", TIME_MODES)
	controls["time"] = time
	time.item_selected.connect(func(index: int) -> void:
		if not _syncing: _environment().set_time_mode(TIME_MODES[index]))
	var sky := _options(page, "Weather", WEATHER_MODES)
	controls["weather"] = sky
	sky.item_selected.connect(func(index: int) -> void:
		if not _syncing: _environment().set_weather_mode(WEATHER_MODES[index]))
	var skip := _row(page, "Skip to")
	for value: int in SKIP_HOURS:
		var hour := value
		var button := _button(skip, "%02d:00" % hour, func() -> void: _environment().set_hour(hour))
		button.custom_minimum_size.x = (OPTION_WIDTH - UiTheme.SPACE_M * 2.0) / SKIP_HOURS.size()

func _build_audio(page: VBoxContainer) -> void:
	audio_controls["master"] = _audio_slider(page, "Master", func(value: float) -> void:
		_master_volume = value
		apply_audio())
	audio_controls["ambience"] = _audio_slider(page, "City ambience", func(value: float) -> void:
		_ambience_volume = value
		apply_audio())
	audio_controls["spoken"] = _toggle(page, "Spoken dialogue", func(value: bool) -> void:
		if not _syncing: hud._game.gameplay.spoken_dialogue = value)

func _audio_slider(page: VBoxContainer, title: String, callback: Callable) -> HSlider:
	var parts := _range(page, title, 0.0, 1.0, 0.05)
	var slider: HSlider = parts[0]
	var value: Label = parts[1]
	slider.value_changed.connect(func(amount: float) -> void:
		value.text = "%d%%" % roundi(amount * 100.0)
		if not _syncing: callback.call(amount))
	return slider

func _build_animations_guide(page: VBoxContainer) -> void:
	var desc := Label.new()
	desc.text = "Comprehensive reference for character animations and input combinations. Every action maps to authentic Mixamo cycles with procedural IK and foot-grounding."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	page.add_child(desc)

	var move_speed_opt := _options(page, "Movement mode (W)", ["Walk by Default (Shift to Run)", "Jog/Run by Default"])
	var current_player: Node = hud._game.get("person") if hud._game != null else null
	if current_player and current_player.get("walk_speed") != null:
		move_speed_opt.select(0 if float(current_player.get("walk_speed")) < 3.0 else 1)
	move_speed_opt.item_selected.connect(func(idx: int) -> void:
		if current_player:
			if idx == 0:
				current_player.set("walk_speed", 2.2)
			else:
				current_player.set("walk_speed", 4.2))

	var categories := [
		{
			"category": "LOCOMOTION & MOVEMENT",
			"items": [
				{"action": "Forward Walk", "keys": "W (Tap / Hold)", "clip": "Walk_Loop", "detail": "Human pace (~2.2 m/s). Feet planted to world speed."},
				{"action": "Jog / Sprint Forward", "keys": "Shift + W / Sprint", "clip": "Jogging / Sprint (4.2 - 6.8 m/s)", "detail": "Full speed running with athletic arm swing."},
				{"action": "Sprint Backward", "keys": "S (Hold)", "clip": "Sprint_Backward", "detail": "Tactical backward retreat while keeping eyes ahead."},
				{"action": "Lateral Strafe", "keys": "A (Left) / D (Right)", "clip": "Strafe / Walk_Left/Right_with_gun", "detail": "Sideways evasive stepping."},
				{"action": "Jump & Vault", "keys": "Spacebar", "clip": "Jump / Running_Jump", "detail": "Ballistic arc with knee compression landing."}
			]
		},
		{
			"category": "STANCES & TACTICAL COVER",
			"items": [
				{"action": "Crouch Stance", "keys": "C / Left Ctrl", "clip": "Crouch_Walking / Idle_Crouching", "detail": "Low profile stance with continuous seamless loop."},
				{"action": "Prone Stance", "keys": "Z Key", "clip": "Prone_Forward / Prone_Idle", "detail": "Drops body to 0.55m; military crawl."},
				{"action": "Tactical Lean / Peek", "keys": "Q (Left) / E (Right)", "clip": "Spine Roll", "detail": "Camera shifts around corners with wall clearance."}
			]
		},
		{
			"category": "COMBAT & WEAPON HANDLING",
			"items": [
				{"action": "Equip / Holster Rifle", "keys": "1 / P Key", "clip": "Low-Ready Stance", "detail": "Shoulders rifle; arms solve via two-bone IK."},
				{"action": "Aim Down Sights (ADS)", "keys": "Right Mouse (Hold)", "clip": "Rifle_Aiming_Idle", "detail": "Aligns sights to camera center with recoil recovery."},
				{"action": "Fire Weapon", "keys": "Left Mouse", "clip": "Firing_Rifle", "detail": "Simulates barrel kick and procedural muzzle impulse."},
				{"action": "Tactical Reload", "keys": "R Key", "clip": "Reload", "detail": "Magazine swap locked to reload duration."},
				{"action": "Throw Frag Grenade", "keys": "G Key", "clip": "Throw_Grenade", "detail": "Windup and throw trajectory."},
				{"action": "Melee Martial Combo", "keys": "Left Mouse (Unarmed)", "clip": "Boxing / Kick Chain", "detail": "Seamless unarmed fighting moves."}
			]
		},
		{
			"category": "VEHICLES & ENVIRONMENT",
			"items": [
				{"action": "Enter / Exit Vehicle", "keys": "F Key", "clip": "Door step-in & drive seated", "detail": "0.35s physical doorway step-in crossfade."},
				{"action": "First Person Cockpit", "keys": "V (While Driving)", "clip": "Driver Eye-Level View", "detail": "Road-aligned perspective with transparent windshield."},
				{"action": "Swimming & Floating", "keys": "Enter River (>0.85m)", "clip": "Swimming / Floating", "detail": "Buoyant surface swimming with head clearance."}
			]
		}
	]

	for cat in categories:
		var cat_title := Label.new()
		cat_title.text = cat.category
		cat_title.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
		cat_title.add_theme_color_override("font_color", UiTheme.ACCENT)
		page.add_child(cat_title)

		for item in cat.items:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, 4))
			var c_box := HBoxContainer.new()
			c_box.add_theme_constant_override("separation", UiTheme.SPACE_M)
			card.add_child(c_box)

			var left_box := VBoxContainer.new()
			left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var act_lbl := Label.new()
			act_lbl.text = item.action
			act_lbl.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
			left_box.add_child(act_lbl)

			var det_lbl := Label.new()
			det_lbl.text = "%s  •  %s" % [item.clip, item.detail]
			det_lbl.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
			det_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
			left_box.add_child(det_lbl)
			c_box.add_child(left_box)

			var key_lbl := Label.new()
			key_lbl.text = item.keys
			key_lbl.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
			key_lbl.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SURFACE_RAISED, 4))
			c_box.add_child(key_lbl)

			page.add_child(card)

func _build_developer(page: VBoxContainer) -> void:
	_button(page, "Bridge teleport", _leave_with.bind(func() -> void: hud._game._teleport_to_godavari_bridge()))
	_button(page, "Flyover teleport", _leave_with.bind(func() -> void: hud._game._teleport_to_ramagundam_flyover()))
	_button(page, "Sketch map", _leave_with.bind(func() -> void:
		get_tree().change_scene_to_file("res://scenes/world/chowrasta_city.tscn")))
	_button(page, "Full district", _leave_with.bind(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main.tscn")))

## Closes every menu, then acts on the running game.
func _leave_with(action: Callable) -> void:
	close_menu()
	pause_menu.close_menu()
	action.call()

func _refresh_developer() -> void:
	tabs.set_tab_hidden(tabs.get_tab_count() - 1, not developer_visible())

func _environment() -> Node:
	return hud._game.environment_controls.environment

## Sets the volumes from the saved values. Called once the city's ambience exists.
func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, _master_volume <= 0.0)
	_environment().ambience.volume = _ambience_volume

func _load_menu_settings() -> void:
	var file := ConfigFile.new()
	if file.load(MENU_SETTINGS_PATH) != OK:
		return
	_master_volume = clampf(float(file.get_value("audio", "master", 1.0)), 0.0, 1.0)
	_ambience_volume = clampf(float(file.get_value("audio", "ambience", 0.65)), 0.0, 1.0)
	_developer_enabled = file.get_value("developer", "tools", false) == true

func _save_menu_settings() -> Error:
	var file := ConfigFile.new()
	file.set_value("audio", "master", _master_volume)
	file.set_value("audio", "ambience", _ambience_volume)
	file.set_value("developer", "tools", _developer_enabled)
	return file.save(MENU_SETTINGS_PATH)

func _refresh() -> void:
	_syncing = true
	preset.select(maxi(0, PRESETS.find(hud.touch_settings.sensitivity_preset)))
	for key: String in controls:
		var control: Control = controls[key]
		if control is HSlider: control.value = hud.touch_settings.get(key)
		elif control is CheckButton: control.button_pressed = hud.touch_settings.get(key)
		elif key == "gyro_mode": control.select(hud.touch_settings.gyro_mode)
	var environment: Node = _environment()
	controls.time.select(maxi(0, TIME_MODES.find(environment.time_mode)))
	controls.weather.select(0 if environment.auto_weather else (3 if environment.storm else (2 if environment.rain_target > 0.5 else 1)))
	audio_controls.master.value = _master_volume
	audio_controls.master.value_changed.emit(_master_volume)
	audio_controls.ambience.value = _ambience_volume
	audio_controls.ambience.value_changed.emit(_ambience_volume)
	audio_controls.spoken.button_pressed = hud._game.gameplay.spoken_dialogue
	if is_instance_valid(_developer_toggle):
		_developer_toggle.button_pressed = _developer_enabled
	var cam = _get_camera_pivot()
	if cam != null:
		if camera_controls.has("view_mode"):
			camera_controls.view_mode.select(1 if cam.is_first_person() else 0)
		if camera_controls.has("tpp_dist"):
			camera_controls.tpp_dist.value = cam.camera_distance
			camera_controls.tpp_dist.value_changed.emit(cam.camera_distance)
		if camera_controls.has("tpp_fov"):
			camera_controls.tpp_fov.value = cam._base_fov
			camera_controls.tpp_fov.value_changed.emit(cam._base_fov)
		if camera_controls.has("fpp_fov"):
			camera_controls.fpp_fov.value = cam.first_person_fov
			camera_controls.fpp_fov.value_changed.emit(cam.first_person_fov)
		if camera_controls.has("shoulder"):
			camera_controls.shoulder.value = cam.shoulder_offset
			camera_controls.shoulder.value_changed.emit(cam.shoulder_offset)
		if camera_controls.has("shake"):
			camera_controls.shake.value = cam.camera_shake_scale
			camera_controls.shake.value_changed.emit(cam.camera_shake_scale)
	_syncing = false

func _apply() -> void:
	hud.touch_settings.sanitize()
	hud.touch_settings.apply_to_camera(hud.player.camera_pivot)

## Selects a tab by index (backwards compatibility).
func _select_page(index: int) -> void:
	if is_instance_valid(tabs) and index >= 0 and index < tabs.get_tab_count():
		tabs.current_tab = index

## Opens over whatever is on screen, including the paused pause menu. Only a shop-style
## pop-up or the map refuses it: those own the screen until they close.
func open_menu() -> void:
	if panel.visible or not hud._game or not hud._game.has_method("pause_tree"):
		return
	if hud._game.city_life.has_modal() or hud._game.is_map_open():
		return
	_was_paused = get_tree().paused
	_mouse_before = Input.mouse_mode
	hud._game._clear_control_inputs()
	hud._game.pause_tree(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_refresh_graphics()
	hint.text = ""
	panel.show()
	tabs.get_tab_bar().grab_focus()
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, UiTheme.MOTION_FAST).from(0.01)

func open_tab(title: String) -> void:
	for index: int in tabs.get_tab_count():
		if tabs.get_tab_title(index) == title:
			tabs.current_tab = index
	open_menu()

func close_menu() -> void:
	if not panel.visible: return
	_apply()
	if hud.touch_settings.save_to() != OK:
		hint.text = "Not saved"
		return
	if hud._game.performance_controller.settings.save_to() != OK or _save_menu_settings() != OK:
		hint.text = "Not saved"
		return
	var dpm_node: Variant = hud._game.get("device_performance_manager")
	if dpm_node != null:
		var pc_values: Dictionary = hud._game.performance_controller.settings.values
		var cascade_val: int = int(pc_values.get("shadow_cascade", 1))
		var shadow_mode_val: int = DirectionalLight3D.SHADOW_ORTHOGONAL if cascade_val == 1 else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if cascade_val == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
		var active_prof: Variant = dpm_node.get("active_profile")
		var tablet_inset: bool = active_prof.get("tablet_hud_inset", false) if active_prof is Dictionary else false
		dpm_node.call("save_settings", {
			"tier": dpm_node.get("active_tier"),
			"tier_name": "Custom Profile",
			"target_fps": pc_values.get("fps", 60),
			"scaling_3d_scale": pc_values.get("scale", 1.0),
			"shadow_enabled": pc_values.get("shadows", true),
			"directional_shadow_mode": shadow_mode_val,
			"directional_shadow_max_distance": pc_values.get("shadow_distance", 35.0),
			"view_distance": pc_values.get("distance", 550.0),
			"simulation_distance": pc_values.get("simulation", 220.0),
			"actors": pc_values.get("actors", 28),
			"effects": pc_values.get("effects", 0.6),
			"tablet_hud_inset": tablet_inset
		}, true)
	panel.hide()
	hud._game.pause_tree(_was_paused)
	hud._game._clear_control_inputs()
	Input.mouse_mode = _mouse_before
	hud._game._sync_input_context()
	closed.emit()

func _build_graphics(page: VBoxContainer) -> void:
	graphics_preset = _options(page, "Preset", GRAPHICS_PRESETS)
	graphics_preset.item_selected.connect(func(index: int) -> void:
		if _graphics_sync: return
		var controller = hud._game.performance_controller
		var dpm = hud._game.get("device_performance_manager")
		var selected_name: String = GRAPHICS_PRESETS[index]
		if selected_name == "Auto" and dpm != null:
			dpm.call("override_tier", dpm.get("detected_tier"), hud._game)
		else:
			controller.settings.select(selected_name)
			controller.apply_settings()
			if dpm != null and selected_name != "Custom":
				var tier_idx := 1 if selected_name == "Low" else (2 if selected_name == "Medium" else 3)
				dpm.set("active_tier", tier_idx)
		_refresh_graphics())
	for item: Array in [["Resolution", "scale", 0.5, 1.0, 0.05], ["Draw distance (m)", "distance", 250.0, 1000.0, 50.0], ["Residents and traffic", "actors", 6.0, 70.0, 1.0], ["Simulation distance (m)", "simulation", 80.0, 450.0, 10.0], ["Weather effects", "effects", 0.0, 1.0, 0.05]]:
		var parts := _range(page, item[0], item[2], item[3], item[4])
		var slider: HSlider = parts[0]
		var label: Label = parts[1]
		var key: String = item[1]
		graphics_controls[key] = slider
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%d%%" % roundi(value * 100) if key in ["scale", "effects"] else str(roundi(value))
			if not _graphics_sync: _graphics_change(key, value))
	var shadows := _toggle(page, "Shadows", func(value: bool) -> void:
		if not _graphics_sync: _graphics_change("shadows", value))
	graphics_controls.shadows = shadows
	var fps := _options(page, "Frame rate", ["30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "Max / V-Sync"])
	graphics_controls.fps = fps
	fps.item_selected.connect(func(index: int) -> void:
		var target := 60
		match index:
			0: target = 30
			1: target = 60
			2: target = 90
			3: target = 120
			4: target = 144
			5: target = 0
		if not _graphics_sync: _graphics_change("fps", target))
	_developer_toggle = _toggle(page, "Developer tools", func(value: bool) -> void:
		if _syncing: return
		_developer_enabled = value
		_refresh_developer())
	_developer_toggle.visible = OS.is_debug_build() and "--dev" not in OS.get_cmdline_user_args()

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
	graphics_preset.select(maxi(0, GRAPHICS_PRESETS.find(settings.preset)))
	for key: String in graphics_controls:
		var control: Control = graphics_controls[key]
		if control is HSlider:
			control.value = settings.values[key]
			control.value_changed.emit(control.value)
		elif control is CheckButton: control.button_pressed = settings.values[key]
		elif control is OptionButton:
			var target_index := 1
			match int(settings.values.fps):
				30: target_index = 0
				60: target_index = 1
				90: target_index = 2
				120: target_index = 3
				144: target_index = 4
				0: target_index = 5
			control.select(target_index)
	_graphics_sync = false
