"""Extract the apartment blocks from the "street-city-buildings-8" pack (улица скетч.fbx) as glTF.

The pack is a small diorama: a ground plate, a placeholder box and repeated copies of a
few panel-block buildings, modelled at 1/10 scale. One copy of each distinct block is
exported, scaled to metres, origin at the centre of its footprint on the ground, +Y up:
  apartment_<name>.glb in OUT_DIR, with a STAT line giving width (X), depth (Z) and height.

Run: blender -b --factory-startup --disable-autoexec --python tools/export_street_blocks.py -- <fbx> assets/models/apartments
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

FBX_PATH, OUT_DIR = sys.argv[sys.argv.index("--") + 1:][:2]
# Diorama scale: the long block is 2.48 units tall, a 9-storey panel block is about 25 m.
SCALE = 10.0
# One representative of each block type in the diorama.
# (Cube.018 is the long block again, turned 45° in the diorama.)
BLOCKS = {"Cube.001": "long", "Cube.003": "section", "Plane": "corner"}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_PATH)
    os.makedirs(OUT_DIR, exist_ok=True)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for source_name, label in BLOCKS.items():
        source = bpy.data.objects.get(source_name)
        if source is None:
            print(f"STAT missing {source_name}")
            continue
        mesh = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph))
        # Keep only rotation and scale; the copy is re-centred on its own footprint.
        world = source.matrix_world.copy()
        mesh.transform(Matrix.LocRotScale(None, world.to_quaternion(), world.to_scale()))
        if world.determinant() < 0.0:
            mesh.flip_normals()
        lo = Vector((min(v.co.x for v in mesh.vertices), min(v.co.y for v in mesh.vertices), min(v.co.z for v in mesh.vertices)))
        hi = Vector((max(v.co.x for v in mesh.vertices), max(v.co.y for v in mesh.vertices), max(v.co.z for v in mesh.vertices)))
        mesh.transform(Matrix.Scale(SCALE, 4) @ Matrix.Translation(Vector(((lo.x + hi.x) / -2, (lo.y + hi.y) / -2, -lo.z))))
        obj = bpy.data.objects.new(f"apartment_{label}", mesh)
        bpy.context.scene.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, f"apartment_{label}.glb"), use_selection=True,
                                  export_format="GLB", export_yup=True, export_cameras=False, export_lights=False,
                                  export_image_format="JPEG")
        size = (hi - lo) * SCALE
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        # Blender X → Godot X, Blender Y → Godot -Z, Blender Z → Godot Y.
        print(f"STAT apartment_{label} width_x={size.x:.2f} depth_z={size.y:.2f} height={size.z:.2f} tris={tris}")
        bpy.data.objects.remove(obj)


main()
