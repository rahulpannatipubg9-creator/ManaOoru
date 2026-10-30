class_name CityLife
extends Node3D
## Offline city activities, commerce, discovery journal and versioned progress.
const EnvironmentController := preload("res://scripts/world/city_environment.gd")
const CommunityController := preload("res://scripts/world/city_community.gd")
const Interior := preload("res://scripts/world/city_shop_interior.gd")
const SAVE_PATH := "user://city_life_v1.json"
const SAVE_VERSION := 1
var environment: Node3D
var community: Node3D
var targets: Array[Dictionary] = []
var discoveries: Dictionary = {}
var achievements: Dictionary = {}
var inventory := {"tea": 0, "snack": 0, "fuel": 0}
var fuel: Dictionary = {}
var energy := 80.0
var save_enabled := true
var save_path := SAVE_PATH
var inside_shop := false
var _game: Node
var _world: Node
var _ui: CanvasLayer
var _bar: Label
var _modal: PanelContainer
var _modal_root: ColorRect
var _shop_feedback: Label
var _interior: Node3D
var _inside_record: Dictionary = {}
var _return_transform := Transform3D.IDENTITY
var _return_respawn := Vector3.ZERO
var _return_fall_limit := -100.0
var _return_first_person := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _timer := 0.0
var _save_timer := 0.0
var _last_wallet := -1
var _last_vehicle_position := Vector3.ZERO
var _last_vehicle: Node3D
var _fuel_stops: Array[Dictionary] = []
var _intro_time := 1.0
var _loaded_progress := false
var _interior_cooldown := 0.0
var _toast: Label
var _toast_timer := 0.0

func setup(game: Node) -> void:
	_game = game
	_world = game.get_node("World")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "CityLife"
	save_enabled = DisplayServer.get_name() != "headless" and "--city-life-no-save" not in OS.get_cmdline_user_args()
	_game.hud.set_coins(8)
	for vehicle: Node3D in game.vehicles:
		fuel[str(vehicle.name)] = 70.0
	_loaded_progress = load_progress()
	community = CommunityController.new()
	add_child(community)
	community.setup(_world)
	environment = EnvironmentController.new()
	add_child(environment)
	environment.setup(game)
	_interior = Interior.new()
	add_child(_interior)
	_interior.build()
	_build_fuel_stops()
	_build_targets()
	_build_ui()
	_last_wallet = _game.hud.coins_available()
	_last_vehicle_position = game.tracked_body().global_position
	_refresh_bar()

func _process(delta: float) -> void:
	if _intro_time > 0.0:
		_intro_time -= delta
		if _intro_time <= 0.0:
			toast("Welcome back • E to interact • F5 City journal" if _loaded_progress else "Welcome home • 8 starter coins • E to interact • F5 City journal")
	_toast_timer = maxf(0.0, _toast_timer - delta)
	_toast.visible = _toast_timer > 0.0
	_interior_cooldown = maxf(0.0, _interior_cooldown - delta)
	if inside_shop:
		var local: Vector3 = _interior.to_local(_game.person.global_position)
		if _interior_cooldown == 0.0 and (local.z > 3.25 or absf(local.x) > 3.7 or local.z < -3.8):
			leave_interior()
		elif absf(_game.person.global_position.y - _interior.global_position.y) > 10.0:
			leave_interior(false)
	energy = maxf(0.0, energy - delta * (0.06 if _game.person.is_running else 0.008))
	_timer += delta
	_save_timer += delta
	if _timer < 0.4:
		return
	_timer = 0.0
	_update_fuel()
	_check_discoveries()
	_refresh_bar()
	if _save_timer > 30.0 or _last_wallet != _game.hud.coins_available():
		_save_timer = 0.0
		_last_wallet = _game.hud.coins_available()
		save_progress()

func _update_fuel() -> void:
	var vehicle: Node3D = _game.active_vehicle
	if _game.control_state == _game.ControlState.DRIVING and vehicle != null and not vehicle is GdkHelicopter:
		if _last_vehicle == vehicle:
			var distance := vehicle.global_position.distance_to(_last_vehicle_position)
			if distance < 100.0:
				fuel[str(vehicle.name)] = maxf(0.0, float(fuel.get(str(vehicle.name), 70.0)) - distance * 0.0025)
		_last_vehicle = vehicle
		_last_vehicle_position = vehicle.global_position
	# Fuel is a casual economy meter; reserve mode never strands the player.

func nearby_shop() -> Dictionary:
	if inside_shop:
		return _inside_record
	var entry: Dictionary = _world.local_activity.nearest_shop(_game.person.global_position, 4.0)
	if not entry.is_empty():
		return entry
	var nearest: Dictionary = {}
	var best := 5.0
	for stop: Dictionary in _fuel_stops:
		var distance: float = _game.person.global_position.distance_to(stop.position)
		if distance < best:
			best = distance
			nearest = stop
	return nearest

func prompt_text() -> String:
	if inside_shop:
		return "[E] LEAVE SHOP" if _interior.to_local(_game.person.global_position).z > 1.4 else "[E] BROWSE COUNTER"
	var shop := nearby_shop()
	return "[E] %s • %s" % [str(shop.name).to_upper(), "REFUEL" if str(shop.get("kind", "")) == "fuel" else "BROWSE SHOP"] if not shop.is_empty() else ""

func interact() -> bool:
	if inside_shop and _interior.to_local(_game.person.global_position).z > 1.4:
		leave_interior()
		return true
	var shop := nearby_shop()
	if shop.is_empty():
		return false
	open_shop(shop)
	return true

func purchase(product: String) -> bool:
	var prices := {"tea": 1, "snack": 2, "fuel": 3}
	if not prices.has(product) or not _game.hud.spend_coins(prices[product]):
		return false
	inventory[product] = int(inventory.get(product, 0)) + 1
	if product == "tea":
		energy = minf(100.0, energy + 15.0)
		_game.person.health = minf(_game.person.max_health, _game.person.health + 10.0)
	elif product == "snack":
		energy = minf(100.0, energy + 30.0)
		_game.person.health = minf(_game.person.max_health, _game.person.health + 20.0)
	else:
		var vehicle: Node3D = _last_vehicle if _last_vehicle != null else _game.active_vehicle
		if vehicle != null:
			fuel[str(vehicle.name)] = minf(100.0, float(fuel.get(str(vehicle.name), 70.0)) + 35.0)
	_game.person.health_changed.emit(_game.person.health, _game.person.max_health)
	_refresh_bar()
	save_progress()
	return true

func _buy(product: String) -> void:
	var success := purchase(product)
	_shop_feedback.text = "%s purchased • %d coins left" % [product.capitalize(), _game.hud.coins_available()] if success else "Not enough coins • explore for rewards"

func enter_interior(shop: Dictionary) -> void:
	if inside_shop:
		return
	close_modal()
	_return_transform = _game.person.global_transform
	_return_respawn = _game.person.respawn_position
	_return_fall_limit = _game.person.fall_limit
	_return_first_person = _game.first_person_view
	_inside_record = shop.duplicate()
	_interior.global_position = _return_transform.origin + Vector3.DOWN * 35.0
	_interior.title.text = str(shop.name).to_upper()
	inside_shop = true
	_interior.set_active(true)
	environment.indoors = true
	_game.person.global_position = _interior.global_position + Vector3(0, 0.12, 1.5)
	_game.person.velocity = Vector3.ZERO
	_game.person.respawn_position = _game.person.global_position
	_game.person.fall_limit = _interior.global_position.y - 20.0
	_game.person.reset_physics_interpolation()
	_interior_cooldown = 1.0
	if not _game.first_person_view:
		_game.toggle_camera_view()
	toast("%s • Browse at the counter • Walk through the door to leave" % str(shop.name))

func leave_interior(teleport := true) -> void:
	if not inside_shop:
		return
	if teleport:
		_game.person.global_transform = _return_transform
		_game.person.velocity = Vector3.ZERO
		_game.person.reset_physics_interpolation()
	_game.person.respawn_position = _return_respawn
	_game.person.fall_limit = _return_fall_limit
	inside_shop = false
	_interior.set_active(false)
	environment.indoors = false
	_interior.position.y = -1000.0
	if _game.first_person_view != _return_first_person:
		_game.toggle_camera_view()
	toast("Back on the street")

func _build_fuel_stops() -> void:
	for poi: Dictionary in _world.map_data.pois:
		if str(poi.kind) != "fuel":
			continue
		var road: Dictionary = _world.signage._nearest_road(poi.position, 80.0)
		if road.is_empty():
			continue
		var sign_side := 1.0 if (poi.position - road.point).dot(road.normal) >= 0.0 else -1.0
		var p: Vector2 = road.point + road.normal * sign_side * (float(road.half_width) + 4.8)
		if not _world.buildings.is_clear(p, 2.0) or _world._is_on_any_road(p, 1.0):
			continue
		var at := GeoProjection.map_to_world(p, _world.ground_height(p))
		var title := str(poi.name) if not str(poi.name).is_empty() else "Local fuel stop"
		_fuel_stops.append({"name": title, "kind": "fuel", "position": at})
		var pump := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.65, 1.4, 0.50)
		pump.mesh = box
		pump.position = at + Vector3.UP * 0.7
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b74f36")
		pump.material_override = material
		add_child(pump)
		var label := Label3D.new()
		label.text = "FUEL\n[E]"
		label.font_size = 32
		label.pixel_size = 0.008
		label.position.y = 0.95
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pump.add_child(label)
		if _fuel_stops.size() >= 6:
			break

func _build_targets() -> void:
	for entry: Dictionary in community.identity_markers:
		_add_target(entry.name, entry.position, "landmark")
	for landmark: Dictionary in _world.map_data.landmarks:
		if targets.size() >= 10:
			break
		var title := str(landmark.name)
		if "ambedkar" in title.to_lower() or "temple" in title.to_lower() or "bus" in title.to_lower():
			_add_target(title, GeoProjection.map_to_world(landmark.position, _world.ground_height(landmark.position)), "landmark")
	# A reachable rooftop viewpoint on an existing broad, low building. It uses
	# the generated roof height; no staircase or real-world viewpoint is invented.
	for i in _world.buildings.footprints.size():
		var points: PackedVector2Array = _world.buildings.footprints[i]
		var rect := Rect2(points[0], Vector2.ZERO)
		var center := Vector2.ZERO
		for p in points:
			center += p
			rect = rect.expand(p)
		center /= points.size()
		var style: Dictionary = _world.buildings._styles[i]
		if center.length() < 700 and rect.size.x > 14 and rect.size.y > 14 and int(style.floors) <= 4 and Geometry2D.is_point_in_polygon(center, points):
			_add_target("Rooftop panorama", Vector3(center.x, float(style.base) + int(style.floors) * 3.0 + 0.3, center.y), "rooftop")
			break
	var spots: Array[Dictionary] = _world.roadside_spots(Vector2(315.6, -334.6), 8, 3.9, 60.0, ["residential", "unclassified", "tertiary"])
	for i in spots.size():
		var p: Vector2 = spots[i].position
		_add_target("Hidden town token %d" % (i + 1), GeoProjection.map_to_world(p, _world.ground_height(p)), "token")

func _add_target(title: String, at: Vector3, kind: String) -> void:
	for target in targets:
		if target.name == title or Vector2(target.position.x, target.position.z).distance_to(Vector2(at.x, at.z)) < 12.0:
			return
	var id := "%s@%.0f,%.0f" % [title, at.x, at.z]
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16 if kind == "token" else 0.22
	sphere.height = sphere.radius * 2.0
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#e7bc54")
	material.emission_enabled = true
	material.emission = Color("#ac7b22")
	marker.material_override = material
	marker.position = at + Vector3.UP * 1.4
	marker.visibility_range_end = 16.0 if kind == "token" else 70.0
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	marker.visible = not discoveries.has(id)
	if kind != "token":
		var label := Label3D.new()
		label.text = title
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		label.pixel_size = 0.009
		label.position.y = 0.65
		label.visibility_range_end = 45.0
		marker.add_child(label)
	targets.append({"id": id, "name": title, "position": at, "kind": kind, "marker": marker})

func _check_discoveries() -> void:
	if inside_shop:
		return
	var point: Vector3 = _game.tracked_body().global_position
	for target: Dictionary in targets:
		if discoveries.has(target.id):
			continue
		var radius := 2.3 if target.kind == "token" else 10.0
		if Vector2(point.x, point.z).distance_to(Vector2(target.position.x, target.position.z)) <= radius and absf(point.y - target.position.y) < 4.0:
			discover(target.id)

func discover(id: String) -> bool:
	if discoveries.has(id):
		return false
	for target: Dictionary in targets:
		if target.id != id:
			continue
		discoveries[id] = true
		target.marker.visible = false
		_game.hud.add_coins(3 if target.kind == "token" else 5)
		toast("Discovered: %s • +%d coins" % [target.name, 3 if target.kind == "token" else 5])
		if discoveries.size() >= 3 and not achievements.has("local_explorer"):
			achievements.local_explorer = true
			_game.hud.add_coins(10)
			toast("Local explorer • 3 discoveries • +10 bonus coins")
		if environment.night > 0.7:
			_award("night_walker", "Night walker")
		if environment.rain > 0.4:
			_award("monsoon_explorer", "Monsoon explorer")
		save_progress()
		return true
	return false

func _award(id: String, title: String) -> void:
	if achievements.has(id):
		return
	achievements[id] = true
	_game.hud.add_coins(3)
	toast("%s • +3 coins" % title)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	var panel := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.08, 0.9)
	background.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", background)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -210
	panel.offset_right = 210
	panel.offset_top = 70
	panel.offset_bottom = 130
	_ui.add_child(panel)
	var row := VBoxContainer.new()
	panel.add_child(row)
	_bar = Label.new()
	_bar.add_theme_color_override("font_color", Color("edf4f7"))
	_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar.add_theme_font_size_override("font_size", 14)
	row.add_child(_bar)
	var buttons := HBoxContainer.new()
	row.add_child(buttons)
	buttons.hide()
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -350
	_toast.offset_right = 350
	_toast.offset_top = 140
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_color_override("font_color", Color("#ffe6a1"))
	_toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	_toast.add_theme_constant_override("shadow_offset_x", 2)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_ui.add_child(_toast)

func _refresh_bar() -> void:
	if _bar == null:
		return
	var vehicle: Node3D = _game.active_vehicle
	var fuel_text := ""
	if vehicle != null and not vehicle is GdkHelicopter:
		fuel_text = " • Fuel %d%%" % int(fuel.get(str(vehicle.name), 70.0))
	_bar.text = "%s • %s • Energy %d%s" % [environment.clock_text(), "Rain" if environment.rain > 0.2 else "Clear", int(energy), fuel_text]

func toast(text: String) -> void:
	if _toast:
		_toast.text = text
		_toast_timer = 5.0

func has_modal() -> bool:
	return is_instance_valid(_modal)

func _new_modal(title: String) -> VBoxContainer:
	close_modal()
	_mouse_before = Input.mouse_mode
	_game._clear_control_inputs()
	_game.get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_modal_root = ColorRect.new()
	_modal_root.color = Color(0.02, 0.03, 0.045, 0.78)
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_modal_root)
	_modal = PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.08, 0.98)
	background.set_corner_radius_all(12)
	background.border_color = Color(0.2, 0.38, 0.47)
	background.set_border_width_all(1)
	_modal.add_theme_stylebox_override("panel", background)
	var theme := Theme.new()
	theme.set_color("font_color", "Label", Color("edf4f7"))
	theme.set_color("font_color", "Button", Color("edf4f7"))
	_modal.theme = theme
	_modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_modal.offset_left = -235
	_modal.offset_right = 235
	_modal.offset_top = -245
	_modal.offset_bottom = 245
	_modal_root.add_child(_modal)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_modal.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 22)
	column.add_child(heading)
	return column

func close_modal() -> void:
	if not has_modal():
		return
	_modal_root.queue_free()
	_modal = null
	_modal_root = null
	_game.get_tree().paused = false
	_game._clear_control_inputs()
	Input.mouse_mode = _mouse_before
	_game._sync_input_context()

func open_shop(shop: Dictionary) -> void:
	if shop.has("market_id") and _game.gameplay and _game.gameplay.market:
		_game.gameplay.market.open_shop(shop)
		return
	if has_modal() or _game.control_state != _game.ControlState.ON_FOOT:
		return
	var column := _new_modal(str(shop.name))
	_shop_feedback = Label.new()
	_shop_feedback.text = "Wallet: %d coins" % _game.hud.coins_available()
	column.add_child(_shop_feedback)
	_button(column, "Tea • 1 coin • +15 energy", func() -> void: _buy("tea"))
	_button(column, "Snack • 2 coins • +30 energy", func() -> void: _buy("snack"))
	if str(shop.get("kind", "")) in ["fuel", "car_wash"]:
		_button(column, "Refuel • 3 coins • +35% fuel", func() -> void: _buy("fuel"))
	if not inside_shop:
		_button(column, "Step inside", func() -> void: enter_interior(shop))
	_button(column, "Back to street" if not inside_shop else "Back to counter", close_modal)

func open_journal() -> void:
	if has_modal() or _game.get_tree().paused:
		return
	var column := _new_modal("Your Godavarikhani journal")
	var summary := Label.new()
	summary.text = "%d discoveries • %d coins • %d achievements\nExplore three places for a 10-coin bonus." % [discoveries.size(), _game.hud.coins_available(), achievements.size()]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 190
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for target: Dictionary in targets:
		if target.kind == "token" and not discoveries.has(target.id):
			continue
		var record: Dictionary = target
		_button(list, ("✓ " if discoveries.has(target.id) else "○ ") + str(target.name), func() -> void:
			close_modal()
			_game.navigator.set_destination(Vector2(record.position.x, record.position.z), record.name)
			toast("GPS set: %s" % record.name))
	for entry: Dictionary in _world.local_activity.shop_entries + _fuel_stops:
		var shop: Dictionary = entry
		_button(list, "Shop: " + str(shop.name), func() -> void:
			close_modal()
			_game.navigator.set_destination(Vector2(shop.position.x, shop.position.z), shop.name)
			toast("Shop route set: %s" % shop.name))
	var times := HBoxContainer.new()
	column.add_child(times)
	for value: int in [8, 17, 21]:
		var h := value
		_button(times, "Wait until %02d:00" % h, func() -> void: environment.set_hour(h))
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = environment.ambience.volume
	volume.tooltip_text = "City ambience volume"
	volume.value_changed.connect(func(value: float) -> void: environment.ambience.volume = value)
	column.add_child(volume)
	_button(column, "Return to city", close_modal)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func save_progress() -> bool:
	if not save_enabled:
		return false
	var record := {"version": SAVE_VERSION, "coins": _game.hud.coins_available(), "energy": energy, "discoveries": discoveries,
		"achievements": achievements, "inventory": inventory, "fuel": fuel}
	if _game.get("gameplay") != null:
		record["gameplay"] = _game.gameplay.export_progress()
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record))
	file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak"))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) == OK

func load_progress() -> bool:
	if not save_enabled:
		return false
	var parsed := _read_save(save_path)
	if parsed.is_empty():
		if FileAccess.file_exists(save_path):
			# Corrupt or from a newer build: move it aside so the next autosave cannot overwrite it.
			push_warning("Unreadable save kept as %s.rejected" % save_path)
			DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".rejected"))
		parsed = _read_save(save_path + ".bak")
		if parsed.is_empty():
			return false
		# city_gameplay reads the gameplay block from save_path, so restore the file as well.
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path + ".bak"), ProjectSettings.globalize_path(save_path))
	_game.hud.set_coins(int(clampf(_safe_number(parsed.get("coins"), 8.0), 0, 999999)))
	energy = clampf(_safe_number(parsed.get("energy"), 80.0), 0, 100)
	for key: String in ["discoveries", "achievements"]:
		var source: Variant = parsed.get(key)
		if source is Dictionary:
			var cleaned := {}
			for id in source:
				if source[id] == true and str(id).length() < 200:
					cleaned[str(id)] = true
			set(key, cleaned)
	var saved_inventory: Variant = parsed.get("inventory")
	if saved_inventory is Dictionary:
		for key: String in ["tea", "snack", "fuel"]:
			inventory[key] = int(clampf(_safe_number(saved_inventory.get(key), 0.0), 0, 9999))
	var saved_fuel: Variant = parsed.get("fuel")
	if saved_fuel is Dictionary:
		for key: String in fuel:
			fuel[key] = clampf(_safe_number(saved_fuel.get(key), 70.0), 0, 100)
	return true

## The record at `path`, or empty if it is missing, corrupt or newer than this build.
## When SAVE_VERSION goes up, migrate older records here, one version at a time.
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != SAVE_VERSION:
		return {}
	return parsed

func _safe_number(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback

func set_map_visibility(map_open: bool) -> void:
	_ui.visible = not map_open
