extends Node
const Settings := preload("res://scripts/performance/graphics_settings.gd")
var settings := Settings.new()
var game: Node
var _timer := 0.0
var _detail_nodes: Array[GeometryInstance3D] = []
var _base_distances: Dictionary = {}
var _shadow_defaults: Dictionary = {}
var _default_camera_far := 2000.0
var active_ambient_count := 0
var active_ai_count := 0

func setup(owner_game: Node) -> void:
	game = owner_game
	settings.load_from()
	# Cache static detail references once; never scan the whole scene each frame.
	for geometry: GeometryInstance3D in game.get_node("World").find_children("*", "GeometryInstance3D", true, false):
		if geometry.get_parent().name.begins_with("BuildingChunk_"): continue
		# Large terrain/road meshes must remain visible across the district.
		var bounds := geometry.get_aabb()
		if maxf(bounds.size.x, bounds.size.z) > 160.0: continue
		_detail_nodes.append(geometry)
		_base_distances[geometry.get_instance_id()] = geometry.visibility_range_end
	for light: Light3D in game.find_children("*", "Light3D", true, false):
		_shadow_defaults[light] = light.shadow_enabled
	apply_settings()

func apply_settings() -> void:
	settings.sanitize()
	var budget: Dictionary = settings.values
	Engine.max_fps = int(budget.fps)
	get_viewport().scaling_3d_scale = budget.scale
	var buildings = game.get_node("World").buildings
	buildings.apply_view_distance(budget.distance)
	buildings.stream_budget_usec = 1500 if settings.values.distance <= 550.0 else 2500
	for geometry in _detail_nodes:
		if not is_instance_valid(geometry): continue
		var original: float = _base_distances[geometry.get_instance_id()]
		geometry.visibility_range_end = minf(original, budget.distance) if original > 0.0 else budget.distance
	for light in _shadow_defaults:
		if is_instance_valid(light): light.shadow_enabled = _shadow_defaults[light] and budget.shadows
	if game.city_life and game.city_life.environment:
		game.city_life.environment.effects_budget = budget.effects
	_timer = 0.0
	_update_simulation()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not game: return
	_timer = 0.5
	_update_simulation()

func _update_simulation() -> void:
	var budget: Dictionary = settings.values
	var position: Vector3 = game.tracked_body().global_position
	var actors := get_tree().get_nodes_in_group("performance_ambient")
	actors.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(position) < b.global_position.distance_squared_to(position))
	active_ambient_count = 0
	for actor: Node3D in actors:
		# Mission passengers and characters explicitly marked critical keep running.
		if actor.is_in_group("performance_critical") or actor.get_parent().get_script() == preload("res://scripts/gameplay/taxi_passenger.gd"): continue
		var active: bool = actor.global_position.distance_squared_to(position) <= budget.simulation * budget.simulation and active_ambient_count < int(budget.actors)
		actor.set_process(active)
		if not active: actor.hide()
		else: active_ambient_count += 1
	active_ai_count = 0
	for actor: Node3D in get_tree().get_nodes_in_group("hostiles"):
		if actor.get("health") != null and actor.health <= 0.0: continue
		var active: bool = actor.global_position.distance_squared_to(position) <= maxf(180.0, budget.simulation) ** 2
		actor.set_physics_process(active)
		if active: active_ai_count += 1
