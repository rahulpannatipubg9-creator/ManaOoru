extends Node3D
## Swimming and boat surfaces follow mapped water polygons, never streets or drains.
var regions: Array[Dictionary] = []

func setup(world: Node) -> void:
	for area: Dictionary in world.map_data.areas:
		if area.kind != "water" or area.points.size() < 3:
			continue
		var ring: PackedVector2Array = area.points
		var center := Vector2.ZERO
		for point in ring:
			center += point
		center /= ring.size()
		# A river built at its own level (the Godavari, GodavariBridgeBuilder) states its surface and draws
		# itself; draped ponds and tanks get a surface 1.5 m above the ground.
		var height: float = area.get("surface_y", world.ground_height(center) + 1.5)
		regions.append({"points": ring, "height": height, "center": center})
		if area.has("surface_y"):
			continue
		var triangles := Geometry2D.triangulate_polygon(ring)
		if triangles.is_empty():
			continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in triangles:
			var p := ring[index]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(p.x, height, p.y))
		var visual := MeshInstance3D.new()
		visual.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.10, 0.38, 0.48, 0.82)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.18
		visual.material_override = material
		add_child(visual)

func surface_at(point: Vector3) -> float:
	for region: Dictionary in regions:
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), region.points):
			return region.height
	return -INF

func boat_spawn() -> Variant:
	for region: Dictionary in regions:
		var ring: PackedVector2Array = region.points
		if absf(_area(ring)) < 300.0:
			continue
		if Geometry2D.is_point_in_polygon(region.center, ring):
			return Vector3(region.center.x, region.height + 0.4, region.center.y)
	return null

func _area(ring: PackedVector2Array) -> float:
	var sum := 0.0
	for i in ring.size():
		sum += ring[i].cross(ring[(i + 1) % ring.size()])
	return sum * 0.5
