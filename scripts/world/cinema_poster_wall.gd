extends RefCounted
## Photo-inspired dressing beside New Ashok Theatre, attached to an existing
## mapped frontage. Poster artwork is original; placement/dimensions approximate.
const BUILDING_ID := "osm/way/599330483"
const TEXTURE_PATH := "res://assets/textures/cinema/weathered_movie_posters.png"

static func build(points: PackedVector2Array, base: float) -> Node3D:
	var root := Node3D.new()
	root.name = "AshokRoadMoviePosterWall"
	root.set_meta("reference", "User supplied Street View screenshot beside New Ashok Theatre; approximate frontage dressing")
	var viewpoint := GeoProjection.lon_lat_to_map(79.515554, 18.7541618)
	var best_edge := -1
	var best_distance := INF
	for edge in points.size():
		var a := points[edge]
		var b := points[(edge + 1) % points.size()]
		var direction := (b - a).normalized()
		var normal := Vector2(direction.y, -direction.x)
		if normal.dot(viewpoint - (a + b) * 0.5) <= 0.0:
			continue
		var distance := viewpoint.distance_to(Geometry2D.get_closest_point_to_segment(viewpoint, a, b))
		if distance < best_distance:
			best_distance = distance
			best_edge = edge
	if best_edge < 0:
		return root
	var paper := MeshSurface.new()
	var a := points[best_edge]
	var b := points[(best_edge + 1) % points.size()]
	_add_wall(root, paper, a, b, base, 0)
	# Continue around the closest corner, as in the photograph. All dressing
	# remains attached to the existing footprint, clear of the road surface.
	var corner_at_a := viewpoint.distance_to(a) < viewpoint.distance_to(b)
	var edge := (best_edge - 1 + points.size()) % points.size() if corner_at_a else (best_edge + 1) % points.size()
	var c := points[edge]
	var d := points[(edge + 1) % points.size()]
	if corner_at_a:
		c = d + (c - d).normalized() * minf(c.distance_to(d), 4.5)
	else:
		d = c + (d - c).normalized() * minf(c.distance_to(d), 4.5)
	_add_wall(root, paper, c, d, base, 2)
	var panels := MeshInstance3D.new()
	panels.name = "WeatheredMoviePosters"
	panels.mesh = paper.to_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(TEXTURE_PATH)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panels.material_override = material
	panels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(panels)
	return root

static func _add_wall(root: Node3D, paper: MeshSurface, a: Vector2, b: Vector2, base: float, variation: int) -> void:
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var outward := Vector2(along.y, -along.x)
	var basis := Basis(Vector3(-along.x, 0, -along.y), Vector3.UP, Vector3(outward.x, 0, outward.y))
	var center := (a + b) * 0.5 + outward * 0.13
	var wall := Node3D.new()
	wall.name = "WeatheredBoundaryWall"
	wall.position = Vector3(center.x, base, center.y)
	wall.basis = basis
	root.add_child(wall)
	var builder := preload("res://scripts/world/ashok_theatre_facade.gd")
	builder.box(wall, "PlasterWall", Vector3(length, 1.7, 0.18), Vector3(0, 0.85, 0), Color("a5a18b"))
	var weathered := ShaderMaterial.new()
	weathered.shader = preload("res://shaders/cinema_wall.gdshader")
	wall.get_node("PlasterWall").material_override = weathered
	builder.box(wall, "WeatheredCoping", Vector3(length + 0.06, 0.11, 0.25), Vector3(0, 1.73, 0), Color("77786b"))
	for index in range(0, ceili(length / 4.0) + 1):
		var x := -length * 0.5 + minf(index * 4.0, length)
		builder.box(wall, "MasonryPier", Vector3(0.32, 1.88, 0.29), Vector3(x, 0.94, 0.03), Color("b4b09b"))
	var count := maxi(1, floori((length - 0.7) / 1.05))
	for index in count:
		# Uneven heights, size and gaps suggest hand-pasted paper rather than signs.
		var width := 0.82 + float(index % 3) * 0.065
		var height := 1.18 + float(index % 2) * 0.13
		var at := a.lerp(b, float(index + 1) / float(count + 1)) + outward * 0.235
		var half := along * width * 0.5
		var low := base + 0.20 + float(index % 3) * 0.045
		var p := Vector3(at.x, low, at.y)
		var span := Vector3(half.x, 0, half.y)
		var lift := Vector3.UP * height
		var cell := (index + variation) % 4
		var u0 := float(cell) / 4.0 + 0.002
		var u1 := float(cell + 1) / 4.0 - 0.002
		paper.quad(p - span, p + span, p + span + lift, p - span + lift,
			Vector3(outward.x, 0, outward.y), Color.WHITE,
			Vector2(u1, 1), Vector2(u0, 1), Vector2(u0, 0), Vector2(u1, 0), Vector2.ZERO, false)
