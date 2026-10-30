#!/usr/bin/env python3
"""
tools/export_suv.py
Exports the SUV 4x4 from ~/Downloads/Suv_4x4/Suv_4x4.blend
to assets/models/suv_4x4/
- suv_body.glb
- suv_wheel.glb
- suv_4x4_complete.glb (full assembled vehicle for traffic/prop)
"""
import sys
import os
import bpy
import mathutils

SOURCE_BLEND = os.path.expanduser("~/Downloads/Suv_4x4/Suv_4x4.blend")
DEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "suv_4x4"))
os.makedirs(DEST_DIR, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

body = bpy.data.objects.get("SUV_Body")
wheel_fl = bpy.data.objects.get("FL_2")
root = bpy.data.objects.get("Suv_4x4")

if not body:
    print("ERROR: SUV_Body not found")
    sys.exit(1)

# 1. Export Complete Vehicle (for traffic/prop/static display)
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
for ch in root.children:
    ch.select_set(True)

complete_path = os.path.join(DEST_DIR, "suv_4x4_complete.glb")
bpy.ops.export_scene.gltf(
    filepath=complete_path,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=True
)
print(f"Exported {complete_path}")

# 2. Export Body Only
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
body_path = os.path.join(DEST_DIR, "suv_body.glb")
bpy.ops.export_scene.gltf(
    filepath=body_path,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=True
)
print(f"Exported {body_path}")

# 3. Export Single Wheel centered at (0,0,0) for VehicleWheel3D
if wheel_fl:
    bpy.ops.object.select_all(action='DESELECT')
    wheel_fl.select_set(True)
    bpy.context.view_layer.objects.active = wheel_fl
    
    orig_loc = wheel_fl.location.copy()
    wheel_fl.parent = None
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    wheel_fl.location = (0, 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    
    wheel_path = os.path.join(DEST_DIR, "suv_wheel.glb")
    bpy.ops.export_scene.gltf(
        filepath=wheel_path,
        export_format='GLB',
        use_selection=True,
        export_cameras=False,
        export_lights=False,
        export_apply=True
    )
    print(f"Exported {wheel_path}")

print("All SUV 4x4 assets exported successfully!")
