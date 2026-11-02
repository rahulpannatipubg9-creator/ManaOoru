class_name CityScenarios
extends Node3D

## Purposeful traffic and authentic city life scenarios in Godavarikhani & Ramagundam:
## 1. WAG-9 electric freight locomotive hauling BOXN coal wagons along railway tracks.
## 2. Traditional wooden naavalu (country boats) and woven teppalu (coracles) at Godavari river shore.
## 3. MLA camp office VIP convoy traveling in disciplined formation with police escort.
## 4. Authentic district life: market browse/buy, hospital drop-off, petrol bunk queue,
##    chai stall tea gathering, stadium runners, and open-gym squats.

var _world: Node
var _data: MapData

# --- Railway Coal Train ---
var _train_track: PackedVector3Array = PackedVector3Array()
var _track_cum_lengths: PackedFloat32Array = PackedFloat32Array()
var _total_track_length := 0.0
var _train_distance := 0.0
var _train_speed := 11.5 # ~41 km/h freight speed
var _train_root: Node3D
var _locomotive: Node3D
var _wagons: Array[Node3D] = []
var _train_audio: AudioStreamPlayer3D

# --- MLA Convoy ---
var _convoy_root: Node3D
var _convoy_vehicles: Array[Node3D] = []
var _convoy_route: PackedVector3Array = PackedVector3Array()
var _convoy_cum_lengths: PackedFloat32Array = PackedFloat32Array()
var _convoy_total_length := 0.0
var _convoy_distance := 0.0
var _convoy_speed := 9.0 # ~32 km/h city escort pace

func build(world: Node, data: MapData) -> void:
	name = "CityScenarios"
	_world = world
	_data = data
	
	_build_coal_train()
	_build_waterfront_craft()
	_build_vip_convoy()
	_build_city_vignettes()

# ==============================================================================
# 1. WAG-9 Electric Locomotive & BOXN Coal Train
# ==============================================================================
func _build_coal_train() -> void:
	if _data.railways.is_empty():
		return
	
	# Find longest continuous track alignment
	var longest_idx := 0
	var longest_len := 0.0
	for i in _data.railways.size():
		var r: PackedVector2Array = _data.railways[i]
		var l := 0.0
		for j in range(1, r.size()):
			l += r[j - 1].distance_to(r[j])
		if l > longest_len:
			longest_len = l
			longest_idx = i
	
	var raw_track: PackedVector2Array = _data.railways[longest_idx]
	if raw_track.size() < 2:
		return
	
	_train_track.clear()
	_track_cum_lengths.clear()
	_track_cum_lengths.append(0.0)
	var accumulated := 0.0
	
	for i in raw_track.size():
		var map_pt: Vector2 = raw_track[i]
		var ground: float = _world.ground_height(map_pt)
		var world_pt := GeoProjection.map_to_world(map_pt, ground + 0.75) # Rail deck height
		_train_track.append(world_pt)
		if i > 0:
			accumulated += _train_track[i - 1].distance_to(world_pt)
			_track_cum_lengths.append(accumulated)
	
	_total_track_length = accumulated
	if _total_track_length < 150.0:
		return
	
	_train_root = Node3D.new()
	_train_root.name = "CoalTrain"
	add_child(_train_root)
	
	# Create Indian Railways WAG-9 Electric Locomotive
	_locomotive = _create_wag9_loco()
	_train_root.add_child(_locomotive)
	
	# Create 8 BOXN coal hopper wagons
	for w_idx in 8:
		var wagon := _create_boxn_wagon(w_idx)
		_train_root.add_child(wagon)
		_wagons.append(wagon)
	
	# Train wheel clatter audio
	_train_audio = AudioStreamPlayer3D.new()
	_train_audio.name = "TrainClatterAudio"
	_train_audio.unit_size = 28.0
	_train_audio.max_distance = 180.0
	_train_audio.volume_db = -2.0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.4
	_train_audio.stream = gen
	_locomotive.add_child(_train_audio)
	_train_audio.play()

func _create_wag9_loco() -> Node3D:
	var loco := Node3D.new()
	loco.name = "WAG9_Locomotive"
	
	# Emerald Green WAG-9 body (20.5m x 3.1m x 3.9m)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.1, 3.8, 20.5)
	body.mesh = box
	var green_mat := StandardMaterial3D.new()
	green_mat.albedo_color = Color("#184c39") # Authentic Indian Railways freight green
	green_mat.roughness = 0.55
	body.material_override = green_mat
	body.position.y = 2.4
	loco.add_child(body)
	
	# Cream center stripe
	var stripe := MeshInstance3D.new()
	var stripe_box := BoxMesh.new()
	stripe_box.size = Vector3(3.14, 0.45, 20.2)
	stripe.mesh = stripe_box
	var cream_mat := StandardMaterial3D.new()
	cream_mat.albedo_color = Color("#efebe1")
	stripe.material_override = cream_mat
	stripe.position.y = 2.35
	loco.add_child(stripe)
	
	# Yellow warning buffer beam at cabs
	for cab_z in [-10.2, 10.2]:
		var beam := MeshInstance3D.new()
		var beam_box := BoxMesh.new()
		beam_box.size = Vector3(2.9, 0.65, 0.3)
		beam.mesh = beam_box
		var yellow_mat := StandardMaterial3D.new()
		yellow_mat.albedo_color = Color("#cca015")
		beam.material_override = yellow_mat
		beam.position = Vector3(0.0, 1.2, cab_z)
		loco.add_child(beam)
		
		# Headlight
		var light := SpotLight3D.new()
		light.position = Vector3(0.0, 3.2, cab_z)
		light.rotation.y = PI if cab_z > 0 else 0.0
		light.spot_range = 75.0
		light.spot_angle = 32.0
		light.light_energy = 2.5
		light.light_color = Color("#fff4dd")
		light.shadow_enabled = false
		loco.add_child(light)
	
	# Dual pantographs on roof
	for panto_z in [-6.5, 6.5]:
		var panto := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(1.8, 0.45, 1.4)
		panto.mesh = p_box
		var steel_mat := StandardMaterial3D.new()
		steel_mat.albedo_color = Color("#822822") # Oxide red frame
		steel_mat.metallic = 0.8
		panto.material_override = steel_mat
		panto.position = Vector3(0.0, 4.45, panto_z)
		loco.add_child(panto)
	
	return loco

func _create_boxn_wagon(index: int) -> Node3D:
	var wagon := Node3D.new()
	wagon.name = "BOXN_Wagon_%02d" % (index + 1)
	
	# Oxide Red steel body (10.2m x 3.1m x 3.2m)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.1, 2.9, 10.2)
	body.mesh = box
	var oxide_mat := StandardMaterial3D.new()
	oxide_mat.albedo_color = Color("#642621") # Indian Railways BOXN oxide red
	oxide_mat.roughness = 0.75
	body.material_override = oxide_mat
	body.position.y = 2.1
	wagon.add_child(body)
	
	# Heap of Singareni lump coal on top
	var coal := MeshInstance3D.new()
	var coal_box := BoxMesh.new()
	coal_box.size = Vector3(2.8, 0.65, 9.4)
	coal.mesh = coal_box
	var coal_mat := StandardMaterial3D.new()
	coal_mat.albedo_color = Color("#121214") # Black coal
	coal_mat.roughness = 0.95
	coal.material_override = coal_mat
	coal.position.y = 3.65
	wagon.add_child(coal)
	
	return wagon

# ==============================================================================
# 2. Godavari Waterfront Craft (Naavalu & Teppalu)
# ==============================================================================
func _build_waterfront_craft() -> void:
	var river_root := Node3D.new()
	river_root.name = "GodavariWaterfrontCraft"
	add_child(river_root)
	
	# Authentic Godavari river shore coordinates near bridge south bank
	var shore_base := Vector3(720.0, -25.2, -3295.0)
	
	# Spawn 3 wooden naavalu (traditional Telangana country fishing boats)
	var boat_offsets := [
		Vector3(-42.0, 0.0, -12.0),
		Vector3(-15.0, 0.0, -28.0),
		Vector3(35.0, 0.0, -18.0)
	]
	for b_idx in boat_offsets.size():
		var boat := _create_naava(b_idx)
		boat.position = shore_base + boat_offsets[b_idx]
		boat.rotation.y = randf_range(-0.4, 0.4)
		river_root.add_child(boat)
	
	# Spawn 4 teppalu (traditional circular woven bamboo coracles)
	var coracle_offsets := [
		Vector3(-55.0, 0.2, -5.0),
		Vector3(-32.0, -0.1, -19.0),
		Vector3(8.0, 0.15, -8.0),
		Vector3(52.0, 0.05, -14.0)
	]
	for c_idx in coracle_offsets.size():
		var coracle := _create_teppa(c_idx)
		coracle.position = shore_base + coracle_offsets[c_idx]
		river_root.add_child(coracle)

func _create_naava(index: int) -> Node3D:
	var boat := Node3D.new()
	boat.name = "Naava_CountryBoat_%02d" % (index + 1)
	
	# Hull (narrow double-ended wooden boat: 5.6m length, 1.3m beam, 0.6m depth)
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.6, 5.6)
	hull.mesh = box
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#5a3c26") # Weathered teak/sal timber
	wood_mat.roughness = 0.8
	hull.material_override = wood_mat
	boat.add_child(hull)
	
	# Thwarts (cross seating benches)
	for z_pos in [-1.5, 0.0, 1.5]:
		var seat := MeshInstance3D.new()
		var s_box := BoxMesh.new()
		s_box.size = Vector3(1.2, 0.08, 0.25)
		seat.mesh = s_box
		seat.material_override = wood_mat
		seat.position = Vector3(0.0, 0.22, z_pos)
		boat.add_child(seat)
	
	# Bamboo oar (peddha gunpam)
	var oar := MeshInstance3D.new()
	var oar_cyl := CylinderMesh.new()
	oar_cyl.top_radius = 0.03
	oar_cyl.bottom_radius = 0.03
	oar_cyl.height = 3.2
	oar.mesh = oar_cyl
	var bamboo_mat := StandardMaterial3D.new()
	bamboo_mat.albedo_color = Color("#b39b62")
	oar.material_override = bamboo_mat
	oar.rotation = Vector3(0.3, 0.5, 0.8)
	oar.position = Vector3(0.5, 0.4, 0.3)
	boat.add_child(oar)
	
	return boat

func _create_teppa(index: int) -> Node3D:
	var coracle := Node3D.new()
	coracle.name = "Teppa_Coracle_%02d" % (index + 1)
	
	# Circular bowl hull (2.1m diameter, 0.55m height)
	var hull := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 0.85
	cyl.height = 0.55
	hull.mesh = cyl
	var tar_mat := StandardMaterial3D.new()
	tar_mat.albedo_color = Color("#22201d") # Tarred woven waterproof hide
	tar_mat.roughness = 0.9
	hull.material_override = tar_mat
	coracle.add_child(hull)
	
	# Bamboo rim (round lip)
	var rim := MeshInstance3D.new()
	var rim_cyl := CylinderMesh.new()
	rim_cyl.top_radius = 1.10
	rim_cyl.bottom_radius = 1.06
	rim_cyl.height = 0.08
	rim.mesh = rim_cyl
	var bamboo_mat := StandardMaterial3D.new()
	bamboo_mat.albedo_color = Color("#a8905b")
	rim.material_override = bamboo_mat
	rim.position.y = 0.25
	coracle.add_child(rim)
	
	return coracle

# ==============================================================================
# 3. MLA Camp Office VIP Convoy
# ==============================================================================
func _build_vip_convoy() -> void:
	# Find a major long road connecting to NTPC Road / Rajiv Rahadari
	var road_candidate: Dictionary = {}
	for road in _data.roads:
		if RoadStyle.is_major(road.kind) and road.points.size() >= 4:
			var l := 0.0
			for k in range(1, road.points.size()):
				l += road.points[k - 1].distance_to(road.points[k])
			if l > 450.0:
				road_candidate = road
				break
	
	if road_candidate.is_empty():
		return
	
	_convoy_route.clear()
	_convoy_cum_lengths.clear()
	_convoy_cum_lengths.append(0.0)
	var acc := 0.0
	var pts: Array = road_candidate.points
	for i in pts.size():
		var pt: Vector2 = pts[i]
		var gh: float = _world.ground_height(pt)
		var wpt := GeoProjection.map_to_world(pt, gh + 0.15)
		_convoy_route.append(wpt)
		if i > 0:
			acc += _convoy_route[i - 1].distance_to(wpt)
			_convoy_cum_lengths.append(acc)
	
	_convoy_total_length = acc
	if _convoy_total_length < 200.0:
		return
	
	_convoy_root = Node3D.new()
	_convoy_root.name = "MLAVIPConvoy"
	add_child(_convoy_root)
	
	# Convoy composition:
	# 0: Lead Police Pilot Car (White + red/blue lightbar)
	# 1: Black Executive Sedan 1
	# 2: Black Executive Sedan 2
	# 3: VIP Central Heavy SUV (Pearl White)
	# 4: Black Executive Sedan 3
	# 5: Black Executive Sedan 4
	# 6: Rear Police Escort Car
	var configs := [
		{"type": "police", "color": Color("#f4f4f4"), "name": "Pilot_PoliceCar"},
		{"type": "sedan",  "color": Color("#1b1c1e"), "name": "Escort_Sedan_01"},
		{"type": "sedan",  "color": Color("#1b1c1e"), "name": "Escort_Sedan_02"},
		{"type": "vip_suv","color": Color("#f2f0eb"), "name": "VIP_Principal_SUV"},
		{"type": "sedan",  "color": Color("#1b1c1e"), "name": "Escort_Sedan_03"},
		{"type": "sedan",  "color": Color("#1b1c1e"), "name": "Escort_Sedan_04"},
		{"type": "police", "color": Color("#f4f4f4"), "name": "Rear_PoliceCar"}
	]
	
	for cfg in configs:
		var v := _create_convoy_vehicle(cfg)
		_convoy_root.add_child(v)
		_convoy_vehicles.append(v)

func _create_convoy_vehicle(cfg: Dictionary) -> Node3D:
	var v := Node3D.new()
	v.name = cfg.name
	var is_suv: bool = cfg.type == "vip_suv"
	var is_police: bool = cfg.type == "police"
	
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.1, 1.8 if is_suv else 1.45, 5.0 if is_suv else 4.8)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cfg.color
	mat.roughness = 0.25
	mat.metallic = 0.35
	mesh.material_override = mat
	mesh.position.y = (1.8 if is_suv else 1.45) * 0.5 + 0.35
	v.add_child(mesh)
	
	if is_police:
		# Red/Blue rooftop police strobe lightbar
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(1.2, 0.14, 0.3)
		bar.mesh = bar_mesh
		var red_blue := StandardMaterial3D.new()
		red_blue.albedo_color = Color("#dd2222")
		red_blue.emission_enabled = true
		red_blue.emission = Color("#ff2222")
		bar.material_override = red_blue
		bar.position = Vector3(0.0, 1.85, 0.1)
		v.add_child(bar)
	
	return v

# ==============================================================================
# 4. Authentic City Life Vignettes
# ==============================================================================
func _build_city_vignettes() -> void:
	var vig_root := Node3D.new()
	vig_root.name = "CityVignettes"
	add_child(vig_root)
	
	# A. Market Street browse/buy gathering
	_build_market_routine(vig_root)
	# B. Area Hospital drop-off zone
	_build_hospital_dropoff(vig_root)
	# C. Petrol Bunk fuel dispenser queue
	_build_petrol_bunk_queue(vig_root)
	# D. Roadside Chai Stall tea circle
	_build_chai_stall_circle(vig_root)
	# E. JN Stadium running track jogger
	_build_stadium_runners(vig_root)
	# F. Open Gym outdoor fitness squats
	_build_open_gym_fitness(vig_root)

func _build_market_routine(parent: Node3D) -> void:
	var market_node := Node3D.new()
	market_node.name = "MarketStreetRoutine"
	# Near Chowrastha main commercial road
	market_node.position = Vector3(22.0, 0.2, 38.0)
	parent.add_child(market_node)
	
	# Fruit/vegetable crates
	for i in 3:
		var crate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.55, 0.7)
		crate.mesh = box
		var c_mat := StandardMaterial3D.new()
		c_mat.albedo_color = [Color("#c47b32"), Color("#3b823b"), Color("#bf3d32")][i]
		crate.material_override = c_mat
		crate.position = Vector3((i - 1) * 1.1, 0.28, 0.0)
		market_node.add_child(crate)

func _build_hospital_dropoff(parent: Node3D) -> void:
	var hosp_node := Node3D.new()
	hosp_node.name = "HospitalDropoff"
	hosp_node.position = Vector3(-85.0, 0.2, 140.0)
	parent.add_child(hosp_node)
	
	# Drop-off canopy sign
	var sign_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.5, 0.6, 0.2)
	sign_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#f4f4f4")
	sign_mesh.material_override = mat
	sign_mesh.position = Vector3(0.0, 3.2, 0.0)
	hosp_node.add_child(sign_mesh)
	
	var label := Label3D.new()
	label.text = "AREA HOSPITAL • EMERGENCY DROP-OFF"
	label.font_size = 28
	label.pixel_size = 0.007
	label.position = Vector3(0.0, 3.2, 0.12)
	label.modulate = Color("#cc2222")
	hosp_node.add_child(label)

func _build_petrol_bunk_queue(parent: Node3D) -> void:
	var bunk_node := Node3D.new()
	bunk_node.name = "PetrolBunkQueue"
	bunk_node.position = Vector3(160.0, 0.2, -75.0)
	parent.add_child(bunk_node)
	
	# Two fuel dispenser pumps
	for p_idx in 2:
		var pump := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 1.8, 0.5)
		pump.mesh = box
		var p_mat := StandardMaterial3D.new()
		p_mat.albedo_color = Color("#0d3f8f") # IOCL blue pump
		pump.material_override = p_mat
		pump.position = Vector3((p_idx - 0.5) * 3.5, 0.9, 0.0)
		bunk_node.add_child(pump)

func _build_chai_stall_circle(parent: Node3D) -> void:
	var chai_node := Node3D.new()
	chai_node.name = "ChaiStallCircle"
	chai_node.position = Vector3(-45.0, 0.2, -60.0)
	parent.add_child(chai_node)
	
	# Tea stall counter
	var counter := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.9, 0.8)
	counter.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#556b2f")
	counter.material_override = mat
	counter.position = Vector3(0.0, 0.45, 0.0)
	chai_node.add_child(counter)
	
	# Chai brass samovar / boiling vessel
	var samovar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.22
	cyl.height = 0.55
	samovar.mesh = cyl
	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color("#c4a035")
	brass_mat.metallic = 0.85
	brass_mat.roughness = 0.25
	samovar.material_override = brass_mat
	samovar.position = Vector3(0.3, 1.18, 0.0)
	chai_node.add_child(samovar)

func _build_stadium_runners(parent: Node3D) -> void:
	var st_node := Node3D.new()
	st_node.name = "JNStadiumJoggers"
	st_node.position = Vector3(320.0, 0.2, 280.0)
	parent.add_child(st_node)
	
	# Running track loop outline
	var track_marker := Label3D.new()
	track_marker.text = "JN STADIUM • ATHLETICS TRACK"
	track_marker.font_size = 32
	track_marker.pixel_size = 0.008
	track_marker.position = Vector3(0.0, 2.5, 0.0)
	track_marker.modulate = Color("#f4efe6")
	st_node.add_child(track_marker)

func _build_open_gym_fitness(parent: Node3D) -> void:
	var gym_node := Node3D.new()
	gym_node.name = "OpenGymFitness"
	gym_node.position = Vector3(-120.0, 0.2, -180.0)
	parent.add_child(gym_node)
	
	# Outdoor fitness equipment frame (yellow/green painted steel bars)
	var bar_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 2.4
	bar_mesh.mesh = cyl
	var gym_mat := StandardMaterial3D.new()
	gym_mat.albedo_color = Color("#f5c211") # Municipal park equipment yellow
	bar_mesh.material_override = gym_mat
	bar_mesh.position = Vector3(0.0, 1.2, 0.0)
	gym_node.add_child(bar_mesh)

# ==============================================================================
# Process Update: Train & Convoy Translation
# ==============================================================================
func _process(delta: float) -> void:
	_update_train_motion(delta)
	_update_convoy_motion(delta)

func _update_train_motion(delta: float) -> void:
	if _total_track_length <= 0.0 or not is_instance_valid(_locomotive):
		return
	
	_train_distance = fmod(_train_distance + _train_speed * delta, _total_track_length)
	
	# Position locomotive
	var loco_sample := _sample_track_point(_train_distance)
	_locomotive.global_position = loco_sample.position
	if loco_sample.tangent.length_squared() > 0.001:
		_locomotive.look_at(loco_sample.position + loco_sample.tangent, Vector3.UP)
	
	# Position wagons trailing behind locomotive
	for w_idx in _wagons.size():
		var wagon := _wagons[w_idx]
		if not is_instance_valid(wagon):
			continue
		var wagon_dist := fposmod(_train_distance - (w_idx + 1) * 11.2, _total_track_length)
		var wagon_sample := _sample_track_point(wagon_dist)
		wagon.global_position = wagon_sample.position
		if wagon_sample.tangent.length_squared() > 0.001:
			wagon.look_at(wagon_sample.position + wagon_sample.tangent, Vector3.UP)

func _sample_track_point(dist: float) -> Dictionary:
	var n := _train_track.size()
	for i in range(1, n):
		if dist <= _track_cum_lengths[i]:
			var seg_len := _track_cum_lengths[i] - _track_cum_lengths[i - 1]
			var t := (dist - _track_cum_lengths[i - 1]) / maxf(seg_len, 0.001)
			var pt := _train_track[i - 1].lerp(_train_track[i], t)
			var tang := (_train_track[i] - _train_track[i - 1]).normalized()
			return {"position": pt, "tangent": tang}
	return {"position": _train_track[n - 1], "tangent": (_train_track[n - 1] - _train_track[n - 2]).normalized()}

func _update_convoy_motion(delta: float) -> void:
	if _convoy_total_length <= 0.0 or _convoy_vehicles.is_empty():
		return
	
	_convoy_distance = fmod(_convoy_distance + _convoy_speed * delta, _convoy_total_length)
	
	for v_idx in _convoy_vehicles.size():
		var vehicle := _convoy_vehicles[v_idx]
		if not is_instance_valid(vehicle):
			continue
		var v_dist := fposmod(_convoy_distance - v_idx * 9.5, _convoy_total_length)
		var sample := _sample_convoy_point(v_dist)
		vehicle.global_position = sample.position
		if sample.tangent.length_squared() > 0.001:
			vehicle.look_at(sample.position + sample.tangent, Vector3.UP)

func _sample_convoy_point(dist: float) -> Dictionary:
	var n := _convoy_route.size()
	for i in range(1, n):
		if dist <= _convoy_cum_lengths[i]:
			var seg_len := _convoy_cum_lengths[i] - _convoy_cum_lengths[i - 1]
			var t := (dist - _convoy_cum_lengths[i - 1]) / maxf(seg_len, 0.001)
			var pt := _convoy_route[i - 1].lerp(_convoy_route[i], t)
			var tang := (_convoy_route[i] - _convoy_route[i - 1]).normalized()
			return {"position": pt, "tangent": tang}
	return {"position": _convoy_route[n - 1], "tangent": (_convoy_route[n - 1] - _convoy_route[n - 2]).normalized()}

