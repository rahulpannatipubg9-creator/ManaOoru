"""Convert the user-supplied Indian water-tank mesh into a game-ready GLB."""
import bpy
import os

root = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "indian_water_tank")
source = os.path.join(root, "source", "tank.obj")
output = os.path.join(root, "gdk_indian_water_tank.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=source)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
print("Exported", output)
