"""Convert the "coal-mine-gallery" SketchUp scene into one light glTF for the game.

Blender 5 has no Collada importer, so the .dae is first converted to .glb by Godot
(see the Run line) and this script cleans that up: it merges the 1,400 SketchUp
instances per material, decimates the heaviest parts (glass lamp covers, steel arches)
and re-centres the gallery: origin at the middle of its floor, +Y up.

Output: coal_mine_gallery.glb in OUT_DIR, plus coal_mine_floor.json: the walkable floor
as 1 m grid cells in Godot coordinates (x, z), used by the game to wall in the gallery
(the SketchUp scene only has arches and roof lagging, no side walls).

Run:
  godot --headless --path <tmp project holding temp_export.dae> --script convert.gd   (writes coalmine.glb)
  blender -b --factory-startup --disable-autoexec --python tools/export_coal_mine.py -- coalmine.glb assets/models/coal_mine
"""
import json
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

GLB_PATH, OUT_DIR = sys.argv[sys.argv.index("--") + 1:][:2]
TRI_BUDGET = 70000
MIN_PART_TRIS = 200
# Lamp glass is 1/3 of the source triangles but tiny on screen: give it a smaller share.
SHARE_SCALE = {"Translucent_Glass_Gray": 0.15, "Translucent_Glass_Safety": 0.3}


def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB_PATH)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    merged = {}
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        mesh.transform(obj.matrix_world)
        tmp = bpy.data.objects.new("part", mesh)
        bpy.context.scene.collection.objects.link(tmp)
        key = mesh.materials[0].name if mesh.materials and mesh.materials[0] else "none"
        merged.setdefault(key, []).append(tmp)
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("part") is False]:
        bpy.data.objects.remove(obj)
    joined = []
    for key, parts in merged.items():
        bpy.ops.object.select_all(action="DESELECT")
        for part in parts:
            part.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts) > 1:
            bpy.ops.object.join()
        parts[0].name = "mine_" + key
        joined.append(parts[0])
    total = sum(tri_count(o.data) for o in joined)
    for obj in joined:
        tris = tri_count(obj.data)
        material = obj.name[len("mine_"):]
        budget = max(MIN_PART_TRIS, int(tris * TRI_BUDGET / total * SHARE_SCALE.get(material, 1.0)))
        if tris > budget:
            mod = obj.modifiers.new("dec", "DECIMATE")
            mod.ratio = budget / tris
            mod.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=mod.name)
    verts = [obj.matrix_world @ v.co for obj in joined for v in obj.data.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    shift = Matrix.Translation(Vector(((lo.x + hi.x) / -2, (lo.y + hi.y) / -2, -lo.z)))
    for obj in joined:
        obj.data.transform(shift @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "coal_mine_gallery.glb"), use_selection=True,
                              export_format="GLB", export_yup=True, export_cameras=False, export_lights=False,
                              export_image_format="JPEG")
    # Walkable floor cells: rays straight down inside the tunnel height must hit an upward face.
    bm = bmesh.new()
    for obj in joined:
        bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    cells = []
    half_x = int((hi.x - lo.x) / 2) + 2
    half_y = int((hi.y - lo.y) / 2) + 2
    for x in range(-half_x, half_x + 1):
        for y in range(-half_y, half_y + 1):
            location, normal, _index, _distance = tree.ray_cast(Vector((x, y, 2.0)), Vector((0, 0, -1)), 3.0)
            if location is not None and abs(normal.z) > 0.8:
                # Blender (x, y) → Godot (x, -y).
                cells.append([x, -y, round(location.z, 3)])
    bm.free()
    with open(os.path.join(OUT_DIR, "coal_mine_floor.json"), "w", encoding="utf-8") as handle:
        json.dump({"cell_size": 1.0, "cells": cells}, handle)
    size = hi - lo
    print(f"STAT coal_mine_gallery floor_cells={len(cells)}  tris={sum(tri_count(o.data) for o in joined)} source_tris={total} "
          f"x={size.x:.2f} z_depth={size.y:.2f} height={size.z:.2f}")


main()
