"""Create a mobile-friendly version of the user-supplied pani-puri cart."""
import bpy
import os

root = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "panipuri_cart")
source = os.path.join(root, "source", "scene.gltf")
output = os.path.join(root, "gdk_panipuri_cart_mobile.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH" or len(obj.data.polygons) < 80:
        continue
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("MobileDecimate", "DECIMATE")
    modifier.ratio = 0.18
    modifier.decimate_type = "COLLAPSE"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
print("Exported", output)
