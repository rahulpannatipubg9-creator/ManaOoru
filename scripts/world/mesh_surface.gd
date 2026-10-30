class_name MeshSurface
extends RefCounted

## Triangle-soup builder shared by the world builders: one ArrayMesh surface
## plus matching collision faces.

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var collision := PackedVector3Array()

## Adds a triangle whose front face points along normal (Godot front faces are clockwise).
func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, info: Vector2, collide: bool) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap_point := b
		b = c
		c = swap_point
		var swap_uv := uv_b
		uv_b = uv_c
		uv_c = swap_uv
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	colors.append_array(PackedColorArray([color, color, color]))
	uvs.append_array(PackedVector2Array([uv_a, uv_b, uv_c]))
	uv2s.append_array(PackedVector2Array([info, info, info]))
	if collide:
		collision.append_array(PackedVector3Array([a, b, c]))

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2, info: Vector2, collide: bool) -> void:
	triangle(a, b, c, normal, color, uv_a, uv_b, uv_c, info, collide)
	triangle(a, c, d, normal, color, uv_a, uv_c, uv_d, info, collide)

func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
