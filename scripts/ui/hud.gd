extends CanvasLayer

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
const FloatingJoystick := preload("res://scripts/mobile/floating_joystick.gd")
const MobileControlsSettings := preload("res://scripts/mobile/mobile_controls_settings.gd")
const MenuTouchBridge := preload("res://scripts/mobile/menu_touch_bridge.gd")
const HudLayoutProfiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const HudLayoutEditor := preload("res://scripts/mobile/hud_layout_editor.gd")
const LanDiscovery := preload("res://scripts/network/lan_discovery.gd")
const SquadLobby := preload("res://scripts/network/squad_lobby.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var status_label: Label = $Panel/Margin/VBox/Status
@onready var position_label: Label = $Panel/Margin/VBox/Position
var _touch_actions: Dictionary = {
	"Up": "forward",
	"Down": "backward",
	"Left": "left",
	"Right": "right",
	"Run": "run",
}
var _active_touch_actions: Dictionary = {}
var _collected_coins := 0
var touch_settings := MobileControlsSettings.new()
var settings_menu: CanvasLayer
var _stick := FloatingJoystick.new()
var _stick_rest := Vector2.ZERO
var _vehicle: PhysicsBody3D
var _game: Node
var minimap: Minimap
var full_map: FullMap

var compass_bar: PanelContainer
var compass_label: Label
var btn_fire_right: Button
var btn_fire_left: Button
var btn_scope: Button
var btn_peek_left: Button
var btn_peek_right: Button
var btn_prone: Button
var btn_crouch: Button
var btn_fire_mode: Button
var btn_gyro_mode: Button
var btn_reload: Button
## Touch buttons for actions that otherwise need a keyboard.
var btn_equip: Button
## Next to the weapon slot, shown once two rifles are owned: brings out the other one.
var btn_swap: Button
var btn_medkit: Button
var btn_grenade: Button
var btn_talk: Button
var btn_surrender: Button
var btn_help: Button
var btn_free_look: Button
var btn_mode: Button
var btn_character: Button
var btn_view: Button
var _scope_overlay: Control
## Player-arranged NORMAL / FIRING / VEHICLE layouts and the editor that arranges them.
var layout_profiles := HudLayoutProfiles.new()
var _layout_editor: HudLayoutEditor
var _applied_profile := &""
var _touch_overlay_enabled: bool = OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

var network_manager: Node
var btn_multiplayer_toggle: Button
var btn_bridge_travel: Button
var btn_revive: Button
var btn_loot: Button
var touch_revive_pressed: bool = false
var touch_loot_pressed: bool = false
var multiplayer_panel: PanelContainer
var squad_discovery: LanDiscovery
var net_room_banner: Label
var lbl_net_status: Label
var lbl_player_list: Label

func configure_network(net_mgr: Node) -> void:
	network_manager = net_mgr
	if is_instance_valid(multiplayer_panel) and multiplayer_panel.has_method("setup"):
		multiplayer_panel.setup(network_manager, squad_discovery)
	if network_manager:
		network_manager.connection_state_changed.connect(_on_net_connection_changed)
		network_manager.peer_list_updated.connect(_on_net_peer_list_updated)
		network_manager.notification_posted.connect(_on_net_notification)

func configure_player(person: CharacterBody3D, vehicle: PhysicsBody3D, game: Node) -> void:
	player = person
	_vehicle = vehicle
	_game = game
	touch_settings.apply_to_camera(player.camera_pivot)

func configure_map(data: MapData, building_footprints: Array[PackedVector2Array],
		landmarks: Array[Dictionary], navigator: GpsNavigator) -> void:
	minimap = Minimap.new()
	add_child(minimap)
	minimap.setup(_game, data, building_footprints, landmarks, navigator)
	minimap.open_full_map_requested.connect(_game.set_map_open.bind(true))
	full_map = FullMap.new()
	add_child(full_map)
	full_map.setup(_game, data, building_footprints, landmarks, navigator)
	full_map.close_requested.connect(_game.set_map_open.bind(false))
	_layout_for_viewport()

func set_full_map_open(value: bool) -> void:
	if value:
		full_map.open()
	else:
		full_map.close()
	minimap.visible = not value
	if is_instance_valid(btn_bridge_travel): btn_bridge_travel.visible = not value
	$TouchControls.visible = _touch_overlay_enabled and not value
	if compass_bar: compass_bar.visible = not value
	$Panel.visible = not value

func set_active_vehicle(vehicle: PhysicsBody3D) -> void:
	_vehicle = vehicle

func _controlled_body() -> PhysicsBody3D:
	if _game and _game.control_state == _game.ControlState.DRIVING:
		return _vehicle
	return player

func set_enter_available(value: bool) -> void:
	$TouchControls/Enter.visible = value and _game.control_state == _game.ControlState.ON_FOOT

func set_interaction_prompt(value: String) -> void:
	$InteractionPrompt.text = value
	$InteractionPrompt.visible = not value.is_empty()

func set_speed(value: float) -> void:
	$Panel/Margin/VBox/Speed.text = "Speed: %03d km/h" % roundi(value)

func set_gear(gear_label: String, engine_rpm: float, automatic: bool) -> void:
	$Panel/Margin/VBox/Gear.text = "Gear: %s  ·  %d rpm" % [gear_label, roundi(engine_rpm / 50.0) * 50]
	$TouchControls/GearMode.text = "AUTO" if automatic else "MANUAL"

func set_flight_altitude(value: float) -> void:
	$Panel/Margin/VBox/Gear.text += "  ·  Δ ALT %.0f m" % value

func set_vehicle_mode(value: bool) -> void:
	var flight := value and _vehicle is GdkHelicopter
	$TouchControls/Enter.visible = false
	$TouchControls/Exit.visible = value
	$TouchControls/JoystickBase.visible = value or not player.movement_enabled
	$TouchControls/Run.visible = not value or flight
	$TouchControls/Run.text = "ASCEND" if flight else "RUN"
	$TouchControls/Jump.visible = not value
	$TouchControls/Handbrake.visible = value
	$TouchControls/Handbrake.text = "DESCEND" if flight else "BRAKE"
	$TouchControls/Camera.visible = value
	$TouchControls/GearMode.visible = value and not flight
	$TouchControls/GearUp.visible = value and not flight
	$TouchControls/GearDown.visible = value and not flight
	$Panel/Margin/VBox/Gear.visible = value
	$TouchControls/LookHint.text = "Swipe right side to look"
	var combat_controls: Array[Button] = [btn_fire_right, btn_fire_left, btn_scope, btn_peek_left, btn_peek_right, btn_crouch, btn_prone, btn_reload,
		btn_equip, btn_medkit, btn_grenade, btn_talk, btn_surrender, btn_help, btn_character]
	for ctrl in combat_controls:
		if is_instance_valid(ctrl): ctrl.visible = not value
	if value:
		set_interaction_prompt("[F]  EXIT VEHICLE")

func show_vehicle_controls_hint() -> void:
	$VehicleControlsHint.text = "VEHICLE CONTROLS\nW Accelerate   S Brake/Reverse   A/D Steer\nT Auto/Manual   X/Z Gear up/down\nSpace Handbrake   F Exit"
	$VehicleControlsHint.visible = true
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property($VehicleControlsHint, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void:
		$VehicleControlsHint.visible = false
		$VehicleControlsHint.modulate.a = 1.0
	)

func show_helicopter_controls_hint() -> void:
	$VehicleControlsHint.text = "HELICOPTER CONTROLS\nW/S Forward/Backward   A/D Strafe + Bank\nSpace Ascend   Shift Descend   Q/E Yaw\nCtrl Fast flight   V Camera   R Recover   F Exit after landing"
	$VehicleControlsHint.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property($VehicleControlsHint, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void:
		$VehicleControlsHint.visible = false
		$VehicleControlsHint.modulate.a = 1.0
	)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var driving: bool = _game != null and _game.control_state == _game.ControlState.DRIVING
	var movement := "Driving" if driving else ("Running" if player.is_running else "Walking")
	status_label.text = "Status: %s" % movement
	# Touch layout and labels follow the control state even while a vehicle is swapping.
	_update_touch_labels()
	var tracked_node: Node3D = _vehicle if driving else player
	if not is_instance_valid(tracked_node):
		return
	position_label.text = "Position: %s" % _format_position(tracked_node.global_position)
	$Panel/Margin/VBox/Coins.text = "Coins: %d" % _collected_coins
	_update_compass()
	_update_multiplayer_hud()

func register_coin_collected() -> void:
	_collected_coins += 1

func coins_available() -> int:
	return _collected_coins

func spend_coins(amount: int) -> bool:
	if amount < 0 or _collected_coins < amount:
		return false
	_collected_coins -= amount
	return true

func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.08, 0.9)
	background.set_corner_radius_all(10)
	$Panel.add_theme_stylebox_override("panel", background)
	for label in $Panel/Margin/VBox.get_children():
		if label is Label:
			label.add_theme_color_override("font_color", Color("edf4f7"))
	$Panel/Margin/VBox/Title.add_theme_color_override("font_color", Color("82d4cc"))
	touch_settings.load_from()
	layout_profiles.load_from()
	_build_compass()
	_setup_bgmi_controls()
	_setup_touch_actions()
	_build_scope_overlay()
	_build_multiplayer_ui()
	settings_menu = preload("res://scripts/ui/settings_menu.gd").new()
	add_child(settings_menu)
	settings_menu.setup(self)
	# Tabs, dropdowns, sliders and scroll lists in paused menus answer to the mouse only.
	var bridge := MenuTouchBridge.new()
	bridge.name = "MenuTouchBridge"
	bridge.is_menu_open = _menu_open
	add_child(bridge)
	$TouchControls.visible = _touch_overlay_enabled
	$TouchControls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for direction_button in [$TouchControls/Up, $TouchControls/Down, $TouchControls/Left, $TouchControls/Right]:
		direction_button.visible = false
	# Buttons take screen touches per finger, so each control owns its own taps;
	# no screen-region shortcuts that could fire under a neighbouring button.
	for button_name in _touch_actions:
		var button: Button = get_node("TouchControls/%s" % button_name)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(_toggle_action.bind(_touch_actions[button_name]))
	$TouchControls/Jump.mouse_filter = Control.MOUSE_FILTER_STOP
	$TouchControls/Jump.button_down.connect(_touch_jump)
	$TouchControls/Reset.mouse_filter = Control.MOUSE_FILTER_STOP
	$TouchControls/Reset.pressed.connect(_reset_player)
	$TouchControls/Enter.pressed.connect(_enter_vehicle)
	$TouchControls/Exit.pressed.connect(_exit_vehicle)
	$TouchControls/Handbrake.button_down.connect(func() -> void:
		if _vehicle is GdkHelicopter:
			_vehicle.set_touch_descend_pressed(true)
		else:
			Input.action_press("vehicle_handbrake"))
	$TouchControls/Handbrake.button_up.connect(func() -> void:
		if _vehicle is GdkHelicopter:
			_vehicle.set_touch_descend_pressed(false)
		else:
			Input.action_release("vehicle_handbrake"))
	$TouchControls/Camera.pressed.connect(_change_vehicle_camera)
	$TouchControls/GearMode.pressed.connect(func() -> void: _vehicle.toggle_transmission_mode())
	$TouchControls/GearUp.pressed.connect(func() -> void: _vehicle.shift_up())
	$TouchControls/GearDown.pressed.connect(func() -> void: _vehicle.shift_down())
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()

## Only the floating stick is handled here; it claims one finger inside its zone,
## which the claw layout keeps clear of every button, and ignores all others.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag and _stick.drag(event.index, event.position):
		_apply_stick()
		get_viewport().set_input_as_handled()

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var modal_open := (is_instance_valid(multiplayer_panel) and multiplayer_panel.visible) or _menu_open()
		if $TouchControls.visible and not modal_open and not _touch_button_at(event.position) and _stick.press(event.index, event.position):
			_apply_stick()
			get_viewport().set_input_as_handled()
	elif event.canceled and event.index == _stick.finger:
		_stick.cancel()
		_apply_stick()
		get_viewport().set_input_as_handled()
	elif _stick.release(event.index):
		_apply_stick()
		get_viewport().set_input_as_handled()

func _apply_stick() -> void:
	var on_foot: bool = _game == null or _game.control_state == _game.ControlState.ON_FOOT
	# Sprint lock only makes sense on foot; in a vehicle it would be cruise control.
	_stick.sprint_lock_enabled = touch_settings.sprint_lock and on_foot
	_stick.deadzone = touch_settings.joystick_deadzone
	var body := _controlled_body()
	if is_instance_valid(body):
		body.set_touch_move_input(_stick.value)
		if on_foot and not _active_touch_actions.has("run"):
			body.set_touch_run_pressed(_stick.wants_sprint())
	_draw_stick()

## The base follows the finger while held and returns to its resting slot after.
func _draw_stick() -> void:
	var base: ColorRect = $TouchControls/JoystickBase
	var knob: ColorRect = $TouchControls/JoystickBase/JoystickKnob
	base.position = _stick.origin - base.size * 0.5 if _stick.is_active() else _stick_rest
	var travel := base.size.x * 0.5 - knob.size.x * 0.5
	knob.position = base.size * 0.5 - knob.size * 0.5 + _stick.knob_offset() / maxf(_stick.radius, 1.0) * travel

func _toggle_action(action: String) -> void:
	var pressed := not _active_touch_actions.has(action)
	if pressed:
		_active_touch_actions[action] = true
	else:
		_active_touch_actions.erase(action)
	if action == "run":
		_controlled_body().set_touch_run_pressed(pressed)
	else:
		_update_touch_move_input()

func _update_touch_move_input() -> void:
	var input_vector := Vector2.ZERO
	for action in _active_touch_actions:
		match action:
			"forward":
				input_vector.y -= 1.0
			"backward":
				input_vector.y += 1.0
			"left":
				input_vector.x -= 1.0
			"right":
				input_vector.x += 1.0
	_controlled_body().set_touch_move_input(input_vector)

func _reset_player() -> void:
	_active_touch_actions.clear()
	_controlled_body().set_touch_move_input(Vector2.ZERO)
	_controlled_body().set_touch_run_pressed(false)
	player.velocity = Vector3.ZERO
	player.global_position = player.respawn_position
	player.rotation = Vector3.ZERO
	var camera := player.get_node_or_null("CameraPivot")
	if camera and camera.has_method("reset_view"):
		camera.reset_view()
	$TouchControls/Up.button_pressed = false
	$TouchControls/Down.button_pressed = false
	$TouchControls/Left.button_pressed = false
	$TouchControls/Right.button_pressed = false
	$TouchControls/Run.button_pressed = false

func clear_touch_inputs() -> void:
	if is_instance_valid(player):
		player.touch_peek_input = 0.0
		player.camera_pivot.clear_touch_look()
	if _game and _game.gameplay: _game.gameplay.touch_fire_pressed = false
	touch_revive_pressed = false
	touch_loot_pressed = false
	_active_touch_actions.clear()
	_stick.cancel()
	_apply_stick()
	if is_instance_valid(btn_scope):
		btn_scope.text = "⌖ SCOPE"
	for button_name in _touch_actions:
		get_node("TouchControls/" + button_name).button_pressed = false

func _enter_vehicle() -> void:
	if _game:
		_game.enter_vehicle()

func _exit_vehicle() -> void:
	if _game:
		_game.exit_vehicle()

func _change_vehicle_camera() -> void:
	if _game and _game.has_method("toggle_camera_view"):
		_game.toggle_camera_view()

func _layout_for_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var short_side: float = minf(viewport_size.x, viewport_size.y)
	var button_size := clampf(short_side * 0.105, 56.0, 88.0)
	var gap := button_size * 0.12
	var margin := clampf(short_side * 0.045, 18.0, 48.0)
	var controls: Control = $TouchControls
	var center := Vector2(margin + button_size * 1.5 + gap, viewport_size.y - margin - button_size * 1.5 - gap)
	var joystick_size := clampf(short_side * 0.22, 128.0, 190.0)
	var joystick_position := Vector2(margin, viewport_size.y - margin - joystick_size)
	$TouchControls/JoystickBase.position = joystick_position
	$TouchControls/JoystickBase.size = Vector2(joystick_size, joystick_size)
	$TouchControls/JoystickBase.color = Color(0.08, 0.14, 0.18, 0.42)
	$TouchControls/JoystickBase/JoystickKnob.position = Vector2(joystick_size * 0.31, joystick_size * 0.31)
	$TouchControls/JoystickBase/JoystickKnob.size = Vector2(joystick_size * 0.38, joystick_size * 0.38)
	_set_button_rect($TouchControls/Up, center + Vector2(-button_size * 0.5, -button_size - gap), button_size * 0.78)
	_set_button_rect($TouchControls/Down, center + Vector2(-button_size * 0.5, gap), button_size * 0.78)
	_set_button_rect($TouchControls/Left, center + Vector2(-button_size * 1.5 - gap, -button_size * 0.5), button_size * 0.78)
	_set_button_rect($TouchControls/Right, center + Vector2(button_size * 0.5 + gap, -button_size * 0.5), button_size * 0.78)
	_set_button_rect($TouchControls/Run, Vector2(center.x + button_size * 1.7, center.y - button_size * 0.5), button_size)
	_set_button_rect($TouchControls/Jump, Vector2(viewport_size.x - margin - button_size * 1.25, viewport_size.y - margin - button_size), button_size * 1.25)
	_set_button_rect($TouchControls/Reset, Vector2(viewport_size.x - margin - button_size * 1.25, viewport_size.y - margin - button_size * 2.25), button_size * 0.95)
	$TouchControls/LookHint.position = Vector2(viewport_size.x - margin - button_size * 3.2, viewport_size.y - margin - 34.0)
	$TouchControls/LookHint.size = Vector2(button_size * 3.2, 28.0)
	$Offline.position = Vector2(margin, viewport_size.y - margin - 28.0)
	$Offline.size = Vector2(240.0, 28.0)

	if compass_bar:
		var compass_width := clampf(viewport_size.x * 0.28, 200.0, 320.0)
		compass_bar.position = Vector2((viewport_size.x - compass_width) * 0.5, 12.0)
		compass_bar.size = Vector2(compass_width, 34.0)

	if is_instance_valid(btn_fire_right):
		var fire_sz := button_size * 1.3
		_set_button_rect(btn_fire_right, Vector2(viewport_size.x - margin - fire_sz * 2.1, viewport_size.y - margin - fire_sz * 1.4), fire_sz)
	if is_instance_valid(btn_fire_left):
		_set_button_rect(btn_fire_left, Vector2(margin, 115.0), button_size * 1.05)
	if is_instance_valid(btn_scope):
		_set_button_rect(btn_scope, Vector2(viewport_size.x - margin - button_size * 1.25, viewport_size.y - margin - button_size * 2.3), button_size * 1.1)
	if is_instance_valid(btn_peek_left):
		_set_button_rect(btn_peek_left, Vector2(viewport_size.x - margin - button_size * 3.3, viewport_size.y - margin - button_size * 2.1), button_size * 0.95)
	if is_instance_valid(btn_peek_right):
		_set_button_rect(btn_peek_right, Vector2(viewport_size.x - margin - button_size * 2.3, viewport_size.y - margin - button_size * 2.5), button_size * 0.95)
	if is_instance_valid(btn_crouch):
		_set_button_rect(btn_crouch, Vector2(viewport_size.x - margin - button_size * 2.3, viewport_size.y - margin - button_size), button_size)
	if is_instance_valid(btn_prone):
		_set_button_rect(btn_prone, Vector2(viewport_size.x - margin - button_size * 3.35, viewport_size.y - margin - button_size), button_size)
	if is_instance_valid(btn_fire_mode):
		_set_button_rect(btn_fire_mode, Vector2(viewport_size.x * 0.5 + 16.0, viewport_size.y - margin - 36.0), button_size * 0.85)
	if is_instance_valid(btn_gyro_mode):
		btn_gyro_mode.position = Vector2(viewport_size.x * 0.5 - button_size * 1.7 - 16.0, viewport_size.y - margin - 36.0)
		btn_gyro_mode.size = Vector2(button_size * 1.7, button_size * 0.52)
	if is_instance_valid(btn_reload):
		_set_button_rect(btn_reload, Vector2(viewport_size.x - margin - button_size * 1.25, viewport_size.y - margin - button_size * 3.45), button_size * 0.95)

	if is_instance_valid(btn_multiplayer_toggle):
		btn_multiplayer_toggle.position = Vector2(viewport_size.x - margin - 120.0, 12.0)
		btn_multiplayer_toggle.size = Vector2(110.0, 32.0)
	if is_instance_valid(btn_bridge_travel):
		btn_bridge_travel.position = Vector2(viewport_size.x - margin - 250.0, 12.0)
		btn_bridge_travel.size = Vector2(120.0, 32.0)
	if is_instance_valid(net_room_banner):
		net_room_banner.position = Vector2(viewport_size.x - margin - 260.0, 48.0)
		net_room_banner.size = Vector2(250.0, 24.0)
	if is_instance_valid(btn_revive):
		btn_revive.position = Vector2(viewport_size.x * 0.5 - 75.0, viewport_size.y - margin - 120.0)
		btn_revive.size = Vector2(150.0, 44.0)
	if is_instance_valid(btn_loot):
		btn_loot.position = Vector2(viewport_size.x * 0.5 - 75.0, viewport_size.y - margin - 170.0)
		btn_loot.size = Vector2(150.0, 44.0)
	if is_instance_valid(multiplayer_panel):
		var panel_w := minf(viewport_size.x - 40.0, 760.0)
		var panel_h := minf(viewport_size.y - 40.0, 660.0)
		multiplayer_panel.position = Vector2((viewport_size.x - panel_w) * 0.5, (viewport_size.y - panel_h) * 0.5)
		multiplayer_panel.size = Vector2(panel_w, panel_h)

	if minimap:
		var minimap_size := clampf(short_side * 0.3, 150.0, 230.0)
		var minimap_bottom := viewport_size.y - margin - 36.0
		if OS.has_feature("android") or _touch_overlay_enabled:
			minimap_bottom = joystick_position.y - 12.0
		minimap.position = Vector2(margin, minimap_bottom - minimap_size)
		minimap.size = Vector2(minimap_size, minimap_size)
	if _touch_overlay_enabled:
		_layout_touch(viewport_size)
	controls.queue_redraw()

## Phones and tablets: a claw layout sized in millimetres inside the display safe
## area (notch, rounded corners, gesture bar). See scripts/mobile/claw_layout.gd.
func _layout_touch(_viewport_size: Vector2) -> void:
	# The player's layout for what they are doing now: walking, fighting or driving.
	var profile := _current_profile()
	var context := _layout_context(profile)
	var slots: Dictionary = layout_profiles.apply(profile, context.rects, context.safe, context.min_target)
	_applied_profile = profile
	$TouchControls.modulate.a = layout_profiles.opacity_for(profile, touch_settings.opacity)
	var stick: Rect2 = slots[&"Joystick"]
	_stick_rest = stick.position
	_stick.zone = slots[&"JoystickZone"]
	_stick.radius = stick.size.x * 0.5
	$TouchControls/JoystickBase.size = stick.size
	$TouchControls/JoystickBase/JoystickKnob.size = stick.size * 0.38
	_make_round($TouchControls/JoystickBase, Color(0.08, 0.14, 0.18, 0.3), 3)
	_make_round($TouchControls/JoystickBase/JoystickKnob, Color(0.85, 0.92, 0.95, 0.55), 0)
	_draw_stick()
	for button_name in ClawLayout.SCENE_BUTTON_SLOTS:
		_set_slot_rect($TouchControls.get_node(String(button_name)), slots[ClawLayout.SCENE_BUTTON_SLOTS[button_name]])
	var tactical := {
		&"Fire": btn_fire_right, &"FireLeft": btn_fire_left, &"Scope": btn_scope, &"Reload": btn_reload,
		&"Crouch": btn_crouch, &"Prone": btn_prone, &"PeekLeft": btn_peek_left, &"PeekRight": btn_peek_right,
		&"FireMode": btn_fire_mode, &"Gyro": btn_gyro_mode, &"Squad": btn_multiplayer_toggle,
		&"Context": btn_revive, &"ContextAlt": btn_loot, &"Equip": btn_equip, &"Medkit": btn_medkit,
		&"Grenade": btn_grenade, &"Talk": btn_talk, &"Surrender": btn_surrender, &"Help": btn_help,
		&"Swap": btn_swap, &"FreeLook": btn_free_look, &"Mode": btn_mode, &"Character": btn_character, &"View": btn_view,
	}
	for slot in tactical:
		if is_instance_valid(tactical[slot]):
			_set_slot_rect(tactical[slot], slots[slot])
	# Compact status: the debug rows would cover the minimap and the left fire button.
	for row in [$Panel/Margin/VBox/Title, $Panel/Margin/VBox/Subtitle, $Panel/Margin/VBox/Position, $Panel/Margin/VBox/Help]:
		row.visible = false
	$Panel.position = slots[&"StatusPanel"].position
	$Panel.size = slots[&"StatusPanel"].size
	var compass: Rect2 = slots[&"Compass"]
	if compass_bar:
		compass_bar.position = compass.position
		compass_bar.size = compass.size
	if is_instance_valid(net_room_banner):
		net_room_banner.position = Vector2(compass.position.x, compass.end.y + 4.0)
		net_room_banner.size = Vector2(compass.size.x, 24.0)
	$TouchControls/LookHint.position = Vector2(compass.position.x, compass.end.y + 30.0)
	$TouchControls/LookHint.size = Vector2(compass.size.x, 28.0)
	$TouchControls/LookHint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if minimap:
		minimap.position = slots[&"Minimap"].position
		minimap.size = slots[&"Minimap"].size
	# Prompts sit above the item bar instead of across it; the offline tag is redundant on touch.
	$InteractionPrompt.position = Vector2(slots[&"ContextAlt"].get_center().x - $InteractionPrompt.size.x * 0.5,
		slots[&"ContextAlt"].position.y - $InteractionPrompt.size.y - 8.0)
	$Offline.visible = false

## Labels whose text changes at runtime are sized for their longest form.
const _LONGEST_LABELS := {&"BtnEquip": "AR 24/120", &"BtnMode": "ACTION", &"BtnFireMode": "SINGLE",
	&"BtnGyroMode": "GYRO: ALWAYS", &"BtnScope": "⌖ SCOPE"}

func _set_slot_rect(button: Button, rect: Rect2) -> void:
	# The slot is authoritative: long labels clip instead of growing into neighbours.
	button.clip_text = true
	button.position = rect.position
	button.size = rect.size
	var label: String = _LONGEST_LABELS.get(button.name, button.text)
	var font_size := rect.size.y * 0.26
	var width := button.get_theme_font("font").get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_size)).x
	var room := rect.size.x * 0.8
	if width > room:
		font_size *= room / width
	button.add_theme_font_size_override("font_size", clampi(floori(font_size), 11, 26))
	_round_style(button, rect)

## Swaps a square ColorRect for a circle drawn by a child panel (BGMI's round stick).
func _make_round(rect: ColorRect, fill: Color, border: int) -> void:
	rect.color = Color(0, 0, 0, 0)
	var disc := rect.get_node_or_null("Disc") as Panel
	if disc == null:
		disc = Panel.new()
		disc.name = "Disc"
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(disc)
		rect.move_child(disc, 0)
	disc.position = Vector2.ZERO
	disc.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(roundi(rect.size.x * 0.5))
	style.set_border_width_all(border)
	style.border_color = Color(1, 1, 1, 0.55)
	disc.add_theme_stylebox_override("panel", style)

## Translucent round buttons with a light rim, as in BGMI; each keeps its own tint.
func _round_style(button: Button, rect: Rect2) -> void:
	var current := button.get_theme_stylebox("normal")
	var tint: Color = (current as StyleBoxFlat).bg_color if current is StyleBoxFlat else Color(0.05, 0.07, 0.09)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(tint, 0.55)
	normal.set_corner_radius_all(roundi(minf(rect.size.x, rect.size.y) * 0.5))
	normal.set_border_width_all(2)
	normal.border_color = Color(1, 1, 1, 0.6)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(tint.lightened(0.35), 0.85)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _build_compass() -> void:
	compass_bar = PanelContainer.new()
	compass_bar.name = "CompassBar"
	add_child(compass_bar)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.8)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	compass_bar.add_theme_stylebox_override("panel", style)
	compass_label = Label.new()
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compass_label.add_theme_font_size_override("font_size", 16)
	compass_label.add_theme_color_override("font_color", Color("ffd45a"))
	compass_bar.add_child(compass_label)

func _update_compass() -> void:
	if not compass_bar or not compass_bar.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var forward := -camera.global_basis.z
	var deg := roundi(fposmod(rad_to_deg(atan2(forward.x, forward.z)) + 180.0, 360.0))
	var cardinal := "N"
	if deg >= 338 or deg < 23: cardinal = "N"
	elif deg >= 23 and deg < 68: cardinal = "NE"
	elif deg >= 68 and deg < 113: cardinal = "E"
	elif deg >= 113 and deg < 158: cardinal = "SE"
	elif deg >= 158 and deg < 203: cardinal = "S"
	elif deg >= 203 and deg < 248: cardinal = "SW"
	elif deg >= 248 and deg < 293: cardinal = "W"
	elif deg >= 293 and deg < 338: cardinal = "NW"
	compass_label.text = "▼  %s  %03d°  ▼" % [cardinal, deg]

func _setup_bgmi_controls() -> void:
	btn_fire_right = _create_tactical_button("BtnFireRight", "🔥 FIRE", Color(0.72, 0.22, 0.18, 0.85))
	btn_fire_right.button_down.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = true
			_game.gameplay.attack())
	btn_fire_right.button_up.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = false)

	btn_fire_left = _create_tactical_button("BtnFireLeft", "🔥", Color(0.72, 0.22, 0.18, 0.75))
	btn_fire_left.button_down.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = true
			_game.gameplay.attack())
	btn_fire_left.button_up.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = false)

	btn_scope = _create_tactical_button("BtnScope", "⌖ SCOPE", Color(0.18, 0.45, 0.65, 0.85))
	btn_scope.pressed.connect(_toggle_scope)

	btn_peek_left = _create_tactical_button("BtnPeekLeft", "< PEEK", Color(0.24, 0.35, 0.42, 0.8))
	btn_peek_left.button_down.connect(func() -> void:
		if is_instance_valid(player) and "touch_peek_input" in player:
			player.touch_peek_input = -1.0)
	btn_peek_left.button_up.connect(func() -> void:
		if is_instance_valid(player) and "touch_peek_input" in player:
			player.touch_peek_input = 0.0)

	btn_peek_right = _create_tactical_button("BtnPeekRight", "PEEK >", Color(0.24, 0.35, 0.42, 0.8))
	btn_peek_right.button_down.connect(func() -> void:
		if is_instance_valid(player) and "touch_peek_input" in player:
			player.touch_peek_input = 1.0)
	btn_peek_right.button_up.connect(func() -> void:
		if is_instance_valid(player) and "touch_peek_input" in player:
			player.touch_peek_input = 0.0)

	btn_crouch = _create_tactical_button("BtnCrouch", "CROUCH", Color(0.22, 0.32, 0.38, 0.8))
	btn_crouch.pressed.connect(func() -> void:
		if is_instance_valid(player) and player.has_method("_update_stance"):
			player._update_stance(not player.crouching, false)
			btn_crouch.text = "STAND" if player.crouching else "CROUCH")

	btn_prone = _create_tactical_button("BtnProne", "PRONE", Color(0.22, 0.32, 0.38, 0.8))
	btn_prone.pressed.connect(func() -> void:
		if is_instance_valid(player) and player.has_method("_update_stance"):
			player._update_stance(false, not player.prone)
			btn_prone.text = "STAND" if player.prone else "PRONE")

	btn_fire_mode = _create_tactical_button("BtnFireMode", "AUTO", Color(0.18, 0.42, 0.32, 0.85))
	btn_fire_mode.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.toggle_fire_mode()
			btn_fire_mode.text = "AUTO" if _game.gameplay.fire_mode == 0 else "SINGLE")

	btn_gyro_mode = _create_tactical_button("BtnGyroMode", "SETTINGS", Color(0.35, 0.28, 0.48, 0.85))
	btn_gyro_mode.pressed.connect(func() -> void:
		if settings_menu: settings_menu.open_menu())

	btn_reload = _create_tactical_button("BtnReload", "RELOAD", Color(0.52, 0.38, 0.18, 0.8))
	btn_reload.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.reload_weapon())

func _create_tactical_button(btn_name: String, text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = text
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.set_corner_radius_all(10)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(1, 1, 1, 0.35)
	btn.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg_color.lightened(0.2)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color("ffffff"))
	$TouchControls.add_child(btn)
	return btn

func _set_button_rect(button: Button, position: Vector2, size: float) -> void:
	button.position = position
	button.size = Vector2(size, size)
	button.add_theme_font_size_override("font_size", maxi(20, roundi(size * 0.28)))

func _press_action(action: String) -> void:
	Input.action_press(action)

func _release_action(action: String) -> void:
	Input.action_release(action)

func _jump() -> void:
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")

## Jump vaults a low obstacle first when one is ahead, as BGMI's jump button does.
func _touch_jump() -> void:
	if _game and _game.gameplay and _game.gameplay.try_vault():
		return
	_jump()

## Touch buttons for actions that otherwise need a keyboard: equip (the weapon slot,
## which also shows ammo), medkit, grenade, talk, surrender, hold-to-help, hold-to-free-look
## and the ACTION / PEACE toggle that firing depends on.
func _setup_touch_actions() -> void:
	btn_equip = _create_tactical_button("BtnEquip", "AR 24/120", Color(0.1, 0.12, 0.14, 0.85))
	btn_equip.pressed.connect(func() -> void:
		if _game and is_instance_valid(player) and player.has_method("set_weapon_equipped"):
			player.set_weapon_equipped(not player.is_weapon_equipped()))
	btn_swap = _create_tactical_button("BtnSwap", "⇄ AK", Color(0.1, 0.12, 0.14, 0.85))
	btn_swap.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.switch_weapon())
	btn_medkit = _create_tactical_button("BtnMedkit", "MED 0", Color(0.55, 0.16, 0.16, 0.85))
	btn_medkit.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.use_medkit())
	btn_grenade = _create_tactical_button("BtnGrenade", "NADE 0", Color(0.3, 0.36, 0.2, 0.85))
	btn_grenade.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.throw_grenade())
	btn_talk = _create_tactical_button("BtnTalk", "TALK", Color(0.2, 0.3, 0.4, 0.85))
	btn_talk.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.talk_nearby())
	btn_surrender = _create_tactical_button("BtnSurrender", "GIVE UP", Color(0.4, 0.4, 0.42, 0.85))
	btn_surrender.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.surrender())
	btn_help = _create_tactical_button("BtnHelp", "HELP", Color(0.2, 0.42, 0.3, 0.85))
	btn_help.button_down.connect(func() -> void: Input.action_press("service"))
	btn_help.button_up.connect(func() -> void: Input.action_release("service"))
	btn_free_look = _create_tactical_button("BtnFreeLook", "LOOK", Color(0.2, 0.22, 0.3, 0.85))
	btn_free_look.button_down.connect(func() -> void:
		if is_instance_valid(player) and "touch_free_look" in player.camera_pivot:
			player.camera_pivot.touch_free_look = true)
	btn_free_look.button_up.connect(func() -> void:
		if is_instance_valid(player) and "touch_free_look" in player.camera_pivot:
			player.camera_pivot.touch_free_look = false)
	btn_mode = _create_tactical_button("BtnMode", "PEACE", Color(0.5, 0.2, 0.15, 0.85))
	btn_mode.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.set_action_mode(not _game.gameplay.action_mode))
	btn_character = _create_tactical_button("BtnCharacter", "AVATAR", Color(0.3, 0.22, 0.42, 0.85))
	btn_character.pressed.connect(_switch_character_touch)
	# BGMI's FPP/TPP switch; the label names the view a tap switches to.
	btn_view = _create_tactical_button("BtnView", "FPP", Color(0.12, 0.3, 0.4, 0.85))
	btn_view.pressed.connect(func() -> void:
		if _game and _game.has_method("toggle_camera_view"):
			_game.toggle_camera_view())

## The touch twin of Tab: cycles the on-foot character and names the new one.
func _switch_character_touch() -> void:
	if _game == null or _game.control_state != _game.ControlState.ON_FOOT or not is_instance_valid(player):
		return
	var character := player.get_node_or_null("TestCharacter")
	if character and character.has_method("toggle_character"):
		var selected: String = character.toggle_character()
		if _game.city_life and _game.city_life.has_method("toast"):
			_game.city_life.toast("Character: %s" % selected)

## NORMAL on foot, FIRING in ACTION mode, VEHICLE while driving.
func _current_profile() -> StringName:
	if _game == null:
		return HudLayoutProfiles.NORMAL
	var action: bool = _game.gameplay != null and _game.gameplay.action_mode
	return HudLayoutProfiles.profile_for(_game.control_state == _game.ControlState.DRIVING, action)

## The default (uncustomised) layout for this screen, and what the editor shows for it.
func _layout_context(profile: StringName) -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var dpi := float(DisplayServer.screen_get_dpi())
	var units_mm := ClawLayout.units_per_mm(viewport_size, Vector2(DisplayServer.window_get_size()), dpi)
	var tablet := ClawLayout.is_tablet(Vector2(DisplayServer.screen_get_size()), dpi)
	var safe := ClawLayout.canvas_safe_rect(get_viewport())
	return {
		"rects": ClawLayout.compute(viewport_size, safe, units_mm, tablet, touch_settings.button_scale, touch_settings.left_handed),
		"safe": safe,
		"min_target": ClawLayout.min_target(safe, units_mm),
		"labels": _slot_labels(profile),
		"opacity": touch_settings.opacity,
	}

## The button each slot shows in a layout: driving reuses on-foot slots for its own buttons.
func _slot_buttons(profile: StringName) -> Dictionary:
	if profile == HudLayoutProfiles.VEHICLE:
		var driving := {&"Run": $TouchControls/Run, &"Reset": $TouchControls/Reset, &"Squad": btn_multiplayer_toggle,
			&"Gyro": btn_gyro_mode, &"FreeLook": btn_free_look, &"View": btn_view}
		for button_name in ClawLayout.SCENE_BUTTON_SLOTS:
			if button_name not in [&"Run", &"Jump", &"Reset", &"Enter"]:
				driving[ClawLayout.SCENE_BUTTON_SLOTS[button_name]] = $TouchControls.get_node(String(button_name))
		return driving
	return {&"Fire": btn_fire_right, &"FireLeft": btn_fire_left, &"Scope": btn_scope, &"Reload": btn_reload,
		&"Jump": $TouchControls/Jump, &"Crouch": btn_crouch, &"Prone": btn_prone, &"PeekLeft": btn_peek_left,
		&"PeekRight": btn_peek_right, &"Run": $TouchControls/Run, &"FreeLook": btn_free_look, &"View": btn_view,
		&"Vehicle": $TouchControls/Enter, &"Surrender": btn_surrender, &"Help": btn_help, &"Talk": btn_talk,
		&"Equip": btn_equip, &"Swap": btn_swap, &"Medkit": btn_medkit, &"Grenade": btn_grenade,
		&"FireMode": btn_fire_mode, &"Mode": btn_mode, &"Character": btn_character, &"Reset": $TouchControls/Reset,
		&"Squad": btn_multiplayer_toggle, &"Gyro": btn_gyro_mode, &"Context": btn_revive, &"ContextAlt": btn_loot}

func _slot_labels(profile: StringName) -> Dictionary:
	var labels := {&"Joystick": "STEER" if profile == HudLayoutProfiles.VEHICLE else "MOVE"}
	var buttons := _slot_buttons(profile)
	for slot in buttons:
		if is_instance_valid(buttons[slot]):
			labels[slot] = buttons[slot].text.strip_edges()
	if profile == HudLayoutProfiles.VEHICLE:
		labels[&"Run"] = "ASCEND"
		labels[&"Fire"] = "BRAKE"
	return labels

## A button dragged onto the joystick zone still gets its own taps.
func _touch_button_at(position: Vector2) -> bool:
	for child in $TouchControls.get_children():
		if child is BaseButton and child.is_visible_in_tree() and child.get_global_rect().has_point(position):
			return true
	return false

## Settings -> Customize HUD layout. Pauses the game and edits the current layout first.
func open_layout_editor() -> void:
	if not is_instance_valid(_layout_editor):
		_layout_editor = HudLayoutEditor.new()
		_layout_editor.profiles = layout_profiles
		_layout_editor.layout_provider = _layout_context
		add_child(_layout_editor)
		_layout_editor.closed.connect(func(_saved: bool) -> void:
			$TouchControls.visible = _touch_overlay_enabled
			_layout_for_viewport())
	clear_touch_inputs()
	$TouchControls.visible = false
	_layout_editor.open(_current_profile())

## Settings and the city's shop/journal pop-ups: full-screen menus over a paused game.
func _menu_open() -> bool:
	if is_instance_valid(settings_menu) and is_instance_valid(settings_menu.panel) and settings_menu.panel.visible:
		return true
	if is_instance_valid(_layout_editor) and _layout_editor.is_open():
		return true
	return _game != null and is_instance_valid(_game.city_life) and _game.city_life.has_modal()

## BGMI's scope button always aims: from PEACE or empty hands it arms the rifle
## first, so one tap is enough. The camera does the sight view (TPP borrows FPP).
func _toggle_scope() -> void:
	if _game == null or _game.gameplay == null or not is_instance_valid(player) or not "touch_aim" in player.camera_pivot:
		return
	var pivot: Node = player.camera_pivot
	if not pivot.touch_aim and _game.gameplay.get("has_rifle") == false:
		if _game.city_life and _game.city_life.has_method("toast"):
			_game.city_life.toast("No rifle yet • pick one up at Chowrastha")
		return
	if not pivot.touch_aim:
		if not _game.gameplay.action_mode:
			_game.gameplay.set_action_mode(true)
		if player.has_method("set_weapon_equipped") and not player.is_weapon_equipped():
			player.set_weapon_equipped(true)
	pivot.touch_aim = not pivot.touch_aim

## A red-dot sight drawn over the view while aiming: a thin ring and a lit dot at the
## exact screen centre the shot ray uses.
func _build_scope_overlay() -> void:
	_scope_overlay = Control.new()
	_scope_overlay.name = "ScopeOverlay"
	_scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_overlay.visible = false
	_scope_overlay.draw.connect(_draw_scope)
	add_child(_scope_overlay)
	move_child(_scope_overlay, 0)

func _draw_scope() -> void:
	var size := _scope_overlay.size
	var center := size * 0.5
	var ring := minf(size.x, size.y) * 0.16
	_scope_overlay.draw_arc(center, ring, 0.0, TAU, 96, Color(0.05, 0.05, 0.05, 0.85), maxf(ring * 0.06, 3.0), true)
	_scope_overlay.draw_arc(center, ring * 1.04, 0.0, TAU, 96, Color(1, 1, 1, 0.25), 1.5, true)
	_scope_overlay.draw_circle(center, maxf(ring * 0.028, 2.5), Color(1.0, 0.12, 0.1, 0.95))
	_scope_overlay.draw_circle(center, maxf(ring * 0.06, 5.0), Color(1.0, 0.15, 0.1, 0.18))

## Keeps the item bar honest when the keyboard, pickups or the gameplay code change state.
func _update_touch_labels() -> void:
	if not $TouchControls.visible or _game == null or _game.gameplay == null or not is_instance_valid(btn_equip):
		return
	if _current_profile() != _applied_profile:
		_layout_for_viewport()
	var play: Node = _game.gameplay
	_set_label(btn_equip, "%s %d/%d" % [Weapons.short_name(player.weapon_id), play.ammo, play.reserve] if player.is_weapon_equipped() else "EQUIP")
	var owned: Array[int] = []
	if play.has_method("rifles"):
		owned = play.rifles()
	btn_swap.visible = btn_equip.visible and owned.size() > 1
	if btn_swap.visible:
		_set_label(btn_swap, "⇄ " + Weapons.short_name(owned[(owned.find(player.weapon_id) + 1) % owned.size()]))
	_set_label(btn_medkit, "MED %d" % play.medkits)
	_set_label(btn_grenade, "NADE %d" % play.grenades)
	_set_label(btn_mode, "ACTION" if play.action_mode else "PEACE")
	_set_label(btn_fire_mode, "AUTO" if play.fire_mode == 0 else "SINGLE")
	_set_label(btn_view, "TPP" if _game.get("first_person_view") == true else "FPP")
	var aiming: bool = player.camera_pivot.get("is_aiming") == true
	_set_label(btn_scope, "EXIT" if aiming else "⌖ SCOPE")
	if is_instance_valid(_scope_overlay) and _scope_overlay.visible != aiming:
		_scope_overlay.visible = aiming
		_scope_overlay.queue_redraw()

func _set_label(button: Button, text: String) -> void:
	if button.text != text:
		button.text = text

func _format_position(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]

func set_coins(amount: int) -> void:
	_collected_coins = maxi(0, amount)

func add_coins(amount: int) -> void:
	_collected_coins += maxi(0, amount)

func _build_multiplayer_ui() -> void:
	# Squad Lobby Toggle Button (Top Right)
	btn_multiplayer_toggle = Button.new()
	btn_multiplayer_toggle.name = "BtnMultiplayerToggle"
	btn_multiplayer_toggle.text = "🌐 SQUAD"
	btn_multiplayer_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	var net_btn_style := StyleBoxFlat.new()
	net_btn_style.bg_color = Color(0.12, 0.24, 0.35, 0.88)
	net_btn_style.border_color = Color(0.3, 0.7, 0.9, 0.7)
	net_btn_style.set_border_width_all(1)
	net_btn_style.set_corner_radius_all(6)
	btn_multiplayer_toggle.add_theme_stylebox_override("normal", net_btn_style)
	btn_multiplayer_toggle.add_theme_font_size_override("font_size", 14)
	btn_multiplayer_toggle.pressed.connect(toggle_multiplayer_panel)
	add_child(btn_multiplayer_toggle)

	# Godavari River Bridge Fast-Travel Button
	btn_bridge_travel = Button.new()
	btn_bridge_travel.name = "BtnBridgeTravel"
	btn_bridge_travel.text = "🌉 BRIDGE [B]"
	btn_bridge_travel.tooltip_text = "Fast Travel to Godavari River Bridge (1,100 m) [Hotkey: B]"
	btn_bridge_travel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bridge_btn_style := StyleBoxFlat.new()
	bridge_btn_style.bg_color = Color(0.12, 0.32, 0.22, 0.88)
	bridge_btn_style.border_color = Color(0.35, 0.8, 0.55, 0.8)
	bridge_btn_style.set_border_width_all(1)
	bridge_btn_style.set_corner_radius_all(6)
	btn_bridge_travel.add_theme_stylebox_override("normal", bridge_btn_style)
	btn_bridge_travel.add_theme_font_size_override("font_size", 13)
	btn_bridge_travel.pressed.connect(func() -> void:
		if _game and _game.has_method("_teleport_to_godavari_bridge"):
			_game._teleport_to_godavari_bridge())
	add_child(btn_bridge_travel)

	# Room Banner
	net_room_banner = Label.new()
	net_room_banner.name = "NetRoomBanner"
	net_room_banner.add_theme_font_size_override("font_size", 13)
	net_room_banner.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 1.0))
	add_child(net_room_banner)

	# Revive & Loot Tactical Buttons
	btn_revive = _create_tactical_button("BtnRevive", "⛑️ REVIVE", Color(0.18, 0.65, 0.35, 0.9))
	btn_revive.visible = false
	btn_revive.button_down.connect(func() -> void: touch_revive_pressed = true)
	btn_revive.button_up.connect(func() -> void: touch_revive_pressed = false)

	btn_loot = _create_tactical_button("BtnLoot", "📦 LOOT", Color(0.68, 0.55, 0.18, 0.9))
	btn_loot.visible = false
	btn_loot.pressed.connect(func() -> void:
		if _game and _game.gameplay and _game.gameplay.has_method("try_loot_nearby"):
			_game.gameplay.try_loot_nearby())

	# SQUAD screen: HOST GAME / FIND GAMES / JOIN BY NUMBER, made for touch (squad_lobby.gd).
	# The finder lives on the HUD so a host keeps announcing its room after the screen closes.
	squad_discovery = LanDiscovery.new()
	squad_discovery.name = "SquadDiscovery"
	add_child(squad_discovery)
	multiplayer_panel = SquadLobby.new()
	multiplayer_panel.name = "MultiplayerPanel"
	multiplayer_panel.visible = false
	multiplayer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Its own layer above the clock, notifications and status text, which would cover the title.
	var squad_layer := CanvasLayer.new()
	squad_layer.name = "SquadLayer"
	squad_layer.layer = 30
	add_child(squad_layer)
	squad_layer.add_child(multiplayer_panel)

func toggle_multiplayer_panel() -> void:
	if multiplayer_panel:
		multiplayer_panel.visible = not multiplayer_panel.visible
		if multiplayer_panel.visible:
			_layout_for_viewport()
		elif is_instance_valid(squad_discovery) and squad_discovery.is_searching():
			# Searching only matters while the screen is open; hosting keeps announcing.
			squad_discovery.stop_searching()

func _update_multiplayer_hud() -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(net_room_banner):
		if network_manager and network_manager.has_method("is_active") and network_manager.is_active():
			var role: String = "HOST (PORT %d)" % network_manager.DEFAULT_PORT if network_manager.is_host() else "CLIENT"
			net_room_banner.text = "🌐 %s • Squad: %d connected" % [role, network_manager.peers.size()]
		else:
			net_room_banner.text = ""

	# Proximity check for revive button
	var near_downed := false
	if network_manager and "puppets" in network_manager:
		for id in network_manager.puppets:
			var p: Node = network_manager.puppets[id]
			if is_instance_valid(p) and p.get("is_downed") == true:
				if player.global_position.distance_to(p.global_position) < 3.0:
					near_downed = true
					break
	if is_instance_valid(btn_revive):
		btn_revive.visible = near_downed and _touch_overlay_enabled

	# Proximity check for loot button
	var near_crate := false
	for crate in get_tree().get_nodes_in_group("loot_crates"):
		if is_instance_valid(crate) and player.global_position.distance_to(crate.global_position) < 3.0:
			near_crate = true
			break
	if is_instance_valid(btn_loot):
		btn_loot.visible = near_crate and _touch_overlay_enabled

func _on_net_connection_changed(active: bool, is_host: bool) -> void:
	if not is_instance_valid(lbl_net_status):
		return
	if active:
		lbl_net_status.text = "Status: Online (%s)" % ("HOST" if is_host else "CLIENT")
		lbl_net_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	else:
		lbl_net_status.text = "Status: Offline (Single Player)"
		lbl_net_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		if is_instance_valid(lbl_player_list):
			lbl_player_list.text = "Connected: None"

func _on_net_peer_list_updated(peers_dict: Dictionary) -> void:
	if not is_instance_valid(lbl_player_list):
		return
	if peers_dict.is_empty():
		lbl_player_list.text = "Connected: None"
		return
	var names: Array[String] = []
	for id in peers_dict:
		var n: String = peers_dict[id].get("nickname", "Player %d" % id)
		var downed_str := " (DOWNED)" if peers_dict[id].get("is_downed") == true else ""
		names.append("%s%s" % [n, downed_str])
	lbl_player_list.text = "Squad (%d): %s" % [peers_dict.size(), ", ".join(names)]

func _on_net_notification(msg: String, _is_alert: bool) -> void:
	if _game and _game.city_life and _game.city_life.has_method("toast"):
		_game.city_life.toast(msg)

