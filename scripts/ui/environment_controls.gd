extends CanvasLayer

var environment: CityEnvironment
var _game: Node
var _panel: PanelContainer
var _status: Label
var _time_options: OptionButton
var _weather_options: OptionButton
var _mouse_before := Input.MOUSE_MODE_VISIBLE

func setup(game: Node) -> void:
	_game = game
	layer = 14
	process_mode = Node.PROCESS_MODE_ALWAYS
	environment = game.city_life.environment
	var open_button := Button.new()
	open_button.text = "Time & weather [F6]"
	open_button.position = Vector2(570, 16)
	open_button.custom_minimum_size = Vector2(200, 44)
	open_button.queue_free()
	open_button.pressed.connect(open_menu)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -210
	_panel.offset_right = 210
	_panel.offset_top = -180
	_panel.offset_bottom = 180
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.06, 0.09, 0.96)
	background.set_corner_radius_all(12)
	_panel.add_theme_stylebox_override("panel", background)
	_panel.visible = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_status = Label.new()
	column.add_child(_status)
	_add_options(column, "Time of day", ["Automatic", "Morning", "Afternoon", "Night"], environment.set_time_mode)
	_add_options(column, "Weather", ["Automatic", "Clear", "Rain", "Storm"], environment.set_weather_mode)
	var hint := Label.new()
	hint.text = "Selected times stay fixed. Automatic resumes the cycle.\nRain changes gradually after returning to the game."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var close := Button.new()
	close.text = "Return to game"
	close.custom_minimum_size.y = 44
	column.add_child(close)
	close.pressed.connect(close_menu)

func _add_options(column: VBoxContainer, title: String, choices: Array, callback: Callable) -> void:
	var label := Label.new()
	label.text = title
	column.add_child(label)
	var options := OptionButton.new()
	options.custom_minimum_size.y = 44
	for choice: String in choices:
		options.add_item(choice)
	column.add_child(options)
	if title == "Time of day":
		_time_options = options
	else:
		_weather_options = options
	options.item_selected.connect(func(index: int) -> void:
		callback.call(choices[index])
		_refresh_status())

func _refresh_status() -> void:
	_status.text = "Time & weather • " + environment.clock_text()

func open_menu() -> void:
	if _panel.visible or get_tree().paused:
		return
	_mouse_before = Input.mouse_mode
	_game._clear_control_inputs()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_time_options.select(["Automatic", "Morning", "Afternoon", "Night"].find(environment.time_mode))
	_weather_options.select(0 if environment.auto_weather else (3 if environment.storm else (2 if environment.rain_target > 0.5 else 1)))
	_panel.show()
	_refresh_status()

func close_menu() -> void:
	if not _panel.visible:
		return
	_panel.hide()
	get_tree().paused = false
	_game._clear_control_inputs()
	Input.mouse_mode = _mouse_before
	_game._sync_input_context()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F6]:
		close_menu()
		get_viewport().set_input_as_handled()
