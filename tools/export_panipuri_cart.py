"""Convert the user-supplied pani-puri cart into a self-contained GLB."""
import bpy
import os

root = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "panipuri_cart")
source = os.path.join(root, "source", "scene.gltf")
output = os.path.join(root, "gdk_panipuri_cart.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
print("Exported", output)
