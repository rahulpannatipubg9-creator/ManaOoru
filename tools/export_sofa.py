#!/usr/bin/env python3
"""
tools/export_sofa.py
Exports the modular sofa set from ~/Downloads/sofas_session.blend
to assets/models/props/furniture/sofa_modular.glb
"""
import sys
import os
import bpy
import mathutils

SOURCE_BLEND = os.path.expanduser("~/Downloads/sofas_session.blend")
DEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "props", "furniture"))
DEST_GLB = os.path.join(DEST_DIR, "sofa_modular.glb")

os.makedirs(DEST_DIR, exist_ok=True)

# Open the blend file
bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

# Find sofa meshes
sofa_parts = [o for o in bpy.data.objects if "Sofa_" in o.name and o.type == 'MESH']
if not sofa_parts:
    print("ERROR: No sofa meshes found")
    sys.exit(1)

# Calculate combined bounding box
all_corners = []
for o in sofa_parts:
    all_corners.extend([o.matrix_world @ mathutils.Vector(c) for c in o.bound_box])

min_x = min(c.x for c in all_corners)
max_x = max(c.x for c in all_corners)
min_y = min(c.y for c in all_corners)
max_y = max(c.y for c in all_corners)
min_z = min(c.z for c in all_corners)

center_x = (min_x + max_x) / 2.0
center_y = (min_y + max_y) / 2.0

# Center the master empty or parts
master = bpy.data.objects.get("Three_Sofas_Set")
if master:
    master.location = (master.location.x - center_x, master.location.y - center_y, master.location.z - min_z)
    bpy.context.view_layer.update()

# Join each section into single mesh per module for optimal draw calls and clean scene tree:
# Sofa_Left, Sofa_Center, Sofa_Right
sections = ["Sofa_Left", "Sofa_Center", "Sofa_Right"]
joined_objects = []

for sec_name in sections:
    sec_empty = bpy.data.objects.get(sec_name)
    parts = [o for o in bpy.data.objects if o.name.startswith(sec_name + "_") and o.type == 'MESH']
    if parts:
        bpy.ops.object.select_all(action='DESELECT')
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        active = bpy.context.view_layer.objects.active
        active.name = sec_name
        joined_objects.append(active)
        if sec_empty:
            bpy.data.objects.remove(sec_empty, do_unlink=True)

# Re-parent joined sections to a clean root
root_empty = bpy.data.objects.get("Three_Sofas_Set")
if not root_empty:
    root_empty = bpy.data.objects.new("Three_Sofas_Set", None)
    bpy.context.scene.collection.objects.link(root_empty)

for obj in joined_objects:
    obj.parent = root_empty
    obj.matrix_parent_inverse = root_empty.matrix_world.inverted()

# Select only the sofa hierarchy for export
bpy.ops.object.select_all(action='DESELECT')
root_empty.select_set(True)
for obj in joined_objects:
    obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=DEST_GLB,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=False
)

print(f"Successfully exported {DEST_GLB}")
