"""Convert a user-supplied USDZ model into a self-contained Godot GLB.

Usage:
  blender -b --factory-startup --disable-autoexec --python tools/export_usdz_asset.py -- source.usdz output.glb
"""
import bpy
import os
import sys

args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 2:
    raise RuntimeError("expected input USDZ and output GLB paths")
source, output = args
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=source)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
os.makedirs(os.path.dirname(output), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
print("Exported", output)
