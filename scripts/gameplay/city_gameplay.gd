extends Node3D
## Offline activity/combat layer. Uses the existing map, wallet, modal and save systems.
const Pursuer := preload("res://scripts/gameplay/pursuer.gd")
const CityAssets := preload("res://scripts/gameplay/city_assets.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
var passenger: Node3D
var market: Node3D
var spoken_dialogue := false
var water: Node3D
var extra_vehicles: Array[Node3D] = []
var game: Node
var life: Node
var mission: Dictionary = {}
var _service_visual: Node3D
var _suspect: CharacterBody3D
var _enemies: Array[CharacterBody3D] = []
var _roadblocks: Array[Node3D] = []
var completed := 0
var story_step := 0
var properties: Dictionary = {}
var medkits := 0
var armour := 0.0
var ammo := 24
## Magazine size and reload time. Team Deathmatch sets 30 rounds and 2 s (docs/TDM_DESIGN.md).
var mag_size := 24
var reload_seconds := 1.5
## Set by tdm_local.gd while a Team Deathmatch is running: no crime, no free-roam respawn.
var tdm_active := false
var tdm_local: Node
## A rifle (M416 or AK-47) is looted from the street (Chowrastha) before one can be drawn; saved.
var has_rifle := false
## Which rifles are owned (weapon_catalog.gd ids); read it through rifles(). Empty while has_rifle is
## set means the M416 alone, as older saves and tests have it.
var owned_rifles: Array[int] = []
## Rounds left in each holstered rifle's magazine, by weapon id. A rifle not listed has a full one.
var _magazines: Dictionary = {}
var reserve := 120
var grenades := 3
var action_mode := false
enum FireMode { AUTO, SINGLE }
var fire_mode: FireMode = FireMode.AUTO
var touch_fire_pressed := false
var wanted_level := 0
var heat := 0.0
var escape_time := 0.0
var _crime_time := 0.0
var _spawn_timer := 0.0
var _shot_cooldown := 0.0
var _reload_time := 0.0
var _foot_timer := 0.0
var _income_time := 0.0
var _npc_timer := 0.0
var _npcs: Array[Node] = []
var _marker: MeshInstance3D
var _status: Label
var _crosshair: Label
var _radio: AudioStreamPlayer
var _radio_station := 0
var _audio: Dictionary = {}
var gun_feel: Node
var _last_health := 100.0
var _last_driving := false
var _vehicle_claims: Dictionary = {}

func setup(owner_game: Node) -> void:
	game = owner_game
	life = game.city_life
	name = "CityGameplay"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	water = preload("res://scripts/gameplay/water_system.gd").new()
	add_child(water)
	water.setup(game.get_node("World"))
	game.person.water_system = water
	_build_ui()
	_build_marker()
	gun_feel = preload("res://scripts/gameplay/gun_feel.gd").new()
	add_child(gun_feel)
	gun_feel.setup(game)
	for sound in ["punch", "step", "explosion"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/gameplay/%s.wav" % sound)
		player.volume_db = -16.0
		add_child(player)
		_audio[sound] = player
	_radio = AudioStreamPlayer.new()
	_radio.volume_db = -22.0
	add_child(_radio)
	game.person.health_changed.connect(_health_changed)
	for vehicle in game.vehicles:
		if vehicle.has_method("take_damage"):
			_attach_vehicle_effects(vehicle)
	if life.save_enabled and FileAccess.file_exists(life.save_path):
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(life.save_path))
		if record is Dictionary and record.get("gameplay") is Dictionary:
			restore_progress(record.gameplay)
	_build_pickups()
	market = preload("res://scripts/gameplay/market_street.gd").new()
	add_child(market)
	market.setup(game)
	_refresh_status()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var button := Button.new()
	button.text = "Activities [F7]"
	button.position = Vector2(780, 16)
	button.custom_minimum_size = Vector2(160, 44)
	button.pressed.connect(open_board)
	button.queue_free()
	_status = Label.new()
	_status.position = Vector2(22, 310)
	_status.add_theme_color_override("font_color", Color("edf4f7"))
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_x", 2)
	_status.add_theme_constant_override("shadow_offset_y", 2)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
	if OS.has_feature("mobile") and game and game.hud and game.hud._touch_overlay_enabled:
		_status.visible = false
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 30)
	_crosshair.add_theme_color_override("font_shadow_color", Color.BLACK)
	_crosshair.add_theme_constant_override("shadow_offset_x", 2)
	_crosshair.add_theme_constant_override("shadow_offset_y", 2)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.custom_minimum_size = Vector2(32, 32)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -16
	_crosshair.offset_top = -16
	_crosshair.offset_right = 16
	_crosshair.offset_bottom = 16
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_crosshair)

func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 3.7
	ring.outer_radius = 4.0
	_marker.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd45a")
	material.emission_enabled = true
	material.emission = Color("ffd45a")
	_marker.material_override = material
	_marker.visible = false
	add_child(_marker)

func _unhandled_input(event: InputEvent) -> void:
	if GameplayControls.text_focused(get_viewport()) or game._window_unfocused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F7:
			open_board()
		elif not get_tree().paused and not game.is_map_open():
			match event.keycode:
				KEY_F8: cycle_radio()
				KEY_Y, KEY_R: reload_weapon()
				KEY_2: switch_weapon()
				KEY_X:
					if game.control_state == game.ControlState.ON_FOOT:
						toggle_fire_mode()
				KEY_G: throw_grenade()
				KEY_J: talk_nearby()
				KEY_K:
					if game.control_state == game.ControlState.ON_FOOT:
						use_medkit()
				KEY_P:
					if event.shift_pressed:
						surrender()
					else:
						toggle_action()
				KEY_U: try_vault()
				KEY_L: try_loot_nearby()
	if event is InputEventMouseButton and event.pressed and not get_tree().paused and not game.is_map_open():
		if event.button_index == MOUSE_BUTTON_LEFT:
			attack()

func _process(delta: float) -> void:
	# Drawing the rifle (key 1 or EQUIP) means fighting: switch to ACTION so it fires straight away.
	# Without a looted rifle there is nothing to draw.
	if game.person.is_weapon_equipped() and not has_rifle:
		game.person.set_weapon_equipped(false)
		life.toast("No rifle yet • pick one up at Chowrastha")
	elif not action_mode and game.person.is_weapon_equipped():
		set_action_mode(true)
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	if not get_tree().paused and not game.is_map_open() and action_mode and fire_mode == FireMode.AUTO and _shot_cooldown == 0.0:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or touch_fire_pressed:
			attack()
	if _reload_time > 0.0:
		_reload_time = maxf(0.0, _reload_time - delta)
		if _reload_time == 0.0:
			var count := mini(mag_size - ammo, reserve)
			ammo += count
			reserve -= count
	if not mission.is_empty():
		mission.time -= delta
		if mission.time <= 0.0:
			end_mission(false, "Time expired")
		else:
			_update_mission(delta)
	_update_police(delta)
	_npc_timer -= delta
	if _npc_timer <= 0.0:
		_npc_timer = 0.5
		_npcs = get_tree().get_nodes_in_group("city_residents")
		for npc in _npcs:
			if is_instance_valid(npc) and npc.global_position.distance_to(game.tracked_body().global_position) < 28.0:
				var danger: bool = action_mode and (_shot_cooldown > 0.0 or (game.control_state == game.ControlState.DRIVING and absf(game.active_vehicle.current_speed) > 9.0))
				if danger:
					npc.react_to_danger(game.tracked_body().global_position)
	_income_time += delta
	if _income_time >= 180.0:
		_income_time = 0.0
		if not properties.is_empty():
			game.hud.add_coins(properties.size() * 3)
			life.toast("Property income +%d coins" % (properties.size() * 3))
	var driving: bool = game.control_state == game.ControlState.DRIVING
	if driving and not _last_driving and action_mode:
		var id := str(game.active_vehicle.name)
		if not _vehicle_claims.has(id):
			_vehicle_claims[id] = true
			report_crime(18.0)
			life.toast("Vehicle taken • police alerted")
	_last_driving = driving
	_radio.stream_paused = not driving
	if game.control_state == game.ControlState.ON_FOOT and game.person.is_on_floor() and game.person.velocity.length() > 0.5:
		_foot_timer -= delta
		if _foot_timer <= 0.0:
			_foot_timer = 0.28 if game.person.is_running else 0.45
			_audio.step.pitch_scale = randf_range(0.9, 1.1)
			_audio.step.play()
	_refresh_status()

func _refresh_status() -> void:
	var vehicle := ""
	if game.control_state == game.ControlState.DRIVING and game.active_vehicle.has_method("repair"):
		vehicle = " • Vehicle %d%%" % game.active_vehicle.condition
	_status.text = "Health %d • Armour %d • Coins %d%s\n%s • Ammo %d/%d%s • Grenades %d • [%s]\n%s" % [game.person.health, armour, game.hud.coins_available(), vehicle,
		"ACTION" if action_mode else "EXPLORE", ammo, reserve, " (reloading)" if _reload_time > 0.0 else "", grenades, "AUTO" if fire_mode == FireMode.AUTO else "SINGLE",
		("Wanted " + str(wanted_level) + "/5 • Escape %.0fs" % escape_time) if wanted_level > 0 else "1 Rifle • P Fire mode • B Auto/Single • R Reload • J Talk • F7 Activities"]
	if not mission.is_empty():
		_status.text += "\n%s • %s • %ds" % [mission.title, mission.stage, ceili(mission.time)]
	_crosshair.visible = action_mode and game.control_state == game.ControlState.ON_FOOT and not game.is_map_open()

func _open(title: String) -> VBoxContainer:
	if life.has_modal() or get_tree().paused or game.is_map_open():
		return null
	return life._new_modal(title)

func _button(column: Node, title: String, callback: Callable) -> void:
	life._button(column, title, callback)

func open_board() -> void:
	if tdm_active:
		return
	var column := _open("City activities")
	if column == null:
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 320)
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var info := Label.new()
	info.text = "Jobs follow the GPS and gold checkpoint. Stop inside it.\n1 equip • 2 switch rifle • Click fire/punch • Right-click aim • Y reload\nG grenade • K medkit • Hold O to help\nP surrender • J talk • U vault • F8 radio"
	info.text += "\nInventory: %d medkits • %d businesses • %d jobs completed" % [medkits, properties.size(), completed]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(info)
	_button(list, "Visit market • GPS", func() -> void:
		life.close_modal()
		market.visit())
	_button(list, "Market produce delivery • 12 coins", func() -> void:
		life.close_modal()
		market.start_delivery())
	for kind in ["story", "delivery", "taxi", "race", "ambulance", "firefighter", "vigilante", "gang"]:
		var job: String = kind
		_button(list, "Start " + job.capitalize(), func() -> void:
			life.close_modal()
			start_mission(job))
	if not mission.is_empty():
		_button(list, "Cancel current activity", func() -> void:
			end_mission(false, "Activity cancelled")
			life.close_modal())
	_button(list, "Mode: " + ("Action" if action_mode else "Peaceful exploration"), func() -> void:
		set_action_mode(not action_mode)
		life.close_modal())
	_button(list, "Squad Multiplayer (Host / Join Room)", func() -> void:
		life.close_modal()
		if game.hud and game.hud.has_method("toggle_multiplayer_panel"):
			game.hud.toggle_multiplayer_panel())
	_button(list, "Spoken dialogue: " + ("On" if spoken_dialogue else "Off"), func() -> void:
		spoken_dialogue = not spoken_dialogue
		life.close_modal()
		life.toast("Spoken dialogue " + ("enabled" if spoken_dialogue else "disabled")))
	_button(list, "Repair nearest vehicle • 5 coins", func() -> void: repair_nearby())
	_button(list, "Medkit • 5 coins", func() -> void: buy_supply("medkit"))
	_button(list, "Armour • 8 coins", func() -> void: buy_supply("armour"))
	_button(list, "Ammo • 4 coins", func() -> void: buy_supply("ammo"))
	_button(list, "3 grenades • 6 coins", func() -> void: buy_supply("grenades"))
	_button(list, "Buy local business • 80 coins", func() -> void: buy_property())
	for kind in ["motorcycle", "scooter", "police", "ambulance", "boat", "plane"]:
		var vehicle_kind: String = kind
		_button(list, "Try " + vehicle_kind + " (blockout)", func() -> void:
			life.close_modal()
			spawn_extra_vehicle(vehicle_kind))
	_button(list, "Return to city", life.close_modal)
	_button(column, "Close", life.close_modal)

func _job_points() -> Array[Vector3]:
	var start: Vector3 = game.tracked_body().global_position
	var candidates: Array[Vector3] = []
	for entry: Dictionary in life.targets:
		var p: Vector3 = entry.position
		var distance := start.distance_to(p)
		if distance < 80.0 or distance > 2200.0:
			continue
		var found: Dictionary = game.road_network.find_route(Vector2(start.x, start.z), Vector2(p.x, p.z), RoadNetwork.Mode.DRIVE)
		if found.get("ok", false):
			var points: PackedVector2Array = found.points
			var end: Vector2 = points[points.size() - 1]
			p = Vector3(end.x, _ground_height(end, p.y), end.y)
			var distinct := true
			for previous in candidates:
				if previous.distance_to(p) < 60.0:
					distinct = false
			if distinct:
				candidates.append(p)
		if candidates.size() >= 5:
			break
	return candidates

func start_mission(kind: String) -> bool:
	if tdm_active:
		return false
	if not mission.is_empty():
		life.toast("Finish or cancel your current activity first")
		return false
	if kind not in ["story", "delivery", "taxi", "race", "ambulance", "firefighter", "vigilante", "gang"]:
		return false
	if kind == "story" and story_step >= 3:
		life.toast("All three neighbourhood chapters completed • try repeatable city jobs")
		return false
	if kind in ["vigilante", "gang"] and not action_mode:
		life.toast("Enable Action mode for vigilante activities")
		return false
	var points := _job_points()
	if points.size() < 2:
		life.toast("No reachable activity here. Return to the city roads.")
		return false
	var titles := {"story": "Neighbourhood chapter %d" % (story_step + 1), "delivery": "Local parcel delivery", "taxi": "Taxi fare", "race": "City checkpoint trial", "ambulance": "Medical supply response", "firefighter": "Fire response", "vigilante": "Wanted suspect patrol", "gang": "Gang hideout response"}
	mission = {"kind": kind, "title": titles[kind], "points": points, "index": 0, "stage": "Pickup", "time": 300.0 if kind != "race" else 240.0, "reward": 20 if kind != "race" else 30, "hold": 0.0}
	if kind in ["race", "ambulance", "firefighter", "vigilante", "gang"]:
		mission.stage = "Checkpoint" if kind == "race" else "Respond"
	if kind != "race":
		mission.points = [points[story_step % points.size()] if kind == "story" else points[0], points[(story_step + 1) % points.size()] if kind == "story" else points[1]]
	if kind == "story":
		mission.title = ["Chapter 1: Market opening", "Chapter 2: Clinic supplies", "Chapter 3: Community celebration"][story_step]
		var column := _open(mission.title)
		if column != null:
			var dialogue := Label.new()
			dialogue.text = ["Market organiser: Help us open for the day. Collect the parcel at the first checkpoint and bring it to the next shop.", "Clinic volunteer: We need medical supplies. Collect the package and deliver it to the marked destination.", "Community organiser: One final delivery for our celebration. Collect the decorations and bring them to the gathering."][story_step]
			dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(dialogue)
			_button(column, "Begin chapter", life.close_modal)
			_speak(dialogue.text)
	if kind == "taxi":
		passenger = preload("res://scripts/gameplay/taxi_passenger.gd").new()
		add_child(passenger)
		passenger.setup(game, mission.points[0])
	_set_mission_target()
	life.toast("%s started • follow GPS" % mission.title)
	return true

func _set_mission_target() -> void:
	var at: Vector3 = mission.points[mission.index]
	_marker.global_position = at + Vector3.UP * 0.25
	_marker.show()
	_build_service_scene(at)
	game.navigator.set_destination(Vector2(at.x, at.z), mission.title + " • " + mission.stage)

func _update_mission(delta: float) -> void:
	var at: Vector3 = mission.points[mission.index]
	var body: Node3D = game.tracked_body()
	var near := Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(at.x, at.z)) < 12.0 and absf(body.global_position.y - at.y) < 12.0
	var driving: bool = game.control_state == game.ControlState.DRIVING
	var stopped := not driving or absf(game.active_vehicle.current_speed) < 2.0
	if not near:
		return
	if mission.kind in ["taxi", "race"] and not driving:
		return
	if mission.kind != "race" and not stopped:
		return
	if mission.kind == "taxi" and is_instance_valid(passenger):
		if mission.index == 0:
			if game.active_vehicle is GdkHelicopter or game.active_vehicle.get("kind") in ["motorcycle", "scooter", "boat", "plane"]:
				life.toast("Use a car or tuk-tuk with a passenger seat")
				return
			if passenger.state == "waiting": passenger.board(game.active_vehicle)
			mission.stage = "Passenger boarding • wait"
			if passenger.state != "riding": return
		elif passenger.state == "riding":
			if game.active_vehicle != passenger.vehicle:
				life.toast("Return to the passenger's vehicle")
				return
			passenger.alight()
			mission.stage = "Passenger alighting • wait"
			return
		elif passenger.state != "complete": return
	if mission.kind in ["ambulance", "firefighter"] and mission.index == 0:
		if driving:
			mission.stage = "Exit vehicle and hold O to help"
			return
		mission.stage = "Hold O to " + ("give first aid" if mission.kind == "ambulance" else "extinguish fire")
		if Input.is_action_pressed("service"):
			mission.hold += delta
			if is_instance_valid(_service_visual) and mission.kind == "firefighter":
				_service_visual.scale = Vector3.ONE * maxf(0.1, 1.0 - mission.hold / 5.0)
		else:
			mission.hold = maxf(0.0, mission.hold - delta)
		if mission.hold < 5.0:
			return
		life.toast("First aid complete • deliver patient to the next stop" if mission.kind == "ambulance" else "Fire extinguished • return to dispatch")
	if mission.kind in ["vigilante", "gang"] and mission.index == 0:
		mission.stage = "Stop the armed suspect"
		for enemy in _enemies:
			if is_instance_valid(enemy) and enemy.health > 0.0:
				return
	mission.index += 1
	if mission.index >= mission.points.size():
		end_mission(true)
	else:
		mission.stage = "Checkpoint %d" % (mission.index + 1) if mission.kind == "race" else "Drop-off"
		_set_mission_target()
		life.toast("Pickup complete • next stop marked")

func end_mission(success: bool, reason := "") -> void:
	if mission.is_empty():
		return
	if success:
		game.hud.add_coins(mission.reward)
		completed += 1
		if mission.kind == "story":
			story_step += 1
		life.toast("%s complete • +%d coins" % [mission.title, mission.reward])
	else:
		life.toast(reason)
	mission.clear()
	if is_instance_valid(passenger):
		passenger.queue_free()
		passenger = null
	_clear_service_scene()
	_marker.hide()
	game.navigator.clear()
	life.save_progress()

## P: fire mode on/off. Turning it on draws the rifle when you have one.
func toggle_action() -> void:
	if tdm_active:
		return
	if action_mode:
		set_action_mode(false)
		return
	set_action_mode(true)
	if not has_rifle:
		life.toast("Fire mode on • pick up a rifle at Chowrastha")
	elif game.control_state == game.ControlState.ON_FOOT:
		game.person.set_weapon_equipped(true)

func set_action_mode(enabled: bool) -> void:
	action_mode = enabled
	game.person.combat_mode = enabled
	if not enabled:
		heat = 0.0
		wanted_level = 0
		game.person.set_weapon_equipped(false)
	life.toast("Action mode enabled" if enabled else "Peaceful exploration enabled")

func toggle_fire_mode() -> void:
	fire_mode = FireMode.SINGLE if fire_mode == FireMode.AUTO else FireMode.AUTO
	life.toast("Firing Mode: " + ("FULL AUTO" if fire_mode == FireMode.AUTO else "SINGLE SHOT"))

## The rifles this player can draw: what they have looted (or, in Team Deathmatch, been given).
func rifles() -> Array[int]:
	var owned: Array[int] = []
	if has_rifle:
		owned.append_array(owned_rifles if not owned_rifles.is_empty() else [Weapons.M416])
	return owned

## Adds a rifle to the owned ones; it arrives with a full magazine. True if it was not owned yet.
func give_rifle(id: int) -> bool:
	if not Weapons.is_valid(id) or rifles().has(id):
		return false
	owned_rifles = rifles()
	owned_rifles.append(id)
	has_rifle = true
	_magazines.erase(id)
	return true

## Key 2 or the touch swap button: the next owned rifle comes out.
func switch_weapon() -> bool:
	var owned := rifles()
	if owned.size() < 2 or game.control_state != game.ControlState.ON_FOOT or not GameplayControls.allows(game.person):
		return false
	var next := owned[(owned.find(game.person.weapon_id) + 1) % owned.size()]
	select_rifle(next)
	life.toast(Weapons.display_name(next))
	return true

## Makes `id` the rifle in the hands (drawn if a rifle was out). Each rifle keeps its own magazine;
## a reload in progress is dropped, and the swap takes as long as drawing.
func select_rifle(id: int) -> void:
	if id == game.person.weapon_id:
		return
	_magazines[game.person.weapon_id] = ammo
	ammo = mini(int(_magazines.get(id, mag_size)), mag_size)
	_reload_time = 0.0
	gun_feel.cancel_reload()
	game.person.weapon_reload_time = 0.0
	game.person.set_weapon_model(id)
	_shot_cooldown = maxf(_shot_cooldown, 0.35)

## Every rifle's magazine full again (a Team Deathmatch respawn).
func reset_magazines() -> void:
	_magazines.clear()
	ammo = mag_size

func attack() -> bool:
	if get_tree().paused or game.is_map_open() or not action_mode or _shot_cooldown > 0.0 or _reload_time > 0.0 or game.control_state != game.ControlState.ON_FOOT or not GameplayControls.allows(game.person):
		return false
	if tdm_active and not tdm_local.can_fire():
		return false
	var armed: bool = game.person.is_weapon_equipped()
	if armed and ammo == 0:
		gun_feel.play_dry()
		reload_weapon()
		return false
	var gun := Weapons.stats(game.person.weapon_id)
	_shot_cooldown = (float(gun.auto_interval) if fire_mode == FireMode.AUTO else float(gun.single_interval)) if armed else 0.55
	var damage: float = gun.body_damage if armed else 15.0
	var camera := get_viewport().get_camera_3d()
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var length := 150.0 if armed else 3.0
	if not armed:
		origin = game.person.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, 0xFFFFFFFF, [game.person.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var endpoint := origin + direction * length
	if not hit.is_empty():
		endpoint = hit.position
	# Resolve the camera's target from the actual barrel as well, so peeking
	# cannot shoot through a wall that covers the weapon.
	if armed:
		var muzzle_origin: Vector3 = game.person.weapon_muzzle_position()
		var barrel_query := PhysicsRayQueryParameters3D.create(muzzle_origin, endpoint, 0xFFFFFFFF, [game.person.get_rid()])
		var barrel_hit := get_world_3d().direct_space_state.intersect_ray(barrel_query)
		if not barrel_hit.is_empty():
			hit = barrel_hit
			endpoint = hit.position
	if not hit.is_empty() and hit.get("collider") != null:
		var col: Object = hit.collider
		if tdm_active and col.has_method("tdm_claim_hit"):
			col.tdm_claim_hit(hit.position, origin, game.person.weapon_id)
		elif tdm_active and col.has_method("tdm_dummy_hit"):
			col.tdm_dummy_hit(hit.position, game.person.weapon_id)
		elif col.has_method("take_damage"):
			col.take_damage(damage)
	# Ambient residents use lightweight Node3D actors: test their hit volumes only
	# before the first world collision, preserving wall occlusion.
	var closest: Node3D
	var closest_distance := origin.distance_to(endpoint)
	for npc in get_tree().get_nodes_in_group("city_residents"):
		var center: Vector3 = npc.global_position + Vector3.UP
		var t := (center - origin).dot(direction)
		if t > 0.0 and t < closest_distance and center.distance_to(origin + direction * t) < 0.65:
			if npc.health <= 0.0:
				continue
			closest = npc
			closest_distance = t
	if closest:
		closest.take_damage(damage)
		endpoint = origin + direction * closest_distance
	if armed:
		ammo -= 1
		if tdm_active:
			tdm_local.on_shot_fired()
		gun_feel.on_shot(game.person.weapon_id, game.person.weapon_muzzle_position(), endpoint, hit, closest != null)
		game.person.weapon_kick = gun.kick
		if game.get("network_manager") and game.network_manager.is_active():
			game.network_manager.notify_local_fired()
		var stance_mult: float = 0.3 if game.person.get("prone") == true else (0.6 if game.person.get("crouching") == true else 1.0)
		if game.person.camera_pivot and game.person.camera_pivot.has_method("add_recoil"):
			var kick: Vector2 = gun_feel.recoil_for(gun.recoil * stance_mult)
			game.person.camera_pivot.add_recoil(kick.x, kick.y)
	else:
		_audio.punch.play()
	var character: Node = game.person.get_node_or_null("TestCharacter")
	if character:
		character.set_meta("attack_until", Time.get_ticks_msec() + 300)
	report_crime(8.0 if armed else (12.0 if closest else 0.0))
	return true

func try_loot_nearby() -> bool:
	if game.control_state != game.ControlState.ON_FOOT or not GameplayControls.allows(game.person):
		return false
	var player_pos: Vector3 = game.person.global_position
	for node in get_tree().get_nodes_in_group("loot_crates"):
		if is_instance_valid(node) and node.has_method("collect"):
			if player_pos.distance_to(node.global_position) < 2.5:
				var loot: Dictionary = node.collect(game.person, self)
				life.toast("Looted crate: +%d Ammo, +%d Medkits, +%d Coins" % [loot.get("ammo", 0), loot.get("medkits", 0), loot.get("coins", 0)])
				return true
	return false

func reload_weapon() -> void:
	if game.control_state != game.ControlState.ON_FOOT or not GameplayControls.allows(game.person):
		return
	if not action_mode or ammo >= mag_size or reserve <= 0 or _reload_time > 0.0:
		return
	_reload_time = reload_seconds
	game.person.weapon_reload_time = reload_seconds
	gun_feel.play_reload(reload_seconds)

func throw_grenade() -> bool:
	if tdm_active:
		return false # No grenades in Team Deathmatch (docs/TDM_DESIGN.md).
	if get_tree().paused or game.is_map_open() or not action_mode or grenades <= 0 or game.control_state != game.ControlState.ON_FOOT or not GameplayControls.allows(game.person):
		return false
	grenades -= 1
	var bomb := RigidBody3D.new()
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	visual.mesh = sphere
	bomb.add_child(visual)
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	collider.shape = shape
	bomb.add_child(collider)
	add_child(bomb)
	bomb.global_position = game.person.global_position + Vector3.UP * 1.6
	bomb.add_collision_exception_with(game.person)
	bomb.linear_velocity = -get_viewport().get_camera_3d().global_basis.z * 16.0 + Vector3.UP * 5.0
	get_tree().create_timer(2.0, false).timeout.connect(func() -> void:
		if is_instance_valid(bomb):
			if action_mode:
				explode(bomb.global_position)
			bomb.queue_free())
	return true

func explode(at: Vector3) -> void:
	_audio.explosion.play()
	var actors: Array = game.vehicles + get_tree().get_nodes_in_group("pursuers") + get_tree().get_nodes_in_group("city_residents") + get_tree().get_nodes_in_group("hostiles") + [game.person]
	for actor in actors:
		var distance: float = actor.global_position.distance_to(at)
		if distance < 10.0 and actor.has_method("take_damage"):
			var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, actor.global_position + Vector3.UP)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.collider == actor:
				actor.take_damage(100.0 * (1.0 - distance / 10.0))
	var flash := OmniLight3D.new()
	flash.light_color = Color.ORANGE
	flash.omni_range = 15
	flash.light_energy = 8
	add_child(flash)
	flash.global_position = at
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.4)
	tween.tween_callback(flash.queue_free)
	report_crime(40.0)

func report_crime(amount: float) -> void:
	if tdm_active or not action_mode or amount <= 0.0:
		return
	heat = clampf(heat + amount, 0.0, 100.0)
	wanted_level = mini(5, ceili(heat / 20.0))
	_crime_time = 0.0
	escape_time = 0.0

func visible_to_player(actor: Node3D) -> bool:
	var from := actor.global_position + Vector3.UP * 1.5
	var to: Vector3 = game.tracked_body().global_position + Vector3.UP
	var exclude: Array[RID] = []
	if actor is CollisionObject3D:
		exclude.append(actor.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
	return hit.is_empty() or hit.collider == game.person or hit.collider == game.active_vehicle

func _update_police(delta: float) -> void:
	if wanted_level == 0:
		for block in _roadblocks:
			if is_instance_valid(block):
				block.queue_free()
		_roadblocks.clear()
		return
	if wanted_level >= 4 and _roadblocks.is_empty():
		_build_roadblock()
	_crime_time += delta
	_spawn_timer -= delta
	var cops := get_tree().get_nodes_in_group("pursuers")
	if _spawn_timer <= 0.0 and cops.size() < mini(3, wanted_level):
		_spawn_timer = 5.0
		_spawn_police()
	var seen := false
	for cop in cops:
		if cop.global_position.distance_to(game.tracked_body().global_position) < 65.0 and visible_to_player(cop):
			seen = true
	escape_time = 0.0 if seen or _crime_time < 8.0 else escape_time + delta
	if escape_time >= 20.0:
		heat = maxf(0.0, heat - 20.0)
		wanted_level = ceili(heat / 20.0)
		escape_time = 0.0
		if wanted_level == 0:
			life.toast("Police pursuit escaped")

func _spawn_police() -> void:
	var target: Vector3 = game.tracked_body().global_position
	var snap: Dictionary = game.road_network.snap(Vector2(target.x, target.z) + Vector2(75, 55).rotated(randf() * TAU), RoadNetwork.Mode.DRIVE)
	if snap.is_empty():
		return
	var p: Vector2 = snap.point
	var cop := Pursuer.new()
	cop.game = game
	cop.controller = self
	add_child(cop)
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, target.y + 200.0, p.y), Vector3(p.x, target.y - 200.0, p.y), 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	cop.global_position = hit.position + Vector3.UP if not hit.is_empty() else target + Vector3(65, 2, 0)

func surrender() -> bool:
	if tdm_active:
		return false
	if wanted_level == 0 or game.control_state != game.ControlState.ON_FOOT:
		return false
	var fine := mini(game.hud.coins_available(), wanted_level * 5)
	game.hud.spend_coins(fine)
	wanted_level = 0
	heat = 0.0
	life.toast("Surrendered • fine %d coins" % fine)
	return true

func _vehicle_impact(other: Node, speed: float, _normal: Vector3, _at: Vector3, source: Node) -> void:
	if game.control_state != game.ControlState.DRIVING or game.active_vehicle != source or other == game.person:
		return
	if action_mode and speed > 5.0 and _shot_cooldown <= 0.0:
		report_crime(minf(speed, 15.0))
		_shot_cooldown = 0.6

func _health_changed(value: float, _maximum: float) -> void:
	if tdm_active:
		return # The host owns health in Team Deathmatch; there is no home respawn.
	if value < _last_health and armour > 0.0:
		var absorbed := minf(armour, (_last_health - value) * 0.6)
		armour -= absorbed
		game.person.health += absorbed
	_last_health = game.person.health
	if game.person.health <= 0.0:
		call_deferred("_respawn")

func _respawn() -> void:
	if game.person.health > 0.0:
		return
	if game.control_state != game.ControlState.ON_FOOT:
		game.entry.cancel()
		game.active_vehicle.set_driving_enabled(false)
		game.control_state = game.ControlState.EXITING
		game._finish_exit_vehicle()
	game.person.global_position = game.person.respawn_position
	game.person.velocity = Vector3.ZERO
	game.person.heal_full()
	wanted_level = 0
	heat = 0.0
	var fee := mini(10, game.hud.coins_available())
	game.hud.spend_coins(fee)
	end_mission(false, "Activity ended • recovered at home")
	life.toast("Recovered • medical fee %d coins" % fee)

func buy_supply(kind: String) -> bool:
	var prices := {"medkit": 5, "ammo": 4, "armour": 8, "grenades": 6}
	if not prices.has(kind) or not game.hud.spend_coins(prices[kind]):
		life.toast("Not enough coins")
		return false
	match kind:
		"medkit": medkits += 1
		"ammo": reserve = mini(999, reserve + 48)
		"armour": armour = 100.0
		"grenades": grenades = mini(30, grenades + 3)
	life.toast(kind.capitalize() + " purchased")
	life.save_progress()
	return true

func use_medkit() -> bool:
	if tdm_active:
		return false # Health comes from regeneration only.
	if medkits <= 0 or game.person.health >= game.person.max_health:
		return false
	medkits -= 1
	game.person.heal_full()
	life.toast("Medkit used")
	return true

func repair_nearby() -> bool:
	var car: Node3D = game.active_vehicle if game.control_state == game.ControlState.DRIVING else game._nearest_vehicle()
	if car == null or not car.has_method("repair"):
		life.toast("Stand beside a repairable vehicle")
		return false
	if car.condition >= 100.0:
		life.toast("Vehicle is already fully repaired")
		return false
	if not game.hud.spend_coins(5):
		life.toast("Repair costs 5 coins")
		return false
	car.repair()
	life.toast("Vehicle repaired")
	return true

func buy_property() -> bool:
	var shop: Dictionary = life.nearby_shop()
	if shop.is_empty():
		life.toast("Stand outside a shop to buy that business")
		return false
	var id := str(shop.name)
	if properties.has(id):
		life.toast("You already own this business")
		return false
	if not game.hud.spend_coins(80):
		life.toast("Business costs 80 coins")
		return false
	properties[id] = true
	life.toast("Business purchased • +3 coins every 3 active minutes")
	life.save_progress()
	return true

func talk_nearby() -> bool:
	if game.control_state != game.ControlState.ON_FOOT:
		return false
	var nearest: Node3D
	var distance := 3.0
	for npc in get_tree().get_nodes_in_group("city_residents"):
		var d: float = npc.global_position.distance_to(game.person.global_position)
		if d < distance and npc.health > 0:
			nearest = npc
			distance = d
	if nearest == null:
		life.toast("Stand near a resident to talk")
		return false
	if nearest.has_meta("market_shop") and market:
		market.open_shop(nearest.get_meta("market_shop"))
		return true
	var column := _open("Neighbourhood conversation")
	if column == null:
		return false
	var text := Label.new()
	text.text = "Hello! Local shops need deliveries. Try the Activities board.\nThe market is lively in the day. Drive carefully near crossings."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	_speak(text.text)
	_button(column, "Ask for delivery work", func() -> void:
		life.close_modal()
		start_mission("delivery"))
	_button(column, "Goodbye", life.close_modal)
	return true

func cycle_radio() -> void:
	_radio_station = (_radio_station + 1) % 3
	if _radio_station == 0:
		_radio.stop()
	else:
		_radio.stream = load("res://assets/audio/gameplay/radio_%d.wav" % _radio_station)
		if _radio.stream is AudioStreamWAV:
			_radio.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_radio.play()
	life.toast(["Radio off", "Godavari FM • original electronic loop", "Colony FM • original mellow loop"][_radio_station])

func try_vault() -> bool:
	if tdm_active:
		return false # Vaulting is off in Team Deathmatch: it can catch on props.
	var person: CharacterBody3D = game.person
	if game.control_state != game.ControlState.ON_FOOT or not person.is_on_floor() or not GameplayControls.allows(person):
		return false
	var facing := person.global_basis.z
	var start := person.global_position + Vector3.UP * 0.5
	var low := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + facing * 1.4, 3, [person.get_rid()]))
	if low.is_empty():
		return false
	# Raise and move through the same collision solver; abort when headroom is blocked.
	if person.test_move(person.global_transform, Vector3.UP * 1.1):
		return false
	var raised := person.global_transform
	raised.origin += Vector3.UP * 1.1
	if person.test_move(raised, facing * 1.5):
		return false
	person.global_transform = raised
	person.move_and_collide(facing * 1.5)
	person.velocity.y = 1.5
	return true

func export_progress() -> Dictionary:
	return {"completed": completed, "story_step": story_step, "properties": properties, "medkits": medkits, "armour": armour, "ammo": ammo, "reserve": reserve, "grenades": grenades, "has_rifle": has_rifle,
		"rifles": rifles(), "weapon": game.person.weapon_id}

func restore_progress(record: Dictionary) -> void:
	for key in ["completed", "story_step", "medkits", "ammo", "reserve", "grenades"]:
		var value: Variant = record.get(key)
		if (value is int or value is float) and is_finite(float(value)):
			set(key, int(clampf(float(value), 0, 999)))
	ammo = mini(ammo, 24)
	grenades = mini(grenades, 30)
	has_rifle = record.get("has_rifle") == true
	owned_rifles.clear()
	var saved_rifles: Variant = record.get("rifles")
	if has_rifle and saved_rifles is Array:
		for id: Variant in saved_rifles:
			if (id is int or id is float) and Weapons.is_valid(int(id)) and not owned_rifles.has(int(id)):
				owned_rifles.append(int(id))
	var saved_weapon: Variant = record.get("weapon", Weapons.M416)
	if (saved_weapon is int or saved_weapon is float) and rifles().has(int(saved_weapon)):
		game.person.set_weapon_model(int(saved_weapon))
	var saved_armour: Variant = record.get("armour", 0)
	if (saved_armour is int or saved_armour is float) and is_finite(float(saved_armour)):
		armour = clampf(float(saved_armour), 0, 100)
	var saved: Variant = record.get("properties")
	if saved is Dictionary:
		for key in saved:
			if saved[key] == true and str(key).length() < 160 and properties.size() < 100:
				properties[str(key)] = true

func _ground_height(point: Vector2, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, fallback + 300.0, point.y), Vector3(point.x, fallback - 300.0, point.y), 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else fallback

func spawn_extra_vehicle(kind: String) -> Node3D:
	if tdm_active:
		return null
	if kind not in ["motorcycle", "scooter", "police", "ambulance", "boat", "plane"] or game.control_state != game.ControlState.ON_FOOT:
		return null
	for existing in extra_vehicles:
		if is_instance_valid(existing) and existing.kind == kind:
			game.navigator.set_destination(Vector2(existing.global_position.x, existing.global_position.z), existing.name)
			life.toast("Existing vehicle marked on GPS")
			return existing
	var at: Vector3 = game.person.global_position + game.person.global_basis.z * 5.0 + Vector3.UP
	if kind == "boat":
		var point: Variant = water.boat_spawn()
		if point == null:
			life.toast("No mapped water large enough for a boat in this district")
			return null
		at = point
	else:
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(8.0 if kind == "plane" else 1.2, 3.0, 5.0)
		query.shape = shape
		query.transform.origin = at + Vector3.UP
		query.exclude = [game.person.get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			life.toast("Move to an open area with space for the vehicle")
			return null
	var vehicle := preload("res://scripts/gameplay/arcade_vehicle.gd").new()
	vehicle.kind = kind
	vehicle.water = water
	vehicle.name = "City " + kind.capitalize()
	vehicle.position = at
	vehicle.rotation.y = game.person.rotation.y
	vehicle.add_to_group("enterable_vehicle")
	game.add_child(vehicle)
	vehicle.respawn_position = at
	vehicle.fall_limit = game.person.fall_limit
	vehicle.set_keyboard_input_enabled(false)
	vehicle.set_driving_enabled(false)
	vehicle.set_input_authority(false)
	game.vehicles.append(vehicle)
	game.parked_transforms[vehicle] = vehicle.global_transform
	extra_vehicles.append(vehicle)
	_attach_vehicle_effects(vehicle)
	life.fuel[str(vehicle.name)] = 70.0
	game.navigator.set_destination(Vector2(at.x, at.z), vehicle.name)
	life.toast("Plane: W throttle, I/K pitch, Q/E bank; reach flying speed" if kind == "plane" else "Vehicle ready • walk alongside and press E")
	return vehicle

func _clear_service_scene() -> void:
	if is_instance_valid(_service_visual):
		_service_visual.queue_free()
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()

func _build_service_scene(at: Vector3) -> void:
	_clear_service_scene()
	if mission.index != 0:
		return
	if mission.kind in ["vigilante", "gang"]:
		for i in (3 if mission.kind == "gang" else 1):
			var enemy := preload("res://scripts/gameplay/mission_actor.gd").new()
			enemy.game = game
			enemy.kind = mission.kind
			add_child(enemy)
			enemy.global_position = at + Vector3(i * 2.0, 1.0, 0)
			_enemies.append(enemy)
		_suspect = _enemies[0]
		return
	_service_visual = Node3D.new()
	add_child(_service_visual)
	_service_visual.global_position = at
	if mission.kind == "ambulance":
		CityAssets.stretcher(_service_visual)
		var ambulance := CityAssets.vehicle(_service_visual, "ambulance")
		ambulance.position = Vector3(3,0,0)
		CityAssets.label(_service_visual,"PATIENT • HOLD O FOR FIRST AID",Vector3(0,2.5,0),24)
	elif mission.kind == "firefighter":
		CityAssets.box(_service_visual,Vector3(0,.5,0),Vector3(1.4,1,1),Color("46382e"))
		for i in 5:
			var flame := CityAssets.cylinder(_service_visual,Vector3((i%3-.9)*.4,1.2+(i%2)*.3,0),.2,1.4,Color("ee7823"))
			var material := flame.material_override as StandardMaterial3D
			material.emission_enabled = true
			material.emission = Color("ff5a0a")
		var equipment := CityAssets.extinguisher(_service_visual)
		equipment.position.x = 1.4
		CityAssets.label(_service_visual,"HOLD O TO EXTINGUISH",Vector3(0,3,0),24)
	else:
		CityAssets.box(_service_visual,Vector3(0,.3,0),Vector3(.6,.6,.6),Color("b4864a"))
		CityAssets.label(_service_visual,"PARCEL PICKUP",Vector3(0,1.3,0),24)

func _build_roadblock() -> void:
	var body: Node3D = game.tracked_body()
	var ahead: Vector3 = body.global_position + body.global_basis.z * 55.0
	var snap: Dictionary = game.road_network.snap(Vector2(ahead.x, ahead.z), RoadNetwork.Mode.DRIVE)
	if snap.is_empty():
		return
	var point: Vector2 = snap.point
	var block := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.0, 0.8, 0.5)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	block.add_child(collision)
	CityAssets.barricade(block)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d8a52c")
	visual.material_override = material
	block.add_child(visual)
	add_child(block)
	block.global_position = Vector3(point.x, _ground_height(point, ahead.y) + 0.5, point.y)
	block.rotation.y = body.rotation.y
	var officer := preload("res://scripts/gameplay/resident_details.gd").officer(block)
	officer.position = Vector3(3,-.5,0)
	_roadblocks.append(block)
	life.toast("Police roadblock deployed")

func _build_touch_controls(layer: CanvasLayer) -> void:
	var panel := GridContainer.new()
	panel.columns = 3
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -330
	panel.offset_top = -220
	panel.offset_right = -12
	panel.offset_bottom = -70
	layer.add_child(panel)
	for title in ["Fire", "Equip", "Reload", "Grenade", "Talk", "Medkit", "Vault", "Surrender"]:
		var choice: String = title
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(100, 44)
		button.pressed.connect(func() -> void:
			match choice:
				"Fire": attack()
				"Equip": game.person.set_weapon_equipped(not game.person.is_weapon_equipped())
				"Reload": reload_weapon()
				"Grenade": throw_grenade()
				"Talk": talk_nearby()
				"Medkit": use_medkit()
				"Vault": try_vault()
				"Surrender": surrender()
		)
		panel.add_child(button)
	var help := Button.new()
	help.text = "Hold: help"
	help.button_down.connect(func() -> void: Input.action_press("service"))
	help.button_up.connect(func() -> void: Input.action_release("service"))
	panel.add_child(help)

func _attach_vehicle_effects(vehicle: Node3D) -> void:
	if vehicle.has_signal("impact"):
		vehicle.impact.connect(_vehicle_impact.bind(vehicle))
	var effects := preload("res://scripts/gameplay/vehicle_effects.gd").new()
	effects.vehicle = vehicle
	effects.gameplay = self
	vehicle.add_child(effects)

## Spots around the Chowrastha junction, relative to where the player starts beside it. The rifles placed
## there alternate M416, AK-47, M416, ...
const RIFLE_SPOTS: Array[Vector2] = [Vector2(3, 4), Vector2(-5, 6), Vector2(7, -5), Vector2(-8, -6), Vector2(12, 2),
	Vector2(-12, 1), Vector2(2, -11), Vector2(0, 13), Vector2(-3, -14), Vector2(15, -9)]
const RIFLE_COUNT := 5

## Rifles to pick up around Chowrastha, only on open, level ground: never inside a
## building, a parked car or a wall, and never floating above or sunk below the street.
func _build_weapon_pickups() -> void:
	# Buildings and cars must be in the physics world before the ground is probed.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var origin: Vector3 = game.person.respawn_position
	var space := get_world_3d().direct_space_state
	var blocker := SphereShape3D.new()
	blocker.radius = 0.55
	var placed := 0
	for spot in RIFLE_SPOTS:
		if placed >= RIFLE_COUNT:
			break
		var top := origin + Vector3(spot.x, 15.0, spot.y)
		var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 30.0, 0xFFFFFFFF, [game.person.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.85 or absf(hit.position.y - origin.y) > 2.0:
			continue
		var probe := PhysicsShapeQueryParameters3D.new()
		probe.shape = blocker
		probe.transform = Transform3D(Basis.IDENTITY, hit.position + Vector3.UP * 0.9)
		probe.exclude = [game.person.get_rid()]
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		var pickup := preload("res://scripts/gameplay/weapon_pickup.gd").new()
		pickup.gameplay = self
		const WEAPONS_CYCLE: Array[int] = [Weapons.M416, Weapons.AK47, Weapons.BREN2]
		pickup.weapon_id = WEAPONS_CYCLE[placed % WEAPONS_CYCLE.size()]
		add_child(pickup)
		pickup.global_position = hit.position
		placed += 1

func _build_pickups() -> void:
	_build_weapon_pickups()
	var points: Array[Vector3] = []
	for target: Dictionary in life.targets:
		if target.kind != "token":
			points.append(target.position)
		if points.size() >= 3:
			break
	for i in points.size():
		var pickup := preload("res://scripts/gameplay/supply_pickup.gd").new()
		pickup.kind = ["health", "armour", "ammo"][i]
		pickup.gameplay = self
		add_child(pickup)
		pickup.global_position = points[i] + Vector3(2, 0.8, 0)

func _speak(text: String) -> void:
	if not spoken_dialogue or DisplayServer.get_name() == "headless":
		return
	var voices := DisplayServer.tts_get_voices()
	if voices.is_empty():
		life.toast("No installed system voice • dialogue remains available as text")
		return
	DisplayServer.tts_speak(text, voices[0].id, 60, 1.0, 1.0, 0, true)

