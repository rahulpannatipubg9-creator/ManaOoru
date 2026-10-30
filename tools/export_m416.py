"""Convert the CC0 "M416 / HK416" .blend (Blend Swap #17759, by natholas) into a game-ready glTF.

Output: m416.glb with the rifle in metres, barrel along Godot +Z (the character's forward),
up = +Y, origin at the top of the pistol grip so it can be held in a hand.

Run: blender -b --factory-startup --disable-autoexec M416.blend --python tools/export_m416.py -- assets/models/weapons
"""
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
import math

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
ROOT_OBJECT = "Circle"
GRIP_OBJECT = "Cube"
# HK416 A5 with a 14.5" barrel and the stock half-extended is about 0.85 m long.
TARGET_LENGTH = 0.85
# A held weapon is seen up close but must stay cheap on phones.
TRI_BUDGET = 14000
MIN_PART_TRIS = 60
# source material: (base colour, metallic, roughness)
COLOURS = {
    "main": ((0.05, 0.05, 0.055), 0.6, 0.45),
    "main.001": ((0.09, 0.09, 0.095), 0.5, 0.5),
    "magazine": ((0.03, 0.03, 0.03), 0.2, 0.7),
    "handle": ((0.06, 0.055, 0.05), 0.1, 0.8),
    "Material.001": ((0.6, 0.45, 0.15), 0.9, 0.3),
    "Material.002": ((0.55, 0.4, 0.12), 0.9, 0.35),
}


def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def decimate(mesh, budget):
    tris = tri_count(mesh)
    if tris <= budget:
        return
    tmp = bpy.data.objects.new("tmp_decimate", mesh)
    bpy.context.scene.collection.objects.link(tmp)
    mod = tmp.modifiers.new("dec", "DECIMATE")
    mod.ratio = budget / tris
    mod.use_collapse_triangulate = True
    reduced = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bm = bmesh.new()
    bm.from_mesh(reduced)
    bm.to_mesh(mesh)
    bm.free()
    bpy.data.meshes.remove(reduced)


def collect(root):
    result = [root]
    for child in root.children:
        result.extend(collect(child))
    # The cartridges (Cylinder.001+) sit inside the magazine and are never seen.
    return [o for o in result if o.type == "MESH" and not o.name.startswith("Cylinder.")]


def main():
    objects = collect(bpy.data.objects[ROOT_OBJECT])
    for obj in objects:
        for slot in obj.material_slots:
            if slot.material is None:
                continue
            colour, metallic, roughness = COLOURS.get(slot.material.name, ((0.08, 0.08, 0.08), 0.4, 0.6))
            mat = slot.material
            mat.use_nodes = True
            nodes = mat.node_tree.nodes
            nodes.clear()
            bsdf = nodes.new("ShaderNodeBsdfPrincipled")
            out = nodes.new("ShaderNodeOutputMaterial")
            mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
            bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
            bsdf.inputs["Metallic"].default_value = metallic
            bsdf.inputs["Roughness"].default_value = roughness
    depsgraph = bpy.context.evaluated_depsgraph_get()
    merged = []
    for obj in objects:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        mesh.transform(obj.matrix_world)
        merged.append(mesh)
    total = sum(tri_count(mesh) for mesh in merged)
    for mesh in merged:
        decimate(mesh, max(MIN_PART_TRIS, int(tri_count(mesh) * TRI_BUDGET / total)))
    verts = [v.co for mesh in merged for v in mesh.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    grip = bpy.data.objects[GRIP_OBJECT]
    grip_box = [grip.matrix_world @ Vector(corner) for corner in grip.bound_box]
    grip_top = Vector((sum(c.x for c in grip_box) / 8, (lo.y + hi.y) / 2, max(c.z for c in grip_box)))
    scale = TARGET_LENGTH / (hi.x - lo.x)
    # Barrel along Blender +X → -Y (glTF/Godot +Z), then metres, origin at the grip.
    transform = Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Scale(scale, 4) @ Matrix.Translation(-grip_top)
    bpy.ops.object.select_all(action="DESELECT")
    parts = []
    for index, mesh in enumerate(merged):
        mesh.transform(transform)
        part = bpy.data.objects.new(f"M416_part_{index}", mesh)
        bpy.context.scene.collection.objects.link(part)
        part.select_set(True)
        parts.append(part)
    tris = sum(len(p.vertices) - 2 for mesh in merged for p in mesh.polygons)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "m416.glb"), use_selection=True, export_format="GLB",
                              export_yup=True, export_texcoords=False, export_cameras=False, export_lights=False)
    print(f"STAT m416 tris={tris} length={TARGET_LENGTH} scale={scale:.5f}")


main()
