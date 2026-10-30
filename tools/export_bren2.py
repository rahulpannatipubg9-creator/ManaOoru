"""Convert the user-supplied CZ Bren 2 .glb into a game-ready glTF for Mana Ooru.

Output: bren2.glb with the rifle in metres, barrel along Godot +Z (the character's forward),
up = +Y, origin at the top of the pistol grip so it can be held in a hand, and PBR materials embedded.

Run: blender -b --factory-startup --disable-autoexec --python tools/export_bren2.py
"""
import math
import os
import sys

import bpy
import mathutils

SRC_FILE = "/Users/rahulpannati/Downloads/czbren2.glb"
OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "weapons"))
OUT_FILE = os.path.join(OUT_DIR, "bren2.glb")

TARGET_LENGTH = 0.85
GRIP_TOP = mathutils.Vector((0.0176, 0.8770, 0.0251))
TRI_BUDGET = 15000

colors = {
    'base': (0.04, 0.04, 0.045, 1.0),
    'front': (0.04, 0.04, 0.045, 1.0),
    'stock': (0.035, 0.035, 0.038, 1.0),
    'grip': (0.03, 0.03, 0.03, 1.0),
    'grip.001': (0.025, 0.025, 0.028, 1.0),
    'rails': (0.06, 0.06, 0.065, 1.0),
    'mag.001': (0.035, 0.035, 0.035, 1.0),
    'bolt': (0.2, 0.2, 0.22, 1.0),
    'ironsight': (0.05, 0.05, 0.05, 1.0),
    'reddot_base': (0.04, 0.04, 0.04, 1.0),
    'glass': (0.2, 0.4, 0.5, 0.4),
    'Material.002': (0.03, 0.03, 0.03, 1.0),
}

def setup_materials():
    for name, col in colors.items():
        mat = bpy.data.materials.get(name)
        if mat and mat.use_nodes:
            mat.use_backface_culling = True
            bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf:
                bsdf.inputs['Base Color'].default_value = col
                if name in ['base', 'front', 'rails', 'ironsight', 'Material.002', 'reddot_base']:
                    bsdf.inputs['Metallic'].default_value = 0.8
                    bsdf.inputs['Roughness'].default_value = 0.4
                elif name in ['bolt']:
                    bsdf.inputs['Metallic'].default_value = 0.95
                    bsdf.inputs['Roughness'].default_value = 0.25
                elif name in ['glass']:
                    bsdf.inputs['Metallic'].default_value = 0.0
                    bsdf.inputs['Roughness'].default_value = 0.05
                    bsdf.inputs['Transmission Weight'].default_value = 0.9
                else:
                    bsdf.inputs['Metallic'].default_value = 0.05
                    bsdf.inputs['Roughness'].default_value = 0.65

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC_FILE)

    setup_materials()

    # Apply transforms
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Join meshes
    bpy.context.view_layer.objects.active = bpy.data.objects['Plane.016']
    bpy.ops.object.join()
    gun = bpy.context.active_object
    gun.name = "BREN2"

    # Measure source length along Y
    verts = [v.co for v in gun.data.vertices]
    min_y = min(v.y for v in verts)
    max_y = max(v.y for v in verts)
    source_length = max_y - min_y
    scale = TARGET_LENGTH / source_length

    # Transform origin to GRIP_TOP, scale to target length
    gun.data.transform(mathutils.Matrix.Translation(-GRIP_TOP))
    gun.data.transform(mathutils.Matrix.Scale(scale, 4))

    # Decimate
    initial_tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)
    mod = gun.modifiers.new('planar', 'DECIMATE')
    mod.decimate_type = 'DISSOLVE'
    mod.angle_limit = math.radians(1.0)
    mod.delimit = {'UV', 'SEAM', 'SHARP'}
    bpy.ops.object.modifier_apply(modifier='planar')

    current_tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)
    if current_tris > TRI_BUDGET:
        mod2 = gun.modifiers.new('collapse', 'DECIMATE')
        mod2.ratio = TRI_BUDGET / current_tris
        bpy.ops.object.modifier_apply(modifier='collapse')

    final_tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)

    # Calculate muzzle tip
    f_verts = [v.co for v in gun.data.vertices]
    tip_y = min(v.y for v in f_verts)
    tip_verts = [v for v in f_verts if v.y < tip_y + 0.005]
    tip = sum(tip_verts, mathutils.Vector()) / len(tip_verts)

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    gun.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_FILE,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False
    )

    print(f"Exported {OUT_FILE}")
    print(f"Tris: {final_tris} (source: {initial_tris})")
    print(f"Length: {TARGET_LENGTH}m, Scale: {scale:.5f}")
    print(f"Godot Muzzle: ({tip.x:.3f}, {tip.z:.3f}, {-tip.y:.3f})")

if __name__ == "__main__":
    main()
