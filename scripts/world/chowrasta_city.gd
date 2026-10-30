class_name ChowrastaCity
extends Node3D

## Complete 3D city reconstruction based faithfully on the "Rough Sketch" reference.
## Features:
## - Central 4-way "Chowrasta" intersection
## - North Road (12m), South Road (12m), East Road (10m), West Road (10m)
## - Asphalt roads with dashed center dividers, entrance stop markings, and curb footpaths
## - Directional arrow signs for North, South, East, and West roads
## - North-West: Petrol Station (red canopy, 4 pillars, concrete island, blue & red dispensers)
##   and 3-Storey Corner Shop with peach facade and "SHOP" sign
## - North-East: Row of 4 colorful shops (Pink, Peach, Cyan, Yellow) and 3-storey "Hotel"
## - South-West: "Houses" residential neighborhood with terracotta tiled roofs and lush trees
## - South-East: Open transit "Bus Stop" (blue canopy roof) and 2-storey "Commercial Building" (8 front windows)
## - Vehicles matching sketch: Red car on North Road, Cyan car on South Road, Blue car on West Road,
##   Orange & White Truck on East Road, plus a parked Indian Tuk-Tuk
## - Playable player with 3rd-person & 1st-person camera, vehicle entry/exit, physics driving, and full HUD

const CAR_SCENE := preload("res://scenes/vehicles/rigid_thar.tscn")
const COMPASS_SCENE := preload("res://scenes/vehicles/jeep_compass.tscn")
const PORSCHE_SCENE := preload("res://scenes/vehicles/porsche_911.tscn")
const TUK_TUK_SCENE := preload("res://scenes/vehicles/tuk_tuk.tscn")
const PERSON_SCENE := preload("res://scenes/player/person.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const UTILITY_POLE_SCENE := "res://assets/models/utility_pole/gdk_utility_pole.glb"
const CCTV_SCENE := "res://assets/models/cctv/gdk_cctv.glb"
const TEA_STALL_SCENE := "res://assets/models/market_street/tea_stall.glb"
const STOOL_SCENE := "res://assets/models/market_street/wooden_stool.glb"
const PANIPURI_SCENE := "res://assets/models/panipuri_cart/gdk_panipuri_cart.glb"
const HOUSE_1_SCENE := "res://assets/models/houses/house_1.glb"
const HOUSE_2_SCENE := "res://assets/models/houses/house_2.glb"
const HOUSE_3_SCENE := "res://assets/models/houses/house_3.glb"
const TREE_IMPOSTOR_TEX := preload("res://assets/textures/trees/broadleaf_impostor.png")

enum ControlState { ON_FOOT, ENTERING, DRIVING, EXITING }

var control_state := ControlState.ON_FOOT
var person: CharacterBody3D
var hud: CanvasLayer
var vehicles: Array[PhysicsBody3D] = []
var active_vehicle: PhysicsBody3D
var parked_transforms: Dictionary = {}
var entry: Node
var exit_speed_limit := 2.0
var _hint_until_msec := 0

# Materials
var _mat_road: StandardMaterial3D
var _mat_road_junction: StandardMaterial3D
var _mat_marking: StandardMaterial3D
var _mat_curb: StandardMaterial3D
var _mat_sidewalk: StandardMaterial3D
var _mat_grass: StandardMaterial3D
var _mat_petrol_red: StandardMaterial3D
var _mat_petrol_blue: StandardMaterial3D
var _mat_petrol_island: StandardMaterial3D
var _mat_forecourt: StandardMaterial3D
var _mat_steel: StandardMaterial3D
var _mat_chrome: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _mat_dark_glass: StandardMaterial3D
var _mat_shop_peach: StandardMaterial3D
var _mat_shop_pink: StandardMaterial3D
var _mat_shop_blue: StandardMaterial3D
var _mat_shop_yellow: StandardMaterial3D
var _mat_wall_white: StandardMaterial3D
var _mat_wall_cream: StandardMaterial3D
var _mat_wall_commercial: StandardMaterial3D
var _mat_roof_tile: StandardMaterial3D
var _mat_roof_flat: StandardMaterial3D
var _mat_bus_blue: StandardMaterial3D
var _mat_truck_orange: StandardMaterial3D
var _mat_truck_white: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_tree_foliage: StandardMaterial3D
var _mat_tree_trunk: StandardMaterial3D
var _tree_mesh: ArrayMesh
var _tree_shader_mat: ShaderMaterial

func _ready() -> void:
	name = "ChowrastaCity"
	_init_materials()
	_init_tree_mesh()
	_setup_environment()
	_build_ground()
	_build_roads_and_chowrasta()
	_build_north_west_quadrant()
	_build_north_east_quadrant()
	_build_south_west_quadrant()
	_build_south_east_quadrant()
	_build_truck_on_east_road()
	_build_street_furniture()
	_spawn_vehicles()
	_setup_player_and_hud()

func _init_materials() -> void:
	_mat_road = StandardMaterial3D.new()
	_mat_road.albedo_color = Color(0.20, 0.21, 0.22)
	_mat_road.roughness = 0.90

	_mat_road_junction = StandardMaterial3D.new()
	_mat_road_junction.albedo_color = Color(0.22, 0.23, 0.24)
	_mat_road_junction.roughness = 0.88

	_mat_marking = StandardMaterial3D.new()
	_mat_marking.albedo_color = Color(0.96, 0.96, 0.94)
	_mat_marking.roughness = 0.50

	_mat_curb = StandardMaterial3D.new()
	_mat_curb.albedo_color = Color(0.72, 0.71, 0.68)
	_mat_curb.roughness = 0.92

	_mat_sidewalk = StandardMaterial3D.new()
	_mat_sidewalk.albedo_color = Color(0.78, 0.77, 0.74)
	_mat_sidewalk.roughness = 0.94

	_mat_grass = StandardMaterial3D.new()
	_mat_grass.albedo_color = Color(0.38, 0.56, 0.28)
	_mat_grass.roughness = 0.96

	_mat_forecourt = StandardMaterial3D.new()
	_mat_forecourt.albedo_color = Color(0.82, 0.81, 0.78)
	_mat_forecourt.roughness = 0.88

	_mat_petrol_red = StandardMaterial3D.new()
	_mat_petrol_red.albedo_color = Color(0.82, 0.14, 0.14)
	_mat_petrol_red.roughness = 0.35

	_mat_petrol_blue = StandardMaterial3D.new()
	_mat_petrol_blue.albedo_color = Color(0.12, 0.42, 0.85)
	_mat_petrol_blue.roughness = 0.35

	_mat_petrol_island = StandardMaterial3D.new()
	_mat_petrol_island.albedo_color = Color(0.88, 0.86, 0.80)
	_mat_petrol_island.roughness = 0.80

	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.26, 0.28, 0.30)
	_mat_steel.metallic = 0.75
	_mat_steel.roughness = 0.45

	_mat_chrome = StandardMaterial3D.new()
	_mat_chrome.albedo_color = Color(0.90, 0.92, 0.94)
	_mat_chrome.metallic = 0.90
	_mat_chrome.roughness = 0.20

	_mat_glass = StandardMaterial3D.new()
	_mat_glass.albedo_color = Color(0.22, 0.35, 0.48, 0.75)
	_mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_glass.roughness = 0.15

	_mat_dark_glass = StandardMaterial3D.new()
	_mat_dark_glass.albedo_color = Color(0.12, 0.15, 0.18, 0.90)
	_mat_dark_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_dark_glass.roughness = 0.10

	_mat_shop_peach = StandardMaterial3D.new()
	_mat_shop_peach.albedo_color = Color(0.92, 0.60, 0.38)
	_mat_shop_peach.roughness = 0.85

	_mat_shop_pink = StandardMaterial3D.new()
	_mat_shop_pink.albedo_color = Color(0.86, 0.38, 0.58)
	_mat_shop_pink.roughness = 0.85

	_mat_shop_blue = StandardMaterial3D.new()
	_mat_shop_blue.albedo_color = Color(0.28, 0.65, 0.90)
	_mat_shop_blue.roughness = 0.85

	_mat_shop_yellow = StandardMaterial3D.new()
	_mat_shop_yellow.albedo_color = Color(0.95, 0.80, 0.18)
	_mat_shop_yellow.roughness = 0.85

	_mat_wall_white = StandardMaterial3D.new()
	_mat_wall_white.albedo_color = Color(0.94, 0.94, 0.93)
	_mat_wall_white.roughness = 0.90

	_mat_wall_cream = StandardMaterial3D.new()
	_mat_wall_cream.albedo_color = Color(0.92, 0.89, 0.83)
	_mat_wall_cream.roughness = 0.92

	_mat_wall_commercial = StandardMaterial3D.new()
	_mat_wall_commercial.albedo_color = Color(0.85, 0.86, 0.88)
	_mat_wall_commercial.roughness = 0.90

	_mat_roof_tile = StandardMaterial3D.new()
	_mat_roof_tile.albedo_color = Color(0.72, 0.28, 0.16)
	_mat_roof_tile.roughness = 0.82

	_mat_roof_flat = StandardMaterial3D.new()
	_mat_roof_flat.albedo_color = Color(0.65, 0.64, 0.62)
	_mat_roof_flat.roughness = 0.95

	_mat_bus_blue = StandardMaterial3D.new()
	_mat_bus_blue.albedo_color = Color(0.16, 0.46, 0.80)
	_mat_bus_blue.roughness = 0.40

	_mat_truck_orange = StandardMaterial3D.new()
	_mat_truck_orange.albedo_color = Color(0.92, 0.38, 0.06)
	_mat_truck_orange.roughness = 0.35

	_mat_truck_white = StandardMaterial3D.new()
	_mat_truck_white.albedo_color = Color(0.92, 0.92, 0.90)
	_mat_truck_white.roughness = 0.55

	_mat_wood = StandardMaterial3D.new()
	_mat_wood.albedo_color = Color(0.55, 0.36, 0.20)
	_mat_wood.roughness = 0.85

	_mat_tree_foliage = StandardMaterial3D.new()
	_mat_tree_foliage.albedo_color = Color(0.24, 0.52, 0.18)
	_mat_tree_foliage.roughness = 0.85

	_mat_tree_trunk = StandardMaterial3D.new()
	_mat_tree_trunk.albedo_color = Color(0.40, 0.30, 0.22)
	_mat_tree_trunk.roughness = 0.95

	_tree_shader_mat = ShaderMaterial.new()
	var shader_res := load("res://shaders/tree_impostor.gdshader") as Shader
	if shader_res:
		_tree_shader_mat.shader = shader_res
		_tree_shader_mat.set_shader_parameter("impostor", TREE_IMPOSTOR_TEX)
		_tree_shader_mat.set_shader_parameter("alpha_cut", 0.45)
		_tree_shader_mat.set_shader_parameter("saturation", 1.25)

func _init_tree_mesh() -> void:
	var surface := MeshSurface.new()
	var half: float = 3.6
	var h: float = 7.2
	for angle: float in [0.0, PI * 0.25, PI * 0.5, PI * 0.75]:
		var dir := Vector3(cos(angle), 0.0, sin(angle)) * half
		var n := Vector3(-sin(angle), 0.0, cos(angle))
		var a := -dir
		var b := dir
		var c := dir + Vector3.UP * h
		var d := -dir + Vector3.UP * h
		surface.quad(a, b, c, d, n, Color.WHITE, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2.ZERO, false)
		surface.quad(b, a, d, c, -n, Color.WHITE, Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2.ZERO, false)
	_tree_mesh = surface.to_mesh()

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8cc5e3")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cce3f0")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color("#b3cfdb")
	env.fog_density = 0.001
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("#fff8ea")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground() -> void:
	# Main landscape green plane
	_box(self, "GroundTerrain", Vector3(240, 1.0, 240), Vector3(0, -0.5, 0), 0.0, _mat_grass, true)

func _build_roads_and_chowrasta() -> void:
	var roads := Node3D.new()
	roads.name = "RoadNetwork"
	add_child(roads)

	# North-South Road: 12 m width, extends from Z = -80 to Z = +80
	# East-West Road: 10 m width, extends from X = -80 to X = +80
	# Chowrasta center box: X = [-6, +6], Z = [-5, +5]
	var ns_width := 12.0
	var ew_width := 10.0
	var road_y := 0.02

	# Chowrasta central intersection
	_box(roads, "ChowrastaCenter", Vector3(ns_width, 0.04, ew_width), Vector3(0, road_y, 0), 0.0, _mat_road_junction, true)

	# North Road (Z from -5 to -80, length 75m)
	_box(roads, "NorthRoad", Vector3(ns_width, 0.04, 75.0), Vector3(0, road_y, -42.5), 0.0, _mat_road, true)
	# South Road (Z from +5 to +80, length 75m)
	_box(roads, "SouthRoad", Vector3(ns_width, 0.04, 75.0), Vector3(0, road_y, 42.5), 0.0, _mat_road, true)
	# West Road (X from -6 to -80, length 74m)
	_box(roads, "WestRoad", Vector3(74.0, 0.04, ew_width), Vector3(-43.0, road_y, 0), 0.0, _mat_road, true)
	# East Road (X from +6 to +80, length 74m)
	_box(roads, "EastRoad", Vector3(74.0, 0.04, ew_width), Vector3(43.0, road_y, 0), 0.0, _mat_road, true)

	# Dashed White Center Lane Lines (North-South: X=0, East-West: Z=0)
	var dash_len := 3.0
	var dash_gap := 3.0
	var mark_y := road_y + 0.025
	var mark_w := 0.18

	# North road dashes
	var z := -7.5
	while z >= -78.0:
		_box(roads, "Marking_N", Vector3(mark_w, 0.01, dash_len), Vector3(0, mark_y, z - dash_len * 0.5), 0.0, _mat_marking, false)
		z -= (dash_len + dash_gap)

	# South road dashes
	z = 7.5
	while z <= 78.0:
		_box(roads, "Marking_S", Vector3(mark_w, 0.01, dash_len), Vector3(0, mark_y, z + dash_len * 0.5), 0.0, _mat_marking, false)
		z += (dash_len + dash_gap)

	# West road dashes
	var x := -8.5
	while x >= -78.0:
		_box(roads, "Marking_W", Vector3(dash_len, 0.01, mark_w), Vector3(x - dash_len * 0.5, mark_y, 0), 0.0, _mat_marking, false)
		x -= (dash_len + dash_gap)

	# East road dashes
	x = 8.5
	while x <= 78.0:
		_box(roads, "Marking_E", Vector3(dash_len, 0.01, mark_w), Vector3(x + dash_len * 0.5, mark_y, 0), 0.0, _mat_marking, false)
		x += (dash_len + dash_gap)

	# Dashed stop lines / junction boundary marks (as shown on sketch!)
	_dashed_line(roads, Vector3(-5.8, mark_y, -5.0), Vector3(5.8, mark_y, -5.0), mark_w, 0.8, 0.4)
	_dashed_line(roads, Vector3(-5.8, mark_y, 5.0), Vector3(5.8, mark_y, 5.0), mark_w, 0.8, 0.4)
	_dashed_line(roads, Vector3(-6.0, mark_y, -4.8), Vector3(-6.0, mark_y, 4.8), mark_w, 0.8, 0.4)
	_dashed_line(roads, Vector3(6.0, mark_y, -4.8), Vector3(6.0, mark_y, 4.8), mark_w, 0.8, 0.4)

	# Sidewalks with curbs (Height: 0.20m, Sidewalk Width: 3.5m)
	_build_sidewalk_quadrant(roads, "NW", Vector2(-6.0, -5.0), Vector2(-1.0, -1.0))
	_build_sidewalk_quadrant(roads, "NE", Vector2(6.0, -5.0), Vector2(1.0, -1.0))
	_build_sidewalk_quadrant(roads, "SW", Vector2(-6.0, 5.0), Vector2(-1.0, 1.0))
	_build_sidewalk_quadrant(roads, "SE", Vector2(6.0, 5.0), Vector2(1.0, 1.0))

	# Direction Signs & Chowrasta Junction marker
	_build_junction_signboards(roads)

func _build_sidewalk_quadrant(parent: Node3D, tag: String, corner: Vector2, dir: Vector2) -> void:
	var sw := Node3D.new()
	sw.name = "Sidewalk_%s" % tag
	parent.add_child(sw)
	var curb_h := 0.20
	var sw_w := 3.2
	var length := 74.0

	# Longitudinal arm along N/S road
	var x_pos := corner.x + dir.x * (sw_w * 0.5)
	var z_pos := corner.y + dir.y * (length * 0.5)
	_box(sw, "Walk_NS", Vector3(sw_w, curb_h, length), Vector3(x_pos, curb_h * 0.5, z_pos), 0.0, _mat_sidewalk, true)
	_box(sw, "Curb_NS", Vector3(0.18, curb_h + 0.02, length), Vector3(corner.x + dir.x * 0.09, curb_h * 0.5, z_pos), 0.0, _mat_curb, true)

	# Lateral arm along E/W road
	var lateral_len := length - sw_w
	var x_lat := corner.x + dir.x * (sw_w + lateral_len * 0.5)
	var z_lat := corner.y + dir.y * (sw_w * 0.5)
	_box(sw, "Walk_EW", Vector3(lateral_len, curb_h, sw_w), Vector3(x_lat, curb_h * 0.5, z_lat), 0.0, _mat_sidewalk, true)
	_box(sw, "Curb_EW", Vector3(lateral_len, curb_h + 0.02, 0.18), Vector3(x_lat, curb_h * 0.5, corner.y + dir.y * 0.09), 0.0, _mat_curb, true)

func _dashed_line(parent: Node3D, from: Vector3, to: Vector3, width: float, dash: float, gap: float) -> void:
	var total_len := from.distance_to(to)
	if total_len <= 0.01:
		return
	var dir := (to - from).normalized()
	var step := dash + gap
	var cur := 0.0
	var idx := 0
	while cur < total_len:
		var d_len := minf(dash, total_len - cur)
		var center := from + dir * (cur + d_len * 0.5)
		var b := _box(parent, "Dash_%d" % idx, Vector3(d_len if absf(dir.x) > 0.5 else width, 0.01, width if absf(dir.x) > 0.5 else d_len), center, 0.0, _mat_marking, false)
		cur += step
		idx += 1

func _build_junction_signboards(parent: Node3D) -> void:
	# Central Chowrasta Junction Signpost
	var junc := Node3D.new()
	junc.name = "ChowrastaPoles"
	parent.add_child(junc)

	# Northwest corner sign facing intersection
	_signpost(junc, Vector3(-6.8, 0.0, -5.8), "చౌరస్తా\nCHOWRASTA", Color.WHITE, Color(0.12, 0.40, 0.72), 3.2, 0.6)

	# North Road arrow sign
	_signpost(junc, Vector3(6.8, 0.0, -18.0), "⬆ North Road", Color.WHITE, Color(0.15, 0.50, 0.25), 2.4, 0.5)
	# South Road arrow sign
	_signpost(junc, Vector3(-6.8, 0.0, 18.0), "⬇ South Road (12 m)", Color.WHITE, Color(0.15, 0.50, 0.25), 2.8, 0.5)
	# West Road arrow sign
	_signpost(junc, Vector3(-18.0, 0.0, 5.8), "⬅ West Road", Color.WHITE, Color(0.15, 0.50, 0.25), 2.4, 0.5)
	# East Road arrow sign
	_signpost(junc, Vector3(18.0, 0.0, -5.8), "East Road (10 m) ➡", Color.WHITE, Color(0.15, 0.50, 0.25), 2.8, 0.5)

func _signpost(parent: Node3D, pos: Vector3, text: String, text_col: Color, bg_col: Color, width: float, height: float) -> void:
	var post := Node3D.new()
	post.position = pos
	parent.add_child(post)
	# Steel pole
	_cylinder(post, "Pole", 0.06, 2.6, Vector3(0, 1.3, 0), Vector3.ZERO, _mat_steel, true)
	# Signboard backplate
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = bg_col
	board_mat.roughness = 0.5
	_box(post, "Board", Vector3(width, height, 0.04), Vector3(0, 2.35, 0), 0.0, board_mat, false)

	# Label 3D front & back
	for facing in [0.03, -0.03]:
		var lbl := Label3D.new()
		lbl.text = text
		lbl.font_size = 32
		lbl.pixel_size = 0.005
		lbl.outline_size = 3
		lbl.outline_modulate = Color.BLACK
		lbl.modulate = text_col
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector3(0, 2.35, facing)
		if facing < 0.0:
			lbl.rotation_degrees.y = 180
		post.add_child(lbl)

# =========================================================================
# QUADRANT 1: NORTH-WEST (Petrol Station & Corner Shop)
# =========================================================================
func _build_north_west_quadrant() -> void:
	var nw := Node3D.new()
	nw.name = "Quadrant_NW_PetrolAndShop"
	add_child(nw)

	# Concrete Forecourt driveway for Petrol Station: X = [-38, -14], Z = [-32, -8]
	_box(nw, "Forecourt", Vector3(24.0, 0.18, 24.0), Vector3(-26.0, 0.09, -20.0), 0.0, _mat_forecourt, true)

	# Petrol Station Canopy: 18m x 10m, Y = 5.2m
	var canopy_center := Vector3(-26.0, 5.0, -20.0)
	var canopy_size := Vector3(18.0, 0.65, 11.0)
	_box(nw, "CanopyRoof", canopy_size, canopy_center, 0.0, _mat_petrol_red, true)

	# Canopy white fascia trim
	_box(nw, "CanopyFascia_Front", Vector3(18.2, 0.70, 0.15), canopy_center + Vector3(0, 0, 5.55), 0.0, _mat_wall_white, false)
	_box(nw, "CanopyFascia_Back", Vector3(18.2, 0.70, 0.15), canopy_center - Vector3(0, 0, 5.55), 0.0, _mat_wall_white, false)
	_box(nw, "CanopyFascia_Left", Vector3(0.15, 0.70, 11.2), canopy_center - Vector3(9.05, 0, 0), 0.0, _mat_wall_white, false)
	_box(nw, "CanopyFascia_Right", Vector3(0.15, 0.70, 11.2), canopy_center + Vector3(9.05, 0, 0), 0.0, _mat_wall_white, false)

	# Signboard on canopy fascia
	_label(nw, "PETROL STATION", canopy_center + Vector3(0, 0, 5.66), 0.0, 48, Color.WHITE, Color(0.8, 0.1, 0.1))
	_label(nw, "PETROL STATION", canopy_center - Vector3(0, 0, 5.66), 180.0, 48, Color.WHITE, Color(0.8, 0.1, 0.1))
	_label(nw, "FUELS", canopy_center + Vector3(9.16, 0, 0), -90.0, 44, Color.WHITE, Color(0.8, 0.1, 0.1))

	# 4 Sturdy Steel Support Pillars
	var col_x := [-32.5, -19.5]
	var col_z := [-23.5, -16.5]
	for px in col_x:
		for pz in col_z:
			_cylinder(nw, "CanopyPillar", 0.32, 4.8, Vector3(px, 2.4, pz), Vector3.ZERO, _mat_steel, true)

	# Raised Central Fueling Island (under canopy)
	var island_pos := Vector3(-26.0, 0.28, -20.0)
	_box(nw, "PumpIsland", Vector3(8.0, 0.25, 2.0), island_pos, 0.0, _mat_petrol_island, true)
	# Yellow & Black Safety hazard edge
	var hazard_mat := StandardMaterial3D.new()
	hazard_mat.albedo_color = Color(0.95, 0.82, 0.12)
	_box(nw, "IslandEdge", Vector3(8.1, 0.08, 2.1), island_pos - Vector3(0, 0.08, 0), 0.0, hazard_mat, false)

	# Blue Fuel Dispenser (Left / Diesel)
	_build_fuel_pump(nw, "Pump_Blue", Vector3(-28.0, 0.40, -20.0), _mat_petrol_blue, "DIESEL")
	# Red Fuel Dispenser (Right / Petrol)
	_build_fuel_pump(nw, "Pump_Red", Vector3(-24.0, 0.40, -20.0), _mat_petrol_red, "PETROL")

	# Canopy downlights
	for dx in [-4.0, 0.0, 4.0]:
		var light_mesh := _cylinder(nw, "Downlight", 0.30, 0.08, canopy_center + Vector3(dx, -0.35, 0), Vector3.ZERO, _mat_chrome, false)
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.96, 0.88)
		omni.light_energy = 1.2
		omni.omni_range = 10.0
		omni.position = canopy_center + Vector3(dx, -0.6, 0)
		nw.add_child(omni)

	# -------------------------------------------------------------
	# Corner Shop: 3-Storey Building (facing North Road)
	# Width: 6.8m (X), Depth: 16.0m (Z), Height: 10.8m (Y)
	# Ground floor has peach storefront with "SHOP"
	# 2nd & 3rd floors have 3 windows each (facing east toward North Road)
	# -------------------------------------------------------------
	var shop_pos := Vector3(-10.2, 0.0, -18.0)
	var shop_node := Node3D.new()
	shop_node.name = "CornerShop3Storey"
	shop_node.position = shop_pos
	nw.add_child(shop_node)

	# Main building shell (cream/white stucco)
	_box(shop_node, "MainStructure", Vector3(6.8, 10.8, 16.0), Vector3(0, 5.4, 0), 0.0, _mat_wall_cream, true)
	# Roof parapet
	_box(shop_node, "Parapet_L", Vector3(0.25, 0.60, 16.0), Vector3(-3.25, 11.1, 0), 0.0, _mat_wall_cream, true)
	_box(shop_node, "Parapet_R", Vector3(0.25, 0.60, 16.0), Vector3(3.25, 11.1, 0), 0.0, _mat_wall_cream, true)
	_box(shop_node, "Parapet_F", Vector3(6.8, 0.60, 0.25), Vector3(0, 11.1, 7.85), 0.0, _mat_wall_cream, true)
	_box(shop_node, "Parapet_B", Vector3(6.8, 0.60, 0.25), Vector3(0, 11.1, -7.85), 0.0, _mat_wall_cream, true)
	_box(shop_node, "RoofSlab", Vector3(6.4, 0.20, 15.6), Vector3(0, 10.75, 0), 0.0, _mat_roof_flat, true)

	# Rooftop HDPE Water Tank
	_add_water_tank(shop_node, Vector3(-1.5, 11.4, -4.0), true)

	# Ground floor: Peach facade front (facing East toward North Road)
	# Size: 3.5m high, spans along Z
	_box(shop_node, "PeachFacade", Vector3(0.12, 3.6, 15.8), Vector3(3.42, 1.8, 0), 0.0, _mat_shop_peach, false)
	# Large "SHOP" signboard on ground floor header
	_label(shop_node, "SHOP", Vector3(3.48, 3.2, 0), -90.0, 56, Color.WHITE, Color(0.85, 0.40, 0.15))
	_label(shop_node, "CHOWRASTA GENERAL STORES", Vector3(3.48, 2.7, 0), -90.0, 24, Color(0.1, 0.1, 0.1))

	# Ground floor shop entrance and glass display showcases
	_box(shop_node, "ShopEntranceDoor", Vector3(0.15, 2.4, 3.2), Vector3(3.43, 1.2, 0), 0.0, _mat_dark_glass, false)
	_box(shop_node, "ShopDisplay_L", Vector3(0.15, 2.0, 3.0), Vector3(3.43, 1.4, -4.5), 0.0, _mat_glass, false)
	_box(shop_node, "ShopDisplay_R", Vector3(0.15, 2.0, 3.0), Vector3(3.43, 1.4, 4.5), 0.0, _mat_glass, false)

	# 2nd Floor: 3 Rectangular Windows facing East (at Y = 5.4m)
	# 3rd Floor: 3 Rectangular Windows facing East (at Y = 8.8m)
	for floor_idx in [1, 2]:
		var wy: float = 5.2 if floor_idx == 1 else 8.6
		for wz in [-4.5, 0.0, 4.5]:
			_window_facade(shop_node, Vector3(3.42, wy, wz), Vector2(1.8, 1.6), 90.0)

	# Trees behind Petrol Station and Corner Shop
	var tree_spots := [
		Vector2(-35.0, -32.0),
		Vector2(-24.0, -34.0),
		Vector2(-12.0, -32.0),
		Vector2(-38.0, -18.0),
		Vector2(-38.0, -8.0)
	]
	for pt in tree_spots:
		_spawn_tree(nw, pt, randf_range(7.0, 9.5))

func _build_fuel_pump(parent: Node3D, node_name: String, pos: Vector3, mat_body: Material, fuel_type: String) -> void:
	var pump := Node3D.new()
	pump.name = node_name
	pump.position = pos
	parent.add_child(pump)

	# Cabinet body
	_box(pump, "Body", Vector3(1.2, 1.8, 0.65), Vector3(0, 0.9, 0), 0.0, mat_body, true)
	# White side panels
	_box(pump, "SideL", Vector3(0.08, 1.76, 0.61), Vector3(-0.61, 0.9, 0), 0.0, _mat_wall_white, false)
	_box(pump, "SideR", Vector3(0.08, 1.76, 0.61), Vector3(0.61, 0.9, 0), 0.0, _mat_wall_white, false)
	# Top signage header
	_box(pump, "Header", Vector3(1.22, 0.35, 0.67), Vector3(0, 1.85, 0), 0.0, _mat_steel, false)

	# LCD Screen display
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.05, 0.15, 0.08)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.1, 0.6, 0.2)
	screen_mat.emission_energy_multiplier = 0.4
	_box(pump, "Screen_Front", Vector3(0.7, 0.45, 0.05), Vector3(0, 1.35, 0.33), 0.0, screen_mat, false)
	_box(pump, "Screen_Back", Vector3(0.7, 0.45, 0.05), Vector3(0, 1.35, -0.33), 0.0, screen_mat, false)

	# Dispenser Nozzle & Hose
	_cylinder(pump, "NozzleL", 0.035, 0.55, Vector3(-0.55, 1.1, 0.30), Vector3(0, 0, 15), _mat_steel, false)
	_cylinder(pump, "NozzleR", 0.035, 0.55, Vector3(0.55, 1.1, 0.30), Vector3(0, 0, -15), _mat_steel, false)

	# Labels
	_label(pump, fuel_type, Vector3(0, 1.85, 0.35), 0.0, 28, Color.WHITE)
	_label(pump, fuel_type, Vector3(0, 1.85, -0.35), 180.0, 28, Color.WHITE)

# =========================================================================
# QUADRANT 2: NORTH-EAST (4 Colorful Shops & Hotel)
# =========================================================================
func _build_north_east_quadrant() -> void:
	var ne := Node3D.new()
	ne.name = "Quadrant_NE_ShopsAndHotel"
	add_child(ne)

	# -------------------------------------------------------------
	# Row of 4 Attached Colorful Shops (along north side of East Road)
	# Position: X = [10, 38], Z = [-18, -8]
	# 4 Shops side by side:
	# 1. Pink
	# 2. Peach
	# 3. Sky Blue
	# 4. Yellow
	# -------------------------------------------------------------
	var shops_node := Node3D.new()
	shops_node.name = "ShopRow4Units"
	shops_node.position = Vector3(24.0, 0.0, -13.0)
	ne.add_child(shops_node)

	# Backing 2-storey building structure (white/grey)
	_box(shops_node, "BackingStructure", Vector3(29.0, 7.5, 10.0), Vector3(0, 3.75, -4.5), 0.0, _mat_wall_white, true)
	_box(shops_node, "BackingRoof", Vector3(29.2, 0.3, 10.2), Vector3(0, 7.6, -4.5), 0.0, _mat_roof_flat, true)
	# Backing upper windows
	for wx in [-10.0, -3.5, 3.5, 10.0]:
		_window_facade(shops_node, Vector3(wx, 5.5, 0.51), Vector2(2.2, 1.6), 0.0)

	# Individual storefront data: {name, color_mat, banner_col, sub_title, x_offset}
	var shop_data := [
		{"name": "SHOP", "sub": "Sri Lakshmi Textiles", "mat": _mat_shop_pink, "banner": Color(0.85, 0.25, 0.50), "x": -10.5},
		{"name": "SHOP", "sub": "Srinivasa Sweet House", "mat": _mat_shop_peach, "banner": Color(0.90, 0.52, 0.20), "x": -3.5},
		{"name": "SHOP", "sub": "Sampath Mobiles", "mat": _mat_shop_blue, "banner": Color(0.18, 0.55, 0.85), "x": 3.5},
		{"name": "SHOP", "sub": "Balaji Kirana Stores", "mat": _mat_shop_yellow, "banner": Color(0.95, 0.75, 0.12), "x": 10.5}
	]

	var shop_w := 6.8
	var shop_depth := 5.0
	var shop_h := 4.2

	for data in shop_data:
		var x: float = data["x"]
		var unit := Node3D.new()
		unit.name = "ShopUnit_%s" % data["sub"].replace(" ", "_")
		unit.position = Vector3(x, 0, 1.0)
		shops_node.add_child(unit)

		# Ground shop enclosure
		_box(unit, "StallBody", Vector3(shop_w - 0.1, shop_h, shop_depth), Vector3(0, shop_h * 0.5, 0), 0.0, _mat_wall_cream, true)

		# Slanted colorful canopy awning (slopes forward and down toward East Road!)
		var awning_len := 2.6
		var awning_slope := deg_to_rad(22.0)
		var awning_mesh := _box(unit, "Awning", Vector3(shop_w, 0.12, awning_len), Vector3(0, shop_h + 0.15, 1.8), 0.0, data["mat"], true)
		awning_mesh.rotation.x = awning_slope

		# Awning support struts (steel)
		_cylinder(unit, "StrutL", 0.03, 1.8, Vector3(-shop_w * 0.46, shop_h - 0.4, 1.8), Vector3(45, 0, 0), _mat_steel, false)
		_cylinder(unit, "StrutR", 0.03, 1.8, Vector3(shop_w * 0.46, shop_h - 0.4, 1.8), Vector3(45, 0, 0), _mat_steel, false)

		# Storefront roll-up shutter / glass display front
		_box(unit, "ShutterDoor", Vector3(shop_w - 1.2, 3.2, 0.12), Vector3(0, 1.6, 2.45), 0.0, _mat_dark_glass, false)
		# Step curb in front of shop
		_box(unit, "EntranceStep", Vector3(shop_w - 0.5, 0.22, 1.0), Vector3(0, 0.11, 2.8), 0.0, _mat_curb, true)

		# Signboard with "Shop" label matching the sketch!
		_label(unit, data["name"], Vector3(0, shop_h + 0.85, 1.7), 0.0, 52, Color.WHITE, data["banner"])
		_label(unit, data["sub"], Vector3(0, shop_h + 0.35, 2.0), 0.0, 22, Color(0.1, 0.1, 0.1))

	# -------------------------------------------------------------
	# Multi-Storey "Hotel" Building (further East along East Road)
	# Position: X = [44, 62], Z = [-26, -8]
	# 3 Storeys, Height ~ 12.0m, bold "HOTEL" header signboard
	# -------------------------------------------------------------
	var hotel_pos := Vector3(53.0, 0.0, -17.0)
	var hotel := Node3D.new()
	hotel.name = "HotelBuilding"
	hotel.position = hotel_pos
	ne.add_child(hotel)

	var h_w := 17.0
	var h_d := 17.0
	var h_h := 12.0
	# Main hotel structure
	_box(hotel, "HotelMain", Vector3(h_w, h_h, h_d), Vector3(0, h_h * 0.5, 0), 0.0, _mat_wall_white, true)
	# Rooftop parapet & slab
	_box(hotel, "RoofSlab", Vector3(h_w + 0.4, 0.30, h_d + 0.4), Vector3(0, h_h + 0.15, 0), 0.0, _mat_roof_flat, true)
	_box(hotel, "Parapet_Front", Vector3(h_w + 0.4, 0.90, 0.25), Vector3(0, h_h + 0.60, h_d * 0.5), 0.0, _mat_wall_white, true)

	# Bold "HOTEL" signboard mounted on top
	_label(hotel, "HOTEL", Vector3(0, h_h + 1.6, h_d * 0.5 + 0.15), 0.0, 72, Color(0.95, 0.82, 0.15), Color(0.12, 0.25, 0.55))
	_label(hotel, "SURYA RESIDENCY & DINE-IN", Vector3(0, h_h + 0.8, h_d * 0.5 + 0.15), 0.0, 26, Color.WHITE)

	# Ground floor entrance lobby with canopy
	_box(hotel, "EntranceCanopy", Vector3(6.5, 0.25, 3.2), Vector3(0, 3.6, h_d * 0.5 + 1.6), 0.0, _mat_steel, true)
	_cylinder(hotel, "CanopyPillarL", 0.12, 3.6, Vector3(-3.0, 1.8, h_d * 0.5 + 3.0), Vector3.ZERO, _mat_chrome, true)
	_cylinder(hotel, "CanopyPillarR", 0.12, 3.6, Vector3(3.0, 1.8, h_d * 0.5 + 3.0), Vector3.ZERO, _mat_chrome, true)
	_box(hotel, "GlassLobbyDoors", Vector3(5.5, 3.0, 0.15), Vector3(0, 1.5, h_d * 0.5 + 0.05), 0.0, _mat_glass, false)

	# Upper floors: 3 Windows per floor (2nd floor at Y = 5.8m, 3rd floor at Y = 9.2m)
	for floor_idx in [1, 2]:
		var wy: float = 5.8 if floor_idx == 1 else 9.2
		for wx in [-5.0, 0.0, 5.0]:
			_window_facade(hotel, Vector3(wx, wy, h_d * 0.5 + 0.05), Vector2(2.4, 1.8), 0.0)

	# Rooftop Water Tank on Hotel
	_add_water_tank(hotel, Vector3(4.0, h_h + 1.2, -4.0), false)
	_add_water_tank(hotel, Vector3(5.5, h_h + 1.2, -4.0), true)

	# Trees between shops and hotel, plus background
	var ne_trees := [
		Vector2(39.5, -11.0),
		Vector2(40.5, -20.0),
		Vector2(20.0, -28.0),
		Vector2(32.0, -28.0),
		Vector2(48.0, -30.0),
		Vector2(64.0, -16.0)
	]
	for pt in ne_trees:
		_spawn_tree(ne, pt, randf_range(7.5, 10.0))

# =========================================================================
# QUADRANT 3: SOUTH-WEST ("Houses" Residential Zone)
# =========================================================================
func _build_south_west_quadrant() -> void:
	var sw := Node3D.new()
	sw.name = "Quadrant_SW_ResidentialHouses"
	add_child(sw)

	# Residential Neighborhood Signboard: "Houses" / "Vidyanagar Residential Colony"
	_signpost(sw, Vector3(-12.0, 0.0, 9.0), "HOUSES\nVidyanagar Colony", Color.WHITE, Color(0.45, 0.25, 0.15), 3.2, 0.65)

	# 5 Residential Houses with terracotta tiled pitched roofs
	# House 1 (North-facing towards West Road)
	_build_tiled_house(sw, "House_1", Vector3(-16.0, 0.0, 16.0), 0.0, Vector3(8.5, 4.2, 7.5))
	# House 2 (West side)
	_build_tiled_house(sw, "House_2", Vector3(-28.0, 0.0, 16.0), 0.0, Vector3(8.0, 4.0, 7.0))
	# House 3 (South-East residential)
	_build_tiled_house(sw, "House_3", Vector3(-16.0, 0.0, 28.0), 0.0, Vector3(9.0, 4.5, 7.5))
	# House 4 (South-West residential)
	_build_tiled_house(sw, "House_4", Vector3(-28.0, 0.0, 28.0), 0.0, Vector3(8.5, 4.2, 7.5))
	# House 5 (Outer corner)
	_build_tiled_house(sw, "House_5", Vector3(-38.0, 0.0, 22.0), deg_to_rad(90.0), Vector3(8.0, 4.0, 7.0))

	# Boundary compound walls and gate paths between houses
	var wall_mat := _mat_wall_cream
	_box(sw, "CompWall_1", Vector3(26.0, 1.2, 0.25), Vector3(-24.0, 0.6, 9.5), 0.0, wall_mat, true)
	_box(sw, "CompWall_2", Vector3(0.25, 1.2, 24.0), Vector3(-9.5, 0.6, 22.0), 0.0, wall_mat, true)

	# Dense Grove of Green Leafy Trees nestled between and around the houses (matching sketch!)
	var house_trees := [
		Vector2(-9.0, 12.0),
		Vector2(-22.0, 11.5),
		Vector2(-35.0, 12.0),
		Vector2(-10.0, 23.0),
		Vector2(-22.0, 23.0),
		Vector2(-35.0, 25.0),
		Vector2(-12.0, 36.0),
		Vector2(-24.0, 36.0),
		Vector2(-36.0, 36.0),
		Vector2(-42.0, 16.0),
		Vector2(-42.0, 28.0)
	]
	for pt in house_trees:
		_spawn_tree(sw, pt, randf_range(6.5, 9.0))

func _build_tiled_house(parent: Node3D, node_name: String, pos: Vector3, rot_y: float, size: Vector3) -> void:
	var house := Node3D.new()
	house.name = node_name
	house.position = pos
	house.rotation.y = rot_y
	parent.add_child(house)

	var w := size.x
	var wall_h := size.y
	var d := size.z
	var roof_h := 2.2

	# Main wall body (cream stucco)
	_box(house, "Walls", Vector3(w, wall_h, d), Vector3(0, wall_h * 0.5, 0), 0.0, _mat_wall_cream, true)

	# Pitched Terracotta Roof (Prism mesh)
	var roof_box := _prism(house, "PitchedRoof", Vector3(w + 0.8, roof_h, d + 0.8), Vector3(0, wall_h + roof_h * 0.5, 0), Vector3.ZERO, _mat_roof_tile, true)

	# Brick / Concrete Plinth base
	_box(house, "Plinth", Vector3(w + 0.4, 0.35, d + 0.4), Vector3(0, 0.175, 0), 0.0, _mat_curb, true)

	# Front Door (Facing +Z)
	_box(house, "Door", Vector3(1.1, 2.2, 0.10), Vector3(0, 1.1, d * 0.5 + 0.05), 0.0, _mat_wood, false)

	# Front Porch / Veranda with terracotta canopy
	_box(house, "PorchRoof", Vector3(2.6, 0.15, 1.6), Vector3(0, 2.6, d * 0.5 + 0.8), 0.0, _mat_roof_tile, true)
	_cylinder(house, "PorchPostL", 0.08, 2.6, Vector3(-1.1, 1.3, d * 0.5 + 1.5), Vector3.ZERO, _mat_wood, true)
	_cylinder(house, "PorchPostR", 0.08, 2.6, Vector3(1.1, 1.3, d * 0.5 + 1.5), Vector3.ZERO, _mat_wood, true)

	# Windows with wood frames & glass
	_window_facade(house, Vector3(-w * 0.28, 1.8, d * 0.5 + 0.05), Vector2(1.2, 1.2), 0.0)
	_window_facade(house, Vector3(w * 0.28, 1.8, d * 0.5 + 0.05), Vector2(1.2, 1.2), 0.0)

	# Chimney / Roof Vent
	_box(house, "Chimney", Vector3(0.65, 1.5, 0.65), Vector3(w * 0.3, wall_h + roof_h * 0.6, 0), 0.0, _mat_wall_cream, true)

# =========================================================================
# QUADRANT 4: SOUTH-EAST (Bus Stop & 2-Storey Commercial Building)
# =========================================================================
func _build_south_east_quadrant() -> void:
	var se := Node3D.new()
	se.name = "Quadrant_SE_BusStopAndCommercial"
	add_child(se)

	# -------------------------------------------------------------
	# Bus Stop: Open transit shelter with arched/pitched Blue metal roof
	# Position: X = [12, 25], Z = [8, 14]
	# -------------------------------------------------------------
	var bus_node := Node3D.new()
	bus_node.name = "ChowrastaBusStop"
	bus_node.position = Vector3(18.5, 0.0, 11.5)
	se.add_child(bus_node)

	var bs_w := 12.0
	var bs_d := 4.2
	var bs_h := 3.6
	# Raised concrete platform
	_box(bus_node, "Platform", Vector3(bs_w + 1.0, 0.30, bs_d + 1.0), Vector3(0, 0.15, 0), 0.0, _mat_sidewalk, true)

	# Curved / pitched bright blue metal canopy roof
	_box(bus_node, "CanopyRoof", Vector3(bs_w + 1.4, 0.25, bs_d + 1.4), Vector3(0, bs_h + 0.2, 0), 0.0, _mat_bus_blue, true)
	# Canopy side fascia
	_box(bus_node, "RoofFasciaF", Vector3(bs_w + 1.4, 0.35, 0.08), Vector3(0, bs_h + 0.15, -(bs_d + 1.4) * 0.5), 0.0, _mat_bus_blue, false)
	_box(bus_node, "RoofFasciaB", Vector3(bs_w + 1.4, 0.35, 0.08), Vector3(0, bs_h + 0.15, (bs_d + 1.4) * 0.5), 0.0, _mat_bus_blue, false)

	# 6 Steel Tubular Support Pillars (2 rows of 3)
	for px in [-bs_w * 0.42, 0.0, bs_w * 0.42]:
		for pz in [-bs_d * 0.35, bs_d * 0.35]:
			_cylinder(bus_node, "Pillar", 0.10, bs_h, Vector3(px, bs_h * 0.5, pz), Vector3.ZERO, _mat_steel, true)

	# Back metal safety rail & waiting benches
	_box(bus_node, "BackRail", Vector3(bs_w - 0.5, 1.1, 0.08), Vector3(0, 0.85, bs_d * 0.38), 0.0, _mat_steel, true)
	for bx in [-3.5, 3.5]:
		_box(bus_node, "Bench_%f" % bx, Vector3(3.2, 0.45, 0.65), Vector3(bx, 0.52, bs_d * 0.15), 0.0, _mat_wood, true)

	# Signboard: "BUS STOP" / "TGSRTC CHOWRASTA"
	_label(bus_node, "BUS STOP", Vector3(0, bs_h + 0.75, -(bs_d + 1.4) * 0.5 - 0.05), 180.0, 52, Color.WHITE, Color(0.12, 0.42, 0.78))
	_label(bus_node, "TGSRTC CHOWRASTA JUNCTION", Vector3(0, bs_h + 0.25, -(bs_d + 1.4) * 0.5 - 0.05), 180.0, 24, Color.WHITE)

	# -------------------------------------------------------------
	# Commercial Building: 2-Storey Modern Commercial Office Block
	# Position: X = [29, 48], Z = [8, 26]
	# Width: 18.0m, Depth: 16.0m, Height: 8.4m
	# Front Facade facing North (toward East Road):
	# FEATURES TWO TIERS OF 4 WINDOWS (8 LARGE RECTANGULAR WINDOWS!)
	# Exactly matching the sketch reference!
	# -------------------------------------------------------------
	var comm_pos := Vector3(38.5, 0.0, 17.0)
	var comm := Node3D.new()
	comm.name = "CommercialBuilding"
	comm.position = comm_pos
	se.add_child(comm)

	var c_w := 18.0
	var c_d := 16.0
	var c_h := 8.4

	# Main commercial structure (grey/blue concrete facade)
	_box(comm, "MainStructure", Vector3(c_w, c_h, c_d), Vector3(0, c_h * 0.5, 0), 0.0, _mat_wall_commercial, true)
	# Rooftop slab & parapet
	_box(comm, "RoofSlab", Vector3(c_w + 0.4, 0.25, c_d + 0.4), Vector3(0, c_h + 0.12, 0), 0.0, _mat_roof_flat, true)
	_box(comm, "Parapet_Front", Vector3(c_w + 0.4, 0.80, 0.25), Vector3(0, c_h + 0.50, -c_d * 0.5), 0.0, _mat_wall_commercial, true)

	# Signboard: "COMMERCIAL BUILDING"
	_label(comm, "COMMERCIAL BUILDING", Vector3(0, c_h + 1.25, -c_d * 0.5 - 0.15), 180.0, 48, Color.WHITE, Color(0.15, 0.22, 0.32))
	_label(comm, "OFFICES & COMPLEX", Vector3(0, c_h + 0.70, -c_d * 0.5 - 0.15), 180.0, 24, Color(0.9, 0.9, 0.9))

	# 8 LARGE RECTANGULAR WINDOWS IN 2 ROWS OF 4! (MATCHING SKETCH!)
	var window_spacing_x := [-6.0, -2.0, 2.0, 6.0]
	# Row 1 (Ground / Lower level: Y = 2.4m)
	for wx in window_spacing_x:
		_window_facade(comm, Vector3(wx, 2.4, -c_d * 0.5 - 0.05), Vector2(2.6, 2.0), 180.0)
	# Row 2 (Upper level: Y = 6.0m)
	for wx in window_spacing_x:
		_window_facade(comm, Vector3(wx, 6.0, -c_d * 0.5 - 0.05), Vector2(2.6, 2.0), 180.0)

	# Modern glass entrance double doors (between central lower windows)
	_box(comm, "EntranceLobbyDoors", Vector3(3.2, 2.8, 0.12), Vector3(0, 1.4, -c_d * 0.5 - 0.08), 0.0, _mat_dark_glass, false)

	# Rooftop AC units / Water Tank
	_add_water_tank(comm, Vector3(5.0, c_h + 0.9, 3.0), false)
	_add_water_tank(comm, Vector3(6.5, c_h + 0.9, 3.0), true)

	# Trees framing Bus Stop and Commercial Building
	var se_trees := [
		Vector2(10.0, 11.0),
		Vector2(26.0, 11.5),
		Vector2(25.0, 22.0),
		Vector2(50.0, 12.0),
		Vector2(50.0, 24.0)
	]
	for pt in se_trees:
		_spawn_tree(se, pt, randf_range(7.5, 9.5))

# =========================================================================
# EAST ROAD TRUCK (Orange Cab + White Container, heading West toward Chowrasta)
# =========================================================================
func _build_truck_on_east_road() -> void:
	# Orange Cab + White Container Commercial Delivery Truck
	# Position: X = +28.0, Z = +2.2 (in the westbound lane of East Road, heading -X toward Chowrasta!)
	var truck := StaticBody3D.new()
	truck.name = "DeliveryTruck_EastRoad"
	truck.position = Vector3(28.0, 0.0, 2.2)
	truck.rotation.y = deg_to_rad(90.0) # Heading West (-X)
	add_child(truck)

	var cab_w := 2.4
	var cab_h := 2.6
	var cab_l := 2.3

	var box_w := 2.45
	var box_h := 2.85
	var box_l := 5.6

	# Chassis frame
	_box(truck, "Chassis", Vector3(cab_w - 0.2, 0.35, 7.8), Vector3(0, 0.65, 0.6), 0.0, _mat_steel, true)

	# Orange Cabin (Front)
	_box(truck, "CabBody", Vector3(cab_w, cab_h, cab_l), Vector3(0, 1.85, -2.6), 0.0, _mat_truck_orange, true)
	# Cab front bumper & grille
	_box(truck, "FrontBumper", Vector3(cab_w + 0.1, 0.45, 0.35), Vector3(0, 0.75, -3.8), 0.0, _mat_steel, true)
	_box(truck, "FrontGrille", Vector3(1.6, 0.85, 0.08), Vector3(0, 1.4, -3.78), 0.0, _mat_steel, false)
	# Headlights
	_box(truck, "HeadlightL", Vector3(0.35, 0.22, 0.05), Vector3(-0.85, 0.85, -3.98), 0.0, _mat_chrome, false)
	_box(truck, "HeadlightR", Vector3(0.35, 0.22, 0.05), Vector3(0.85, 0.85, -3.98), 0.0, _mat_chrome, false)

	# Windshield (tinted dark glass, facing forward)
	_box(truck, "Windshield", Vector3(2.1, 1.1, 0.08), Vector3(0, 2.4, -3.76), 0.0, _mat_dark_glass, false)

	# Side Windows & Mirrors
	_box(truck, "SideWindowL", Vector3(0.06, 0.8, 1.0), Vector3(-cab_w * 0.5 - 0.02, 2.3, -2.6), 0.0, _mat_dark_glass, false)
	_box(truck, "SideWindowR", Vector3(0.06, 0.8, 1.0), Vector3(cab_w * 0.5 + 0.02, 2.3, -2.6), 0.0, _mat_dark_glass, false)
	_box(truck, "MirrorL", Vector3(0.12, 0.35, 0.18), Vector3(-cab_w * 0.5 - 0.25, 2.2, -3.4), 0.0, _mat_steel, false)
	_box(truck, "MirrorR", Vector3(0.12, 0.35, 0.18), Vector3(cab_w * 0.5 + 0.25, 2.2, -3.4), 0.0, _mat_steel, false)

	# White Cargo Container (Rear)
	_box(truck, "CargoBox", Vector3(box_w, box_h, box_l), Vector3(0, 2.1, 1.4), 0.0, _mat_truck_white, true)
	# Cargo box vertical ribs
	for rz in [-1.0, 0.2, 1.4, 2.6, 3.8]:
		_box(truck, "RibL_%f" % rz, Vector3(0.06, box_h - 0.1, 0.10), Vector3(-box_w * 0.5 - 0.02, 2.1, rz), 0.0, _mat_truck_white, false)
		_box(truck, "RibR_%f" % rz, Vector3(0.06, box_h - 0.1, 0.10), Vector3(box_w * 0.5 + 0.02, 2.1, rz), 0.0, _mat_truck_white, false)

	# Rear Truck Typography & Chevron safety markings
	_label(truck, "HORN PLEASE   OK", Vector3(0, 2.6, 4.22), 0.0, 36, Color(0.9, 0.2, 0.1), Color(0.95, 0.85, 0.2))
	_label(truck, "ALL INDIA PERMIT", Vector3(0, 1.9, 4.22), 0.0, 26, Color(0.1, 0.2, 0.8))

	# 6 Heavy Duty Truck Wheels (Front pair, Rear dual pairs)
	var wheel_radius := 0.48
	var wheel_width := 0.32
	var wheel_z := [-2.6, 2.2, 3.6]
	for wz in wheel_z:
		_cylinder(truck, "WheelL", wheel_radius, wheel_width, Vector3(-cab_w * 0.5 + 0.1, wheel_radius, wz), Vector3(0, 0, 90), _mat_steel, true)
		_cylinder(truck, "WheelR", wheel_radius, wheel_width, Vector3(cab_w * 0.5 - 0.1, wheel_radius, wz), Vector3(0, 0, 90), _mat_steel, true)

# =========================================================================
# VEHICLES: Red Car (North), Cyan Car (South), Blue Car (West), Tuk-Tuk
# =========================================================================
func _spawn_vehicles() -> void:
	var veh_root := Node3D.new()
	veh_root.name = "DrivableVehicles"
	add_child(veh_root)

	# 1. Red Car on North Road (heading South toward Chowrasta, Z = -22.0, X = 2.8)
	var red_car: RigidVehicle = _instantiate_car(CAR_SCENE, Vector3(2.8, 0.8, -22.0), deg_to_rad(180.0), Color(0.85, 0.12, 0.12))
	red_car.name = "RedCar_NorthRoad"
	veh_root.add_child(red_car)
	vehicles.append(red_car)

	# 2. Cyan / Light Blue Car on South Road (heading North toward Chowrasta, Z = 22.0, X = -2.8)
	var cyan_car: RigidVehicle = _instantiate_car(CAR_SCENE, Vector3(-2.8, 0.8, 22.0), 0.0, Color(0.15, 0.72, 0.90))
	cyan_car.name = "CyanCar_SouthRoad"
	veh_root.add_child(cyan_car)
	vehicles.append(cyan_car)

	# 3. Blue Car on West Road (heading East toward Chowrasta, X = -24.0, Z = -2.2)
	var blue_car: RigidVehicle = _instantiate_car(CAR_SCENE, Vector3(-24.0, 0.8, -2.2), deg_to_rad(-90.0), Color(0.12, 0.35, 0.85))
	blue_car.name = "BlueCar_WestRoad"
	veh_root.add_child(blue_car)
	vehicles.append(blue_car)

	# 4. Indian Tuk-Tuk / Auto Rickshaw parked near the shopfront corner
	var tuk_tuk: RigidVehicle = _instantiate_car(TUK_TUK_SCENE, Vector3(8.5, 0.8, -7.5), deg_to_rad(75.0), Color(0.14, 0.55, 0.28))
	tuk_tuk.name = "AutoRickshaw_Chowrasta"
	veh_root.add_child(tuk_tuk)
	vehicles.append(tuk_tuk)

	for v in vehicles:
		parked_transforms[v] = v.global_transform
		v.set_driving_enabled(false)
		v.set_keyboard_input_enabled(false)

	active_vehicle = red_car

func _instantiate_car(scene: PackedScene, pos: Vector3, yaw: float, color: Color) -> RigidVehicle:
	var car: RigidVehicle = scene.instantiate()
	car.position = pos
	car.rotation.y = yaw
	car.paint_color = color
	car.respawn_position = pos
	car.add_to_group("enterable_vehicle")
	return car

# =========================================================================
# STREET FURNITURE & AMBIENCE (Utility Poles, CCTV, Chai Stall, Panipuri)
# =========================================================================
func _build_street_furniture() -> void:
	var props := Node3D.new()
	props.name = "StreetProps"
	add_child(props)

	# Utility Poles along the roads
	var pole_res := load(UTILITY_POLE_SCENE) as PackedScene
	if pole_res:
		var pole_spots := [
			Vector3(-6.8, 0, -25.0),
			Vector3(-6.8, 0, -50.0),
			Vector3(6.8, 0, 25.0),
			Vector3(6.8, 0, 50.0),
			Vector3(-25.0, 0, 5.8),
			Vector3(-50.0, 0, 5.8),
			Vector3(25.0, 0, -5.8),
			Vector3(50.0, 0, -5.8)
		]
		for p in pole_spots:
			var pole := pole_res.instantiate()
			pole.position = p
			props.add_child(pole)

	# CCTV Camera Pole at the Chowrasta junction corner
	var cctv_res := load(CCTV_SCENE) as PackedScene
	if cctv_res:
		var cctv := cctv_res.instantiate()
		cctv.position = Vector3(6.8, 0, -5.8)
		cctv.rotation.y = deg_to_rad(-135.0) # Aiming into the intersection!
		props.add_child(cctv)

	# Chai / Tea Stall near the shop row
	var tea_res := load(TEA_STALL_SCENE) as PackedScene
	if tea_res:
		var tea := tea_res.instantiate()
		tea.position = Vector3(8.5, 0.20, -10.5)
		tea.rotation.y = deg_to_rad(-45.0)
		props.add_child(tea)

	# Wooden stools by chai stall
	var stool_res := load(STOOL_SCENE) as PackedScene
	if stool_res:
		for offset in [Vector3(7.8, 0.20, -11.5), Vector3(8.8, 0.20, -11.8), Vector3(9.2, 0.20, -10.8)]:
			var stool := stool_res.instantiate()
			stool.position = offset
			props.add_child(stool)

	# Panipuri Cart near corner
	var panipuri_res := load(PANIPURI_SCENE) as PackedScene
	if panipuri_res:
		var cart := panipuri_res.instantiate()
		cart.position = Vector3(-7.2, 0.20, 6.8)
		cart.rotation.y = deg_to_rad(40.0)
		cart.scale = Vector3.ONE * 0.01
		props.add_child(cart)

# =========================================================================
# PLAYER, VEHICLE ENTRY & HUD
# =========================================================================
func _setup_player_and_hud() -> void:
	# Instantiate Player Character
	person = PERSON_SCENE.instantiate()
	person.name = "Player"
	# Spawns on the sidewalk at the Chowrasta junction
	person.position = Vector3(4.5, 0.35, 4.5)
	add_child(person)

	# Instantiate VehicleEntry system
	var entry_script := load("res://scripts/vehicle/vehicle_entry.gd") as GDScript
	if entry_script:
		entry = entry_script.new()
		entry.name = "VehicleEntry"
		entry.finished.connect(_on_entry_finished)
		add_child(entry)

	# Instantiate HUD
	hud = HUD_SCENE.instantiate()
	hud.name = "HUD"
	add_child(hud)
	hud.configure_player(person, active_vehicle, self)

	# City Switcher button
	_create_city_switch_ui()

func _create_city_switch_ui() -> void:
	var btn := Button.new()
	btn.text = "Switch Map: Godavarikhani"
	btn.name = "CitySwitchBtn"
	btn.position = Vector2(16, 80)
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	hud.add_child(btn)

func _process(_delta: float) -> void:
	if person == null:
		return

	# Handle enter/exit prompts when on foot
	if control_state == ControlState.ON_FOOT:
		var nearest := _nearest_vehicle()
		if nearest and person.global_position.distance_to(nearest.global_position) < 4.0:
			hud.set_enter_available(true)
			hud.set_interaction_prompt("[E] Drive %s" % nearest.name.replace("_", " "))
			if Input.is_action_just_pressed("service") or Input.is_action_just_pressed("loot") or Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_E):
				enter_vehicle(nearest)
		else:
			hud.set_enter_available(false)
			hud.set_interaction_prompt("")
	elif control_state == ControlState.DRIVING and active_vehicle:
		hud.set_speed(active_vehicle.current_speed)
		hud.set_interaction_prompt("")
		if Input.is_action_just_pressed("service") or Input.is_action_just_pressed("loot") or Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_E):
			exit_vehicle()

func _nearest_vehicle() -> PhysicsBody3D:
	var best: PhysicsBody3D = null
	var best_dist := 999999.0
	for v in vehicles:
		var d := person.global_position.distance_to(v.global_position)
		if d < best_dist:
			best_dist = d
			best = v
	return best

func enter_vehicle(target: PhysicsBody3D) -> void:
	if control_state != ControlState.ON_FOOT or target == null:
		return
	active_vehicle = target
	hud.set_active_vehicle(active_vehicle)
	control_state = ControlState.ENTERING
	person.set_movement_enabled(false)
	person.set_collision_enabled(false)
	person.velocity = Vector3.ZERO
	if entry:
		entry.begin_enter(person, active_vehicle)
	_set_camera_target(active_vehicle)
	hud.set_vehicle_mode(true)

func exit_vehicle() -> void:
	if control_state != ControlState.DRIVING or active_vehicle == null:
		return
	if absf(active_vehicle.current_speed) > exit_speed_limit:
		_show_control_hint("Slow down before exiting")
		return
	var exit_pos := active_vehicle.global_position + active_vehicle.global_transform.basis.x * -2.2
	control_state = ControlState.EXITING
	active_vehicle.set_driving_enabled(false)
	active_vehicle.set_keyboard_input_enabled(false)
	active_vehicle.velocity = Vector3.ZERO
	person.set_movement_enabled(false)
	person.visible = true
	if entry:
		entry.begin_exit(exit_pos)
	else:
		person.global_position = exit_pos
		_finish_exit_vehicle()
	_set_camera_target(person)
	hud.set_vehicle_mode(false)

func _on_entry_finished(entered: bool) -> void:
	if entered:
		_finish_enter_vehicle()
	else:
		_finish_exit_vehicle()

func _finish_enter_vehicle() -> void:
	control_state = ControlState.DRIVING
	active_vehicle.set_driving_enabled(true)
	active_vehicle.set_keyboard_input_enabled(true)
	active_vehicle.set_input_authority(true)
	hud.set_vehicle_mode(true)
	hud.show_vehicle_controls_hint()

func _finish_exit_vehicle() -> void:
	control_state = ControlState.ON_FOOT
	person.set_movement_enabled(true)
	person.set_collision_enabled(true)
	person.visible = true
	hud.set_vehicle_mode(false)

func _set_camera_target(target: Node3D) -> void:
	var person_cam := person.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	var car_cam := target.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if target == person:
		if person_cam: person_cam.current = true
		if car_cam: car_cam.current = false
	else:
		if car_cam: car_cam.current = true
		if person_cam: person_cam.current = false

func _show_control_hint(msg: String) -> void:
	if hud and hud.has_method("set_interaction_prompt"):
		hud.set_interaction_prompt(msg)

# =========================================================================
# PROCEDURAL MESH GENERATION HELPERS
# =========================================================================
func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, rot_y: float, mat: Material, add_collision: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	instance.mesh = box_mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation.y = rot_y
	parent.add_child(instance)

	if add_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "_Col"
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		instance.add_child(body)

	return instance

func _cylinder(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, rot: Vector3, mat: Material, add_collision: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	instance.mesh = cyl
	instance.material_override = mat
	instance.position = pos
	instance.rotation_degrees = rot
	parent.add_child(instance)

	if add_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "_Col"
		var shape := CollisionShape3D.new()
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = radius
		cyl_shape.height = height
		shape.shape = cyl_shape
		body.add_child(shape)
		instance.add_child(body)

	return instance

func _prism(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, rot: Vector3, mat: Material, add_collision: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var prism := PrismMesh.new()
	prism.size = size
	instance.mesh = prism
	instance.material_override = mat
	instance.position = pos
	instance.rotation_degrees = rot
	parent.add_child(instance)

	if add_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "_Col"
		var shape := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = size * Vector3(1.0, 0.7, 1.0)
		shape.shape = col_shape
		body.add_child(shape)
		instance.add_child(body)

	return instance

func _label(parent: Node3D, text: String, pos: Vector3, rot_y: float, font_size: int, color: Color, bg_color: Color = Color.TRANSPARENT) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.position = pos
	wrapper.rotation_degrees.y = rot_y
	parent.add_child(wrapper)

	if bg_color.a > 0.01:
		var bg_mat := StandardMaterial3D.new()
		bg_mat.albedo_color = bg_color
		bg_mat.roughness = 0.6
		var char_count := text.length()
		var bg_w := maxf(float(char_count) * 0.35, 1.6)
		_box(wrapper, "LabelBG", Vector3(bg_w, 0.85, 0.04), Vector3(0, 0, -0.02), 0.0, bg_mat, false)

	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = font_size
	lbl.pixel_size = 0.005
	lbl.modulate = color
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.05, 0.05, 0.05)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrapper.add_child(lbl)

	return wrapper

func _window_facade(parent: Node3D, pos: Vector3, size: Vector2, rot_y: float) -> void:
	var win_node := Node3D.new()
	win_node.position = pos
	win_node.rotation_degrees.y = rot_y
	parent.add_child(win_node)

	# Dark Outer Frame
	_box(win_node, "Frame", Vector3(size.x, size.y, 0.08), Vector3.ZERO, 0.0, _mat_steel, false)
	# Glass Pane
	_box(win_node, "Glass", Vector3(size.x - 0.16, size.y - 0.16, 0.10), Vector3.ZERO, 0.0, _mat_glass, false)
	# Window Sill
	_box(win_node, "Sill", Vector3(size.x + 0.20, 0.08, 0.22), Vector3(0, -size.y * 0.5 - 0.04, 0.05), 0.0, _mat_curb, false)

func _add_water_tank(parent: Node3D, pos: Vector3, is_black: bool) -> void:
	var tank_mat := StandardMaterial3D.new()
	tank_mat.albedo_color = Color(0.12, 0.12, 0.12) if is_black else Color(0.92, 0.94, 0.95)
	tank_mat.roughness = 0.35
	_cylinder(parent, "WaterTank", 0.55, 1.2, pos, Vector3.ZERO, tank_mat, true)

func _spawn_tree(parent: Node3D, map_pos: Vector2, height: float) -> void:
	var tree := MeshInstance3D.new()
	tree.name = "Tree"
	tree.position = Vector3(map_pos.x, 0, map_pos.y)

	if _tree_mesh and _tree_shader_mat:
		tree.mesh = _tree_mesh
		tree.material_override = _tree_shader_mat
		var scale_factor: float = height / 7.2
		tree.scale = Vector3(scale_factor, scale_factor, scale_factor)
	else:
		# Fallback volumetric foliage sphere + trunk
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.25
		trunk.bottom_radius = 0.35
		trunk.height = height * 0.45
		var trunk_inst := MeshInstance3D.new()
		trunk_inst.mesh = trunk
		trunk_inst.material_override = _mat_tree_trunk
		trunk_inst.position.y = trunk.height * 0.5
		tree.add_child(trunk_inst)

		var crown := SphereMesh.new()
		crown.radius = height * 0.35
		crown.height = height * 0.70
		var crown_inst := MeshInstance3D.new()
		crown_inst.mesh = crown
		crown_inst.material_override = _mat_tree_foliage
		crown_inst.position.y = height * 0.65
		tree.add_child(crown_inst)

	# Trunk collision
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.30
	shape.height = 3.5
	col.shape = shape
	col.position = Vector3(0, 1.75, 0)
	body.add_child(col)
	tree.add_child(body)

	parent.add_child(tree)
