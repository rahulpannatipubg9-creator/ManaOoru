"""Convert the Jeep Compass 2022 low-poly FBX into game-ready glTF parts for MANA OORU.

Outputs (in OUT_DIR), same frames as tools/export_thar.py / export_porsche.py so the car scene can reuse
the Thar layout:
  compass_body.glb  body shell + interior + brakes, origin on the ground between the axles, front = -Y (Godot +Z)
  compass_tyre.glb  one tyre, centred, axle along +Z (Godot +Y), outer face on +Z
  compass_rim.glb   matching alloy rim, same frame as the tyre

Source: "car jeep compad.zip" (Jeep Compass 2022 18, 3ds Max + "FBX low poly.fbx"), downloaded by the user.
No licence file came with the download; the source and licence must be confirmed before any public release.
Run: blender -b --factory-startup --disable-autoexec --python tools/export_compass.py -- "FBX low poly.fbx" assets/models/jeep_compass
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
SOURCE, OUT_DIR = ARGS[0], ARGS[1]
# 2022 Compass Limited tyre 225/55 R18: 0.2286 m rim radius + 0.124 m sidewall.
TARGET_WHEEL_RADIUS = 0.353
# The FBX models the car with its front towards -X; the game frame wants the front towards -Y.
SOURCE_TO_GAME = Matrix.Rotation(math.pi / 2, 4, "Z")
TYRE_OBJECTS = {"left front tire", "right front tire", "left rear tire", "right rear tire"}
RIM_OBJECTS = {"front left rim", "front right rim", "left rear rim", "right rear rim"}
# After SOURCE_TO_GAME the FBX "left" side is +X, so its rear wheel is the reusable template
# (the same +X rear pick as the Thar and Porsche exports).
TEMPLATE_TYRE = "left rear tire"
TEMPLATE_RIM = "left rear rim"
FRONT_TYRE = "left front tire"
TYRE_MATERIALS = {"tire", "tire-side"}
BODY_TRI_BUDGET = 110000
MIN_PART_TRIS = 150
TYRE_TRI_BUDGET = 3500
RIM_TRI_BUDGET = 9000

# role: (base colour, metallic, roughness, emission strength, alpha)
ROLES = {
    "Paint": ((0.62, 0.64, 0.66), 0.45, 0.28, 0.0, 1.0),
    "Roof": ((0.02, 0.02, 0.022), 0.3, 0.15, 0.0, 1.0),
    "BlackGloss": ((0.015, 0.015, 0.017), 0.2, 0.1, 0.0, 1.0),
    "Black": ((0.035, 0.038, 0.04), 0.0, 0.45, 0.0, 1.0),
    "Glass": ((0.30, 0.32, 0.34), 0.3, 0.05, 0.0, 0.35),
    "DarkGlass": ((0.06, 0.07, 0.08), 0.2, 0.08, 0.0, 0.75),
    "Chrome": ((0.75, 0.75, 0.77), 0.6, 0.2, 0.0, 1.0),
    "Alloy": ((0.55, 0.55, 0.57), 0.6, 0.35, 0.0, 1.0),
    "Indicator": ((0.95, 0.45, 0.05), 0.0, 0.2, 0.4, 0.85),
    "TailLens": ((0.7, 0.01, 0.0), 0.1, 0.15, 0.3, 1.0),
    "TailLight": ((0.8, 0.02, 0.0), 0.0, 0.3, 0.8, 1.0),
    "Headlight": ((1.0, 0.97, 0.9), 0.0, 0.3, 1.2, 1.0),
    "Plate": ((0.85, 0.85, 0.83), 0.0, 0.5, 0.0, 1.0),
    "Tyre": ((0.012, 0.012, 0.013), 0.0, 0.9, 0.0, 1.0),
}
# source material -> role
MATERIALS = {
    "vray_paint_white": "Paint",
    "vray Fer Pur body titan": "Roof",
    "black gloss": "BlackGloss", "black gloss.001": "BlackGloss", "black_gloss": "BlackGloss", "black_gloss.001": "BlackGloss",
    "grey gloss": "Black", "grey mate": "Black", "grey matt": "Black", "vray_Base": "Black", "Material #2147470907": "Black",
    "glass": "Glass", "glass.001": "Glass",
    "glass black": "DarkGlass", "glass black.001": "DarkGlass",
    "chrome": "Chrome", "chrome gloss": "Chrome", "chrome gloss.001": "Chrome", "chrome.001": "Chrome",
    "chrome.002": "Chrome", "chrome_gloss": "Chrome", "chrome_gloss.001": "Chrome", "mirror": "Chrome",
    "light grey": "Alloy", "light grey.001": "Alloy",
    "light_matt": "Headlight",
    "Glass_orange": "Indicator", "Glass_orange.001": "Indicator",
    "Glass_red": "TailLens", "Glass_red.001": "TailLens",
    "red_light_on": "TailLight", "red_light_on.001": "TailLight",
    "plate": "Plate",
    "tire": "Tyre", "tire-side": "Tyre",
}
FALLBACK_ROLE = "Black"


def build_materials() -> dict[str, bpy.types.Material]:
    result = {}
    for role, (colour, metallic, roughness, emission, alpha) in ROLES.items():
        mat = bpy.data.materials.new("Compass_" + role)
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
        result[role] = mat
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
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SOURCE)
    pbr = build_materials()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    body_parts: list[bpy.types.Mesh] = []
    tyre_parts: list[bpy.types.Mesh] = []
    rim_parts: list[bpy.types.Mesh] = []
    wheel_centres: dict[str, tuple[Vector, float]] = {}
    unmapped: set[str] = set()
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=False)
        mesh.transform(SOURCE_TO_GAME @ obj.matrix_world)
        tyre_slots = set()
        for index, slot in enumerate(mesh.materials):
            source = slot.name if slot else ""
            if source not in MATERIALS:
                unmapped.add(source)
            if source in TYRE_MATERIALS:
                tyre_slots.add(index)
            mesh.materials[index] = pbr[MATERIALS.get(source, FALLBACK_ROLE)]
        parts = split_by_material(mesh, obj.name)
        bpy.data.meshes.remove(mesh)
        if obj.name in TYRE_OBJECTS:
            tyre = [p for p in parts if part_material(p) == pbr["Tyre"]]
            lo, hi = bounds(tyre)
            wheel_centres[obj.name] = ((lo + hi) / 2, (hi.z - lo.z) / 2)
            if obj.name == TEMPLATE_TYRE:
                tyre_parts.extend(tyre)
                # Valve/hub bits modelled inside the tyre object travel with the rim.
                rim_parts.extend(p for p in parts if part_material(p) != pbr["Tyre"])
        elif obj.name in RIM_OBJECTS:
            if obj.name == TEMPLATE_RIM:
                rim_parts.extend(parts)
        else:
            body_parts.extend(parts)
    if unmapped:
        print("STAT unmapped_materials", sorted(unmapped))

    total = sum(tri_count(m) for m in body_parts)
    print("STAT source_body_tris", total)
    for mesh in body_parts:
        decimate(mesh, max(MIN_PART_TRIS, int(tri_count(mesh) * BODY_TRI_BUDGET / total)))
    for group, budget in ((tyre_parts, TYRE_TRI_BUDGET), (rim_parts, RIM_TRI_BUDGET)):
        group_total = sum(tri_count(m) for m in group)
        for mesh in group:
            decimate(mesh, max(MIN_PART_TRIS, int(tri_count(mesh) * budget / group_total)))

    template_centre, radius = wheel_centres[TEMPLATE_TYRE]
    front_y = wheel_centres[FRONT_TYRE][0].y
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

    export(groups["body"], f"{OUT_DIR}/compass_body.glb")
    export(groups["tyre"], f"{OUT_DIR}/compass_tyre.glb")
    export(groups["rim"], f"{OUT_DIR}/compass_rim.glb")


main()
