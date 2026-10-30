#!/usr/bin/env python3
"""
tools/export_road_props.py
Exports individual road and traffic elements from ~/Downloads/Model/Models.blend
to assets/models/city_props/road/
"""
import sys
import os
import bpy
import mathutils

SOURCE_BLEND = os.path.expanduser("~/Downloads/Model/Models.blend")
DEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "city_props", "road"))
os.makedirs(DEST_DIR, exist_ok=True)

# Open source blend file
bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

def export_object(obj_name: str, out_filename: str, center_xy: bool = True, ground_z: bool = True):
    obj = bpy.data.objects.get(obj_name)
    if not obj:
        print(f"Warning: {obj_name} not found")
        return
    
    # Deselect all
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    
    # Store original transform
    orig_loc = obj.location.copy()
    
    bbox = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    min_x = min(c.x for c in bbox)
    max_x = max(c.x for c in bbox)
    min_y = min(c.y for c in bbox)
    max_y = max(c.y for c in bbox)
    min_z = min(c.z for c in bbox)
    
    center_x = (min_x + max_x) / 2.0 if center_xy else 0.0
    center_y = (min_y + max_y) / 2.0 if center_xy else 0.0
    ground_offset = min_z if ground_z else 0.0
    
    obj.location = (orig_loc.x - center_x, orig_loc.y - center_y, orig_loc.z - ground_offset)
    bpy.context.view_layer.update()
    
    out_path = os.path.join(DEST_DIR, out_filename)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=True,
        export_cameras=False,
        export_lights=False,
        export_apply=True
    )
    print(f"Exported {out_path}")
    
    # Restore
    obj.location = orig_loc
    bpy.context.view_layer.update()

# Export props
export_object("Metal_Crash_Barrier_01", "metal_crash_barrier.glb")
export_object("Speed ​​limit sign", "sign_speed_limit.glb")
export_object("Winding road sign", "sign_winding_road.glb")
export_object("Slippery road sign", "sign_slippery_road.glb")
export_object("Pylon_01", "electrical_pylon.glb")

print("All road props exported successfully!")
