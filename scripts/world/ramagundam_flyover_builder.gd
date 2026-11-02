class_name RamagundamFlyoverBuilder
extends Node3D

## Procedurally builds the Ramagundam ROB (Railway Over Bridge) Flyover on Rajiv Rahadari
## (State Highway 1 / NH 163G) connecting Godavarikhani and Ramagundam over the South Central
## Railway corridor and ground-level street junctions.
##
## Surveyed real-world bounds:
## - South Abutment / Ramp Start: 18.770717, 79.511481 -> map (-193.89, -2088.90)
## - North Abutment / Ramp End:   18.775844, 79.517389 -> map (424.32, -2655.01)
## - Total Length: ~846 meters
##
## Architectural twin features:
## - 4-lane divided dual-carriageway asphalt deck (2 northbound + 2 southbound lanes)
## - Parabolic approach ramps climbing to +6.5m elevated clearance
## - Reinforced Earth (RE) vertical concrete retaining walls with civic murals along the ramps
## - Concrete pier shafts, plinths, and wide hammerhead portal crossbeams along the elevated span
## - Open underpass clearance for ground-level cross traffic
## - Central median divider with black-and-yellow hazard curbs, street light poles, and potted palms
## - Continuous outer concrete parapets with galvanized steel safety railings and black-and-white curbs
## - Roadside advertising billboard and overhead green highway direction signs

const ROAD_LAYER := 2

const FLYOVER_WAYS := [
	817699100, 758926574, 817699106, 1320685006,
	1320685009, 1320685008, 817699110, 817699098, 1320685005
]

## Surveyed centerline waypoints from South Abutment to North Abutment
const PATH_NODES: Array[Vector2] = [
	Vector2(-193.89, -2088.90), # South Ramp Start (18.770717, 79.511481)
	Vector2(-181.43, -2117.23),
	Vector2(-170.02, -2140.12),
	Vector2(-145.82, -2180.23),
	Vector2(-112.50, -2221.94), # Underpass crossing zone / ramp crest
	Vector2(-88.65, -2247.74),
	Vector2(-68.04, -2266.62),
	Vector2(-9.89, -2315.03),
	Vector2(313.32, -2557.58), # Long straight elevated highway section
	Vector2(377.14, -2620.01), # Descent ramp start
	Vector2(410.40, -2646.23),
	Vector2(421.95, -2655.38), # North Ramp End (18.775844, 79.517389)
]

const TOTAL_WIDTH := 17.0
const CARRIAGEWAY_WIDTH := 7.0
const MEDIAN_WIDTH := 1.6
const MEDIAN_HEIGHT := 0.25
const BARRIER_WIDTH := 0.45
const BARRIER_HEIGHT := 0.95
const RAILING_HEIGHT := 0.45
const FLYOVER_CLEARANCE := 6.5
const SOUTH_RAMP_LENGTH := 140.0
const NORTH_RAMP_LENGTH := 140.0
const PIER_SPACING := 28.0
const LAMP_SPACING := 32.0
const POT_SPACING := 14.0
const SAMPLE_STEP := 2.0

var _cumulative_dists: Array[float] = []
var _total_length: float = 0.0
var _terrain: TerrainData
var spawn_spot: Dictionary = {}

static func add_to_map(data: MapData) -> void:
	for road: Dictionary in data.roads:
		var way_id: int = int(road.get("way_id", 0))
		var road_name: String = str(road.get("name", ""))
		if way_id in FLYOVER_WAYS or road_name == "Flyover":
			road["structure"] = "bridge"
	data.landmarks.append({
		"name": "Ramagundam ROB Flyover",
		"category": "Bridge",
		"position": Vector2(113.8, -2370.5)
	})

func _init() -> void:
	name = "RamagundamFlyover"
	_init_path_metrics()

func _init_path_metrics() -> void:
	_cumulative_dists.clear()
	_cumulative_dists.append(0.0)
	for i in range(1, PATH_NODES.size()):
		var d := PATH_NODES[i].distance_to(PATH_NODES[i - 1])
		_cumulative_dists.append(_cumulative_dists[-1] + d)
	_total_length = _cumulative_dists[-1]

func sample_path(s: float) -> Dictionary:
	var s_clamped := clampf(s, 0.0, _total_length)
	var pos := PATH_NODES[0]
	var tangent := Vector2(0, -1)
	if s_clamped <= 0.0:
		pos = PATH_NODES[0]
		tangent = (PATH_NODES[1] - PATH_NODES[0]).normalized()
	elif s_clamped >= _total_length:
		pos = PATH_NODES[-1]
		tangent = (PATH_NODES[-1] - PATH_NODES[-2]).normalized()
	else:
		for i in range(_cumulative_dists.size() - 1):
			if _cumulative_dists[i] <= s_clamped and s_clamped <= _cumulative_dists[i + 1]:
				var seg_len := _cumulative_dists[i + 1] - _cumulative_dists[i]
				var t := (s_clamped - _cumulative_dists[i]) / maxf(seg_len, 0.001)
				pos = PATH_NODES[i].lerp(PATH_NODES[i + 1], t)
				tangent = (PATH_NODES[i + 1] - PATH_NODES[i]).normalized()
				break
	var normal := Vector2(-tangent.y, tangent.x) # Right-hand lateral normal
	var h_fly := FLYOVER_CLEARANCE
	if s_clamped < SOUTH_RAMP_LENGTH:
		var t := s_clamped / SOUTH_RAMP_LENGTH
		h_fly = FLYOVER_CLEARANCE * (3.0 * t * t - 2.0 * t * t * t)
	elif s_clamped > _total_length - NORTH_RAMP_LENGTH:
		var t := (_total_length - s_clamped) / NORTH_RAMP_LENGTH
		h_fly = FLYOVER_CLEARANCE * (3.0 * t * t - 2.0 * t * t * t)
	var gy := _terrain.height_at(pos) if _terrain else 0.0
	var deck_y := gy + h_fly
	return {
		"s": s_clamped,
		"pos": pos,
		"tangent": tangent,
		"normal": normal,
		"ground_y": gy,
		"clearance": h_fly,
		"deck_y": deck_y
	}

func deck_height_at(point: Vector2) -> float:
	var best_dist := INF
	var best_s := 0.0
	for i in range(PATH_NODES.size() - 1):
		var a := PATH_NODES[i]
		var b := PATH_NODES[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var d := point.distance_to(closest)
		if d < best_dist:
			best_dist = d
			var t := (closest - a).length() / maxf(a.distance_to(b), 0.001)
			best_s = _cumulative_dists[i] + t * (a.distance_to(b))
	if best_dist <= TOTAL_WIDTH * 0.5 + 1.0 and best_s >= 0.0 and best_s <= _total_length:
		var sample := sample_path(best_s)
		return sample.deck_y
	return -INF

func build(world: Node, data: MapData) -> void:
	_terrain = data.terrain
	var sample_count := int(ceil(_total_length / SAMPLE_STEP)) + 1
	var samples: Array[Dictionary] = []
	for i in sample_count:
		var s := minf(i * SAMPLE_STEP, _total_length)
		samples.append(sample_path(s))

	# 1. Mesh surfaces
	var s_deck := MeshSurface.new()
	var s_median := MeshSurface.new()
	var s_barriers := MeshSurface.new()
	var s_markings := MeshSurface.new()
	var s_re_walls := MeshSurface.new()
	var s_piers := MeshSurface.new()

	var half_w := TOTAL_WIDTH * 0.5
	var half_med := MEDIAN_WIDTH * 0.5

	# Generate roadway quad ribbons
	for i in range(1, samples.size()):
		var prev: Dictionary = samples[i - 1]
		var curr: Dictionary = samples[i]

		var p_prev: Vector2 = prev.pos
		var p_curr: Vector2 = curr.pos
		var n_prev: Vector2 = prev.normal
		var n_curr: Vector2 = curr.normal
		var dy_prev: float = prev.deck_y
		var dy_curr: float = curr.deck_y
		var gy_prev: float = prev.ground_y
		var gy_curr: float = curr.ground_y
		var clr_prev: float = prev.clearance
		var clr_curr: float = curr.clearance

		# Lateral offsets:
		# Left Outer Barrier: -half_w to -(half_w - BARRIER_WIDTH)
		# Southbound Carriageway: -(half_w - BARRIER_WIDTH) to -half_med
		# Central Median: -half_med to +half_med
		# Northbound Carriageway: +half_med to +(half_w - BARRIER_WIDTH)
		# Right Outer Barrier: +(half_w - BARRIER_WIDTH) to +half_w

		var l_outer_p := _v3(p_prev - n_prev * half_w, dy_prev)
		var l_outer_c := _v3(p_curr - n_curr * half_w, dy_curr)
		var l_inner_p := _v3(p_prev - n_prev * (half_w - BARRIER_WIDTH), dy_prev)
		var l_inner_c := _v3(p_curr - n_curr * (half_w - BARRIER_WIDTH), dy_curr)

		var m_left_p := _v3(p_prev - n_prev * half_med, dy_prev)
		var m_left_c := _v3(p_curr - n_curr * half_med, dy_curr)
		var m_right_p := _v3(p_prev + n_prev * half_med, dy_prev)
		var m_right_c := _v3(p_curr + n_curr * half_med, dy_curr)

		var r_inner_p := _v3(p_prev + n_prev * (half_w - BARRIER_WIDTH), dy_prev)
		var r_inner_c := _v3(p_curr + n_curr * (half_w - BARRIER_WIDTH), dy_curr)
		var r_outer_p := _v3(p_prev + n_prev * half_w, dy_prev)
		var r_outer_c := _v3(p_curr + n_curr * half_w, dy_curr)

		# Southbound Deck (Asphalt, collidable layer 3)
		var asphalt_col := Color(0.12, 0.12, 0.13)
		s_deck.quad(l_inner_p, l_inner_c, m_left_c, m_left_p,
			Vector3.UP, asphalt_col,
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2.ZERO, true)

		# Northbound Deck (Asphalt, collidable layer 3)
		s_deck.quad(m_right_p, m_right_c, r_inner_c, r_inner_p,
			Vector3.UP, asphalt_col,
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2.ZERO, true)

		# Deck bottom soffit (Concrete slab bottom)
		var soffit_h := 0.75 # Girder slab thickness
		var l_soffit_p := _v3(p_prev - n_prev * (half_w - 0.2), dy_prev - soffit_h)
		var l_soffit_c := _v3(p_curr - n_curr * (half_w - 0.2), dy_curr - soffit_h)
		var r_soffit_p := _v3(p_prev + n_prev * (half_w - 0.2), dy_prev - soffit_h)
		var r_soffit_c := _v3(p_curr + n_curr * (half_w - 0.2), dy_curr - soffit_h)
		var conc_grey := Color(0.68, 0.67, 0.64)
		s_deck.quad(l_soffit_p, r_soffit_p, r_soffit_c, l_soffit_c,
			Vector3.DOWN, conc_grey,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, false)

		# Central Median (Raised curb with hazard alternating black & yellow paint)
		var is_yellow_block: bool = (int(prev.s) / 2) % 2 == 0
		var curb_col := Color(0.95, 0.78, 0.15) if is_yellow_block else Color(0.15, 0.15, 0.16)
		var m_top_lp := _v3(p_prev - n_prev * half_med, dy_prev + MEDIAN_HEIGHT)
		var m_top_lc := _v3(p_curr - n_curr * half_med, dy_curr + MEDIAN_HEIGHT)
		var m_top_rp := _v3(p_prev + n_prev * half_med, dy_prev + MEDIAN_HEIGHT)
		var m_top_rc := _v3(p_curr + n_curr * half_med, dy_curr + MEDIAN_HEIGHT)

		# Median Left Curb face
		s_median.quad(m_left_p, m_left_c, m_top_lc, m_top_lp,
			-Vector3(n_prev.x, 0, n_prev.y), curb_col,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Median Top face
		s_median.quad(m_top_lp, m_top_lc, m_top_rc, m_top_rp,
			Vector3.UP, Color(0.58, 0.58, 0.56),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Median Right Curb face
		s_median.quad(m_top_rp, m_top_rc, m_right_c, m_right_p,
			Vector3(n_prev.x, 0, n_prev.y), curb_col,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)

		# Outer Crash Barriers (Parapet Wall + Hazard Black/White Striping)
		var is_white_block: bool = (int(prev.s) / 2) % 2 == 0
		var outer_curb_col := Color(0.94, 0.94, 0.92) if is_white_block else Color(0.15, 0.15, 0.16)
		var bar_top_lp := _v3(p_prev - n_prev * half_w, dy_prev + BARRIER_HEIGHT)
		var bar_top_lc := _v3(p_curr - n_curr * half_w, dy_curr + BARRIER_HEIGHT)
		var bar_inner_top_lp := _v3(p_prev - n_prev * (half_w - BARRIER_WIDTH), dy_prev + BARRIER_HEIGHT)
		var bar_inner_top_lc := _v3(p_curr - n_curr * (half_w - BARRIER_WIDTH), dy_curr + BARRIER_HEIGHT)

		var bar_top_rp := _v3(p_prev + n_prev * half_w, dy_prev + BARRIER_HEIGHT)
		var bar_top_rc := _v3(p_curr + n_curr * half_w, dy_curr + BARRIER_HEIGHT)
		var bar_inner_top_rp := _v3(p_prev + n_prev * (half_w - BARRIER_WIDTH), dy_prev + BARRIER_HEIGHT)
		var bar_inner_top_rc := _v3(p_curr + n_curr * (half_w - BARRIER_WIDTH), dy_curr + BARRIER_HEIGHT)

		# Left barrier inside face (facing roadway)
		s_barriers.quad(l_inner_p, l_inner_c, bar_inner_top_lc, bar_inner_top_lp,
			Vector3(n_prev.x, 0, n_prev.y), outer_curb_col,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Left barrier top face
		s_barriers.quad(bar_inner_top_lp, bar_inner_top_lc, bar_top_lc, bar_top_lp,
			Vector3.UP, conc_grey,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Left barrier outside face
		s_barriers.quad(bar_top_lp, bar_top_lc, l_soffit_c, l_soffit_p,
			-Vector3(n_prev.x, 0, n_prev.y), conc_grey,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)

		# Right barrier inside face (facing roadway)
		s_barriers.quad(bar_inner_top_rp, bar_inner_top_rc, r_inner_c, r_inner_p,
			-Vector3(n_prev.x, 0, n_prev.y), outer_curb_col,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Right barrier top face
		s_barriers.quad(bar_top_rp, bar_top_rc, bar_inner_top_rc, bar_inner_top_rp,
			Vector3.UP, conc_grey,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
		# Right barrier outside face
		s_barriers.quad(r_soffit_p, r_soffit_c, bar_top_rc, bar_top_rp,
			Vector3(n_prev.x, 0, n_prev.y), conc_grey,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)

		# Road Markings: Solid white edge lines & center dashed lines
		var white_line_col := Color(0.96, 0.96, 0.92)
		var line_w := 0.15
		var ym := 0.015

		# Solid inner edge line (Southbound)
		var sb_edge_p := _v3(p_prev - n_prev * (half_med + line_w), dy_prev + ym)
		var sb_edge_c := _v3(p_curr - n_curr * (half_med + line_w), dy_curr + ym)
		s_markings.quad(m_left_p + Vector3(0, ym, 0), m_left_c + Vector3(0, ym, 0), sb_edge_c, sb_edge_p,
			Vector3.UP, white_line_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)

		# Solid inner edge line (Northbound)
		var nb_edge_p := _v3(p_prev + n_prev * (half_med + line_w), dy_prev + ym)
		var nb_edge_c := _v3(p_curr + n_curr * (half_med + line_w), dy_curr + ym)
		s_markings.quad(nb_edge_p, nb_edge_c, m_right_c + Vector3(0, ym, 0), m_right_p + Vector3(0, ym, 0),
			Vector3.UP, white_line_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)

		# Dashed center lane lines (3m dash, 3m gap)
		if (int(prev.s) / 3) % 2 == 0:
			var sb_mid_p := p_prev - n_prev * (half_med + CARRIAGEWAY_WIDTH * 0.5)
			var sb_mid_c := p_curr - n_curr * (half_med + CARRIAGEWAY_WIDTH * 0.5)
			s_markings.quad(
				_v3(sb_mid_p - n_prev * (line_w * 0.5), dy_prev + ym),
				_v3(sb_mid_c - n_curr * (line_w * 0.5), dy_curr + ym),
				_v3(sb_mid_c + n_curr * (line_w * 0.5), dy_curr + ym),
				_v3(sb_mid_p + n_prev * (line_w * 0.5), dy_prev + ym),
				Vector3.UP, white_line_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)

			var nb_mid_p := p_prev + n_prev * (half_med + CARRIAGEWAY_WIDTH * 0.5)
			var nb_mid_c := p_curr + n_curr * (half_med + CARRIAGEWAY_WIDTH * 0.5)
			s_markings.quad(
				_v3(nb_mid_p - n_prev * (line_w * 0.5), dy_prev + ym),
				_v3(nb_mid_c - n_curr * (line_w * 0.5), dy_curr + ym),
				_v3(nb_mid_c + n_curr * (line_w * 0.5), dy_curr + ym),
				_v3(nb_mid_p + n_prev * (line_w * 0.5), dy_prev + ym),
				Vector3.UP, white_line_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)

		# Approach Ramp Retaining Walls (Reinforced Earth panel walls with civic murals)
		# Build vertical drop walls from soffit down to ground on ramp sections
		var on_ramp: bool = (prev.s < SOUTH_RAMP_LENGTH and prev.s > 4.0) or (prev.s > _total_length - NORTH_RAMP_LENGTH and prev.s < _total_length - 4.0)
		if on_ramp:
			var mural_tint := Color(0.82, 0.80, 0.74)
			var g_left_p := _v3(p_prev - n_prev * (half_w - 0.2), gy_prev)
			var g_left_c := _v3(p_curr - n_curr * (half_w - 0.2), gy_curr)
			var g_right_p := _v3(p_prev + n_prev * (half_w - 0.2), gy_prev)
			var g_right_c := _v3(p_curr + n_curr * (half_w - 0.2), gy_curr)

			# West retaining wall
			s_re_walls.quad(g_left_p, g_left_c, l_soffit_c, l_soffit_p,
				-Vector3(n_prev.x, 0, n_prev.y), mural_tint,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)
			# East retaining wall
			s_re_walls.quad(r_soffit_p, r_soffit_c, g_right_c, g_right_p,
				Vector3(n_prev.x, 0, n_prev.y), mural_tint,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, true)

	# 2. Elevated Span Piers, Crossbeams, and Underpass
	_build_piers_and_superstructure(samples, s_piers)

	# 3. Create MeshInstances with PBR Materials & Trimesh Collisions
	var root_body := StaticBody3D.new()
	root_body.name = "FlyoverStructure"
	root_body.collision_layer = 1 | (1 << (ROAD_LAYER - 1)) # Layer 3
	root_body.collision_mask = 0
	add_child(root_body)

	_add_surface_mesh(root_body, s_deck, _make_asphalt_material(), true)
	_add_surface_mesh(root_body, s_median, _make_curb_material(), true)
	_add_surface_mesh(root_body, s_barriers, _make_concrete_material(), true)
	_add_surface_mesh(root_body, s_markings, _make_marking_material(), false)
	_add_surface_mesh(root_body, s_re_walls, _make_re_wall_material(), true)
	_add_surface_mesh(root_body, s_piers, _make_pier_material(), true)

	# 4. Dressing: Median Potted Palm Trees, Street Light Poles & Roadside Billboard
	_place_median_planters_and_lamps(samples)
	_place_overhead_gantry_and_billboard(samples)

	# 5. Pre-calculated spawn spot at South Ramp
	var spawn_sample := sample_path(18.0)
	var spawn_pos := Vector3(spawn_sample.pos.x + spawn_sample.normal.x * 4.3, spawn_sample.deck_y + 0.35, spawn_sample.pos.y + spawn_sample.normal.y * 4.3)
	var spawn_yaw := atan2(spawn_sample.tangent.x, spawn_sample.tangent.y)
	spawn_spot = {
		"position": spawn_pos,
		"yaw": spawn_yaw,
		"name": "Ramagundam ROB Flyover"
	}

	print("Ramagundam ROB Flyover built successfully from (%0.1f, %0.1f) to (%0.1f, %0.1f) length: %0.1f m" %
		[PATH_NODES[0].x, PATH_NODES[0].y, PATH_NODES[-1].x, PATH_NODES[-1].y, _total_length])

func _build_piers_and_superstructure(samples: Array[Dictionary], surface: MeshSurface) -> void:
	var pier_col := Color(0.64, 0.63, 0.60)
	var underpass_s := 150.0 # Underpass clearance zone

	var pier_s := SOUTH_RAMP_LENGTH + 8.0
	while pier_s <= _total_length - NORTH_RAMP_LENGTH - 8.0:
		var sample := sample_path(pier_s)
		var pos: Vector2 = sample.pos
		var normal: Vector2 = sample.normal
		var tangent: Vector2 = sample.tangent
		var gy: float = sample.ground_y
		var dy: float = sample.deck_y
		var soffit_y: float = dy - 0.75

		# Hammerhead / Portal Crossbeam under deck (width 15.5m, height 1.4m, thickness 2.2m)
		var bw := 7.75
		var bh := 1.4
		var bt := 1.1 # half thickness

		var cb_tl_f := _v3(pos - normal * bw + tangent * bt, soffit_y)
		var cb_tl_b := _v3(pos - normal * bw - tangent * bt, soffit_y)
		var cb_tr_f := _v3(pos + normal * bw + tangent * bt, soffit_y)
		var cb_tr_b := _v3(pos + normal * bw - tangent * bt, soffit_y)

		var cb_bl_f := _v3(pos - normal * bw + tangent * bt, soffit_y - bh)
		var cb_bl_b := _v3(pos - normal * bw - tangent * bt, soffit_y - bh)
		var cb_br_f := _v3(pos + normal * bw + tangent * bt, soffit_y - bh)
		var cb_br_b := _v3(pos + normal * bw - tangent * bt, soffit_y - bh)

		# Top & Bottom
		surface.quad(cb_tl_f, cb_tr_f, cb_tr_b, cb_tl_b, Vector3.UP, pier_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)
		surface.quad(cb_bl_f, cb_bl_b, cb_br_b, cb_br_f, Vector3.DOWN, pier_col, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO, false)
		# Front & Back faces
		surface.quad(cb_tl_f, cb_bl_f, cb_br_f, cb_tr_f, Vector3(tangent.x, 0, tangent.y), pier_col, Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, true)
		surface.quad(cb_tr_b, cb_br_b, cb_bl_b, cb_tl_b, -Vector3(tangent.x, 0, tangent.y), pier_col, Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, true)
		# Left & Right end caps
		surface.quad(cb_tl_b, cb_bl_b, cb_bl_f, cb_tl_f, -Vector3(normal.x, 0, normal.y), pier_col, Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, true)
		surface.quad(cb_tr_f, cb_br_f, cb_br_b, cb_tr_b, Vector3(normal.x, 0, normal.y), pier_col, Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, true)

		# Twin Pier Shafts (cylindrical columns) supporting each crossbeam
		# Left shaft at -4.2m lateral, Right shaft at +4.2m lateral
		for sign: float in [-1.0, 1.0]:
			var pier_center: Vector2 = pos + normal * (sign * 4.2)
			var col_rad: float = 0.95
			var col_top: float = soffit_y - bh
			var col_bot: float = gy
			var segments: int = 10
			for seg in segments:
				var a0: float = float(seg) / float(segments) * TAU
				var a1: float = float(seg + 1) / float(segments) * TAU
				var v0: Vector2 = pier_center + Vector2(cos(a0), sin(a0)) * col_rad
				var v1: Vector2 = pier_center + Vector2(cos(a1), sin(a1)) * col_rad
				var p_tl := _v3(v0, col_top)
				var p_tr := _v3(v1, col_top)
				var p_bl := _v3(v0, col_bot)
				var p_br := _v3(v1, col_bot)
				var norm := Vector3((cos(a0) + cos(a1)) * 0.5, 0, (sin(a0) + sin(a1)) * 0.5).normalized()
				surface.quad(p_tl, p_bl, p_br, p_tr, norm, pier_col, Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, true)

		pier_s += PIER_SPACING

func _place_median_planters_and_lamps(samples: Array[Dictionary]) -> void:
	var props_root := Node3D.new()
	props_root.name = "FlyoverDressing"
	add_child(props_root)

	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.72, 0.36, 0.22) # Terracotta
	pot_mat.roughness = 0.88

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.18, 0.48, 0.22) # Lush green
	leaf_mat.roughness = 0.55

	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.32, 0.35, 0.38) # Dark galvanized steel
	steel_mat.metallic = 0.85
	steel_mat.roughness = 0.35

	var lamp_glass := StandardMaterial3D.new()
	lamp_glass.albedo_color = Color(1.0, 0.96, 0.85)
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.95, 0.80)
	lamp_glass.emission_energy_multiplier = 2.5

	# Terracotta Pot & Palm Foliage along Median
	var pot_s := 20.0
	while pot_s <= _total_length - 20.0:
		var sample := sample_path(pot_s)
		var center := Vector3(sample.pos.x, sample.deck_y + MEDIAN_HEIGHT, sample.pos.y)

		# Terracotta Planter Pot
		var pot := MeshInstance3D.new()
		var pot_mesh := CylinderMesh.new()
		pot_mesh.top_radius = 0.45
		pot_mesh.bottom_radius = 0.35
		pot_mesh.height = 0.60
		pot_mesh.radial_segments = 12
		pot_mesh.material = pot_mat
		pot.mesh = pot_mesh
		pot.position = center + Vector3(0, 0.30, 0)
		props_root.add_child(pot)

		# Fan Palm Bush Foliage inside Pot
		var bush := Node3D.new()
		bush.position = center + Vector3(0, 0.60, 0)
		for f in range(6):
			var frond := MeshInstance3D.new()
			var frond_mesh := BoxMesh.new()
			frond_mesh.size = Vector3(0.35, 0.04, 1.4)
			frond_mesh.material = leaf_mat
			frond.mesh = frond_mesh
			var angle := float(f) / 6.0 * TAU
			frond.rotation = Vector3(0.45, angle, 0.2)
			frond.position = Vector3(sin(angle) * 0.45, 0.45, cos(angle) * 0.45)
			bush.add_child(frond)
		props_root.add_child(bush)

		pot_s += POT_SPACING

	# Dual-Arm Highway Street Light Poles along Median
	var lamp_s := 16.0
	while lamp_s <= _total_length - 16.0:
		var sample := sample_path(lamp_s)
		var center := Vector3(sample.pos.x, sample.deck_y + MEDIAN_HEIGHT, sample.pos.y)
		var normal: Vector2 = sample.normal

		var pole := Node3D.new()
		pole.position = center

		# Vertical Mast
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.10
		mast_mesh.bottom_radius = 0.18
		mast_mesh.height = 8.5
		mast_mesh.radial_segments = 8
		mast_mesh.material = steel_mat
		mast.mesh = mast_mesh
		mast.position.y = 4.25
		pole.add_child(mast)

		# Twin Outreach Arms extending laterally over both carriageways
		for dir in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var arm_mesh := BoxMesh.new()
			arm_mesh.size = Vector3(2.4, 0.08, 0.08)
			arm_mesh.material = steel_mat
			arm.mesh = arm_mesh
			var arm_rot := atan2(normal.x, normal.y) + PI * 0.5
			arm.rotation.y = arm_rot
			arm.position = Vector3(normal.x * dir * 1.2, 8.4, normal.y * dir * 1.2)
			pole.add_child(arm)

			# Luminaire Head
			var head := MeshInstance3D.new()
			var head_mesh := BoxMesh.new()
			head_mesh.size = Vector3(0.65, 0.12, 0.28)
			head_mesh.material = lamp_glass
			head.mesh = head_mesh
			head.rotation.y = arm_rot
			head.position = Vector3(normal.x * dir * 2.3, 8.35, normal.y * dir * 2.3)
			pole.add_child(head)

		props_root.add_child(pole)
		lamp_s += LAMP_SPACING

func _place_overhead_gantry_and_billboard(samples: Array[Dictionary]) -> void:
	# 1. Roadside Advertising Billboard beside flyover approach (matching Street View)
	var bb_sample := sample_path(90.0)
	var bb_pos := Vector3(bb_sample.pos.x + bb_sample.normal.x * 12.0, bb_sample.ground_y, bb_sample.pos.y + bb_sample.normal.y * 12.0)
	var bb_node := Node3D.new()
	bb_node.name = "FlyoverBillboard"
	bb_node.position = bb_pos
	var bb_yaw := atan2(bb_sample.tangent.x, bb_sample.tangent.y)
	bb_node.rotation.y = bb_yaw

	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.28, 0.32, 0.36)
	steel_mat.metallic = 0.9

	# Steel Support Columns
	for offset_x in [-3.5, 3.5]:
		var col := MeshInstance3D.new()
		var col_mesh := CylinderMesh.new()
		col_mesh.top_radius = 0.25
		col_mesh.bottom_radius = 0.28
		col_mesh.height = 10.0
		col_mesh.radial_segments = 8
		col_mesh.material = steel_mat
		col.mesh = col_mesh
		col.position = Vector3(offset_x, 5.0, 0)
		bb_node.add_child(col)

	# Billboard Display Board
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(10.0, 5.0, 0.35)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.92, 0.45, 0.15) # Warm festive billboard
	board_mesh.material = board_mat
	board.mesh = board_mesh
	board.position = Vector3(0, 11.5, 0)
	bb_node.add_child(board)
	add_child(bb_node)

	# 2. Overhead Green Highway Gantry Sign at Ramp Entrance
	var gantry_sample := sample_path(35.0)
	var gantry := Node3D.new()
	gantry.name = "OverheadDirectionGantry"
	gantry.position = Vector3(gantry_sample.pos.x, gantry_sample.deck_y, gantry_sample.pos.y)
	gantry.rotation.y = atan2(gantry_sample.tangent.x, gantry_sample.tangent.y)

	var green_sign_mat := StandardMaterial3D.new()
	green_sign_mat.albedo_color = Color(0.08, 0.42, 0.22) # Indian Highway green
	green_sign_mat.roughness = 0.5

	for side in [-1.0, 1.0]:
		var g_mast := MeshInstance3D.new()
		var g_mast_mesh := CylinderMesh.new()
		g_mast_mesh.top_radius = 0.16
		g_mast_mesh.bottom_radius = 0.18
		g_mast_mesh.height = 6.2
		g_mast_mesh.material = steel_mat
		g_mast.mesh = g_mast_mesh
		g_mast.position = Vector3(side * (TOTAL_WIDTH * 0.5 - 0.2), 3.1, 0)
		gantry.add_child(g_mast)

	var g_beam := MeshInstance3D.new()
	var g_beam_mesh := BoxMesh.new()
	g_beam_mesh.size = Vector3(TOTAL_WIDTH - 0.2, 0.4, 0.4)
	g_beam_mesh.material = steel_mat
	g_beam.mesh = g_beam_mesh
	g_beam.position = Vector3(0, 6.0, 0)
	gantry.add_child(g_beam)

	# Signboard Face
	var sign_board := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(8.5, 1.8, 0.12)
	sign_mesh.material = green_sign_mat
	sign_board.mesh = sign_mesh
	sign_board.position = Vector3(0, 5.0, 0)
	gantry.add_child(sign_board)
	add_child(gantry)

func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func _add_surface_mesh(parent: Node, surface: MeshSurface, mat: Material, collide: bool) -> void:
	if surface.vertices.is_empty():
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = surface.to_mesh()
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)

	if collide and not surface.collision.is_empty():
		var col_shape := ConcavePolygonShape3D.new()
		col_shape.set_faces(surface.collision)
		var col_node := CollisionShape3D.new()
		col_node.shape = col_shape
		parent.add_child(col_node)

func _make_asphalt_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	mat.roughness = 0.88
	mat.metallic = 0.05
	return mat

func _make_curb_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.75
	return mat

func _make_concrete_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(0.68, 0.67, 0.64)
	mat.roughness = 0.78
	return mat

func _make_marking_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(0.96, 0.96, 0.92)
	mat.roughness = 0.45
	return mat

func _make_re_wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(0.84, 0.82, 0.76)
	mat.roughness = 0.85
	return mat

func _make_pier_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(0.64, 0.63, 0.60)
	mat.roughness = 0.82
	return mat
