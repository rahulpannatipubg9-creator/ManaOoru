extends CanvasLayer

## The in-game HUD, built to docs/reference/UI_DESIGN.md: the town first, and only what the
## moment needs. Readouts live in hud_readouts.gd, the rare actions in action_wheel.gd; this
## script feeds them from the game and runs the touch controls.
##
## For other systems: set_vitals, set_ammo, set_wanted, set_objective, clear_objective,
## show_coin_delta, set_interaction_prompt, set_speed, set_gear and set_flight_altitude.
## Most of these fill themselves from the game each frame, so calling them is optional.

const ClawLayout := preload("res://scripts/mobile/claw_layout.gd")
const FloatingJoystick := preload("res://scripts/mobile/floating_joystick.gd")
const MobileControlsSettings := preload("res://scripts/mobile/mobile_controls_settings.gd")
const MenuTouchBridge := preload("res://scripts/mobile/menu_touch_bridge.gd")
const HudLayoutProfiles := preload("res://scripts/mobile/hud_layout_profiles.gd")
const HudLayoutEditor := preload("res://scripts/mobile/hud_layout_editor.gd")
const LanDiscovery := preload("res://scripts/network/lan_discovery.gd")
const SquadLobby := preload("res://scripts/network/squad_lobby.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
const Icons := preload("res://scripts/ui/hud_icons.gd")
const Readouts := preload("res://scripts/ui/hud_readouts.gd")
const Compass := preload("res://scripts/ui/hud_compass.gd")
const ActionWheel := preload("res://scripts/ui/action_wheel.gd")

## Held on desktop to open the action wheel. Tab swaps character and every letter is taken.
const WHEEL_KEY := KEY_ALT
## The help action needs a hold of 5 s; picking it in the wheel holds it for slightly longer.
const HELP_HOLD_SECONDS := 5.5
const SLOT_NAMES := {&"Joystick": "Move", &"Jump": "Jump", &"Run": "Run", &"Vehicle": "Use", &"Wheel": "Wheel",
	&"Menu": "Menu", &"Context": "Revive", &"ContextAlt": "Loot", &"Fire": "Fire", &"Scope": "Aim",
	&"Reload": "Reload", &"Crouch": "Crouch", &"Swap": "Swap"}
const VEHICLE_SLOT_NAMES := {&"Joystick": "Steer", &"Fire": "Brake", &"Scope": "Camera", &"Reload": "Gear up",
	&"Crouch": "Gear down", &"Vehicle": "Exit", &"Run": "Ascend", &"Wheel": "Wheel", &"Menu": "Menu"}

@onready var player: CharacterBody3D = get_parent().get_node("Player")
var _run_latched := false
var _collected_coins := 0
var touch_settings := MobileControlsSettings.new()
var settings_menu: CanvasLayer
var _stick := FloatingJoystick.new()
var _stick_rest := Vector2.ZERO
var _vehicle: PhysicsBody3D
var _game: Node
var _navigator: GpsNavigator
var minimap: Minimap
var full_map: FullMap

var readouts: Readouts
var compass_bar: Compass
var action_wheel: ActionWheel
var btn_fire_right: Button
var btn_scope: Button
var btn_crouch: Button
var btn_reload: Button
var btn_swap: Button
var btn_wheel: Button
var btn_menu: Button
var _scope_overlay: Control
var _enter_available := false
var _prompt_usable := false
var _manual_gears := false
var _objective_from_game := false
var _help_left := 0.0
## Player-arranged NORMAL / FIRING / VEHICLE layouts and the editor that arranges them.
var layout_profiles := HudLayoutProfiles.new()
var _layout_editor: HudLayoutEditor
var _applied_profile := &""
var _touch_overlay_enabled: bool = OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

var network_manager: Node
var btn_revive: Button
var btn_loot: Button
var touch_revive_pressed: bool = false
var touch_loot_pressed: bool = false
var multiplayer_panel: PanelContainer
var squad_discovery: LanDiscovery
var net_room_banner: Label
var lbl_net_status: Label
var lbl_player_list: Label
## In a match only the buttons that work in a fight stay on screen (see _match_hidden).
var _match_mode := false

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
	_navigator = navigator
	# Last child, so it sees touches before the map under it.
	move_child(action_wheel, -1)
	_layout_for_viewport()

func set_full_map_open(value: bool) -> void:
	if value:
		full_map.open()
	else:
		full_map.close()
	minimap.visible = not value
	$TouchControls.visible = _touch_overlay_enabled and not value
	compass_bar.visible = not value
	readouts.visible = not value
	readouts.prompt_root.visible = false

func set_active_vehicle(vehicle: PhysicsBody3D) -> void:
	_vehicle = vehicle

func _controlled_body() -> PhysicsBody3D:
	if _game and _game.control_state == _game.ControlState.DRIVING:
		return _vehicle
	return player

func set_enter_available(value: bool) -> void:
	_enter_available = value

## One pill, or silence. An "[E]" line on foot also lights the touch action button.
func set_interaction_prompt(value: String) -> void:
	readouts.set_prompt(value)
	_prompt_usable = value.begins_with("[E]")

func set_speed(value: float) -> void:
	readouts.set_speed(value)

func set_gear(gear_label: String, engine_rpm: float, automatic: bool) -> void:
	readouts.set_gear(gear_label, engine_rpm, automatic)
	_manual_gears = not automatic

func set_flight_altitude(value: float) -> void:
	readouts.set_altitude(value)

func set_vitals(health: float, max_health: float, armour: float) -> void:
	readouts.set_vitals(health, max_health, armour)

func set_ammo(mag: int, reserve: int, weapon_name: String) -> void:
	readouts.set_ammo(mag, reserve, weapon_name)

func set_wanted(level: int) -> void:
	readouts.set_wanted(level)

## Top-right block. The game's own jobs and GPS route fill this too; a caller's objective
## stays until it clears it.
func set_objective(title: String, detail: String) -> void:
	_objective_from_game = false
	readouts.set_objective(title, detail)

func clear_objective() -> void:
	_objective_from_game = false
	readouts.clear_objective()

func show_coin_delta(amount: int) -> void:
	readouts.show_coin_delta(amount)

func set_vehicle_mode(_value: bool) -> void:
	_refresh_touch()

## Controls are taught by the help page and by the prompts, never by a wall of text.
func show_vehicle_controls_hint() -> void:
	pass

func show_helicopter_controls_hint() -> void:
	pass

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var paused := get_tree().paused
	_tick_latches(0.0 if paused else delta)
	# Touch layout and labels follow the control state even while a vehicle is swapping.
	_refresh_touch()
	_read_game_state()
	readouts.tick(delta, paused)
	_update_compass()
	_update_multiplayer_hud()
	if _match_mode:
		for node: CanvasItem in _match_hidden():
			node.visible = false

func _match_hidden() -> Array[CanvasItem]:
	var nodes: Array[CanvasItem] = [$TouchControls/Enter]
	for node in [compass_bar, net_room_banner, btn_wheel, btn_revive, btn_loot]:
		if is_instance_valid(node):
			nodes.append(node)
	return nodes

func set_match_mode(value: bool) -> void:
	if value == _match_mode:
		return
	_match_mode = value
	if minimap:
		minimap.set_compact(value)
	if not value:
		for node: CanvasItem in _match_hidden():
			node.visible = true
		# These have their own conditions and come back when those hold.
		for node: CanvasItem in [$TouchControls/Enter, btn_revive, btn_loot]:
			node.visible = false

func _driving() -> bool:
	return _game != null and _game.control_state == _game.ControlState.DRIVING

func _on_foot() -> bool:
	return _game == null or _game.control_state == _game.ControlState.ON_FOOT

func _flying() -> bool:
	return _driving() and _vehicle is GdkHelicopter

func _play() -> Node:
	return _game.get("gameplay") as Node if _game != null else null

func _armed() -> bool:
	return _on_foot() and player.has_method("is_weapon_equipped") and player.is_weapon_equipped()

func _in_match() -> bool:
	var match_node: Variant = _game.get("tdm_local") if _game != null else null
	return is_instance_valid(match_node) and match_node.in_match

## Reads what can be read directly, so the HUD works without anyone calling its setters.
func _read_game_state() -> void:
	readouts.driving = _driving()
	readouts.flying = _flying()
	readouts.rifle_out = _armed()
	# Team Deathmatch has its own health, ammo and score displays.
	readouts.suppressed = _in_match()
	var play := _play()
	var health: Variant = player.get("health")
	if health != null:
		var armour: Variant = play.get("armour") if play != null else 0.0
		readouts.set_vitals(health, player.max_health, armour if armour != null else 0.0)
	if play == null:
		return
	var weapon: Variant = player.get("weapon_id")
	if weapon != null and play.get("ammo") != null:
		readouts.set_ammo(play.ammo, play.reserve, Weapons.short_name(weapon))
	if play.get("wanted_level") != null:
		readouts.set_wanted(play.wanted_level)
	_read_objective(play)
	_read_vehicle()
	# Everything on the old status line now has a home here.
	var status: Variant = play.get("_status")
	if status is CanvasItem and status.visible:
		status.visible = false

func _read_objective(play: Node) -> void:
	var mission: Variant = play.get("mission")
	var title := ""
	var detail := PackedStringArray()
	if mission is Dictionary and not mission.is_empty():
		title = mission.title
		detail.append(mission.stage)
		var seconds := ceili(mission.time)
		detail.append("%d:%02d" % [seconds / 60, seconds % 60])
	var routed: bool = _navigator != null and _navigator.has_destination and not _navigator.arrived
	if routed:
		if title.is_empty():
			title = _navigator.destination_name if not _navigator.destination_name.is_empty() else "Waypoint"
		detail.append(_navigator.format_distance(_navigator.remaining_distance))
	if not title.is_empty():
		_objective_from_game = true
		readouts.set_objective(title, "  •  ".join(detail))
	elif _objective_from_game:
		_objective_from_game = false
		readouts.clear_objective()

func _read_vehicle() -> void:
	if not _driving() or not is_instance_valid(_vehicle):
		return
	var gearbox: Variant = _vehicle.get("gearbox")
	if gearbox != null and gearbox.get("profile") != null:
		readouts.rpm_full = gearbox.profile.redline_rpm
	var life: Variant = _game.get("city_life")
	if is_instance_valid(life) and life.get("fuel") is Dictionary:
		readouts.set_fuel(float(life.fuel.get(str(_vehicle.name), 100.0)))

func register_coin_collected() -> void:
	_collected_coins += 1
	readouts.show_coin_delta(1)

func coins_available() -> int:
	return _collected_coins

func spend_coins(amount: int) -> bool:
	if amount < 0 or _collected_coins < amount:
		return false
	_collected_coins -= amount
	readouts.show_coin_delta(-amount)
	return true

func _ready() -> void:
	touch_settings.load_from()
	layout_profiles.load_from()
	readouts = Readouts.new()
	readouts.name = "Readouts"
	add_child(readouts)
	readouts.build_prompt(self)
	compass_bar = Compass.new()
	compass_bar.name = "CompassBar"
	add_child(compass_bar)
	_setup_touch_buttons()
	_build_action_wheel()
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
	move_child(action_wheel, -1)
	$TouchControls.visible = _touch_overlay_enabled
	$TouchControls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()

## Only the floating stick is handled here; it claims one finger inside its zone,
## which the claw layout keeps clear of every button, and ignores all others.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == WHEEL_KEY and not event.echo:
		_handle_wheel_key(event.pressed)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag and _stick.drag(event.index, event.position):
		_apply_stick()
		get_viewport().set_input_as_handled()

func _handle_wheel_key(pressed: bool) -> void:
	if not pressed:
		action_wheel.key_up()
	elif not get_tree().paused and not _menu_open() and not GameplayControls.text_focused(get_viewport()) \
			and not (is_instance_valid(multiplayer_panel) and multiplayer_panel.visible):
		action_wheel.key_down()

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
		if on_foot and not _run_latched:
			body.set_touch_run_pressed(_stick.wants_sprint())
	_draw_stick()

## The base follows the finger while held and returns to its resting slot after.
func _draw_stick() -> void:
	var base: ColorRect = $TouchControls/JoystickBase
	var knob: ColorRect = $TouchControls/JoystickBase/JoystickKnob
	base.position = _stick.origin - base.size * 0.5 if _stick.is_active() else _stick_rest
	var travel := base.size.x * 0.5 - knob.size.x * 0.5
	knob.position = base.size * 0.5 - knob.size * 0.5 + _stick.knob_offset() / maxf(_stick.radius, 1.0) * travel

## On foot a tap latches running; in the air the same button is held to climb.
func _on_run_pressed() -> void:
	if _flying():
		return
	_run_latched = not _run_latched
	_controlled_body().set_touch_run_pressed(_run_latched)
	$TouchControls/Run.queue_redraw()

func _on_run_held(held: bool) -> void:
	if _flying():
		_vehicle.set_touch_run_pressed(held)

func _reset_player() -> void:
	_run_latched = false
	_controlled_body().set_touch_move_input(Vector2.ZERO)
	_controlled_body().set_touch_run_pressed(false)
	player.velocity = Vector3.ZERO
	player.global_position = player.respawn_position
	player.rotation = Vector3.ZERO
	var camera := player.get_node_or_null("CameraPivot")
	if camera and camera.has_method("reset_view"):
		camera.reset_view()

func clear_touch_inputs() -> void:
	if is_instance_valid(player):
		player.touch_peek_input = 0.0
		player.camera_pivot.clear_touch_look()
		if "touch_free_look" in player.camera_pivot:
			player.camera_pivot.touch_free_look = false
	if _game and _game.gameplay: _game.gameplay.touch_fire_pressed = false
	touch_revive_pressed = false
	touch_loot_pressed = false
	_run_latched = false
	_release_help()
	if is_instance_valid(action_wheel):
		action_wheel.close()
	_stick.cancel()
	_apply_stick()

## The context button: whatever the prompt offers, as E does on a keyboard.
func _use_context() -> void:
	if _game == null:
		return
	if _game.has_method("_try_on_foot_interaction"):
		_game._try_on_foot_interaction()
	else:
		_game.enter_vehicle()

func _exit_vehicle() -> void:
	if _game:
		_game.exit_vehicle()

func _change_vehicle_camera() -> void:
	if _game and _game.has_method("toggle_camera_view"):
		_game.toggle_camera_view()

func _layout_for_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if _touch_overlay_enabled:
		_layout_touch()
	else:
		_place_shared(_desktop_rects(viewport_size), false)
	if is_instance_valid(multiplayer_panel):
		var panel_w := minf(viewport_size.x - 40.0, 760.0)
		var panel_h := minf(viewport_size.y - 40.0, 660.0)
		multiplayer_panel.position = Vector2((viewport_size.x - panel_w) * 0.5, (viewport_size.y - panel_h) * 0.5)
		multiplayer_panel.size = Vector2(panel_w, panel_h)

## One corner per job: map and vitals bottom-left, weapon or speed bottom-right, objective top-right.
func _desktop_rects(viewport_size: Vector2) -> Dictionary:
	var margin := float(UiTheme.SPACE_L)
	var map_size := clampf(minf(viewport_size.x, viewport_size.y) * 0.26, 150.0, 240.0)
	var bottom := viewport_size.y - margin
	var map := Rect2(margin, bottom - map_size, map_size, map_size)
	var vitals := Rect2(map.end.x + UiTheme.SPACE_M, bottom - ClawLayout.VITALS_SIZE.y, ClawLayout.VITALS_SIZE.x + 30.0, ClawLayout.VITALS_SIZE.y)
	var compass_width := clampf(viewport_size.x * 0.28, 200.0, 360.0)
	var readout := Vector2(ClawLayout.READOUT_SIZE.x, ClawLayout.READOUT_SIZE.y)
	return {
		&"Minimap": map,
		&"Vitals": vitals,
		&"Coins": Rect2(vitals.position - Vector2(0.0, ClawLayout.COINS_HEIGHT + UiTheme.SPACE_XS), Vector2(vitals.size.x, ClawLayout.COINS_HEIGHT)),
		&"Wanted": Rect2(margin, margin, vitals.size.x, ClawLayout.WANTED_HEIGHT),
		&"Compass": Rect2((viewport_size.x - compass_width) * 0.5, UiTheme.SPACE_M, compass_width, 30.0),
		&"Objective": Rect2(viewport_size.x - margin - ClawLayout.OBJECTIVE_WIDTH, margin, ClawLayout.OBJECTIVE_WIDTH, ClawLayout.OBJECTIVE_HEIGHT),
		&"Readout": Rect2(viewport_size - Vector2(margin, margin) - readout, readout),
		&"Prompt": Rect2(viewport_size.x * 0.25, viewport_size.y * 0.72, viewport_size.x * 0.5, ClawLayout.PROMPT_HEIGHT),
	}

## The parts desktop and touch share, wherever each screen puts them.
func _place_shared(rects: Dictionary, touch: bool) -> void:
	readouts.place(rects, touch)
	compass_bar.position = rects[&"Compass"].position
	compass_bar.size = rects[&"Compass"].size
	if is_instance_valid(net_room_banner):
		net_room_banner.position = Vector2(rects[&"Compass"].position.x, rects[&"Compass"].end.y + UiTheme.SPACE_XS)
		net_room_banner.size = Vector2(rects[&"Compass"].size.x, 24.0)
	if minimap:
		minimap.position = rects[&"Minimap"].position
		minimap.size = rects[&"Minimap"].size

## Phones and tablets: a claw layout sized in millimetres inside the display safe
## area (notch, rounded corners, gesture bar). See scripts/mobile/claw_layout.gd.
func _layout_touch() -> void:
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
	_make_round($TouchControls/JoystickBase, Color(UiTheme.SURFACE, 0.22), 2)
	_make_round($TouchControls/JoystickBase/JoystickKnob, Color(UiTheme.TEXT, 0.4), 0)
	_draw_stick()
	for button_name in ClawLayout.SCENE_BUTTON_SLOTS:
		_set_slot_rect($TouchControls.get_node(String(button_name)), slots[ClawLayout.SCENE_BUTTON_SLOTS[button_name]])
	var tactical := {&"Fire": btn_fire_right, &"Scope": btn_scope, &"Reload": btn_reload, &"Crouch": btn_crouch,
		&"Swap": btn_swap, &"Wheel": btn_wheel, &"Menu": btn_menu, &"Context": btn_revive, &"ContextAlt": btn_loot}
	for slot in tactical:
		if is_instance_valid(tactical[slot]):
			_set_slot_rect(tactical[slot], slots[slot])
	_place_shared(slots, true)
	_refresh_touch()

func _set_slot_rect(button: Button, rect: Rect2) -> void:
	# The slot is authoritative: nothing grows into a neighbour.
	button.clip_text = true
	button.position = rect.position
	button.size = rect.size
	_round_style(button, rect)

## Swaps a square ColorRect for a circle drawn by a child panel.
func _make_round(rect: ColorRect, fill: Color, border: int) -> void:
	rect.color = Color.TRANSPARENT
	var disc := rect.get_node_or_null("Disc") as Panel
	if disc == null:
		disc = Panel.new()
		disc.name = "Disc"
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(disc)
		rect.move_child(disc, 0)
	disc.position = Vector2.ZERO
	disc.size = rect.size
	var style := UiTheme.box(fill, roundi(rect.size.x * 0.5))
	if border > 0:
		style.set_border_width_all(border)
		style.border_color = Color(UiTheme.TEXT, 0.3)
	disc.add_theme_stylebox_override("panel", style)

## Translucent discs with a thin rim, so the town shows through. Icon buttons paint their
## own disc (a StyleBox this round leaves a seam down the middle); text buttons get a pill.
func _round_style(button: Button, rect: Rect2) -> void:
	var empty := StyleBoxEmpty.new()
	var has_icon: bool = button.get_meta(&"icon", &"") != &""
	var radius := roundi(minf(rect.size.x, rect.size.y) * 0.5)
	var fill: Color = button.get_meta(&"fill", UiTheme.SURFACE)
	button.add_theme_stylebox_override("normal", empty if has_icon else UiTheme.box(fill, radius, UiTheme.LINE))
	button.add_theme_stylebox_override("hover", empty if has_icon else UiTheme.box(fill, radius, UiTheme.LINE))
	button.add_theme_stylebox_override("pressed", empty if has_icon else UiTheme.box(Color(UiTheme.ACCENT, 0.55), radius))
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)

func _update_compass() -> void:
	if not compass_bar.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	compass_bar.set_heading(rad_to_deg(atan2(forward.x, forward.z)) + 180.0)

## Every touch button draws an icon rather than a word. The buttons from hud.tscn get theirs
## here too, and all of them are built before the first layout.
func _setup_touch_buttons() -> void:
	var controls: Control = $TouchControls
	for scene_button: Button in [controls.get_node("Run"), controls.get_node("Jump"), controls.get_node("Enter"), controls.get_node("Exit"),
			controls.get_node("Handbrake"), controls.get_node("Camera"), controls.get_node("GearUp"), controls.get_node("GearDown")]:
		scene_button.mouse_filter = Control.MOUSE_FILTER_STOP
		scene_button.focus_mode = Control.FOCUS_NONE
		scene_button.draw.connect(_paint_icon.bind(scene_button))
	_set_icon(controls.get_node("Run"), &"run")
	_set_icon(controls.get_node("Jump"), &"jump")
	_set_icon(controls.get_node("Enter"), &"interact")
	_set_icon(controls.get_node("Exit"), &"exit")
	_set_icon(controls.get_node("Handbrake"), &"handbrake")
	_set_icon(controls.get_node("Camera"), &"camera")
	_set_icon(controls.get_node("GearUp"), &"plus")
	_set_icon(controls.get_node("GearDown"), &"minus")
	$TouchControls/Run.pressed.connect(_on_run_pressed)
	$TouchControls/Run.button_down.connect(_on_run_held.bind(true))
	$TouchControls/Run.button_up.connect(_on_run_held.bind(false))
	$TouchControls/Jump.button_down.connect(_touch_jump)
	$TouchControls/Enter.pressed.connect(_use_context)
	$TouchControls/Exit.pressed.connect(_exit_vehicle)
	$TouchControls/Handbrake.button_down.connect(_on_brake.bind(true))
	$TouchControls/Handbrake.button_up.connect(_on_brake.bind(false))
	$TouchControls/Camera.pressed.connect(_change_vehicle_camera)
	$TouchControls/GearUp.pressed.connect(func() -> void: _vehicle.shift_up())
	$TouchControls/GearDown.pressed.connect(func() -> void: _vehicle.shift_down())

	btn_fire_right = _create_tactical_button("BtnFireRight", &"fire", Color(UiTheme.DANGER, 0.5))
	btn_fire_right.button_down.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = true
			_game.gameplay.attack())
	btn_fire_right.button_up.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.touch_fire_pressed = false)
	btn_scope = _create_tactical_button("BtnScope", &"aim")
	btn_scope.pressed.connect(_toggle_scope)
	btn_crouch = _create_tactical_button("BtnCrouch", &"crouch")
	btn_crouch.pressed.connect(_toggle_crouch)
	btn_reload = _create_tactical_button("BtnReload", &"reload")
	btn_reload.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.reload_weapon())
	btn_swap = _create_tactical_button("BtnSwap", &"swap")
	btn_swap.pressed.connect(func() -> void:
		if _game and _game.gameplay:
			_game.gameplay.switch_weapon())
	btn_wheel = _create_tactical_button("BtnWheel", &"wheel")
	btn_wheel.pressed.connect(func() -> void:
		if not action_wheel.is_open():
			action_wheel.open_sticky())
	btn_menu = _create_tactical_button("BtnMenu", &"menu")
	btn_menu.set_meta(&"bare", true)
	btn_menu.pressed.connect(func() -> void:
		if settings_menu: settings_menu.open_menu())

func _on_brake(held: bool) -> void:
	if _vehicle is GdkHelicopter:
		_vehicle.set_touch_descend_pressed(held)
	elif held:
		Input.action_press("vehicle_handbrake")
	else:
		Input.action_release("vehicle_handbrake")

func _toggle_crouch() -> void:
	if is_instance_valid(player) and player.has_method("_update_stance"):
		player._update_stance(not player.crouching, false)

func _toggle_prone() -> void:
	if is_instance_valid(player) and player.has_method("_update_stance"):
		player._update_stance(false, not player.prone)

func _create_tactical_button(btn_name: String, icon_id: StringName, fill := UiTheme.SURFACE) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta(&"fill", fill)
	_set_icon(btn, icon_id)
	btn.draw.connect(_paint_icon.bind(btn))
	$TouchControls.add_child(btn)
	return btn

func _set_icon(button: Button, icon_id: StringName) -> void:
	if button.get_meta(&"icon", &"") != icon_id:
		button.set_meta(&"icon", icon_id)
		button.queue_redraw()

func _paint_icon(button: Button) -> void:
	var icon_id: StringName = button.get_meta(&"icon", &"")
	if icon_id == &"":
		return
	var middle := button.size * 0.5
	var radius := minf(button.size.x, button.size.y) * 0.5
	if not button.get_meta(&"bare", false):
		var fill: Color = Color(UiTheme.ACCENT, 0.55) if button.is_pressed() else button.get_meta(&"fill", UiTheme.SURFACE)
		button.draw_circle(middle, radius - 1.0, fill, true, -1.0, true)
		button.draw_arc(middle, radius - 1.0, 0.0, TAU, 64, UiTheme.LINE, 1.5, true)
	var lit: bool = button.get_meta(&"lit", false)
	Icons.paint(button, icon_id, middle, radius * 0.92, UiTheme.ACCENT if lit else UiTheme.TEXT)

## Marks a latched button, such as running or aiming.
func _set_lit(button: Button, value: bool) -> void:
	if button.get_meta(&"lit", false) != value:
		button.set_meta(&"lit", value)
		button.queue_redraw()

func _jump() -> void:
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")

## Jump vaults a low obstacle first when one is ahead, as BGMI's jump button does.
func _touch_jump() -> void:
	if _game and _game.gameplay and _game.gameplay.try_vault():
		return
	_jump()

## The wheel holds whatever does not earn a permanent button, and only what fits the moment.
func _build_action_wheel() -> void:
	action_wheel = ActionWheel.new()
	action_wheel.name = "ActionWheel"
	action_wheel.provider = _wheel_items
	action_wheel.trigger = btn_wheel
	action_wheel.chosen.connect(_on_wheel_chosen)
	add_child(action_wheel)

func _wheel_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var play := _play()
	if _driving():
		if not _flying() and is_instance_valid(_vehicle) and _vehicle.has_method("toggle_transmission_mode"):
			items.append({"id": &"gearbox", "icon": &"gearbox", "label": "Manual" if not _manual_gears else "Automatic", "active": _manual_gears})
		if _flying():
			items.append({"id": &"camera", "icon": &"camera", "label": "Camera"})
		if play != null and play.has_method("cycle_radio"):
			items.append({"id": &"radio", "icon": &"radio", "label": "Radio"})
		items.append({"id": &"recover", "icon": &"unstuck", "label": "Recover"})
		return items
	var action: bool = play != null and play.get("action_mode") == true
	var armed := _armed()
	var in_match: bool = play != null and play.get("tdm_active") == true
	if play != null:
		var has_rifle: bool = play.get("has_rifle") != false
		var title := "Put away" if action else ("Rifle" if has_rifle else "Fists")
		items.append({"id": &"action", "icon": &"rifle", "label": title, "active": action})
	if not in_match and play != null:
		items.append({"id": &"medkit", "icon": &"medkit", "label": "Medkit", "count": play.medkits, "enabled": play.medkits > 0})
		items.append({"id": &"grenade", "icon": &"grenade", "label": "Grenade", "count": play.grenades,
			"enabled": play.grenades > 0 and action})
		var wanted: Variant = play.get("wanted_level")
		if wanted != null and wanted > 0:
			items.append({"id": &"surrender", "icon": &"surrender", "label": "Give up"})
	if armed:
		items.append({"id": &"fire_mode", "icon": &"fire_auto" if play.fire_mode == 0 else &"fire_single",
			"label": "Auto" if play.fire_mode == 0 else "Single"})
		items.append({"id": &"peek_left", "icon": &"peek_left", "label": "Peek left", "active": player.touch_peek_input < 0.0})
		items.append({"id": &"peek_right", "icon": &"peek_right", "label": "Peek right", "active": player.touch_peek_input > 0.0})
	if not action:
		items.append({"id": &"crouch", "icon": &"crouch", "label": "Crouch", "active": player.get("crouching") == true})
	items.append({"id": &"prone", "icon": &"prone", "label": "Prone", "active": player.get("prone") == true})
	items.append({"id": &"talk", "icon": &"talk", "label": "Talk"})
	items.append({"id": &"help", "icon": &"help", "label": "Help", "active": _help_left > 0.0})
	items.append({"id": &"avatar", "icon": &"avatar", "label": "Avatar"})
	items.append({"id": &"view", "icon": &"view", "label": "Third person" if _game != null and _game.get("first_person_view") == true else "First person"})
	if "touch_free_look" in player.camera_pivot:
		items.append({"id": &"look", "icon": &"look", "label": "Free look", "active": player.camera_pivot.touch_free_look})
	items.append({"id": &"unstuck", "icon": &"unstuck", "label": "Unstuck"})
	return items

func _on_wheel_chosen(id: StringName) -> void:
	var play := _play()
	match id:
		&"action":
			play.toggle_action()
		&"medkit":
			play.use_medkit()
		&"grenade":
			play.throw_grenade()
		&"surrender":
			play.surrender()
		&"talk":
			play.talk_nearby()
		&"fire_mode":
			play.toggle_fire_mode()
		&"radio":
			play.cycle_radio()
		&"help":
			_toggle_help()
		&"peek_left":
			player.touch_peek_input = 0.0 if player.touch_peek_input < 0.0 else -1.0
		&"peek_right":
			player.touch_peek_input = 0.0 if player.touch_peek_input > 0.0 else 1.0
		&"crouch":
			_toggle_crouch()
		&"prone":
			_toggle_prone()
		&"avatar":
			_switch_character_touch()
		&"view", &"camera":
			_change_vehicle_camera()
		&"look":
			player.camera_pivot.touch_free_look = not player.camera_pivot.touch_free_look
		&"unstuck":
			_reset_player()
		&"recover":
			if is_instance_valid(_vehicle) and _vehicle.has_method("recover_vehicle"):
				_vehicle.recover_vehicle()
		&"gearbox":
			if is_instance_valid(_vehicle):
				_vehicle.toggle_transmission_mode()

## Help has to be held, which a wheel cannot do, so choosing it holds it for you.
func _toggle_help() -> void:
	if _help_left > 0.0:
		_release_help()
	else:
		_help_left = HELP_HOLD_SECONDS
		Input.action_press("service")

func _release_help() -> void:
	if _help_left > 0.0:
		_help_left = 0.0
		Input.action_release("service")

## Wheel choices that stay on let go when they stop making sense.
func _tick_latches(delta: float) -> void:
	if _help_left > 0.0:
		_help_left = maxf(0.0, _help_left - delta)
		if _help_left <= 0.0:
			Input.action_release("service")
	if player.get("touch_peek_input") != null and player.touch_peek_input != 0.0 and not _armed():
		player.touch_peek_input = 0.0

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

var _tablet_inset_override := false

func set_tablet_ergonomics_inset(enabled: bool) -> void:
	if _tablet_inset_override != enabled:
		_tablet_inset_override = enabled
		if _touch_overlay_enabled:
			_layout_touch()

## The default (uncustomised) layout for this screen, and what the editor shows for it.
func _layout_context(profile: StringName) -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var dpi := float(DisplayServer.screen_get_dpi())
	var units_mm := ClawLayout.units_per_mm(viewport_size, Vector2(DisplayServer.window_get_size()), dpi)
	var tablet := ClawLayout.is_tablet(Vector2(DisplayServer.screen_get_size()), dpi) or _tablet_inset_override
	var safe := ClawLayout.canvas_safe_rect(get_viewport())
	return {
		"rects": ClawLayout.compute(viewport_size, safe, units_mm, tablet, touch_settings.button_scale, touch_settings.left_handed),
		"safe": safe,
		"min_target": ClawLayout.min_target(safe, units_mm),
		"labels": _slot_labels(profile),
		"opacity": touch_settings.opacity,
	}

func _slot_labels(profile: StringName) -> Dictionary:
	return VEHICLE_SLOT_NAMES if profile == HudLayoutProfiles.VEHICLE else SLOT_NAMES

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
			_game.city_life.toast("No rifle yet, find one at Chowrastha")
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

## Shows the buttons this moment needs, and only those (UI_DESIGN.md, "Touch").
func _refresh_touch() -> void:
	if not $TouchControls.visible:
		return
	if _current_profile() != _applied_profile:
		_layout_for_viewport()
	var controls: Control = $TouchControls
	var foot := _on_foot()
	var driving := _driving()
	var flying := _flying()
	var play := _play()
	var action: bool = foot and play != null and play.get("action_mode") == true
	var has_rifle: bool = play == null or play.get("has_rifle") != false
	var owned: Array[int] = []
	if play != null and play.has_method("rifles"):
		owned = play.rifles()
	controls.get_node("Run").visible = foot or flying
	controls.get_node("Jump").visible = foot
	controls.get_node("Enter").visible = foot and (_enter_available or _prompt_usable)
	controls.get_node("Exit").visible = driving
	controls.get_node("Handbrake").visible = driving
	controls.get_node("Camera").visible = driving and not flying
	controls.get_node("GearUp").visible = driving and not flying and _manual_gears
	controls.get_node("GearDown").visible = driving and not flying and _manual_gears
	btn_fire_right.visible = action
	btn_scope.visible = action and has_rifle
	btn_reload.visible = action and _armed()
	btn_crouch.visible = action
	btn_swap.visible = action and owned.size() > 1
	_set_icon(controls.get_node("Run"), &"up" if flying else &"run")
	_set_icon(controls.get_node("Handbrake"), &"down" if flying else &"handbrake")
	_set_lit(controls.get_node("Run"), _run_latched and not flying)
	_set_lit(btn_crouch, player.get("crouching") == true)
	var aiming: bool = player.camera_pivot != null and player.camera_pivot.get("is_aiming") == true
	_set_lit(btn_scope, aiming)
	if is_instance_valid(_scope_overlay) and _scope_overlay.visible != aiming:
		_scope_overlay.visible = aiming
		_scope_overlay.queue_redraw()

func set_coins(amount: int) -> void:
	_collected_coins = maxi(0, amount)

func add_coins(amount: int) -> void:
	_collected_coins += maxi(0, amount)
	readouts.show_coin_delta(maxi(0, amount))

func _build_multiplayer_ui() -> void:
	# Room Banner
	net_room_banner = Label.new()
	net_room_banner.name = "NetRoomBanner"
	net_room_banner.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	net_room_banner.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	net_room_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	net_room_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(net_room_banner)

	# Revive & Loot Tactical Buttons
	btn_revive = _create_tactical_button("BtnRevive", &"", Color(UiTheme.HEALTH, 0.55))
	btn_revive.text = "Revive"
	btn_revive.visible = false
	btn_revive.button_down.connect(func() -> void: touch_revive_pressed = true)
	btn_revive.button_up.connect(func() -> void: touch_revive_pressed = false)

	btn_loot = _create_tactical_button("BtnLoot", &"", Color(UiTheme.ACCENT, 0.55))
	btn_loot.text = "Loot"
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
			net_room_banner.text = "Squad %d" % network_manager.peers.size()
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

