"""Convert the "Singing Fountains" OBJ (nine water jets, 1.55 M triangles) into a light glTF.

The source is only the water: a column and a spray cloud per jet. The column is kept,
the spray is decimated hard (it reads as mist at game distances). Output fountain_jets.glb
in OUT_DIR: metres, origin at the centre of the jet row on the ground, +Y up, jets spread
along X. The basin and pool are built in Godot.

Run: blender -b --factory-startup --disable-autoexec --python tools/export_fountain.py -- <obj> assets/models/fountain
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

OBJ_PATH, OUT_DIR = sys.argv[sys.argv.index("--") + 1:][:2]
TRI_BUDGET = 40000
# The OBJ is in centimetres (3ds Max export).
UNIT_SCALE = 0.01


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=OBJ_PATH)
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mesh = obj.data
    mesh.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = TRI_BUDGET / tris
    mod.use_collapse_triangulate = True
    reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    obj.modifiers.remove(mod)
    obj.data = reduced
    lo = Vector((min(v.co.x for v in reduced.vertices), min(v.co.y for v in reduced.vertices), min(v.co.z for v in reduced.vertices)))
    hi = Vector((max(v.co.x for v in reduced.vertices), max(v.co.y for v in reduced.vertices), max(v.co.z for v in reduced.vertices)))
    reduced.transform(Matrix.Scale(UNIT_SCALE, 4) @ Matrix.Translation(Vector(((lo.x + hi.x) / -2, (lo.y + hi.y) / -2, -lo.z))))
    water = bpy.data.materials.new("FountainWater")
    water.use_nodes = True
    bsdf = water.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.85, 0.93, 1.0, 1.0)
    bsdf.inputs["Alpha"].default_value = 0.55
    bsdf.inputs["Roughness"].default_value = 0.1
    water.surface_render_method = "BLENDED"
    reduced.materials.clear()
    reduced.materials.append(water)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "fountain_jets.glb"), use_selection=True, export_format="GLB",
                              export_yup=True, export_texcoords=False, export_cameras=False, export_lights=False)
    size = (hi - lo) * UNIT_SCALE
    print(f"STAT fountain tris={sum(len(p.vertices) - 2 for p in reduced.polygons)} source_tris={tris} "
          f"width_x={size.x:.2f} depth={size.y:.2f} height={size.z:.2f}")


main()
