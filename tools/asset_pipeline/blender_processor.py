#!/usr/bin/env python3
"""
tools/asset_pipeline/blender_processor.py
Headless Blender script for automated testing, cleaning, optimization,
ground-origin alignment, classification, and GLB export.

Usage:
  blender -b --factory-startup --disable-autoexec --python tools/asset_pipeline/blender_processor.py -- [args]
"""
import sys
import os
import json
import argparse
import math
import bpy
import mathutils

def clear_blender_scene():
    """Removes all objects, meshes, materials, lamps, and cameras."""
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_asset(filepath: str):
    """Imports 3D model into Blender based on file extension."""
    ext = os.path.splitext(filepath)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=filepath)
        return
    
    clear_blender_scene()
    if ext in {".obj"}:
        if hasattr(bpy.ops.wm, 'obj_import'):
            bpy.ops.wm.obj_import(filepath=filepath, forward_axis='NEGATIVE_Z', up_axis='Y')
        else:
            bpy.ops.import_scene.obj(filepath=filepath)
    elif ext in {".fbx"}:
        bpy.ops.import_scene.fbx(filepath=filepath)
    elif ext in {".gltf", ".glb"}:
        bpy.ops.import_scene.gltf(filepath=filepath)
    elif ext in {".dae"}:
        bpy.ops.wm.collada_import(filepath=filepath)
    elif ext in {".usd", ".usda", ".usdc", ".usdz"}:
        bpy.ops.wm.usd_import(filepath=filepath)
    elif ext in {".stl"}:
        if hasattr(bpy.ops.wm, 'stl_import'):
            bpy.ops.wm.stl_import(filepath=filepath)
        else:
            bpy.ops.import_mesh.stl(filepath=filepath)
    elif ext in {".ply"}:
        if hasattr(bpy.ops.wm, 'ply_import'):
            bpy.ops.wm.ply_import(filepath=filepath)
        else:
            bpy.ops.import_mesh.ply(filepath=filepath)
    else:
        raise ValueError(f"Unsupported file format: {ext}")

def purge_lights_and_cameras() -> int:
    """Removes all lights and cameras. Crucial rule: lamps in glb turn the game white."""
    removed = 0
    to_remove = [o for o in bpy.data.objects if o.type in {'LIGHT', 'CAMERA'}]
    for o in to_remove:
        bpy.data.objects.remove(o, do_unlink=True)
        removed += 1
    return removed

def calculate_mesh_stats():
    """Calculates vertex, polygon, and triangle counts."""
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    total_verts = sum(len(o.data.vertices) for o in mesh_objects)
    total_faces = sum(len(o.data.polygons) for o in mesh_objects)
    total_tris = 0
    for o in mesh_objects:
        o.data.calc_loop_triangles()
        total_tris += len(o.data.loop_triangles)
    return {
        "mesh_count": len(mesh_objects),
        "vertex_count": total_verts,
        "face_count": total_faces,
        "triangle_count": total_tris
    }

def calculate_world_bounds():
    """Computes overall AABB bounding box in world coordinates."""
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    if not mesh_objects:
        return None
    
    all_points = []
    for o in mesh_objects:
        for c in o.bound_box:
            all_points.append(o.matrix_world @ mathutils.Vector(c))
    
    min_x = min(p.x for p in all_points)
    max_x = max(p.x for p in all_points)
    min_y = min(p.y for p in all_points)
    max_y = max(p.y for p in all_points)
    min_z = min(p.z for p in all_points)
    max_z = max(p.z for p in all_points)
    
    return {
        "min_x": float(min_x), "max_x": float(max_x),
        "min_y": float(min_y), "max_y": float(max_y),
        "min_z": float(min_z), "max_z": float(max_z),
        "dim_x": float(max_x - min_x),
        "dim_y": float(max_y - min_y),
        "dim_z": float(max_z - min_z),
        "center_x": float((min_x + max_x) / 2.0),
        "center_y": float((min_y + max_y) / 2.0),
        "center_z": float((min_z + max_z) / 2.0),
    }

def align_to_ground_origin(bounds):
    """
    Shifts all mesh objects so bottom touches Z=0 and horizontal center is at (0,0).
    Applies transforms so origins are normalized.
    """
    center_x = bounds["center_x"]
    center_y = bounds["center_y"]
    min_z = bounds["min_z"]
    
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in mesh_objects:
        o.location.x -= center_x
        o.location.y -= center_y
        o.location.z -= min_z
        bpy.context.view_layer.update()
    
    # Apply transforms
    bpy.ops.object.select_all(action='DESELECT')
    for o in mesh_objects:
        o.select_set(True)
    if mesh_objects:
        bpy.context.view_layer.objects.active = mesh_objects[0]
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

def apply_decimation_if_needed(target_max_tris: int):
    """Applies decimation modifier to reduce polygon count if exceeding budget."""
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    stats = calculate_mesh_stats()
    current_tris = stats["triangle_count"]
    
    if current_tris <= target_max_tris or current_tris == 0:
        return False, current_tris
    
    ratio = max(0.05, min(0.95, target_max_tris / float(current_tris)))
    for o in mesh_objects:
        mod = o.modifiers.new(name="AutoBudgetDecimate", type='DECIMATE')
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    
    new_stats = calculate_mesh_stats()
    return True, new_stats["triangle_count"]

def setup_pbr_materials():
    """Ensures Principled BSDF shader and clean default PBR properties."""
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf:
            bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
            output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None)
            if not output:
                output = nodes.new(type='ShaderNodeOutputMaterial')
            mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

def classify_asset(name_hint: str, bounds: dict, stats: dict) -> dict:
    """
    Intelligently determines the asset category, tags, and placement profile
    based on geometry, dimensions, and semantic keywords.
    """
    name_lower = name_hint.lower()
    dim_x = bounds["dim_x"]
    dim_y = bounds["dim_y"]
    dim_z = bounds["dim_z"]
    max_horiz = max(dim_x, dim_y)
    
    # Keyword & geometric classification
    if any(k in name_lower for k in ["tree", "plant", "palm", "banana", "flower", "bush", "grass", "foliage", "hedge"]):
        return {
            "category": "foliage",
            "suggested_dest": "assets/models/foliage",
            "collision_type": "cylinder",
            "recommended_budget": 15000,
            "tags": ["foliage", "nature", "ground"]
        }
    elif any(k in name_lower for k in ["car", "suv", "truck", "auto", "rickshaw", "jeep", "bike", "vehicle", "bus", "thar", "scooter"]):
        return {
            "category": "vehicles",
            "suggested_dest": "assets/models/vehicles",
            "collision_type": "box",
            "recommended_budget": 50000,
            "tags": ["vehicle", "transport", "parking", "driveway"]
        }
    elif any(k in name_lower for k in ["stall", "panipuri", "chai", "tea", "haathgaadi", "bhelpuri", "cart", "vendor", "tarp"]):
        return {
            "category": "market_street",
            "suggested_dest": "assets/models/market_street",
            "collision_type": "box",
            "recommended_budget": 20000,
            "tags": ["food_stall", "market", "commercial", "pedestrian"]
        }
    elif any(k in name_lower for k in ["sofa", "chair", "table", "bench", "desk", "bed", "couch", "stool", "furniture"]):
        return {
            "category": "furniture",
            "suggested_dest": "assets/models/props/furniture",
            "collision_type": "box",
            "recommended_budget": 15000,
            "tags": ["furniture", "interior", "verandah", "patio"]
        }
    elif any(k in name_lower for k in ["barrier", "sign", "guardrail", "pylon", "pole", "cone", "traffic", "hydrant", "light"]):
        return {
            "category": "road_props",
            "suggested_dest": "assets/models/city_props/road",
            "collision_type": "box",
            "recommended_budget": 10000,
            "tags": ["road_prop", "traffic", "highway", "bridge"]
        }
    elif any(k in name_lower for k in ["brick", "bricks", "stone", "rock", "rubble", "debris", "concrete_block", "mine"]):
        return {
            "category": "debris",
            "suggested_dest": "assets/models/debris",
            "collision_type": "trimesh",
            "recommended_budget": 15000,
            "tags": ["debris", "construction", "industrial", "coal_mine"]
        }
    elif any(k in name_lower for k in ["house", "building", "shop", "theatre", "station", "hotel", "hut", "temple"]) or (dim_z > 4.0 and max_horiz > 6.0):
        return {
            "category": "city_buildings",
            "suggested_dest": "assets/models/city_buildings",
            "collision_type": "trimesh",
            "recommended_budget": 60000,
            "tags": ["building", "architecture", "structure"]
        }
    else:
        # Generic prop
        return {
            "category": "city_props",
            "suggested_dest": "assets/models/city_props",
            "collision_type": "trimesh",
            "recommended_budget": 15000,
            "tags": ["prop", "general", "ground"]
        }

def export_clean_glb(dest_glb_path: str):
    """Exports all mesh objects to an optimized GLB file, strictly stripping cameras and lights."""
    os.makedirs(os.path.dirname(dest_glb_path), exist_ok=True)
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    
    bpy.ops.object.select_all(action='DESELECT')
    for o in mesh_objects:
        o.select_set(True)
    if mesh_objects:
        bpy.context.view_layer.objects.active = mesh_objects[0]

    bpy.ops.export_scene.gltf(
        filepath=dest_glb_path,
        export_format='GLB',
        use_selection=True,
        export_cameras=False,
        export_lights=False,
        export_apply=True
    )

def main():
    # Parse arguments passed after '--'
    argv = sys.argv
    if "--" in argv:
        args_to_parse = argv[argv.index("--") + 1:]
    else:
        args_to_parse = []

    parser = argparse.ArgumentParser(description="Blender Asset Processor for ManaOoru")
    parser.add_argument("--input", required=True, help="Input model filepath")
    parser.add_argument("--slug", required=True, help="Asset slug identifier")
    parser.add_argument("--dest-glb", required=True, help="Target GLB export path")
    parser.add_argument("--report-json", required=True, help="Target diagnostic JSON report path")
    parser.add_argument("--auto-decimate", action="store_true", help="Auto-decimate if exceeding performance budget")
    parser.add_argument("--max-tris", type=int, default=0, help="Custom maximum triangle budget override")

    args = parser.parse_args(args_to_parse)

    print(f"=== ManaOoru Blender Processor ===")
    print(f"Input:   {args.input}")
    print(f"Slug:    {args.slug}")
    print(f"Dest:    {args.dest_glb}")

    # 1. Import
    import_asset(args.input)

    # 2. Strip cameras and lights
    purged_count = purge_lights_and_cameras()
    print(f"Purged {purged_count} lights/cameras (complying with docs/lessons/IMPORTING_MODELS.md).")

    # 3. Calculate initial stats
    initial_stats = calculate_mesh_stats()
    if initial_stats["mesh_count"] == 0:
        print("ERROR: No mesh objects found in asset!")
        sys.exit(1)

    # 4. Calculate bounds
    bounds = calculate_world_bounds()
    print(f"Dimensions: X={bounds['dim_x']:.2f}m, Y={bounds['dim_y']:.2f}m, Z(height)={bounds['dim_z']:.2f}m")
    print(f"Triangles:  {initial_stats['triangle_count']}, Vertices: {initial_stats['vertex_count']}")

    # 5. Classify
    classification = classify_asset(args.slug, bounds, initial_stats)
    print(f"Category:   {classification['category']} (tags: {classification['tags']})")

    # 6. Check performance budget & decimate if requested
    target_budget = args.max_tris if args.max_tris > 0 else classification["recommended_budget"]
    decimated = False
    final_tris = initial_stats["triangle_count"]
    if args.auto_decimate and final_tris > target_budget:
        print(f"Triangles ({final_tris}) exceed budget ({target_budget}). Decimating...")
        decimated, final_tris = apply_decimation_if_needed(target_budget)
        print(f"Decimated: New triangle count = {final_tris}")

    # 7. Ground origin alignment (Zmin = 0, Center XY = 0)
    align_to_ground_origin(bounds)
    print("Aligned base to ground (Z=0) and centered horizontally.")

    # 8. Setup materials
    setup_pbr_materials()

    # 9. Export GLB
    export_clean_glb(args.dest_glb)
    print(f"Successfully exported clean GLB to: {args.dest_glb}")

    # 10. Generate Report
    report = {
        "slug": args.slug,
        "source_file": args.input,
        "dest_glb": args.dest_glb,
        "classification": classification,
        "metrics": {
            "initial_triangles": initial_stats["triangle_count"],
            "final_triangles": final_tris,
            "vertices": initial_stats["vertex_count"],
            "mesh_objects": initial_stats["mesh_count"],
            "decimated": decimated,
            "purged_lights_or_cameras": purged_count,
            "dimensions": {
                "width_x": round(bounds["dim_x"], 3),
                "depth_y": round(bounds["dim_y"], 3),
                "height_z": round(bounds["dim_z"], 3)
            }
        },
        "budget": {
            "target_budget": target_budget,
            "within_budget": final_tris <= (target_budget * 1.2),
            "status": "PASS" if final_tris <= (target_budget * 1.2) else "WARN_OVERBUDGET"
        }
    }

    os.makedirs(os.path.dirname(args.report_json), exist_ok=True)
    with open(args.report_json, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"Wrote diagnostic report to: {args.report_json}")

if __name__ == "__main__":
    main()
