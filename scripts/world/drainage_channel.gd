extends Node3D
## Reusable visual channel. All dimensions and points must be supplied explicitly.
## No automatic placement, hydraulic simulation, or inferred real-world geometry.

func build(points: PackedVector3Array, width: float, depth: float, covered := false) -> void:
	assert(width > 0.0 and depth > 0.0)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("8a8980")
	concrete.roughness = 0.95
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("385d54")
	water.roughness = 0.35
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var segment := Node3D.new()
		add_child(segment)
		segment.position = (a + b) * 0.5
		segment.look_at(segment.global_position + (b - a), Vector3.UP)
		_box(segment, Vector3(0, -depth, 0), Vector3(width + 0.3, 0.15, length), concrete)
		for side in [-1.0, 1.0]:
			_box(segment, Vector3(side * (width + 0.15) * 0.5, -depth * 0.5, 0), Vector3(0.15, depth, length), concrete)
		if covered:
			_box(segment, Vector3(0, 0.05, 0), Vector3(width + 0.3, 0.15, length), concrete)
		else:
			_box(segment, Vector3(0, -depth + 0.12, 0), Vector3(width, 0.025, length), water, false)

func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material, solid := true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	if not solid:
		return
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collider.shape = box_shape
	body.position = at
	body.add_child(collider)
	parent.add_child(body)
