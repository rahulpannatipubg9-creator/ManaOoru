extends Node3D

@onready var person: CharacterBody3D = $Player
enum ControlState { ON_FOOT, ENTERING, DRIVING, EXITING }
var hud: CanvasLayer
## Drivable cars are rigid bodies (scripts/vehicle/rigid_vehicle.gd).
var vehicles: Array[PhysicsBody3D] = []
var parked_transforms: Dictionary = {}
var active_vehicle: PhysicsBody3D
var control_state := ControlState.ON_FOOT
@export var enter_distance := 2.5
var exit_speed_limit := 2.0
var _enter_was_pressed := false
var _exit_was_pressed := false
var _interact_was_pressed := false
var _camera_was_pressed := false
var _map_was_pressed := false
var _recover_was_pressed := false
var _character_was_pressed := false
var _pause_was_pressed := false
var _paused := false
var _map_open := false
var _zoom_in_was_pressed := false
var _zoom_out_was_pressed := false
var _orientation_was_pressed := false
var road_network: RoadNetwork
const CameraController := preload("res://scripts/camera/camera_controller.gd")
var first_person_view := false
var navigator: GpsNavigator
const VehicleEntry := preload("res://scripts/vehicle/vehicle_entry.gd")
var entry: VehicleEntry
var _window_unfocused := false
var _input_suspended := false
var _transition_camera: Camera3D
var _transition_target: Camera3D
var _transition_start := Transform3D.IDENTITY
var _transition_elapsed := 1.0
var _last_mouse_mode := Input.MOUSE_MODE_VISIBLE
const CityLifeController := preload("res://scripts/world/city_life.gd")
var city_life: Node3D
var gameplay: Node3D
var performance_controller: Node
var device_performance_manager: Node
var environment_controls: CanvasLayer
var network_manager: Node
## Team Deathmatch (scripts/tactical): the networking session and the on-device gameplay around it.
var tdm_session: Node
var tdm_local: Node

func _ready() -> void:
	# A staged world finishes after this runs; everything below needs it whole.
	if $World.building:
		await $World.built
	var environment := WorldEnvironment.new()
	environment.name = "DayEnvironment"
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color("#91b8cc")
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("#c0cbd2")
	world_environment.ambient_light_energy = 0.30
	world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.tonemap_exposure = 0.78
	# Low-density haze retains street/building contrast; the weather controller
	# increases it for rain without bleaching the clear-day view.
	world_environment.fog_enabled = true
	world_environment.fog_light_color = Color("#a1afb5")
	world_environment.fog_density = 0.00025
	world_environment.fog_sky_affect = 0.0
	environment.environment = world_environment
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#fff6e8")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	add_child(sun)

	hud = preload("res://scenes/ui/hud.tscn").instantiate()
	preload("res://scripts/performance/startup_profile.gd").mark("main: hud = preload('res://scenes/ui/hud.tscn').instanti")
	add_child(hud)
	vehicles.assign(get_tree().get_nodes_in_group("enterable_vehicle"))
	# This node keeps running while paused to handle the map and pause keys; gameplay nodes pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	for gameplay_node: Node in [$World, person] + vehicles:
		gameplay_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	_place_on_real_roadsides()
	preload("res://scripts/performance/startup_profile.gd").mark("main: _place_on_real_roadsides()")
	for candidate in vehicles:
		parked_transforms[candidate] = candidate.global_transform
		candidate.set_keyboard_input_enabled(false)
	_park_all_vehicles()
	preload("res://scripts/performance/startup_profile.gd").mark("main: _park_all_vehicles()")
	active_vehicle = _nearest_vehicle()
	if active_vehicle == null and not vehicles.is_empty():
		active_vehicle = vehicles[0]
	hud.configure_player(person, active_vehicle, self)
	var world := $World
	road_network = RoadNetwork.new(world.map_data)
	preload("res://scripts/performance/startup_profile.gd").mark("main: road_network = RoadNetwork.new(world.map_data)")
	navigator = GpsNavigator.new()
	navigator.name = "GpsNavigator"
	navigator.process_mode = Node.PROCESS_MODE_PAUSABLE
	navigator.setup(road_network, _navigation_state)
	preload("res://scripts/performance/startup_profile.gd").mark("main: navigator.setup(road_network, _navigation_state)")
	add_child(navigator)
	var player_focus := func() -> Vector2: return GeoProjection.world_to_map(tracked_body().global_position)
	world.buildings.focus = player_focus
	if world.roads:
		world.roads.focus = player_focus
	hud.configure_map(world.map_data, world.rendered_building_footprints, world.map_data.landmarks, navigator)
	preload("res://scripts/performance/startup_profile.gd").mark("main: hud.configure_map(world.map_data, world.rendered_b")
	entry = VehicleEntry.new()
	entry.name = "VehicleEntry"
	entry.process_mode = Node.PROCESS_MODE_PAUSABLE
	entry.finished.connect(_on_entry_finished)
	add_child(entry)
	_set_control_authority(person)
	_set_camera_target(person)
	city_life = CityLifeController.new()
	add_child(city_life)
	city_life.setup(self)
	preload("res://scripts/performance/startup_profile.gd").mark("main: city_life.setup(self)")
	gameplay = preload("res://scripts/gameplay/city_gameplay.gd").new()
	add_child(gameplay)
	gameplay.setup(self)
	preload("res://scripts/performance/startup_profile.gd").mark("main: gameplay.setup(self)")
	environment_controls = preload("res://scripts/ui/environment_controls.gd").new()
	add_child(environment_controls)
	environment_controls.setup(self)
	preload("res://scripts/performance/startup_profile.gd").mark("main: environment_controls.setup(self)")
	performance_controller = preload("res://scripts/performance/performance_controller.gd").new()
	add_child(performance_controller)
	performance_controller.setup(self)
	preload("res://scripts/performance/startup_profile.gd").mark("main: performance_controller.setup(self)")
	device_performance_manager = preload("res://scripts/core/device_performance_manager.gd").new()
	device_performance_manager.name = "DevicePerformanceManager"
	add_child(device_performance_manager)
	device_performance_manager.setup(self)
	network_manager = preload("res://scripts/network/network_manager.gd").new()
	add_child(network_manager)
	network_manager.setup(self)
	preload("res://scripts/performance/startup_profile.gd").mark("main: network_manager.setup(self)")
	if hud and hud.has_method("configure_network"):
		hud.configure_network(network_manager)
	tdm_session = preload("res://scripts/tactical/tdm_session.gd").new()
	add_child(tdm_session)
	tdm_local = preload("res://scripts/tactical/tdm_local.gd").new()
	add_child(tdm_local)
	tdm_local.setup(self, tdm_session)
	preload("res://scripts/performance/startup_profile.gd").mark("main: tdm_local.setup(self, tdm_session)")
	hud.multiplayer_panel.tdm_local = tdm_local
	preload("res://scripts/performance/startup_profile.gd").report("main")

## Spawn and parked cars come from roadside spots the world picked on real roads.
func _place_on_real_roadsides() -> void:
	var world := $World
	var fall_limit: float = world.map_data.terrain.min_height - 20.0
	person.fall_limit = fall_limit
	for vehicle in vehicles:
		vehicle.fall_limit = fall_limit
	if not world.player_spawn.is_empty():
		person.global_position = world.player_spawn.position
		person.rotation.y = world.player_spawn.yaw
		person.reset_physics_interpolation()
		person.respawn_position = world.player_spawn.position
	for vehicle in vehicles:
		if vehicle.get("keep_custom_spawn") == true and not world.helicopter_spawn.is_empty():
			var helicopter_spot: Dictionary = world.helicopter_spawn
			vehicle.global_position = helicopter_spot.position
			vehicle.rotation.y = helicopter_spot.yaw
			vehicle.respawn_position = helicopter_spot.position
			if vehicle.has_method("settle_on_ground"):
				vehicle.settle_on_ground()
			vehicle.reset_physics_interpolation()
	for index in mini(vehicles.size(), world.vehicle_spawns.size()):
		if vehicles[index].get("keep_custom_spawn") == true or vehicles[index].name.contains("Bridge"):
			continue
		var spot: Dictionary = world.vehicle_spawns[index]
		vehicles[index].global_position = spot.position
		vehicles[index].rotation.y = spot.yaw
		vehicles[index].respawn_position = spot.position
		vehicles[index].settle_on_ground()
	for vehicle in vehicles:
		if vehicle.name.contains("Bridge"):
			var bridge_spot := Vector3(751.15, -24.8, -3275.0)
			vehicle.global_position = bridge_spot
			vehicle.rotation.y = deg_to_rad(-4.57)
			vehicle.respawn_position = bridge_spot
			if vehicle.has_method("settle_on_ground"):
				vehicle.settle_on_ground()
	for vehicle in vehicles:
		if vehicle.name != "Tuk Tuk" or world.player_spawn.is_empty():
			continue
		var spawn: Dictionary = world.player_spawn
		var yaw: float = spawn.yaw
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		# The detailed Tuk Tuk is the player's vehicle, not ambient traffic. Keep
		# it beside the start and leave a narrow collision gap from the player/car.
		var tuk_position: Vector3 = spawn.position + forward * 2.0 + right * 1.65
		tuk_position.y = world.ground_height(GeoProjection.world_to_map(tuk_position))
		vehicle.global_position = tuk_position
		vehicle.rotation.y = yaw
		if vehicle.has_method("settle_on_ground"):
			vehicle.settle_on_ground()
		vehicle.respawn_position = vehicle.global_position
		vehicle.settle_on_ground()

func _process(_delta: float) -> void:
	if _last_mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_control_inputs()
	_last_mouse_mode = Input.mouse_mode
	_sync_input_context()
	_handle_menu_input()
	_update_camera_transition(_delta)
	if get_tree().paused:
		return
	if _input_suspended:
		return
	if control_state == ControlState.DRIVING:
		_activate_only(active_vehicle)
	elif control_state == ControlState.ON_FOOT:
		_park_all_vehicles()
	var in_match := _in_match()
	var enter_pressed := Input.is_action_pressed("vehicle_enter") or Input.is_key_pressed(KEY_E)
	var exit_pressed := Input.is_action_pressed("vehicle_exit") or Input.is_key_pressed(KEY_F)
	# E is also lean right, so a player aiming round a corner never opens a shop.
	var aiming: bool = person.is_weapon_equipped() and Input.is_action_pressed("aim")
	if enter_pressed and not _enter_was_pressed and control_state == ControlState.ON_FOOT and not in_match and not aiming:
		_try_on_foot_interaction()
	if exit_pressed and not _exit_was_pressed and control_state == ControlState.DRIVING:
		exit_vehicle()
	if Input.is_action_pressed("vehicle_recover") and not _recover_was_pressed:
		if active_vehicle and control_state == ControlState.DRIVING:
			var recovered: Variant = active_vehicle.recover_vehicle()
			_show_control_hint("No clear recovery spot" if recovered == false else "Vehicle recovered")
		elif control_state == ControlState.ON_FOOT and not in_match:
			if person.has_method("recover_person"):
				_show_control_hint("Returned to safe ground" if person.recover_person() else "No clear recovery spot")
	_interact_was_pressed = false
	var camera_pressed := Input.is_action_pressed("vehicle_camera")
	if camera_pressed and not _camera_was_pressed:
		toggle_camera_view()
	_camera_was_pressed = camera_pressed
	_enter_was_pressed = enter_pressed
	_exit_was_pressed = exit_pressed
	_recover_was_pressed = Input.is_action_pressed("vehicle_recover")
	var nearby_vehicle := _nearest_vehicle()
	if in_match:
		pass
	elif control_state == ControlState.ON_FOOT and nearby_vehicle:
		active_vehicle = nearby_vehicle
		hud.set_active_vehicle(active_vehicle)
		hud.set_enter_available(true)
		_set_prompt("[E] Enter %s" % active_vehicle.name)
	elif control_state == ControlState.ON_FOOT:
		hud.set_enter_available(false)
		var shop := _nearby_shop()
		if not shop.is_empty():
			_set_prompt(city_life.prompt_text() if city_life else "[E] Shop")
		elif not _nearby_terminal().is_empty():
			_set_prompt("[E] Bus routes")
		else:
			_set_prompt("")
	# The driver stays visible in the seat, except in first person where the
	# camera sits inside their head.
	if control_state != ControlState.ON_FOOT:
		person.visible = not (control_state == ControlState.DRIVING and (first_person_view or active_vehicle is GdkHelicopter))
	if control_state == ControlState.DRIVING:
		hud.set_speed(absf(active_vehicle.current_speed) * 3.6)
		if active_vehicle.has_method("vehicle_hud_state"):
			var flight_state: Dictionary = active_vehicle.vehicle_hud_state()
			hud.set_gear(flight_state.label, flight_state.rpm, flight_state.automatic)
			hud.set_flight_altitude(float(flight_state.get("altitude", 0.0)))
		else:
			hud.set_gear(active_vehicle.gearbox.label(), active_vehicle.gearbox.rpm, active_vehicle.is_automatic())
		# Silent while moving: the pill only appears when getting out is a real option.
		var airborne: bool = active_vehicle is GdkHelicopter and not active_vehicle._grounded
		var stopped: bool = absf(active_vehicle.current_speed) < 1.0
		_set_prompt("" if not stopped else ("[F]  LAND TO EXIT" if airborne else "[F]  EXIT VEHICLE"))

func _input(event: InputEvent) -> void:
	if get_tree().paused or _input_suspended or GameplayControls.text_focused(get_viewport()) or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	# Free-roam shortcuts stay out of a match: each one would teleport, pause or pull a player out of the fight.
	if _in_match():
		return
	if city_life and key_event.keycode == KEY_F5:
		city_life.open_journal()
		get_viewport().set_input_as_handled()
		return
	if environment_controls and key_event.keycode == KEY_F6:
		environment_controls.open_menu()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F9:
		_teleport_to_godavari_bridge()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_HOME and control_state == ControlState.ON_FOOT:
		_show_control_hint("Returned to safe ground" if person.recover_person() else "No clear recovery spot")
		get_viewport().set_input_as_handled()
		return
	if _is_key(key_event, KEY_E, 101):
		if control_state == ControlState.ON_FOOT:
			# `_process` owns the action edge, avoiding a double purchase from the
			# same press while still consuming the event for the game world.
			get_viewport().set_input_as_handled()
	elif _is_key(key_event, KEY_F, 102):
		if control_state == ControlState.DRIVING:
			exit_vehicle()
			get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_TAB and control_state == ControlState.ON_FOOT:
		_switch_character()
		get_viewport().set_input_as_handled()

func _switch_character() -> void:
	var character := person.get_node_or_null("TestCharacter")
	if character and character.has_method("toggle_character"):
		var selected: String = character.toggle_character()
		_show_control_hint(selected)

func _handle_menu_input() -> void:
	var pause_menu: CanvasLayer = hud.settings_menu.pause_menu
	if pause_menu.owns_keys():
		_pause_was_pressed = Input.is_action_pressed("pause")
		_map_was_pressed = Input.is_action_pressed("map_toggle")
		return
	if city_life and city_life.has_modal():
		var close_pressed := Input.is_action_pressed("pause")
		if close_pressed and not _pause_was_pressed:
			city_life.close_modal()
		_pause_was_pressed = close_pressed
		return
	if GameplayControls.text_focused(get_viewport()):
		return
	var map_pressed := Input.is_action_pressed("map_toggle")
	if map_pressed and not _map_was_pressed:
		set_map_open(not _map_open)
	_map_was_pressed = map_pressed
	var pause_pressed := Input.is_action_pressed("pause")
	if pause_pressed and not _pause_was_pressed:
		if _map_open:
			set_map_open(false)
		else:
			if _in_match() and tdm_local.has_method("toggle_menu"):
				tdm_local.toggle_menu()
			else:
				pause_menu.open_menu()
	_pause_was_pressed = pause_pressed
	var zoom_in := Input.is_action_pressed("minimap_zoom_in")
	var zoom_out := Input.is_action_pressed("minimap_zoom_out")
	var orientation := Input.is_action_pressed("minimap_orientation")
	if not get_tree().paused:
		if zoom_in and not _zoom_in_was_pressed:
			hud.minimap.change_zoom(1)
		if zoom_out and not _zoom_out_was_pressed:
			hud.minimap.change_zoom(-1)
		if orientation and not _orientation_was_pressed:
			hud.minimap.toggle_orientation()
	_zoom_in_was_pressed = zoom_in
	_zoom_out_was_pressed = zoom_out
	_orientation_was_pressed = orientation

## Opens or closes the full-screen map. Gameplay is paused while it is open so
## no person or vehicle input leaks through, and resumes exactly where it was.
func set_map_open(value: bool) -> void:
	if value == _map_open:
		return
	_map_open = value
	if city_life:
		city_life.set_map_visibility(value)
	_paused = false
	pause_tree(value)
	# The map covers the screen, so skip rendering the 3D world behind it.
	get_viewport().disable_3d = value
	hud.set_full_map_open(value)
	hud.set_interaction_prompt("")
	_update_mouse_mode()

func is_map_open() -> bool:
	return _map_open

## A live Team Deathmatch never pauses: the match runs on the host and the other players keep moving.
func pause_tree(value: bool) -> void:
	get_tree().paused = value and not (tdm_local != null and tdm_local.in_match)

func _set_menu_paused(value: bool) -> void:
	_paused = value
	pause_tree(value)
	hud.set_interaction_prompt("Paused" if value else "")
	_update_mouse_mode()

## Hosting or joining usually happens from the pause screen; a match must never start paused.
func prepare_for_match() -> void:
	_paused = false
	get_tree().paused = false
	hud.set_interaction_prompt("")
	_update_mouse_mode()

func refresh_mouse_mode() -> void:
	_update_mouse_mode()

func _in_match() -> bool:
	return tdm_local != null and tdm_local.in_match

## The lobby, end screen and in-match menu need a cursor, and clicks on them must not fire the rifle.
func _match_needs_cursor() -> bool:
	return _in_match() and tdm_local.has_method("needs_cursor") and tdm_local.needs_cursor()

func _update_mouse_mode() -> void:
	if OS.has_feature("android"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused or _match_needs_cursor() else Input.MOUSE_MODE_CAPTURED
	_clear_control_inputs()

func _notification(what: int) -> void:
	# Android rarely sends a close request: it pauses the app or asks to go back instead.
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_APPLICATION_PAUSED] and is_instance_valid(city_life):
		city_life.save_progress()
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_unfocused = true
		GameplayControls.blocked = true
		_clear_control_inputs()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_unfocused = false

func _clear_control_inputs() -> void:
	GameplayControls.clear_held()
	if is_instance_valid(person):
		person.set_touch_move_input(Vector2.ZERO)
		person.set_touch_run_pressed(false)
	for vehicle in vehicles:
		vehicle.set_touch_move_input(Vector2.ZERO)
		vehicle.set_touch_run_pressed(false)
	if hud and hud.has_method("clear_touch_inputs"):
		hud.clear_touch_inputs()

func _sync_input_context() -> void:
	var text := GameplayControls.text_focused(get_viewport())
	var cursor := _match_needs_cursor()
	var suspended := _window_unfocused or text or get_tree().paused or cursor
	if suspended and not _input_suspended:
		_clear_control_inputs()
	_input_suspended = suspended
	GameplayControls.blocked = suspended
	if get_tree().paused:
		GameplayControls.mode = GameplayControls.Mode.PAUSED
	elif text or _window_unfocused or cursor:
		GameplayControls.mode = GameplayControls.Mode.UI_FOCUSED
	elif control_state == ControlState.ON_FOOT:
		GameplayControls.mode = GameplayControls.Mode.ON_FOOT
	elif control_state == ControlState.DRIVING:
		GameplayControls.mode = GameplayControls.Mode.FLYING_HELICOPTER if active_vehicle is GdkHelicopter else GameplayControls.Mode.DRIVING_CAR
	else:
		GameplayControls.mode = GameplayControls.Mode.TRANSITION

## The body the camera, minimap and GPS follow: the car from the moment the person gets in.
func tracked_body() -> Node3D:
	if active_vehicle and control_state in [ControlState.ENTERING, ControlState.DRIVING]:
		return active_vehicle
	return person

func vehicle_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var tracked := tracked_body()
	for vehicle in vehicles:
		if vehicle != tracked:
			markers.append({"position": GeoProjection.world_to_map(vehicle.global_position),
				"heading": MapCanvas.heading_of(vehicle)})
	return markers

func _navigation_state() -> Dictionary:
	var driving := control_state in [ControlState.ENTERING, ControlState.DRIVING]
	return {
		"position": GeoProjection.world_to_map(tracked_body().global_position),
		"mode": RoadNetwork.Mode.DRIVE if driving else RoadNetwork.Mode.WALK,
	}

func _is_key(event: InputEventKey, keycode: Key, unicode: int) -> bool:
	return event.keycode == keycode or event.physical_keycode == keycode or event.unicode == unicode

func _park_all_vehicles() -> void:
	for candidate in vehicles:
		candidate.set_input_authority(false)
		candidate.set_driving_enabled(false)
		candidate.set_keyboard_input_enabled(false)

func _activate_only(selected: PhysicsBody3D) -> void:
	GameplayControls.owner_id = selected.get_instance_id()
	for candidate in vehicles:
		var is_selected := candidate == selected
		candidate.set_input_authority(is_selected)
		candidate.set_driving_enabled(is_selected)
		candidate.set_keyboard_input_enabled(is_selected)

func _nearby_shop() -> Dictionary:
	if city_life:
		return city_life.nearby_shop()
	var world := $World
	if world.local_activity == null:
		return {}
	return world.local_activity.nearest_shop(person.global_position)

func _nearby_terminal() -> Dictionary:
	var world := $World
	if world.bus_station == null:
		return {}
	return world.bus_station.nearest_terminal(person.global_position)

func _try_on_foot_interaction() -> void:
	if city_life and city_life.inside_shop:
		city_life.interact()
		return
	var nearby_vehicle := _nearest_vehicle()
	if nearby_vehicle != null:
		enter_vehicle(nearby_vehicle)
		return
	if city_life and city_life.interact():
		return
	var shop := _nearby_shop()
	if not shop.is_empty():
		if hud.spend_coins(1):
			_show_control_hint("Purchased")
		else:
			_show_control_hint("Need 1 coin")
		return
	var terminal := _nearby_terminal()
	if not terminal.is_empty():
		_show_control_hint("Mancherial, Ramagundam, Karimnagar")

## V switches every camera between first and third person, so the choice
## carries over when getting in or out of a vehicle.
func toggle_camera_view() -> void:
	first_person_view = not first_person_view
	var mode := CameraController.ViewMode.FIRST_PERSON if first_person_view else CameraController.ViewMode.THIRD_PERSON
	for node: Node3D in [person] + vehicles:
		var camera := node.get_node_or_null("CameraPivot")
		if camera and camera.has_method("set_view_mode"):
			camera.set_view_mode(mode)

func _toggle_camera_shoulder() -> void:
	var target: Node3D = active_vehicle if control_state == ControlState.DRIVING else person
	var camera := target.get_node_or_null("CameraPivot") as Node3D
	if camera and camera.has_method("toggle_shoulder"):
		camera.toggle_shoulder()

## Action feedback goes to the one toast queue; the prompt pill only says what a key will do next.
func _show_control_hint(message: String) -> void:
	if city_life:
		city_life.toast(message)

func _teleport_to_godavari_bridge() -> void:
	var bridge_target := Vector3(751.15, -24.8, -3275.0)
	var bridge_yaw := deg_to_rad(-4.57)
	var current_pos: Vector3 = active_vehicle.global_position if (control_state == ControlState.DRIVING and active_vehicle) else person.global_position

	# If already near the bridge (within 1,500m), teleport back to Chowrastha
	if current_pos.distance_to(bridge_target) < 1500.0:
		var chowrastha_target: Vector3 = $World.player_spawn.get("position", Vector3(120, 1.2, -105))
		var chowrastha_yaw: float = float($World.player_spawn.get("yaw", 0.0))
		if control_state == ControlState.DRIVING and active_vehicle:
			active_vehicle.global_position = chowrastha_target
			active_vehicle.rotation = Vector3(0.0, chowrastha_yaw, 0.0)
			active_vehicle.linear_velocity = Vector3.ZERO
			active_vehicle.angular_velocity = Vector3.ZERO
			active_vehicle.respawn_position = chowrastha_target
			if active_vehicle.has_method("settle_on_ground"):
				active_vehicle.settle_on_ground()
			_show_control_hint("Back at Chowrastha")
		elif control_state == ControlState.ON_FOOT and person:
			person.global_position = chowrastha_target
			person.rotation.y = chowrastha_yaw
			_show_control_hint("Back at Chowrastha")
	else:
		if control_state == ControlState.DRIVING and active_vehicle:
			active_vehicle.global_position = bridge_target
			active_vehicle.rotation = Vector3(0.0, bridge_yaw, 0.0)
			active_vehicle.linear_velocity = Vector3.ZERO
			active_vehicle.angular_velocity = Vector3.ZERO
			active_vehicle.respawn_position = bridge_target
			if active_vehicle.has_method("settle_on_ground"):
				active_vehicle.settle_on_ground()
			_show_control_hint("At Godavari bridge")
		elif control_state == ControlState.ON_FOOT and person:
			# Also bring the active vehicle to the bridge approach so the player can drive immediately!
			if active_vehicle:
				active_vehicle.global_position = bridge_target
				active_vehicle.rotation = Vector3(0.0, bridge_yaw, 0.0)
				active_vehicle.linear_velocity = Vector3.ZERO
				active_vehicle.angular_velocity = Vector3.ZERO
				active_vehicle.respawn_position = bridge_target
				if active_vehicle.has_method("settle_on_ground"):
					active_vehicle.settle_on_ground()
			person.global_position = bridge_target + Vector3(2.5, 0.2, 0.0)
			person.rotation.y = bridge_yaw
			_show_control_hint("At Godavari bridge")

func _set_prompt(message: String) -> void:
	hud.set_interaction_prompt(message)

func enter_vehicle(vehicle_override: PhysicsBody3D = null) -> void:
	if tdm_local != null and tdm_local.in_match:
		return # No vehicles in Team Deathmatch.
	var nearby_vehicle := vehicle_override if vehicle_override != null else _nearest_vehicle()
	if control_state != ControlState.ON_FOOT or nearby_vehicle == null or not _is_vehicle_available(nearby_vehicle):
		return
	active_vehicle = nearby_vehicle
	_clear_control_inputs()
	hud.set_active_vehicle(active_vehicle)
	control_state = ControlState.ENTERING
	person.set_movement_enabled(false)
	_set_control_authority(null)
	person.set_collision_enabled(false)
	person.velocity = Vector3.ZERO
	_set_weapon_visible(false)
	# Walk to the driver's door, open it, climb in, shut it; _on_entry_finished hands over control.
	entry.begin_enter(person, active_vehicle)
	_set_camera_target(active_vehicle)
	$HUD.set_vehicle_mode(true)

func exit_vehicle() -> void:
	if control_state != ControlState.DRIVING or active_vehicle == null:
		return
	if absf(active_vehicle.current_speed) > exit_speed_limit:
		_show_control_hint("Slow down before exiting")
		return
	if active_vehicle.has_method("can_exit_safely") and not active_vehicle.can_exit_safely():
		_show_control_hint("Land before exiting")
		return
	var exit_position: Variant = _safe_exit_position()
	if exit_position == null:
		_show_control_hint("No space to exit")
		return
	parked_transforms[active_vehicle] = active_vehicle.global_transform
	control_state = ControlState.EXITING
	_set_control_authority(null)
	active_vehicle.set_driving_enabled(false)
	active_vehicle.velocity = Vector3.ZERO
	person.set_movement_enabled(false)
	person.visible = true
	# Door opens, the driver climbs out to the exit spot, door shuts.
	entry.begin_exit(exit_position)
	_set_camera_target(person)
	$HUD.set_vehicle_mode(false)

func _on_entry_finished(entered: bool) -> void:
	if entered:
		_finish_enter_vehicle()
	else:
		_finish_exit_vehicle()

## An equipped weapon stays out of sight while the person is in a car.
func _set_weapon_visible(value: bool) -> void:
	var weapon := person.get_node_or_null("Weapon") as Node3D
	if weapon:
		weapon.visible = value

func _finish_enter_vehicle() -> void:
	if control_state != ControlState.ENTERING:
		return
	control_state = ControlState.DRIVING
	_activate_only(active_vehicle)
	if active_vehicle.has_method("vehicle_hud_state"):
		$HUD.show_helicopter_controls_hint()
	else:
		$HUD.show_vehicle_controls_hint()

func _finish_exit_vehicle() -> void:
	if control_state != ControlState.EXITING:
		return
	control_state = ControlState.ON_FOOT
	_clear_control_inputs()
	person.set_movement_enabled(true)
	person.set_collision_enabled(true)
	_set_weapon_visible(true)
	_set_control_authority(person)
	parked_transforms[active_vehicle] = active_vehicle.global_transform

func _safe_exit_position() -> Variant:
	var basis := active_vehicle.global_transform.basis
	# Driver's side first: the side the seat is on.
	var seat := active_vehicle.global_transform.affine_inverse() * entry.seat_transform(active_vehicle).origin
	var driver_side := 1.0 if seat.x > 0.05 else -1.0
	var candidates := [
		active_vehicle.global_position + basis.x * 2.6 * driver_side,
		active_vehicle.global_position - basis.x * 2.6 * driver_side,
		active_vehicle.global_position - basis.z * 2.8,
		active_vehicle.global_position + basis.z * 2.8,
	]
	for candidate in candidates:
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.0, candidate + Vector3.DOWN * 6.0, person.collision_mask, [person.get_rid(), active_vehicle.get_rid()])
		var floor_hit := person.get_world_3d().direct_space_state.intersect_ray(ray)
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).angle_to(Vector3.UP) > person.floor_max_angle:
			continue
		var grounded: Vector3 = candidate
		grounded.y = floor_hit.position.y + 0.03
		if _is_exit_position_clear(grounded):
			return grounded
	return null

func _is_exit_position_clear(candidate: Vector3) -> bool:
	# The person's shape is disabled while driving, so test_move would always report clear.
	var collision_shape := person.get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	# Lift the probe slightly so resting on the road does not count as blocked.
	query.transform = Transform3D(collision_shape.global_transform.basis, candidate + collision_shape.position + Vector3.UP * 0.15)
	query.exclude = [person.get_rid(), active_vehicle.get_rid()]
	return person.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _set_control_authority(controller: Node) -> void:
	GameplayControls.owner_id = controller.get_instance_id() if controller else -1
	person.set_input_authority(controller == person)
	for candidate in vehicles:
		candidate.set_input_authority(controller == candidate)

func _set_camera_target(target: Node3D) -> void:
	var old_camera := get_viewport().get_camera_3d()
	for node in [person] + vehicles:
		var camera: Camera3D = node.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if camera:
			camera.current = node == target
			if node == target and old_camera and old_camera != camera:
				_transition_start = old_camera.global_transform
				_transition_target = camera
				_transition_elapsed = 0.0
	if _transition_target and _transition_elapsed == 0.0:
		if not _transition_camera:
			_transition_camera = Camera3D.new()
			_transition_camera.name = "TransitionCamera"
			add_child(_transition_camera)
		_transition_camera.global_transform = _transition_start
		_transition_camera.current = true

func _update_camera_transition(delta: float) -> void:
	if not _transition_camera or not is_instance_valid(_transition_target) or _transition_elapsed >= 0.4:
		return
	_transition_elapsed += delta
	var blend := smoothstep(0.0, 1.0, minf(_transition_elapsed / 0.4, 1.0))
	_transition_camera.global_transform = _transition_start.interpolate_with(_transition_target.global_transform, blend)
	_transition_camera.fov = _transition_target.fov
	if _transition_elapsed >= 0.4:
		_transition_target.current = true

func _nearest_vehicle() -> PhysicsBody3D:
	var closest: PhysicsBody3D
	var closest_distance := enter_distance
	for candidate in vehicles:
		if not is_instance_valid(candidate) or not _is_vehicle_available(candidate):
			continue
		var distance := minf(person.global_position.distance_to(_door_position(candidate, -1.0)),
			person.global_position.distance_to(_door_position(candidate, 1.0)))
		if distance <= closest_distance:
			closest = candidate
			closest_distance = distance
	return closest

func _door_position(vehicle: PhysicsBody3D, side: float) -> Vector3:
	if vehicle.has_method("entry_door_position"):
		return vehicle.entry_door_position(side)
	var half_width: Variant = vehicle.get("entry_half_width")
	var door_offset: float = 1.45
	if half_width is float and half_width > 0.0:
		door_offset = float(half_width) + 0.35
	return vehicle.global_transform * Vector3(door_offset * side, 0.1, 0.0)

func _is_vehicle_available(vehicle: PhysicsBody3D) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return false
	if control_state == ControlState.DRIVING and vehicle == active_vehicle:
		return false
	return true
