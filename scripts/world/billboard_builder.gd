class_name BillboardBuilder
extends Node3D

## Uses the user's downloaded billboard artwork as a four-panel roadside board.
## Placement is computed from real road geometry and rejects carriageways and
## mapped building footprints, so this is street furniture, not an obstruction.

const AD_TEXTURE := preload("res://assets/textures/billboards/gdk_ads.png")
const PANEL_SIZE := Vector2(3.4, 2.0)

var billboard_count := 0

func build(world: Node, data: MapData) -> void:
	name = "ChowrasthaBillboards"
	var road: Dictionary = world.signage._nearest_road(Vector2.ZERO, 420.0)
	if road.is_empty():
		return
	var point: Vector2 = road.point
	var normal: Vector2 = road.normal
	var position: Vector2 = Vector2.ZERO
	for side in [1.0, -1.0]:
		var candidate: Vector2 = point + normal * side * (road.half_width + 5.0)
		if world.buildings.is_clear(candidate, 4.5):
			position = candidate
			break
	if position == Vector2.ZERO:
		return
	var yaw := atan2(-normal.x, -normal.y)
	_add_billboard(world, position, yaw)

func _add_billboard(world: Node, point: Vector2, yaw: float) -> void:
	var ground: float = world.ground_height(point)
	var root := Node3D.new()
	root.name = "ChowrasthaAdvertisement"
	add_child(root)
	# Two steel posts and a frame keep the downloaded ads in a believable
	# Indian roadside format rather than leaving them as floating flat planes.
	for sideways in [-3.6, 3.6]:
		_add_box(root, Vector3(point.x, ground + 2.25, point.y), Vector3(0.22, 4.5, 0.22), yaw, sideways, Color("#2e3334"))
	_add_box(root, Vector3(point.x, ground + 4.6, point.y), Vector3(7.7, 4.7, 0.16), yaw, 0.0, Color("#202526"))
	for row in 2:
		for column in 2:
			var region := Rect2(Vector2(column * 0.5, row * 0.5), Vector2(0.5, 0.5))
			_add_ad_panel(root, Vector3(point.x, ground + 4.6, point.y), yaw, Vector2((column - 0.5) * PANEL_SIZE.x, (0.5 - row) * PANEL_SIZE.y), region)
	var label := Label3D.new()
	label.text = "CHOWRASTHA • GODAVARIKHANI"
	label.font_size = 25
	label.pixel_size = 0.006
	label.outline_size = 3
	label.modulate = Color("#fff4ca")
	label.position = Vector3(point.x, ground + 7.08, point.y)
	label.rotation.y = yaw
	root.add_child(label)
	billboard_count += 1

func _add_box(parent: Node3D, center: Vector3, size: Vector3, yaw: float, sideways: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = center + Basis(Vector3.UP, yaw) * Vector3(sideways, 0.0, 0.0)
	mesh.rotation.y = yaw
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.55
	material.roughness = 0.48
	mesh.material_override = material
	parent.add_child(mesh)

func _add_ad_panel(parent: Node3D, center: Vector3, yaw: float, offset: Vector2, region: Rect2) -> void:
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	panel.mesh = quad
	var local_offset := Vector3(offset.x, offset.y, 0.1)
	panel.position = center + Basis(Vector3.UP, yaw) * local_offset
	panel.rotation.y = yaw
	var atlas := AtlasTexture.new()
	atlas.atlas = AD_TEXTURE
	atlas.region = Rect2(region.position * AD_TEXTURE.get_size(), region.size * AD_TEXTURE.get_size())
	var material := StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = material
	parent.add_child(panel)
