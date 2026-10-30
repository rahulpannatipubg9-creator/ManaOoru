#!/usr/bin/env python3
"""
tools/export_banana_tree.py
Exports the Banana Tree model from ~/Downloads/Banana_Plant_01.obj to
assets/models/foliage/banana_tree.glb with proper ground origin and PBR material.
"""
import sys
import os
import bpy
import mathutils

SOURCE_OBJ = os.path.expanduser("~/Downloads/Banana_Plant_01.obj")
DEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models", "foliage"))
DEST_GLB = os.path.join(DEST_DIR, "banana_tree.glb")

os.makedirs(DEST_DIR, exist_ok=True)

# Clear existing objects in Blender
for o in bpy.data.objects:
    bpy.data.objects.remove(o, do_unlink=True)
for m in bpy.data.materials:
    bpy.data.materials.remove(m, do_unlink=True)

# Import OBJ
bpy.ops.wm.obj_import(
    filepath=SOURCE_OBJ,
    forward_axis='NEGATIVE_Z',
    up_axis='Y',
    use_split_objects=False,
    use_split_groups=False
)

banana_obj = next((o for o in bpy.data.objects if o.type == 'MESH'), None)
if not banana_obj:
    print("ERROR: No mesh found after importing OBJ")
    sys.exit(1)

banana_obj.name = "BananaTree"

# Compute bounding box and align bottom of trunk to Z=0 and center at XY=(0,0)
bbox = [banana_obj.matrix_world @ mathutils.Vector(c) for c in banana_obj.bound_box]
min_x = min(c.x for c in bbox)
max_x = max(c.x for c in bbox)
min_y = min(c.y for c in bbox)
max_y = max(c.y for c in bbox)
min_z = min(c.z for c in bbox)

center_x = (min_x + max_x) / 2.0
center_y = (min_y + max_y) / 2.0

bpy.context.view_layer.objects.active = banana_obj
banana_obj.select_set(True)
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
banana_obj.location = (-center_x, -center_y, -min_z)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

# Setup Material
mat = bpy.data.materials.new(name="BananaPlant_Mat")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
if bsdf:
    # Rich tropical banana leaf green
    bsdf.inputs['Base Color'].default_value = (0.22, 0.52, 0.12, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.35
    bsdf.inputs['Metallic'].default_value = 0.0

if banana_obj.data.materials:
    banana_obj.data.materials[0] = mat
else:
    banana_obj.data.materials.append(mat)

# Select only the mesh for export
bpy.ops.object.select_all(action='DESELECT')
banana_obj.select_set(True)

# Export to GLTF / GLB (strip cameras and lights)
bpy.ops.export_scene.gltf(
    filepath=DEST_GLB,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=True
)

print(f"Successfully exported {DEST_GLB}")
