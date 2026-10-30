#!/usr/bin/env python3
"""
tools/export_swimming_pool.py
Exports the luxury swimming pool from ~/Downloads/swimming pool rigged/Swimming_Pool.blend
to assets/models/environment/pool/swimming_pool_luxury.glb
"""
import sys
import os
import bpy

SOURCE_BLEND = os.path.expanduser("~/Downloads/swimming pool rigged/Swimming_Pool.blend")
DEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "environment", "pool"))
DEST_GLB = os.path.join(DEST_DIR, "swimming_pool_luxury.glb")

os.makedirs(DEST_DIR, exist_ok=True)

# Open source blend file
bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

pool_obj = bpy.data.objects.get("Swimming_Pool")
if not pool_obj:
    print("ERROR: Swimming_Pool object not found")
    sys.exit(1)

bpy.ops.object.select_all(action='DESELECT')
pool_obj.select_set(True)
bpy.context.view_layer.objects.active = pool_obj

# 1. Apply scale (converts from mm to real meters)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# 2. Re-center XY to (0,0) and place top pool deck lip at Z=0
import mathutils
bbox = [pool_obj.matrix_world @ mathutils.Vector(c) for c in pool_obj.bound_box]
min_x = min(c.x for c in bbox)
max_x = max(c.x for c in bbox)
min_y = min(c.y for c in bbox)
max_y = max(c.y for c in bbox)
max_z = max(c.z for c in bbox)

center_x = (min_x + max_x) / 2.0
center_y = (min_y + max_y) / 2.0

pool_obj.location = (-center_x, -center_y, -max_z)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

# Export GLB (strip cameras and lights)
bpy.ops.export_scene.gltf(
    filepath=DEST_GLB,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=True
)

print(f"Successfully exported {DEST_GLB}")
