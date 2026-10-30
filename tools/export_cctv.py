"""Export the user-supplied low-poly CCTV asset for Mana Ooru.

Run from the project root:
  blender -b --factory-startup --disable-autoexec ~/Downloads/cctv-v1.blend \
    --python tools/export_cctv.py
"""
import bpy
import os

low_poly = bpy.data.collections.get("Lowpoly_Tri")
if low_poly is None:
    raise RuntimeError("Lowpoly_Tri collection not found in CCTV source")

bpy.ops.object.select_all(action="DESELECT")
for obj in low_poly.objects:
    obj.select_set(True)
    obj.hide_render = False

output = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "cctv", "gdk_cctv.glb")
os.makedirs(os.path.dirname(output), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=output,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_materials="EXPORT",
)
print("Exported", output)
