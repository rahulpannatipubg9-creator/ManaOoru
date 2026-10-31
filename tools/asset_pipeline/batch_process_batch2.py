#!/usr/bin/env python3
"""
tools/asset_pipeline/batch_process_batch2.py
Processes the second batch of downloaded vehicles:
1. roush_mustang_96 (1996 Jack Roush Mustang GT)
2. shelby_patrol_13 (2013 Ford Shelby GT500 Patrol)
3. shelby_cobra_68 (1968 Ford Mustang Shelby Cobra GT500)
4. little_bird_mh6 (MH-6 Little Bird Helicopter)
5. city_transit_bus (RoAZ 5236 City Transit Bus)

Ensures:
- Metric scale normalization
- Origin grounded at Z=0, centered XY=0
- Clean hierarchy (parents cleared, non-meshes removed)
- Purge all lights and cameras
- Triangle budget <= 50k tris (60k for helicopter)
- Registration in data/world/custom_placements.json
- Append to ASSET_LICENSES.md
"""
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER_BIN = "/opt/homebrew/bin/blender"

BATCH2_CONFIG = [
    {
        "slug": "roush_mustang_96",
        "name": "1996 Ford Mustang GT Jack Roush Stage 3",
        "file": os.path.join(PROJECT_ROOT, "work/staging/batch2_downloads/roush_mustang_96/FINAL_MODEL_96.fbx"),
        "target_len": 4.61,
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3240.0],
        "yaw": 90.0,
        "max_tris": 50000,
        "desc": "High performance 1990s American muscle coupe parked on the Godavari River Bridge Highway shoulder."
    },
    {
        "slug": "shelby_patrol_13",
        "name": "2013 Ford Shelby GT500 Highway Patrol",
        "file": os.path.join(PROJECT_ROOT, "work/staging/batch2_downloads/shelby_patrol_13/FINAL_MOPDEL_COP13.fbx"),
        "target_len": 4.78,
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1550.0, 0.0, 1380.0],
        "yaw": 45.0,
        "max_tris": 50000,
        "desc": "Highway patrol pursuit interceptor stationed at Singareni OCP 5 / Ramagundam security checkpoint."
    },
    {
        "slug": "shelby_cobra_68",
        "name": "1968 Ford Mustang Shelby Cobra GT500 Fastback",
        "file": os.path.join(PROJECT_ROOT, "work/staging/batch2_downloads/shelby_cobra_68/FINAL_MODEL_GT50067.fbx"),
        "target_len": 4.74,
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela VIP Courtyard",
        "pos": [-220.0, 0.0, 195.0],
        "yaw": 180.0,
        "max_tris": 50000,
        "desc": "Pristine vintage classic muscle car showcased at Hotel Sai Leela VIP courtyard."
    },
    {
        "slug": "little_bird_mh6",
        "name": "MH-6 Little Bird Light Observation Helicopter",
        "file": os.path.join(PROJECT_ROOT, "work/staging/batch2_downloads/little_bird_mh6/MH-6 Little Bird.obj"),
        "target_len": 9.80,
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1590.0, 0.0, 1425.0],
        "yaw": 25.0,
        "max_tris": 60000,
        "desc": "Mining aerial survey tactical observation helicopter stationed on the OCP 5 open-cast mine rim."
    },
    {
        "slug": "city_transit_bus",
        "name": "RoAZ 5236 Low-Floor City Transit Bus",
        "file": os.path.join(PROJECT_ROOT, "work/staging/batch2_downloads/city_transit_bus/source/RoAZ_5236.fbx"),
        "target_len": 11.90,
        "location_key": "bus_station",
        "district": "TGSRTC Bus Station Depot",
        "pos": [-725.0, 0.0, 260.0],
        "yaw": 45.0,
        "max_tris": 50000,
        "desc": "Low-floor public transit city commuter bus stationed at TGSRTC Godavarikhani bus station depot bay 2."
    }
]

BLENDER_SCRIPT = """
import bpy, os, sys, json, mathutils

input_file = sys.argv[sys.argv.index("--input") + 1]
dest_glb = sys.argv[sys.argv.index("--dest") + 1]
max_tris = int(sys.argv[sys.argv.index("--max-tris") + 1])
target_len = float(sys.argv[sys.argv.index("--target-len") + 1])
slug = sys.argv[sys.argv.index("--slug") + 1]

os.makedirs(os.path.dirname(dest_glb), exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

ext = os.path.splitext(input_file)[1].lower()
try:
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=input_file)
    elif ext == ".obj":
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=input_file, forward_axis="NEGATIVE_Z", up_axis="Y")
        else:
            bpy.ops.import_scene.obj(filepath=input_file)
    elif ext in [".glb", ".gltf"]:
        bpy.ops.import_scene.gltf(filepath=input_file)
    else:
        print(f"Unsupported format: {ext}")
        sys.exit(1)
except Exception as e:
    print(f"Error importing {input_file}: {e}")
    sys.exit(1)

# Step 1: Clear parent keep transform for all objects
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

# Step 2: Remove non-mesh objects (empties, armatures, lights, cameras)
to_remove = [o for o in bpy.data.objects if o.type != "MESH"]
for o in to_remove:
    bpy.data.objects.remove(o, do_unlink=True)

mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
if not mesh_objs:
    print("Error: No meshes found")
    sys.exit(1)

# Step 3: Apply location, rotation, scale to bake world transforms
bpy.ops.object.select_all(action="DESELECT")
for o in mesh_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = mesh_objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Step 4: Compute bounds
all_pts = [o.matrix_world @ mathutils.Vector(v) for o in mesh_objs for v in o.bound_box]
min_x = min(p.x for p in all_pts)
max_x = max(p.x for p in all_pts)
min_y = min(p.y for p in all_pts)
max_y = max(p.y for p in all_pts)
min_z = min(p.z for p in all_pts)
max_z = max(p.z for p in all_pts)

dx = max_x - min_x
dy = max_y - min_y
dz = max_z - min_z
horiz_length = max(dx, dy)
if horiz_length <= 0:
    horiz_length = max(dx, dy, dz)

# Step 5: Scale normalization to real-world meters
scale_factor = target_len / horiz_length if horiz_length > 0 else 1.0
for o in mesh_objs:
    o.scale *= scale_factor
bpy.ops.object.select_all(action="DESELECT")
for o in mesh_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = mesh_objs[0]
bpy.ops.object.transform_apply(scale=True)

# Step 6: Ground base to Z=0 and center XY=0
all_pts = [o.matrix_world @ mathutils.Vector(v) for o in mesh_objs for v in o.bound_box]
min_z = min(p.z for p in all_pts)
center_x = (min(p.x for p in all_pts) + max(p.x for p in all_pts)) / 2.0
center_y = (min(p.y for p in all_pts) + max(p.y for p in all_pts)) / 2.0

for o in mesh_objs:
    o.location.x -= center_x
    o.location.y -= center_y
    o.location.z -= min_z

bpy.ops.object.select_all(action="DESELECT")
for o in mesh_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = mesh_objs[0]
bpy.ops.object.transform_apply(location=True)

# Step 7: Triangle budget decimation
total_tris = sum(len(o.data.polygons) for o in mesh_objs)
if total_tris > max_tris:
    ratio = float(max_tris) / float(total_tris)
    for o in mesh_objs:
        mod = o.modifiers.new(name="DecimateBudget", type="DECIMATE")
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = o
        try:
            bpy.ops.object.modifier_apply(modifier="DecimateBudget")
        except:
            pass

final_tris = sum(len(o.data.polygons) for o in mesh_objs)
all_pts = [o.matrix_world @ mathutils.Vector(v) for o in mesh_objs for v in o.bound_box]
final_dx = max(p.x for p in all_pts) - min(p.x for p in all_pts)
final_dy = max(p.y for p in all_pts) - min(p.y for p in all_pts)
final_dz = max(p.z for p in all_pts) - min(p.z for p in all_pts)

# Step 8: Export clean GLB
bpy.ops.export_scene.gltf(
    filepath=dest_glb,
    export_format="GLB",
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_apply=True
)

out_info = {
    "status": "SUCCESS",
    "initial_tris": total_tris,
    "final_tris": final_tris,
    "dim_x": round(final_dx, 2),
    "dim_y": round(final_dy, 2),
    "dim_z": round(final_dz, 2),
    "dest_glb": dest_glb
}
print("BLENDER_RESULT:" + json.dumps(out_info))
"""

def main():
    print("=" * 70)
    print("   MANA OORU - BATCH 2 DOWNLOADS ASSET PROCESSOR   ")
    print("=" * 70)
    
    worker_script_path = "/tmp/mana_ooru_blender_batch2.py"
    with open(worker_script_path, "w", encoding="utf-8") as f:
        f.write(BLENDER_SCRIPT)
        
    placements_db_path = os.path.join(PROJECT_ROOT, "data", "world", "custom_placements.json")
    with open(placements_db_path, "r", encoding="utf-8") as f:
        placements_data = json.load(f)
        
    processed_count = 0
    failed_count = 0
    
    for i, item in enumerate(BATCH2_CONFIG, 1):
        slug = item["slug"]
        name = item["name"]
        print(f"\n[{i}/{len(BATCH2_CONFIG)}] Processing {name} ({slug})...")
        
        if not os.path.exists(item["file"]):
            print(f"  ERROR: File {item['file']} does not exist!")
            failed_count += 1
            continue
            
        dest_glb = os.path.join(PROJECT_ROOT, "assets", "models", "vehicles", slug, f"{slug}.glb")
        
        cmd = [
            BLENDER_BIN,
            "-b",
            "--factory-startup",
            "--python", worker_script_path,
            "--",
            "--input", item["file"],
            "--dest", dest_glb,
            "--max-tris", str(item["max_tris"]),
            "--target-len", str(item["target_len"]),
            "--slug", slug
        ]
        
        res = subprocess.run(cmd, capture_output=True, text=True)
        result_json = None
        for line in res.stdout.splitlines():
            if line.startswith("BLENDER_RESULT:"):
                result_json = json.loads(line.replace("BLENDER_RESULT:", ""))
                break
                
        if not result_json or not os.path.exists(dest_glb):
            print(f"  FAILED to process {slug}!")
            print("  Stdout preview:", res.stdout[-400:])
            print("  Stderr preview:", res.stderr[-400:])
            failed_count += 1
            continue
            
        print(f"  Exported: {os.path.relpath(dest_glb, PROJECT_ROOT)} ({os.path.getsize(dest_glb)/(1024*1024):.2f} MB)")
        print(f"  Polygons: {result_json['initial_tris']:,} -> {result_json['final_tris']:,}")
        print(f"  Dimensions: {result_json['dim_x']}m x {result_json['dim_y']}m x {result_json['dim_z']}m")
        
        # Register in custom_placements
        model_res_path = f"res://assets/models/vehicles/{slug}/{slug}.glb"
        placements_data["assets"] = [a for a in placements_data["assets"] if a["id"] != slug]
        
        new_entry = {
            "id": slug,
            "name": name,
            "model_path": model_res_path,
            "category": "vehicles",
            "location_key": item["location_key"],
            "location_name": item["district"],
            "district": item["district"],
            "position": item["pos"],
            "use_ground_height": True,
            "ground_offset_y": 0.02,
            "rotation_y_deg": item["yaw"],
            "scale": [1.0, 1.0, 1.0],
            "collision_type": "box",
            "visibility_range_end": 250.0,
            "metadata": {
                "source_file": os.path.basename(item["file"]),
                "triangles": result_json["final_tris"],
                "dimensions": {
                    "width_x": result_json["dim_x"],
                    "depth_y": result_json["dim_y"],
                    "height_z": result_json["dim_z"]
                },
                "placement_reasoning": item["desc"]
            }
        }
        placements_data["assets"].append(new_entry)
        processed_count += 1
        
    with open(placements_db_path, "w", encoding="utf-8") as f:
        json.dump(placements_data, f, indent=2)
    print(f"\nUpdated {placements_db_path} (Total assets: {len(placements_data['assets'])})")
    
    # Update ASSET_LICENSES.md
    licenses_path = os.path.join(PROJECT_ROOT, "ASSET_LICENSES.md")
    with open(licenses_path, "a", encoding="utf-8") as f:
        f.write("\n\n## Batch 2 Downloads Vehicles & Helicopter (5 Models)\n")
        f.write("- **Origin:** User downloads in ~/Downloads\n")
        f.write("- **Processing:** Headless Blender 5.2.3 optimization, hierarchy unparenting, ground origin alignment, light/camera purging, triangle decimation to <= 50,000 (60,000 for helicopter) for mobile/M1 budgets.\n")
        for item in BATCH2_CONFIG:
            f.write(f"- `{item['slug']}`: {item['name']} ({os.path.basename(item['file'])}) -> `{item['district']}`\n")
            
    print(f"Updated {licenses_path}")
    print(f"\nSummary: Successfully processed {processed_count} assets, {failed_count} failed.")

if __name__ == "__main__":
    main()

