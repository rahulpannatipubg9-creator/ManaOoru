extends Node3D
## A small fictional market activity at verified-clear roadside positions.
const PROP_DIR := "res://assets/models/market_street/"
const RESIDENT := preload("res://scenes/world/pedestrian.tscn")
const PANIPURI := preload("res://assets/models/panipuri_cart/gdk_panipuri_cart_mobile.glb")
var game: Node
var world: Node
var shops: Array[Dictionary] = []
var stalls: Array[Node3D] = []
var keepers: Array[Node3D] = []
var parcel: MeshInstance3D
var _lod_timer := 0.0

func setup(owner_game: Node) -> void:
	game = owner_game
	world = game.get_node("World")
	name = "MarketStreet"
	var center := GeoProjection.world_to_map(game.person.respawn_position)
	var candidates: Array[Dictionary] = world.roadside_spots(center, 40, 6.8, 12.0, ["secondary", "tertiary", "residential", "primary"])
	var first := Vector2.INF
	for spot in candidates:
		var point: Vector2 = spot.position
		if not world.buildings.is_clear(point, 3.5):
			continue
		if first.is_finite() and first.distance_to(point) > 150.0:
			continue
		var blocked := false
		for obstacle: Vector3 in world.street_life.occupied():
			if point.distance_to(Vector2(obstacle.x, obstacle.y)) < 2.6 + obstacle.z:
				blocked = true
				break
		if blocked:
			continue
		if not first.is_finite():
			first = point
		_add_stall(spot, shops.size())
		if shops.size() == 3:
			break
	parcel = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.35, 0.35)
	parcel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a57943")
	parcel.material_override = material
	parcel.hide()
	add_child(parcel)
	print("Market Street: %d clear roadside stalls, %d shopkeepers" % [shops.size(), keepers.size()])

func _prop(file: String, parent: Node3D, at := Vector3.ZERO) -> Node3D:
	var asset := load(PROP_DIR + file + ".glb") as PackedScene
	var visual := asset.instantiate() as Node3D
	parent.add_child(visual)
	visual.position = at
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 180.0
	return visual

func _add_stall(spot: Dictionary, index: int) -> void:
	var stand := Node3D.new()
	stand.name = ["ChaiCorner", "FreshProduce", "StreetSnacks"][index]
	add_child(stand)
	var point: Vector2 = spot.position
	stand.global_position = GeoProjection.map_to_world(point, world.ground_height(point))
	var facing: Vector2 = (spot.direction as Vector2).orthogonal()
	stand.rotation.y = atan2(facing.x, facing.y)
	stalls.append(stand)
	var title: String = ["Market Chai Corner", "Market Fresh Produce", "Market Street Snacks"][index]
	if index == 0:
		_prop("tea_stall", stand)
	elif index == 1:
		_prop("vegetable_cart", stand)
	else:
		var cart := PANIPURI.instantiate() as Node3D
		stand.add_child(cart)
		# The source uses centimetres, matching StreetLifeBuilder.
		cart.scale = Vector3.ONE * 0.01
	_prop("market_shopfront", stand, Vector3(0, 0, -2.0))
	var assets := preload("res://scripts/gameplay/city_assets.gd")
	# Small local details on the fictional stall facade, clear of the walking aisle.
	assets.box(stand,Vector3(0,3.45,-2.1),Vector3(3.6,.15,1.3),Color("bdb49b"))
	assets.cylinder(stand,Vector3(.9,3.9,-2.1),.42,.8,Color("323a40"))
	for x in [-1.55,1.55]:
		assets.box(stand,Vector3(x,2.8,-1.45),Vector3(.05,.7,.05),Color("434b50"))
	assets.box(stand,Vector3(0,3.1,-1.45),Vector3(3.1,.05,.05),Color("434b50"))
	_prop("wooden_stool", stand, Vector3(-1.4, 0, 1.45))
	_prop("wooden_stool", stand, Vector3(-0.8, 0, 1.45))
	_prop("parked_scooter", stand, Vector3(2.4, 0, 0))
	_solid(stand, Vector3(0, 0.8, 0), Vector3(2.5, 1.6, 1.3))
	_solid(stand, Vector3(0, 1.65, -2.0), Vector3(3.4, 3.3, 0.4))
	_solid(stand, Vector3(2.4, 0.7, 0), Vector3(0.6, 1.4, 1.8))
	var entrance: Vector3 = stand.to_global(Vector3(0, 0, 2.1))
	var record := {"name": title, "kind": ["tea", "greengrocer", "fast_food"][index], "position": entrance, "market_id": index}
	shops.append(record)
	world.local_activity.shop_entries.append(record)
	var keeper := RESIDENT.instantiate() as Node3D
	keeper.name = "MarketShopkeeper_%d" % index
	keeper.idle_mode = true
	keeper.talking_mode = true
	keeper.simulation_distance = 180.0
	keeper.set_meta("market_shop", record)
	stand.add_child(keeper)
	keeper.position = Vector3(0, 0, -1.15)
	keeper.ground_sampler = keeper.sample_world_surface.bind(world)
	keepers.append(keeper)
	var visitor := RESIDENT.instantiate() as Node3D
	visitor.name = "MarketCustomer_%d" % index
	visitor.idle_mode = true
	visitor.simulation_distance = 180.0
	visitor.shirt_color = Color("af7737")
	stand.add_child(visitor)
	visitor.position = Vector3(1.0, 0, 1.9)
	visitor.ground_sampler = visitor.sample_world_surface.bind(world)
	var sign := Label3D.new()
	sign.text = title + "\n[E] Browse • Delivery work"
	sign.position = Vector3(0, 3.6, 0)
	sign.font_size = 26
	sign.pixel_size = 0.008
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.visibility_range_end = 55.0
	stand.add_child(sign)

func _solid(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at

func open_shop(record: Dictionary) -> void:
	var life: Node = game.city_life
	if life.has_modal() or game.control_state != game.ControlState.ON_FOOT:
		return
	var column: VBoxContainer = life._new_modal(record.name)
	var wallet: Label = life._header_chip("")
	life._refresh_wallet(wallet)
	life._row(column, "Tea", "1", func() -> void: life._refresh_wallet(wallet, life.purchase("tea")))
	life._row(column, "Snack", "2", func() -> void: life._refresh_wallet(wallet, life.purchase("snack")))
	life._row(column, "Produce delivery", "+12", func() -> void:
		life.close_modal()
		start_delivery())

func visit() -> bool:
	if shops.is_empty():
		game.city_life.toast("Market placement unavailable in this map")
		return false
	var at: Vector3 = shops[0].position
	game.navigator.set_destination(Vector2(at.x, at.z), "Market Chai Corner")
	game.city_life.toast("Market marked on GPS • walk to the counter and press E")
	return true

func start_delivery() -> bool:
	var gameplay: Node = game.gameplay
	if shops.size() < 2 or not gameplay.mission.is_empty():
		game.city_life.toast("Finish or cancel the current activity first")
		return false
	gameplay.mission = {"kind": "market_delivery", "title": "Market produce delivery", "points": [shops[1].position, shops[0].position], "index": 0, "stage": "Collect parcel at Fresh Produce", "time": 180.0, "reward": 12, "hold": 0.0}
	gameplay._set_mission_target()
	game.city_life.toast("Collect a parcel at Fresh Produce • then deliver to Chai Corner")
	return true

func _process(delta: float) -> void:
	if not game or not is_instance_valid(parcel):
		return
	var gameplay: Node = game.gameplay
	if gameplay:
		parcel.visible = not gameplay.mission.is_empty() and gameplay.mission.kind == "market_delivery" and gameplay.mission.index == 1
		if parcel.visible:
			parcel.global_transform = game.person.global_transform * Transform3D(Basis(), Vector3(0, 1.0, -0.4))
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var point: Vector3 = game.tracked_body().global_position
		for stand in stalls:
			stand.visible = stand.global_position.distance_squared_to(point) < 240.0 * 240.0
