extends RefCounted
## Local photo-reference dressing. The screenshot identifies Vidya Nagar 1;
## entrance styling/dimensions are approximate, aligned to the mapped lane.
const JUNCTION := Vector2(79.5157767, 18.754333)
const LANE_POINT := Vector2(79.5155625, 18.7544947)

static func build(world: Node, number := 1, junction := JUNCTION, lane_point := LANE_POINT) -> Node3D:
	var root := Node3D.new()
	root.name = "VidyaNagar%dPhotoEntrance" % number
	root.set_meta("reference", "User-supplied Vidya Nagar %d Street View screenshot; approximate entrance styling" % number)
	var start := GeoProjection.lon_lat_to_map(junction.x, junction.y)
	var end := GeoProjection.lon_lat_to_map(lane_point.x, lane_point.y)
	var direction := (end - start).normalized()
	var across := -direction.orthogonal()
	var center := start + direction * 11.0
	var road: Dictionary = world.street_life._entrance_road(center)
	if road.is_empty():
		return root
	var half: float = road.half_width + 0.55
	var safe := false
	for distance: float in [7, 11, 15, 19, 23, 27, 31, 35, 39]:
		var candidate := start + direction * distance
		var nearest: Dictionary = world.street_life._entrance_road(candidate)
		if nearest.is_empty():
			continue
		candidate = nearest.point
		var clear := true
		for sample_index in 13:
			var at := candidate + across * lerpf(-half, half, float(sample_index) / 12.0)
			clear = clear and world.buildings.is_clear(at, 0.25)
		if clear:
			center = candidate
			safe = true
			break
	if not safe:
		push_warning("Vidya Nagar 1 arch omitted: no clear mapped frontage")
		return root
	root.position = Vector3(center.x, world.ground_height(center), center.y)
	root.basis = Basis(Vector3(across.x, 0, across.y), Vector3.UP, Vector3(-direction.x, 0, -direction.y))
	root.set_meta("road_half_width", road.half_width)
	root.set_meta("clearance", 5.2)
	var rusty := ShaderMaterial.new()
	rusty.shader = preload("res://shaders/vidya_entrance_rust.gdshader")
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("898176")
	concrete.roughness = 1.0
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("49423b")
	steel.roughness = 0.95
	for side: float in [-1, 1]:
		_box(root, "RustyArchUpright", Vector3(0.10, 5.95, 0.10), Vector3(side * half, 2.975, 0), rusty)
		_box(root, "ConcreteFooting", Vector3(0.36, 0.48, 0.36), Vector3(side * half, 0.24, 0), concrete)
		_beam(root, "DiagonalArchBrace", Vector3(side * half, 4.6, 0), Vector3(side * (half - 0.85), 5.22, 0), 0.055, steel)
	_box(root, "FadedRustNamePanel", Vector3(half * 2.0 - 0.65, 0.65, 0.07), Vector3(0, 5.55, 0), rusty)
	for y: float in [5.18, 5.94]:
		_box(root, "ThinArchFrame", Vector3(half * 2.0 + 0.12, 0.045, 0.08), Vector3(0, y, 0), steel)
	for face: float in [-1, 1]:
		var label := Label3D.new()
		label.name = "VidyaNagar%dName" % number
		label.text = "VIDYA NAGAR %d" % number
		label.font_size = 54
		label.pixel_size = minf(0.0065, half * 1.55 / 490.0)
		label.position = Vector3(0, 5.54, face * 0.043)
		label.rotation.y = PI if face < 0 else 0.0
		label.modulate = Color("cbb58c")
		label.outline_size = 0
		label.shaded = true
		label.visibility_range_end = 120
		root.add_child(label)
	# Dense local service wiring, rather than applying this clutter city-wide.
	var wires := MeshSurface.new()
	var poles: Array[Vector3] = []
	for step in 4:
		for side: float in [-1, 1]:
			var p := Vector3(side * (half + 0.8), 0, 7.0 - step * 17.0)
			var world_p := root.transform * p
			var map_p := Vector2(world_p.x, world_p.z)
			if not world.buildings.is_clear(map_p, 0.25):
				continue
			p.y = world.ground_height(map_p) - root.position.y
			poles.append(p)
			_box(root, "ConcreteElectricPole", Vector3(0.22, 8.2, 0.23), p + Vector3.UP * 4.1, concrete)
			for level: float in [6.6, 7.4]:
				_box(root, "CrossArm", Vector3(1.5, 0.085, 0.09), p + Vector3.UP * level, steel)
				for offset: float in [-0.6, 0, 0.6]:
					_box(root, "Insulator", Vector3(0.11, 0.18, 0.11), p + Vector3(offset, level + 0.1, 0), steel)
			_box(root, "ServiceJunctionBox", Vector3(0.33, 0.44, 0.22), p + Vector3(0.12, 4.9, 0.18), steel)
	for i in poles.size():
		for j in range(i + 1, poles.size()):
			var a := poles[i]
			var b := poles[j]
			if a.distance_to(b) > 21.0 or (absf(a.z - b.z) > 1 and a.x * b.x < 0):
				continue
			for cable in 7:
				var height := 6.55 + float(cable % 3) * 0.31
				var offset := Vector3((cable - 3) * 0.15, height, 0)
				for piece in 10:
					var t0 := float(piece) / 10
					var t1 := float(piece + 1) / 10
					var p0 := a.lerp(b, t0) + offset - Vector3.UP * sin(t0 * PI) * 0.38
					var p1 := a.lerp(b, t1) + offset - Vector3.UP * sin(t1 * PI) * 0.38
					var side := Vector3.UP * 0.012
					wires.quad(p0 - side, p1 - side, p1 + side, p0 + side, Vector3.FORWARD, Color("272727"), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	if not wires.vertices.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.name = "DenseOverheadServiceWires"
		mesh.mesh = wires.to_mesh()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = material
		mesh.visibility_range_end = 160
		root.add_child(mesh)
	world.street_life._keep_clear.append(Vector3(center.x, center.y, half + 1.5))
	return root

static func _box(root: Node3D, title: String, size: Vector3, at: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	node.visibility_range_end = 200
	root.add_child(node)

static func _beam(root: Node3D, title: String, a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	_box(root, title, Vector3(thickness, a.distance_to(b), thickness), (a + b) * 0.5, material)
	var node := root.get_child(root.get_child_count() - 1) as Node3D
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
