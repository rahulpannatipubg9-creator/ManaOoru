class_name VidyaNagarTwoStreetBuilder
extends Node3D

## Street replica builder for Vidyanagar Road No. 2 based on 17 sequential
## Google Street View reference photos and satellite footprints.
## Adds modular procedural house elements, corrugated porches, compound walls,
## gates, authentic color palettes, water tanks, and setback trees.

const PHOTO_SEQUENCE_PATH := "res://data/local/vidyanagar2_photo_sequence.json"
const VISIBILITY_DISTANCE := 220.0
const IMPOSTOR_TEXTURE := preload("res://assets/textures/trees/broadleaf_impostor.png")
const BANANA_TREE_SCENE := preload("res://assets/models/foliage/banana_tree.glb")
## Keep the authored photo-reference houses behind the mapped residential
## carriageway.  Their porches are part of the frontage, so the clearance is
## measured from the outer porch edge rather than only from the wall body.
const ROAD_HALF_WIDTH := 2.25
const FRONTAGE_GAP := 0.35

# Materials
var _pale_blue_mat: StandardMaterial3D
var _cream_mat: StandardMaterial3D
var _pale_green_mat: StandardMaterial3D
var _brick_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _corrugated_zinc_mat: StandardMaterial3D
var _corrugated_blue_mat: StandardMaterial3D
var _gate_mat: StandardMaterial3D
var _steel_post_mat: StandardMaterial3D
var _tank_black_mat: StandardMaterial3D
var _tank_white_mat: StandardMaterial3D
var _concrete_slab_mat: StandardMaterial3D
var _jaali_mat: StandardMaterial3D
var _tree_shader_mat: ShaderMaterial

# Shared Meshes
var _tree_mesh: ArrayMesh

var wall_count := 0
var gate_count := 0
var porch_count := 0
var house_count := 0
var tank_count := 0
var tree_count := 0
var banana_tree_count := 0

func _init() -> void:
	name = "VidyaNagar2Street"
	_init_materials()
	_init_tree_mesh()

func _init_materials() -> void:
	_pale_blue_mat = StandardMaterial3D.new()
	_pale_blue_mat.albedo_color = Color("#b9d4e0")
	_pale_blue_mat.roughness = 0.90

	_cream_mat = StandardMaterial3D.new()
	_cream_mat.albedo_color = Color("#f4f1ea")
	_cream_mat.roughness = 0.90

	_pale_green_mat = StandardMaterial3D.new()
	_pale_green_mat.albedo_color = Color("#c9dfb7")
	_pale_green_mat.roughness = 0.90

	_brick_mat = StandardMaterial3D.new()
	_brick_mat.albedo_color = Color("#8f4234")
	_brick_mat.roughness = 0.95

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color("#d3cec4")
	_wall_mat.roughness = 0.92

	_corrugated_zinc_mat = StandardMaterial3D.new()
	_corrugated_zinc_mat.albedo_color = Color("#848d94")
	_corrugated_zinc_mat.metallic = 0.55
	_corrugated_zinc_mat.roughness = 0.52

	_corrugated_blue_mat = StandardMaterial3D.new()
	_corrugated_blue_mat.albedo_color = Color("#2a557a")
	_corrugated_blue_mat.roughness = 0.70

	_gate_mat = StandardMaterial3D.new()
	_gate_mat.albedo_color = Color("#223328")
	_gate_mat.metallic = 0.80
	_gate_mat.roughness = 0.40

	_steel_post_mat = StandardMaterial3D.new()
	_steel_post_mat.albedo_color = Color("#44494d")
	_steel_post_mat.metallic = 0.70
	_steel_post_mat.roughness = 0.50

	_tank_black_mat = StandardMaterial3D.new()
	_tank_black_mat.albedo_color = Color("#181818")
	_tank_black_mat.roughness = 0.35

	_tank_white_mat = StandardMaterial3D.new()
	_tank_white_mat.albedo_color = Color("#e2e5e8")
	_tank_white_mat.roughness = 0.40

	_concrete_slab_mat = StandardMaterial3D.new()
	_concrete_slab_mat.albedo_color = Color("#827d75")
	_concrete_slab_mat.roughness = 0.95

	_jaali_mat = StandardMaterial3D.new()
	_jaali_mat.albedo_color = Color("#cfcbbe")
	_jaali_mat.roughness = 0.90

	_tree_shader_mat = ShaderMaterial.new()
	_tree_shader_mat.shader = preload("res://shaders/tree_impostor.gdshader")
	_tree_shader_mat.set_shader_parameter("impostor", IMPOSTOR_TEXTURE)

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

func build(world: Node, _map_data: MapData) -> void:
	if not FileAccess.file_exists(PHOTO_SEQUENCE_PATH):
		push_warning("Vidyanagar 2 photo sequence file missing")
		return
	var text: String = FileAccess.get_file_as_string(PHOTO_SEQUENCE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.has("camera_points_lat_lon"):
		push_warning("Invalid Vidyanagar 2 photo sequence format")
		return

	var raw_points: Array = parsed.camera_points_lat_lon
	if raw_points.size() < 17:
		return

	var map_pts: Array[Vector2] = []
	for p: Array in raw_points:
		# lat, lon format in json
		var lat: float = float(p[0])
		var lon: float = float(p[1])
		map_pts.append(GeoProjection.lon_lat_to_map(lon, lat))

	# Group 1: Photos 1 to 5 (Indices 0 to 4) - Entrance Lane, tight houses left, wall & trees right
	_build_segment_1(world, map_pts[0], map_pts[4])

	# Group 2: Photos 6 to 9 (Indices 5 to 8) - Wide tree-lined setbacks, single-storey quarters, low walls & gates
	_build_segment_2(world, map_pts[5], map_pts[8])

	# Group 3: Photos 10 to 12 (Indices 9 to 11) - Narrower lane, taller pale blue dwelling right, brick parapet, dense vegetation left
	_build_segment_3(world, map_pts[9], map_pts[11])

	# Group 4: Photos 13 to 17 (Indices 12 to 16) - Closely spaced low houses, pale colors, corrugated porches, water tanks
	_build_segment_4(world, map_pts[12], map_pts[16])

	print("Vidya Nagar 2 street replica built: %d walls, %d gates, %d porches, %d houses, %d water tanks, %d trees, %d banana trees" %
		[wall_count, gate_count, porch_count, house_count, tank_count, tree_count, banana_tree_count])

## Segment 1: Photos 1-5 - Entrance section
func _build_segment_1(world: Node, p_start: Vector2, p_end: Vector2) -> void:
	var dir: Vector2 = (p_end - p_start).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x) # +normal = right, -normal = left
	var length: float = p_start.distance_to(p_end)

	# Left side (houses close to lane, corrugated porch roofs, window grilles)
	var house1_pt: Vector2 = _house_center(p_start + dir * (length * 0.28), -normal, 6.0, 2.2)
	_build_house_facade(world, house1_pt, dir, -normal, 7.5, 3.4, 6.0, _pale_blue_mat, true, true, false)

	var house2_pt: Vector2 = _house_center(p_start + dir * (length * 0.72), -normal, 5.5, 2.2)
	_build_house_facade(world, house2_pt, dir, -normal, 7.0, 3.4, 5.5, _cream_mat, true, false, false)

	# Right side (continuous compound wall and roadside trees)
	var wall_start: Vector2 = p_start + dir * 3.0 + normal * 2.8
	var wall_end: Vector2 = p_end - dir * 2.0 + normal * 2.8
	_build_compound_wall(world, wall_start, wall_end, 1.05)

	var tree_pt: Vector2 = p_start + dir * (length * 0.50) + normal * 4.6
	_add_tree(world, tree_pt, 7.5)

	# Front garden banana tree (Arati chettu)
	var banana_pt1: Vector2 = p_start + dir * (length * 0.35) - normal * 3.8
	_add_banana_tree(world, banana_pt1, 0.4, 1.0)

## Segment 2: Photos 6-9 - Wide tree-lined setbacks, quarters, low walls & gates
func _build_segment_2(world: Node, p_start: Vector2, p_end: Vector2) -> void:
	var dir: Vector2 = (p_end - p_start).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var length: float = p_start.distance_to(p_end)

	# Left side set back: low wall with gate, single-storey quarters
	var left_house_pt: Vector2 = p_start + dir * (length * 0.45) - normal * 7.5
	_build_house_facade(world, left_house_pt, dir, -normal, 8.5, 3.3, 6.5, _cream_mat, false, false, true)

	var left_wall_a: Vector2 = p_start + dir * 1.5 - normal * 4.2
	var left_gate_a: Vector2 = p_start + dir * (length * 0.38) - normal * 4.2
	var left_gate_b: Vector2 = p_start + dir * (length * 0.52) - normal * 4.2
	var left_wall_b: Vector2 = p_end - dir * 1.5 - normal * 4.2
	_build_compound_wall(world, left_wall_a, left_gate_a, 0.95)
	_build_gate(world, (left_gate_a + left_gate_b) * 0.5, dir, 2.4, 1.1)
	_build_compound_wall(world, left_gate_b, left_wall_b, 0.95)

	# Right side set back: low wall with gate, single-storey quarters
	var right_house_pt: Vector2 = p_start + dir * (length * 0.50) + normal * 7.5
	_build_house_facade(world, right_house_pt, dir, normal, 8.0, 3.3, 6.0, _pale_green_mat, false, false, true)

	var right_wall_a: Vector2 = p_start + dir * 1.5 + normal * 4.2
	var right_gate_a: Vector2 = p_start + dir * (length * 0.42) + normal * 4.2
	var right_gate_b: Vector2 = p_start + dir * (length * 0.56) + normal * 4.2
	var right_wall_b: Vector2 = p_end - dir * 1.5 + normal * 4.2
	_build_compound_wall(world, right_wall_a, right_gate_a, 0.95)
	_build_gate(world, (right_gate_a + right_gate_b) * 0.5, dir, 2.4, 1.1)
	_build_compound_wall(world, right_gate_b, right_wall_b, 0.95)

	# Roadside drainage slab crossing the shoulder
	var drain_pt: Vector2 = p_start + dir * (length * 0.25) - normal * 2.8
	var drain_ground: float = float(world.ground_height(drain_pt))
	_build_box_mesh("DrainSlab", Vector3(1.4, 0.15, 2.2), Vector3(drain_pt.x, drain_ground + 0.05, drain_pt.y), atan2(dir.x, dir.y), _concrete_slab_mat)

	# Spaced shade trees along open setbacks
	_add_tree(world, p_start + dir * (length * 0.20) - normal * 4.8, 8.0)
	_add_tree(world, p_start + dir * (length * 0.75) - normal * 5.0, 7.8)
	_add_tree(world, p_start + dir * (length * 0.30) + normal * 4.8, 8.2)
	_add_tree(world, p_start + dir * (length * 0.80) + normal * 4.9, 7.6)

	# Residential yard banana tree
	var banana_pt2: Vector2 = p_start + dir * (length * 0.50) - normal * 3.9
	_add_banana_tree(world, banana_pt2, -0.6, 1.1)

## Segment 3: Photos 10-12 - Narrow lane, taller pale blue dwelling right, dense vegetation left
func _build_segment_3(world: Node, p_start: Vector2, p_end: Vector2) -> void:
	var dir: Vector2 = (p_end - p_start).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var length: float = p_start.distance_to(p_end)

	# Right side: Taller pale blue dwelling (2-storey, 6.4m), exposed brick parapet, steps, gate, porch roof
	var tall_house_pt: Vector2 = _house_center(p_start + dir * (length * 0.50), normal, 6.5, 2.4)
	_build_taller_dwelling(world, tall_house_pt, dir, normal, 9.0, 6.4, 6.5)

	# Compound wall & gate in front of the tall dwelling
	var r_wall_a: Vector2 = p_start + dir * 1.0 + normal * 2.9
	var r_gate_a: Vector2 = p_start + dir * (length * 0.35) + normal * 2.9
	var r_gate_b: Vector2 = p_start + dir * (length * 0.55) + normal * 2.9
	var r_wall_b: Vector2 = p_end - dir * 1.0 + normal * 2.9
	_build_compound_wall(world, r_wall_a, r_gate_a, 1.1)
	_build_gate(world, (r_gate_a + r_gate_b) * 0.5, dir, 2.4, 1.2)
	_build_compound_wall(world, r_gate_b, r_wall_b, 1.1)

	# Left side: Dense lush vegetation / tree cluster
	var left_veg_1: Vector2 = p_start + dir * (length * 0.25) - normal * 3.8
	var left_veg_2: Vector2 = p_start + dir * (length * 0.60) - normal * 4.2
	var left_veg_3: Vector2 = p_start + dir * (length * 0.85) - normal * 3.6
	_add_tree(world, left_veg_1, 7.5)
	_add_tree(world, left_veg_2, 8.5)
	_add_tree(world, left_veg_3, 7.0)
	_add_banana_tree(world, p_start + dir * (length * 0.42) - normal * 3.9, 1.2, 0.95)
	_add_banana_tree(world, p_start + dir * (length * 0.72) - normal * 4.0, -0.8, 1.05)
	_build_compound_wall(world, p_start + normal * -2.8, p_end + normal * -2.8, 0.90)

## Segment 4: Photos 13-17 - Closely spaced low houses, pale green/cream/blue, corrugated porches, water tanks
func _build_segment_4(world: Node, p_start: Vector2, p_end: Vector2) -> void:
	var dir: Vector2 = (p_end - p_start).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var length: float = p_start.distance_to(p_end)

	# House 1 (left): Pale mint green, corrugated zinc porch, black Sintex water tank
	var h1_pt: Vector2 = _house_center(p_start + dir * (length * 0.18), -normal, 5.5, 2.2)
	_build_house_facade(world, h1_pt, dir, -normal, 7.2, 3.4, 5.5, _pale_green_mat, true, true, false, true, false)

	# House 2 (right): Warm cream, blue awning, white water tank, ventilation blocks
	var h2_pt: Vector2 = _house_center(p_start + dir * (length * 0.38), normal, 5.2, 2.2)
	_build_house_facade(world, h2_pt, dir, normal, 7.0, 3.4, 5.2, _cream_mat, true, false, true, false, true)

	# House 3 (left): Pale sky blue, corrugated porch, black water tank, steps
	var h3_pt: Vector2 = _house_center(p_start + dir * (length * 0.62), -normal, 5.5, 2.2)
	_build_house_facade(world, h3_pt, dir, -normal, 7.5, 3.4, 5.5, _pale_blue_mat, true, true, false, true, true)

	# House 4 (right): Pale mint green, low boundary wall with gate, white water tank
	var h4_pt: Vector2 = _house_center(p_start + dir * (length * 0.82), normal, 5.5, 2.2)
	_build_house_facade(world, h4_pt, dir, normal, 7.2, 3.4, 5.5, _pale_green_mat, true, false, false, false, true)

	# Front boundary wall segments along the lane
	_build_compound_wall(world, p_start - normal * 2.6, p_start + dir * (length * 0.45) - normal * 2.6, 0.90)
	_build_compound_wall(world, p_start + dir * (length * 0.55) - normal * 2.6, p_end - normal * 2.6, 0.90)
	_build_compound_wall(world, p_start + normal * 2.6, p_start + dir * (length * 0.40) + normal * 2.6, 0.90)
	_add_banana_tree(world, p_start + dir * (length * 0.25) + normal * 3.8, 0.7, 1.0)
	_build_compound_wall(world, p_start + dir * (length * 0.50) + normal * 2.6, p_end + normal * 2.6, 0.90)

## Builds a modular house facade with flat slab roof, parapet, optional corrugated porch, and water tank
func _build_house_facade(world: Node, center_map: Vector2, road_dir: Vector2, outward_normal: Vector2,
		width: float, height: float, depth: float, paint: Material,
		has_porch: bool, porch_zinc: bool, has_blue_awning: bool,
		tank_black: bool = false, tank_white: bool = false) -> void:
	var yaw: float = atan2(road_dir.x, road_dir.y)
	var ground: float = float(world.ground_height(center_map))
	var house := Node3D.new()
	house.name = "House_%d" % (house_count + 1)
	add_child(house)
	house_count += 1

	# Main house body
	_box(house, "BuildingBody", Vector3(width, height, depth), Vector3(center_map.x, ground + height * 0.5, center_map.y), yaw, paint, true)

	# Parapet around the flat roof
	var roof_y: float = ground + height
	_box(house, "RoofParapet", Vector3(width + 0.1, 0.45, depth + 0.1), Vector3(center_map.x, roof_y + 0.22, center_map.y), yaw, paint)

	# Porch or Awning extending toward lane
	if has_porch or has_blue_awning:
		var porch_w: float = width * 0.65
		var porch_depth: float = 2.2
		var porch_center: Vector2 = center_map + outward_normal * (depth * 0.5 + porch_depth * 0.5)
		var porch_y: float = ground + 2.75
		var mat: Material = _corrugated_blue_mat if has_blue_awning else (_corrugated_zinc_mat if porch_zinc else _wall_mat)
		_box(house, "PorchRoof", Vector3(porch_w, 0.10, porch_depth), Vector3(porch_center.x, porch_y, porch_center.y), yaw, mat)

		# Slender steel support posts at outer corners
		for side: float in [-1.0, 1.0]:
			var post_map: Vector2 = porch_center + road_dir * (side * (porch_w * 0.45)) + outward_normal * (porch_depth * 0.45)
			_box(house, "PorchPost", Vector3(0.07, 2.7, 0.07), Vector3(post_map.x, ground + 1.35, post_map.y), yaw, _steel_post_mat)
		porch_count += 1

	# Entry plinth steps
	var step_center: Vector2 = center_map + outward_normal * (depth * 0.5 + 0.5)
	_box(house, "EntryStepLower", Vector3(2.0, 0.18, 0.6), Vector3(step_center.x, ground + 0.09, step_center.y), yaw, _concrete_slab_mat)
	_box(house, "EntryStepUpper", Vector3(1.6, 0.18, 0.4), Vector3(step_center.x - outward_normal.x * 0.15, ground + 0.27, step_center.y - outward_normal.y * 0.15), yaw, _concrete_slab_mat)

	# Water tank on roof
	if tank_black or tank_white:
		var tank_map: Vector2 = center_map - road_dir * (width * 0.3) - outward_normal * (depth * 0.25)
		_add_water_tank(house, Vector3(tank_map.x, roof_y + 0.70, tank_map.y), tank_black)

## Return a frontage centre whose outermost porch/awning edge stays beyond the
## mapped road.  This keeps the visual house bodies and their roofs out of the
## lane while preserving the photo-reference alignment along the road.
func _house_center(along_lane: Vector2, outward_normal: Vector2, depth: float, frontage_depth: float) -> Vector2:
	var offset := ROAD_HALF_WIDTH + FRONTAGE_GAP + depth * 0.5 + frontage_depth
	return along_lane + outward_normal.normalized() * offset

## Builds the taller 2-storey dwelling from Segment 3 with exposed brick parapet
func _build_taller_dwelling(world: Node, center_map: Vector2, road_dir: Vector2, outward_normal: Vector2,
		width: float, height: float, depth: float) -> void:
	var yaw: float = atan2(road_dir.x, road_dir.y)
	var ground: float = float(world.ground_height(center_map))
	var house := Node3D.new()
	house.name = "TallerDwelling_01"
	add_child(house)
	house_count += 1

	# 2-Storey pale blue body
	_box(house, "BuildingBody", Vector3(width, height, depth), Vector3(center_map.x, ground + height * 0.5, center_map.y), yaw, _pale_blue_mat, true)

	# Exposed red-brick parapet on rooftop
	var roof_y: float = ground + height
	_box(house, "ExposedBrickParapet", Vector3(width + 0.15, 0.85, depth + 0.15), Vector3(center_map.x, roof_y + 0.42, center_map.y), yaw, _brick_mat)

	# First floor chajja ledge
	var ledge_center: Vector2 = center_map + outward_normal * (depth * 0.5 + 0.25)
	_box(house, "MidFloorLedge", Vector3(width + 0.2, 0.09, 0.5), Vector3(ledge_center.x, ground + 3.2, ledge_center.y), yaw, _concrete_slab_mat)

	# Ground porch roof
	var porch_w: float = width * 0.55
	var porch_depth: float = 2.4
	var porch_center: Vector2 = center_map + outward_normal * (depth * 0.5 + porch_depth * 0.5)
	_box(house, "FrontPorchRoof", Vector3(porch_w, 0.14, porch_depth), Vector3(porch_center.x, ground + 3.0, porch_center.y), yaw, _concrete_slab_mat)
	porch_count += 1

	# Posts
	for side: float in [-1.0, 1.0]:
		var post_map: Vector2 = porch_center + road_dir * (side * (porch_w * 0.45)) + outward_normal * (porch_depth * 0.45)
		_box(house, "PorchPost", Vector3(0.18, 3.0, 0.18), Vector3(post_map.x, ground + 1.5, post_map.y), yaw, _wall_mat)

	# Entry steps
	var step_map: Vector2 = center_map + outward_normal * (depth * 0.5 + 0.7)
	_box(house, "EntryStep1", Vector3(2.4, 0.20, 0.7), Vector3(step_map.x, ground + 0.10, step_map.y), yaw, _concrete_slab_mat)
	_box(house, "EntryStep2", Vector3(2.0, 0.20, 0.5), Vector3(step_map.x - outward_normal.x * 0.2, ground + 0.30, step_map.y - outward_normal.y * 0.2), yaw, _concrete_slab_mat)

	# Rooftop water tank
	var tank_map: Vector2 = center_map - road_dir * (width * 0.3)
	_add_water_tank(house, Vector3(tank_map.x, roof_y + 0.70, tank_map.y), true)

## Builds a concrete/plaster compound wall between two points with top coping and collision
func _build_compound_wall(world: Node, a_map: Vector2, b_map: Vector2, height: float) -> void:
	var dist: float = a_map.distance_to(b_map)
	if dist < 0.5:
		return
	var center: Vector2 = (a_map + b_map) * 0.5
	var dir: Vector2 = (b_map - a_map).normalized()
	var yaw: float = atan2(dir.x, dir.y)
	var ground: float = float(world.ground_height(center))

	var wall_node := Node3D.new()
	wall_node.name = "CompoundWall_%d" % (wall_count + 1)
	add_child(wall_node)
	wall_count += 1

	# Main wall panel
	_box(wall_node, "WallPanel", Vector3(0.20, height, dist), Vector3(center.x, ground + height * 0.5, center.y), yaw, _wall_mat, true)

	# Coping slab on top
	_box(wall_node, "Coping", Vector3(0.26, 0.06, dist + 0.04), Vector3(center.x, ground + height + 0.03, center.y), yaw, _concrete_slab_mat)

	# Boundary posts at ends
	for pt: Vector2 in [a_map, b_map]:
		var pt_ground: float = float(world.ground_height(pt))
		_box(wall_node, "WallPillar", Vector3(0.32, height + 0.15, 0.32), Vector3(pt.x, pt_ground + (height + 0.15) * 0.5, pt.y), yaw, _wall_mat)

## Builds a steel-tube access gate between two gate pillars
func _build_gate(world: Node, center_map: Vector2, road_dir: Vector2, width: float, height: float) -> void:
	var yaw: float = atan2(road_dir.x, road_dir.y)
	var ground: float = float(world.ground_height(center_map))
	var gate := Node3D.new()
	gate.name = "SteelGate_%d" % (gate_count + 1)
	add_child(gate)
	gate_count += 1

	# Gate pillars on both sides
	var half_w: float = width * 0.5
	for side: float in [-1.0, 1.0]:
		var post_map: Vector2 = center_map + road_dir * (side * (half_w + 0.20))
		_box(gate, "GatePillar", Vector3(0.36, height + 0.20, 0.36), Vector3(post_map.x, ground + (height + 0.20) * 0.5, post_map.y), yaw, _wall_mat)

	# Gate outer frame
	_box(gate, "GateFrameTop", Vector3(width, 0.05, 0.05), Vector3(center_map.x, ground + height, center_map.y), yaw, _gate_mat)
	_box(gate, "GateFrameBottom", Vector3(width, 0.05, 0.05), Vector3(center_map.x, ground + 0.12, center_map.y), yaw, _gate_mat)

	# Vertical bars / balusters
	var bar_count: int = int(width / 0.22)
	for i: int in bar_count:
		var frac: float = float(i) / float(bar_count - 1)
		var offset: float = lerpf(-half_w + 0.1, half_w - 0.1, frac)
		var bar_map: Vector2 = center_map + road_dir * offset
		_box(gate, "GateBar", Vector3(0.035, height - 0.15, 0.035), Vector3(bar_map.x, ground + height * 0.5, bar_map.y), yaw, _gate_mat)

## Adds a cylindrical HDPE water tank
func _add_water_tank(parent: Node3D, pos: Vector3, is_black: bool) -> void:
	var tank := MeshInstance3D.new()
	tank.name = "WaterTank_%d" % (tank_count + 1)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 0.95
	tank.mesh = mesh
	tank.material_override = _tank_black_mat if is_black else _tank_white_mat
	tank.position = pos
	tank.visibility_range_end = VISIBILITY_DISTANCE
	parent.add_child(tank)
	tank_count += 1

## Adds an impostor tree
func _add_tree(world: Node, map_pos: Vector2, height: float) -> void:
	if world._is_on_any_road(map_pos, 1.0):
		return # Keep both trunk and its solid collider outside the carriageway.
	var ground: float = float(world.ground_height(map_pos))
	var tree := MeshInstance3D.new()
	tree.name = "SetbackTree_%d" % (tree_count + 1)
	tree.mesh = _tree_mesh
	tree.material_override = _tree_shader_mat
	tree.position = Vector3(map_pos.x, ground, map_pos.y)
	var scale_factor: float = height / 7.2
	tree.scale = Vector3(scale_factor, scale_factor, scale_factor)
	tree.visibility_range_end = VISIBILITY_DISTANCE
	tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(tree)

	# Trunk collision shape
	var body := StaticBody3D.new()
	body.name = "TrunkCollider"
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 3.5
	col.shape = shape
	col.position = Vector3(0, 1.75, 0)
	body.add_child(col)
	tree.add_child(body)
	tree_count += 1

## Adds a 3D Banana Tree model
func _add_banana_tree(world: Node, map_pos: Vector2, rot_y: float = 0.0, scale_factor: float = 1.0) -> void:
	if world._is_on_any_road(map_pos, 0.8):
		return # Keep outside carriageway
	var ground: float = float(world.ground_height(map_pos))
	var tree_node := BANANA_TREE_SCENE.instantiate() as Node3D
	tree_node.name = "BananaTree_%d" % (banana_tree_count + 1)
	tree_node.position = Vector3(map_pos.x, ground, map_pos.y)
	tree_node.rotation.y = rot_y
	tree_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	for child: Node in tree_node.find_children("*", "GeometryInstance3D"):
		var geom := child as GeometryInstance3D
		if geom:
			geom.visibility_range_end = VISIBILITY_DISTANCE

	# Add thin trunk collision so character cannot walk straight through trunk
	var body := StaticBody3D.new()
	body.name = "TrunkCollider"
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.18
	shape.height = 2.4
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	body.add_child(col)
	tree_node.add_child(body)

	add_child(tree_node)
	banana_tree_count += 1
	banana_tree_count += 1

## Reusable box mesh helper with optional static collision
func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, rot_y: float, mat: Material, add_collision: bool = false) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation.y = rot_y
	instance.visibility_range_end = VISIBILITY_DISTANCE
	parent.add_child(instance)

	if add_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "_Collision"
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		instance.add_child(body)

func _build_box_mesh(node_name: String, size: Vector3, pos: Vector3, rot_y: float, mat: Material) -> void:
	_box(self, node_name, size, pos, rot_y, mat, false)
