"""Convert the three houses in "building House.zip" (house.FBX + maps/) into game-ready glTF files.

Outputs house_1.glb, house_2.glb, house_3.glb in OUT_DIR: metres, origin at the centre of the
footprint on the ground, +Y up. Each house keeps its textures (resized to 1024 px) and is
decimated to a budget suitable for placing many copies. A STAT line per house gives its
footprint size, height and the source facing so the game can align it to real footprints.

Run: blender -b --factory-startup --disable-autoexec --python tools/export_houses.py -- <house.FBX> <maps dir> assets/models/houses
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

FBX_PATH, MAPS_DIR, OUT_DIR = sys.argv[sys.argv.index("--") + 1:][:3]
TRI_BUDGET = 9000
MIN_PART_TRIS = 40
MAX_TEXTURE = 1024
# Keyword in the source material name → (texture file or None, fallback colour, roughness, alpha)
MATERIAL_RULES = [
    ("glass", (None, (0.10, 0.14, 0.18), 0.05, 0.6)),
    ("window frame", (None, (0.92, 0.92, 0.9), 0.5, 1.0)),
    ("roof house 2", ("tile house 2 diffuse, displacement,reflection,glossines.jpg", (0.35, 0.2, 0.15), 0.8, 1.0)),
    ("roof", ("tile house 1 diffuse, displacement,reflection,glossines.jpg", (0.35, 0.2, 0.15), 0.8, 1.0)),
    ("siding 2", ("siding 2 house 1-2-3 diffuse.png", (0.8, 0.78, 0.7), 0.7, 1.0)),
    ("siding", ("siding1-2-3 house 1-2-3 diffuse,bump.jpg", (0.8, 0.78, 0.7), 0.7, 1.0)),
    ("plinth house 1.001", ("plinth house 2 diffuse.jpg", (0.55, 0.5, 0.45), 0.9, 1.0)),
    ("plinth", ("plinth house 1 diffuse.jpg", (0.55, 0.5, 0.45), 0.9, 1.0)),
    ("painted wood", ("painted wood diffuse bump.jpg", (0.85, 0.85, 0.82), 0.6, 1.0)),
    ("tile", ("tile diffuse.jpg", (0.6, 0.55, 0.5), 0.8, 1.0)),
    ("brick", ("brick diffuse.jpg", (0.55, 0.3, 0.22), 0.9, 1.0)),
    ("plaster", ("plaster diffuse.jpg", (0.85, 0.82, 0.75), 0.9, 1.0)),
    ("profile sheet", ("profile sheet.jpg", (0.5, 0.5, 0.52), 0.5, 1.0)),
    ("wall", ("stucco-texture_(83).jpg", (0.88, 0.85, 0.78), 0.9, 1.0)),
    ("metall", (None, (0.45, 0.46, 0.48), 0.4, 1.0)),
]
FALLBACK = (None, (0.7, 0.7, 0.7), 0.8, 1.0)


def rule_for(name):
    lower = name.lower()
    for keyword, rule in MATERIAL_RULES:
        if keyword in lower:
            return rule
    return FALLBACK


def make_material(name, cache):
    texture, colour, roughness, alpha = rule_for(name)
    key = (texture, colour, roughness, alpha)
    if key in cache:
        return cache[key]
    mat = bpy.data.materials.new("House_" + (os.path.splitext(texture)[0][:20] if texture else name[:20]))
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if texture and os.path.exists(os.path.join(MAPS_DIR, texture)):
        image = bpy.data.images.load(os.path.join(MAPS_DIR, texture))
        if max(image.size) > MAX_TEXTURE:
            factor = MAX_TEXTURE / max(image.size)
            image.scale(max(1, int(image.size[0] * factor)), max(1, int(image.size[1] * factor)))
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED"
    cache[key] = mat
    return mat


def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def decimate(obj, budget):
    tris = tri_count(obj.data)
    if tris <= budget:
        return
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = budget / tris
    mod.use_collapse_triangulate = True
    reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    obj.modifiers.remove(mod)
    old = obj.data
    obj.data = reduced
    bpy.data.meshes.remove(old)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_PATH)
    cache = {}
    os.makedirs(OUT_DIR, exist_ok=True)
    houses = sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)
    for index, source in enumerate(houses, start=1):
        mesh = source.data.copy()
        mirrored = source.matrix_world.determinant() < 0.0
        mesh.transform(source.matrix_world)
        if mirrored:
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(mesh)
            bm.free()
        for slot, material in enumerate(mesh.materials):
            mesh.materials[slot] = make_material(material.name if material else "fallback", cache)
        lo = Vector((min(v.co.x for v in mesh.vertices), min(v.co.y for v in mesh.vertices), min(v.co.z for v in mesh.vertices)))
        hi = Vector((max(v.co.x for v in mesh.vertices), max(v.co.y for v in mesh.vertices), max(v.co.z for v in mesh.vertices)))
        mesh.transform(Matrix.Translation(Vector(((lo.x + hi.x) / -2, (lo.y + hi.y) / -2, -lo.z))))
        obj = bpy.data.objects.new(f"house_{index}", mesh)
        bpy.context.scene.collection.objects.link(obj)
        decimate(obj, max(MIN_PART_TRIS, TRI_BUDGET))
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, f"house_{index}.glb"), use_selection=True,
                                  export_format="GLB", export_yup=True, export_cameras=False, export_lights=False,
                                  export_image_format="JPEG")
        size = hi - lo
        # Blender X → Godot X, Blender Y → Godot -Z, Blender Z → Godot Y.
        print(f"STAT house_{index} source={source.name} width_x={size.x:.2f} depth_z={size.y:.2f} height={size.z:.2f} "
              f"tris={tri_count(obj.data)}")
        bpy.data.objects.remove(obj)


main()
