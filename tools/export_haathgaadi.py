"""Export haathgaadi (Indian handcart) model to GLB for Mana Ooru."""
import os
import bpy

blend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "haathgaadi", "haathgaadi.blend"))
output_glb = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "haathgaadi", "gdk_haathgaadi.glb"))

bpy.ops.wm.open_mainfile(filepath=blend_path)

# Deselect all
bpy.ops.object.select_all(action="DESELECT")

# Select only mesh objects (no lights, no cameras as per lessons)
for obj in bpy.data.objects:
    if obj.type == "MESH":
        obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=output_glb,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_materials="EXPORT",
    export_apply=True
)

print(f"Successfully exported {output_glb}")

