"""Convert the CC-BY Mahindra Thar .blend into game-ready glTF parts for MANA OORU.

Outputs (in OUT_DIR):
  thar_body.glb  body shell, origin on the ground between the axles, front = -Y (glTF/Godot +Z)
  thar_tyre.glb  one tyre, centred, axle along +Z (Godot +Y), outer face on +Z
  thar_rim.glb   matching alloy rim + brake disc, same frame as the tyre

Source: "Mahindra Thar 3D Model" by aakash2 (CC-BY), https://www.blendswap.com/blend/31849
Run: blender -b --disable-autoexec "Mahindra Thar 3D Model.blend" --python tools/export_thar.py -- assets/models/thar
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# Real Thar runs 255/65 R18 tyres: 0.2286 m rim radius + 0.1658 m sidewall.
TARGET_WHEEL_RADIUS = 0.394

WHEEL_OBJECTS = {"Wheel_Tyre": "tyre", "Wheel_alloys final": "rim", "Wheel_alloys": "rim", "Disc Brake": "rim"}
NO_SUBSURF = {"Wheel_alloys final", "Wheel_alloys", "Spare_Wheel_Rim", "Mahindra Logo", "Thar Side Logo",
              "Thar Front Logo", "4x4 Logo", "m_HAWK130"}
# Per-object triangle budget after modifiers; anything heavier is collapse-decimated.
TRI_BUDGET = {"Wheel_Tyre": 4000, "Wheel_alloys final": 10000, "Wheel_alloys": 1500, "Spare_Wheel_Rim": 1800, "WIper's": 600,
              "Mahindra Logo": 500, "Thar Side Logo": 500, "Thar Front Logo": 500, "4x4 Logo": 400, "m_HAWK130": 300}
DEFAULT_TRI_BUDGET = 1600

# name: (base colour, metallic, roughness, emission strength). Metallic stays below 1 because
# the sky gives little reflection, and fully metallic chrome renders black in-game.
MATERIALS = {
    "Car Paint": ((0.50, 0.012, 0.010), 0.55, 0.28, 0.0),
    "Glass_Black": ((0.012, 0.016, 0.02), 0.25, 0.05, 0.0),
    "Glass_Clear": ((0.85, 0.87, 0.88), 0.3, 0.06, 0.25),
    "Glass_Red": ((0.55, 0.01, 0.008), 0.1, 0.12, 0.6),
    "Metal_Black_Semi_Bumpy.Small": ((0.03, 0.03, 0.032), 0.6, 0.45, 0.0),
    "Metal_Chrome": ((0.72, 0.73, 0.75), 0.55, 0.3, 0.0),
    "Metal_Chrome_TailLight": ((0.8, 0.8, 0.82), 1.0, 0.12, 0.0),
    "Mirror": ((0.75, 0.77, 0.8), 0.6, 0.08, 0.0),
    "Plastic_Black_Dull": ((0.022, 0.022, 0.024), 0.0, 0.75, 0.0),
    "Plastic_Black_Gloss": ((0.02, 0.02, 0.022), 0.0, 0.25, 0.0),
    "Plastic_Black_Semi_Bumpy.Big": ((0.025, 0.025, 0.027), 0.0, 0.6, 0.0),
    "Plastic_Black_Semi_Bumpy.Med": ((0.025, 0.025, 0.027), 0.0, 0.55, 0.0),
    "Plastic_Grey.Dark_Dull": ((0.05, 0.05, 0.052), 0.0, 0.8, 0.0),
    "Plastic_Grey.Dark_Semi_Bumpy.Med": ((0.045, 0.045, 0.048), 0.0, 0.65, 0.0),
    "Plastic_Grey_Semi_Bumpy.Small": ((0.06, 0.06, 0.065), 0.1, 0.5, 0.0),
    "Plastic_Silver_Semi_Bumpy.Tiny": ((0.45, 0.46, 0.48), 0.7, 0.35, 0.0),
    "Tire": ((0.022, 0.022, 0.024), 0.0, 0.9, 0.0),
}
FALLBACK_MATERIAL = "Plastic_Black_Dull"
# The model has no cabin interior; tinted see-through windows keep first-person view usable.
WINDOW_ALPHA = {"Glass_Black": 0.55}


def is_renderable(obj: bpy.types.Object) -> bool:
    if obj.type != "MESH" or obj.hide_render:
        return False
    return not any(c.hide_render or c.name == "LCA" for c in obj.users_collection)


def build_material(name: str) -> bpy.types.Material:
    colour, metallic, roughness, emission = MATERIALS[name]
    mat = bpy.data.materials.new("Thar_" + name.replace(".", "_"))
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    if name in WINDOW_ALPHA:
        bsdf.inputs["Alpha"].default_value = WINDOW_ALPHA[name]
        mat.surface_render_method = "BLENDED"
    return mat


def tri_count(mesh: bpy.types.Mesh) -> int:
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def decimate(mesh: bpy.types.Mesh, budget: int) -> None:
    tris = tri_count(mesh)
    if tris <= budget:
        return
    tmp = bpy.data.objects.new("tmp_decimate", mesh)
    bpy.context.scene.collection.objects.link(tmp)
    mod = tmp.modifiers.new("dec", "DECIMATE")
    mod.ratio = budget / tris
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    reduced = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bm = bmesh.new()
    bm.from_mesh(reduced)
    bm.to_mesh(mesh)
    bm.free()
    bpy.data.meshes.remove(reduced)


def islands(mesh: bpy.types.Mesh) -> list[tuple[Vector, Vector, list[int]]]:
    """(bbox min, bbox max, face indices) for every loose part."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    seen: set[int] = set()
    parts = []
    for face in bm.faces:
        if face.index in seen:
            continue
        stack, faces = [face], []
        seen.add(face.index)
        while stack:
            f = stack.pop()
            faces.append(f.index)
            for edge in f.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        coords = [v.co for i in faces for v in bm.faces[i].verts]
        lo = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
        hi = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
        parts.append((lo, hi, faces))
    bm.free()
    return parts


def keep_faces(mesh: bpy.types.Mesh, keep: set[int]) -> None:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(mesh)
    bm.free()


def export(objects: list[bpy.types.Object], path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=False,
                              export_yup=True, export_texcoords=False, export_cameras=False, export_lights=False)


def main() -> None:
    sources = [o for o in bpy.data.objects if is_renderable(o)]
    for obj in sources:
        for mod in obj.modifiers:
            if mod.type == "SUBSURF":
                cap = 0 if obj.name in NO_SUBSURF else 1
                mod.levels = min(mod.levels, cap)
                mod.render_levels = min(mod.render_levels, cap)

    pbr = {name: build_material(name) for name in MATERIALS}
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    baked: dict[str, list[bpy.types.Object]] = {"body": [], "tyre": [], "rim": []}
    for obj in sources:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=False)
        if not mesh.polygons:
            continue
        mesh.transform(obj.matrix_world)
        for index, slot in enumerate(mesh.materials):
            original = slot.name if slot else FALLBACK_MATERIAL
            mesh.materials[index] = pbr.get(original, pbr[FALLBACK_MATERIAL])
        if not mesh.materials:
            mesh.materials.append(pbr[FALLBACK_MATERIAL])
        decimate(mesh, TRI_BUDGET.get(obj.name, DEFAULT_TRI_BUDGET))
        baked[WHEEL_OBJECTS.get(obj.name, "body")].append(bpy.data.objects.new(obj.name + "_baked", mesh))

    # Wheel centres come from the tyre islands; there are four plus none in the spare (separate object).
    tyre_parts = [(lo, hi) for t in baked["tyre"] for lo, hi, _ in islands(t.data) if (hi.z - lo.z) > 0.5]
    centres = [(lo + hi) / 2 for lo, hi in tyre_parts]
    radius = max((hi.z - lo.z) / 2 for lo, hi in tyre_parts)
    rear_right = max(centres, key=lambda c: (c.x > 0, c.y))
    front_y = min(c.y for c in centres)
    rear_y = max(c.y for c in centres)
    axle_mid_y = (front_y + rear_y) / 2
    scale = TARGET_WHEEL_RADIUS / radius

    # Keep only the rear-right wheel's geometry for the reusable tyre/rim meshes.
    for kind in ("tyre", "rim"):
        for obj in baked[kind]:
            keep = {i for lo, hi, faces in islands(obj.data)
                    if ((lo + hi) / 2 - rear_right).length < radius * 1.2 for i in faces}
            keep_faces(obj.data, keep)
            obj.data.transform(Matrix.Translation(-rear_right))
            obj.data.transform(Matrix.Rotation(-math.pi / 2, 4, "Y"))
            obj.data.transform(Matrix.Scale(scale, 4))

    ground_z = rear_right.z - radius
    body_matrix = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((0.0, -axle_mid_y, -ground_z)))
    for obj in baked["body"]:
        obj.data.transform(body_matrix)

    scene = bpy.context.scene
    for objs in baked.values():
        for obj in objs:
            scene.collection.objects.link(obj)

    body_verts = [v.co for o in baked["body"] for v in o.data.vertices]
    lo = Vector((min(v.x for v in body_verts), min(v.y for v in body_verts), min(v.z for v in body_verts)))
    hi = Vector((max(v.x for v in body_verts), max(v.y for v in body_verts), max(v.z for v in body_verts)))
    print("STAT scale", round(scale, 4))
    print("STAT wheel_radius", round(radius * scale, 4))
    print("STAT wheel_x", round(rear_right.x * scale, 4))
    print("STAT front_axle_godot_z", round((axle_mid_y - front_y) * scale, 4))
    print("STAT body_godot_x", round(lo.x, 3), round(hi.x, 3), "y", round(lo.z, 3), round(hi.z, 3),
          "z", round(-hi.y, 3), round(-lo.y, 3))
    for kind, objs in baked.items():
        print("STAT tris", kind, sum(tri_count(o.data) for o in objs))

    export(baked["body"], f"{OUT_DIR}/thar_body.glb")
    export(baked["tyre"], f"{OUT_DIR}/thar_tyre.glb")
    export(baked["rim"], f"{OUT_DIR}/thar_rim.glb")


main()
