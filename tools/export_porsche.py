"""Convert the CC BY-NC Porsche 911 Carrera 4S (992) .blend into game-ready glTF parts for MANA OORU.

Outputs (in OUT_DIR), same frames as tools/export_thar.py so the car scene can reuse the Thar layout:
  porsche_body.glb  body shell + brake calipers, origin on the ground between the axles, front = -Y (Godot +Z)
  porsche_tyre.glb  one tyre, centred, axle along +Z (Godot +Y), outer face on +Z
  porsche_rim.glb   matching alloy rim + disc, same frame as the tyre

Source: "Realistic new 2020 porsche 911 carrera 4s 992 with materials", Blend Swap #93636, CC BY-NC 3.0,
https://www.blendswap.com/blends/view/93636
Run: blender -b --disable-autoexec "911 4s final.blend" --python tools/export_porsche.py -- assets/models/porsche_911
"""
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
import math

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# 992 Carrera 4S rear tyre 305/30 ZR21: 0.2667 m rim radius + 0.0915 m sidewall.
TARGET_WHEEL_RADIUS = 0.358
EXCLUDED_OBJECTS = {"Plane", "Plane.006"}
WHEEL_OBJECTS = {"flwheel", "frwheel", "blwheel", "brwheel"}
# The rear wheel on the +X side becomes the reusable tyre/rim (same pick as the Thar export).
TEMPLATE_WHEEL = "blwheel"
TYRE_MATERIAL = "Material.014"
BODY_TRI_BUDGET = 110000
MIN_PART_TRIS = 150
TYRE_TRI_BUDGET = 3500
RIM_TRI_BUDGET = 9000

# source material: (role, base colour, metallic, roughness, emission strength, alpha)
MATERIALS = {
    "Material": ("Paint", (0.55, 0.56, 0.50), 0.35, 0.25, 0.0, 1.0),
    "Material.001": ("BlackGloss", (0.015, 0.015, 0.017), 0.2, 0.08, 0.0, 1.0),
    "Material.002": ("Glass", (0.30, 0.32, 0.34), 0.3, 0.05, 0.0, 0.35),
    "Material.003": ("Glass", (0.30, 0.32, 0.34), 0.3, 0.05, 0.0, 0.35),
    "Material.020": ("Glass", (0.30, 0.32, 0.34), 0.3, 0.05, 0.0, 0.35),
    "Material.010": ("SmokedLens", (0.08, 0.08, 0.09), 0.2, 0.2, 0.0, 0.7),
    "Material.004": ("LampHousing", (0.20, 0.22, 0.29), 0.6, 0.3, 0.0, 1.0),
    "Material.005": ("DaytimeLight", (0.75, 0.85, 1.0), 0.0, 0.3, 1.5, 1.0),
    "Material.016": ("Headlight", (1.0, 0.97, 0.9), 0.0, 0.3, 1.2, 1.0),
    "Material.015": ("TailLight", (0.8, 0.02, 0.0), 0.0, 0.3, 0.8, 1.0),
    "Material.021": ("TailLens", (0.7, 0.01, 0.0), 0.1, 0.15, 0.3, 1.0),
    "Material.009": ("TailHousing", (0.15, 0.01, 0.0), 0.0, 0.8, 0.0, 1.0),
    "Material.006": ("Caliper", (0.75, 0.02, 0.02), 0.2, 0.3, 0.0, 1.0),
    "Material.007": ("Trim", (0.022, 0.025, 0.029), 0.0, 0.4, 0.0, 1.0),
    "Material.011": ("Interior", (0.05, 0.05, 0.05), 0.0, 0.8, 0.0, 1.0),
    "Material.013": ("Black", (0.035, 0.038, 0.04), 0.0, 0.35, 0.0, 1.0),
    "Material.023": ("Black", (0.035, 0.038, 0.04), 0.0, 0.35, 0.0, 1.0),
    "Material.008": ("Chrome", (0.75, 0.75, 0.77), 0.55, 0.25, 0.0, 1.0),
    "Material.022": ("Chrome", (0.75, 0.75, 0.77), 0.55, 0.25, 0.0, 1.0),
    "Material.027": ("Chrome", (0.75, 0.75, 0.77), 0.55, 0.25, 0.0, 1.0),
    "Material.012": ("Alloy", (0.55, 0.52, 0.55), 0.6, 0.35, 0.0, 1.0),
    "Material.017": ("BrakeDisc", (0.25, 0.25, 0.26), 0.6, 0.5, 0.0, 1.0),
    "Material.018": ("Alloy", (0.55, 0.52, 0.55), 0.6, 0.35, 0.0, 1.0),
    # Badge textures are not in the download, so badges and lettering get a flat silver.
    "Material.019": ("Badge", (0.7, 0.7, 0.72), 0.6, 0.2, 0.0, 1.0),
    "Material.026": ("Badge", (0.7, 0.7, 0.72), 0.6, 0.2, 0.0, 1.0),
    "imatriculation.001": ("Plate", (0.85, 0.85, 0.83), 0.0, 0.5, 0.0, 1.0),
    TYRE_MATERIAL: ("Tyre", (0.012, 0.012, 0.013), 0.0, 0.9, 0.0, 1.0),
}
FALLBACK_MATERIAL = "Material.013"


def build_materials() -> dict[str, bpy.types.Material]:
    by_role: dict[str, bpy.types.Material] = {}
    result = {}
    for source, (role, colour, metallic, roughness, emission, alpha) in MATERIALS.items():
        if role not in by_role:
            mat = bpy.data.materials.new("Porsche_" + role)
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
            if alpha < 1.0:
                bsdf.inputs["Alpha"].default_value = alpha
                mat.surface_render_method = "BLENDED"
            by_role[role] = mat
        result[source] = by_role[role]
    return result


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


def split_by_material(mesh: bpy.types.Mesh, name: str) -> list[bpy.types.Mesh]:
    """One mesh per material slot, so decimation never trades a small part away for a big one."""
    parts = []
    for slot in range(len(mesh.materials)):
        part = mesh.copy()
        bm = bmesh.new()
        bm.from_mesh(part)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != slot], context="FACES")
        bm.to_mesh(part)
        bm.free()
        if part.polygons:
            part.name = f"{name}_{slot}"
            parts.append(part)
        else:
            bpy.data.meshes.remove(part)
    return parts


def part_material(mesh: bpy.types.Mesh) -> bpy.types.Material:
    return mesh.materials[mesh.polygons[0].material_index]


def bounds(meshes: list[bpy.types.Mesh]) -> tuple[Vector, Vector]:
    verts = [v.co for m in meshes for v in m.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    return lo, hi


def export(objects: list[bpy.types.Object], path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=False,
                              export_yup=True, export_texcoords=False, export_cameras=False, export_lights=False)


def main() -> None:
    pbr = build_materials()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    body_parts: list[bpy.types.Mesh] = []
    tyre_parts: list[bpy.types.Mesh] = []
    rim_parts: list[bpy.types.Mesh] = []
    wheel_centres: dict[str, Vector] = {}
    for obj in [o for o in bpy.data.objects if o.type == "MESH" and o.name not in EXCLUDED_OBJECTS]:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=False)
        mesh.transform(obj.matrix_world)
        sources = [slot.name if slot else FALLBACK_MATERIAL for slot in mesh.materials]
        for index, source in enumerate(sources):
            mesh.materials[index] = pbr.get(source, pbr[FALLBACK_MATERIAL])
        parts = split_by_material(mesh, obj.name)
        bpy.data.meshes.remove(mesh)
        if obj.name in WHEEL_OBJECTS:
            tyre = [p for p in parts if part_material(p) == pbr[TYRE_MATERIAL]]
            lo, hi = bounds(tyre)
            wheel_centres[obj.name] = ((lo + hi) / 2, (hi.z - lo.z) / 2)
            if obj.name == TEMPLATE_WHEEL:
                tyre_parts.extend(tyre)
                rim_parts.extend(p for p in parts if part_material(p) != pbr[TYRE_MATERIAL])
        else:
            body_parts.extend(parts)

    total = sum(tri_count(m) for m in body_parts)
    for mesh in body_parts:
        decimate(mesh, max(MIN_PART_TRIS, int(tri_count(mesh) * BODY_TRI_BUDGET / total)))
    for group, budget in ((tyre_parts, TYRE_TRI_BUDGET), (rim_parts, RIM_TRI_BUDGET)):
        group_total = sum(tri_count(m) for m in group)
        for mesh in group:
            decimate(mesh, max(MIN_PART_TRIS, int(tri_count(mesh) * budget / group_total)))

    template_centre, radius = wheel_centres[TEMPLATE_WHEEL]
    front_y = wheel_centres["flwheel"][0].y
    rear_y = template_centre.y
    axle_mid_y = (front_y + rear_y) / 2
    scale = TARGET_WHEEL_RADIUS / radius
    for mesh in tyre_parts + rim_parts:
        mesh.transform(Matrix.Translation(-template_centre))
        mesh.transform(Matrix.Rotation(-math.pi / 2, 4, "Y"))
        mesh.transform(Matrix.Scale(scale, 4))
    ground_z = template_centre.z - radius
    body_matrix = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((0.0, -axle_mid_y, -ground_z)))
    for mesh in body_parts:
        mesh.transform(body_matrix)

    scene = bpy.context.scene
    groups: dict[str, list[bpy.types.Object]] = {}
    for kind, meshes in (("body", body_parts), ("tyre", tyre_parts), ("rim", rim_parts)):
        groups[kind] = []
        for mesh in meshes:
            obj = bpy.data.objects.new(mesh.name, mesh)
            scene.collection.objects.link(obj)
            groups[kind].append(obj)

    lo, hi = bounds(body_parts)
    print("STAT scale", round(scale, 4))
    print("STAT wheel_radius", round(radius * scale, 4))
    print("STAT wheel_x", round(template_centre.x * scale, 4))
    print("STAT front_axle_godot_z", round((axle_mid_y - front_y) * scale, 4))
    print("STAT body_godot_x", round(lo.x, 3), round(hi.x, 3), "y", round(lo.z, 3), round(hi.z, 3),
          "z", round(-hi.y, 3), round(-lo.y, 3))
    for kind, objs in groups.items():
        print("STAT tris", kind, sum(tri_count(o.data) for o in objs))

    export(groups["body"], f"{OUT_DIR}/porsche_body.glb")
    export(groups["tyre"], f"{OUT_DIR}/porsche_tyre.glb")
    export(groups["rim"], f"{OUT_DIR}/porsche_rim.glb")


main()
