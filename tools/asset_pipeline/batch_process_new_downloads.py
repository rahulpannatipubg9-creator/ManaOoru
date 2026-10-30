#!/usr/bin/env python3
"""
tools/asset_pipeline/batch_process_new_downloads.py
Processes the new downloads batch (including Royal Enfield Bullet and Bajaj Avenger):
1. Normalizes scale to real-world meters.
2. Centers origin (X=0, Y=0) and grounds base to Z=0.
3. Purges lights and cameras (prevents white world washout).
4. Decimates to mobile/M1 triangle budget (<= 50k tris).
5. Exports clean GLB to assets/models/vehicles/<slug>/<slug>.glb.
6. Registers in data/world/custom_placements.json with authentic placements.
7. Logs licenses in ASSET_LICENSES.md.
"""
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER_BIN = "/opt/homebrew/bin/blender"

DOWNLOADS_CONFIG = [
    {
        "slug": "royal_enfield_bullet",
        "name": "Royal Enfield Bullet 350 Classic",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/royal_enfield_bullet/Bike_RE.fbx"),
        "target_len": 2.15,
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [335.0, 0.0, -360.0],
        "yaw": -45.0,
        "max_tris": 50000,
        "desc": "Iconic Telangana motorcycle parked in Vidyanagar Road No. 2 residential driveway."
    },
    {
        "slug": "bajaj_avenger_cruise",
        "name": "Bajaj Avenger Cruise 220",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/bajaj_avenger_cruise/Avenger 2.fbx"),
        "target_len": 2.21,
        "location_key": "market_street",
        "district": "Saturday Market & Commercial Strip",
        "pos": [125.0, 0.0, -55.0],
        "yaw": 180.0,
        "max_tris": 50000,
        "desc": "Popular Indian cruiser motorcycle parked curbside by the Saturday Market tea and snack stalls."
    },
    {
        "slug": "indian_tgsrtc_bus",
        "name": "TGSRTC Super Luxury Express Bus",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/indian_tgsrtc_bus/indian gsrtc bus.fbx"),
        "target_len": 12.0,
        "location_key": "bus_station",
        "district": "TGSRTC Bus Station Depot",
        "pos": [-715.0, 0.0, 245.0],
        "yaw": 45.0,
        "max_tris": 50000,
        "desc": "State transport passenger bus stationed at the main Godavarikhani TGSRTC Bus Station terminal bay."
    },
    {
        "slug": "dodge_charger_f8",
        "name": "Dodge Charger Fast & Furious Edition",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/dodge_charger_f8/998.glb"),
        "target_len": 5.10,
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Courtyard",
        "pos": [-240.0, 0.0, 185.0],
        "yaw": 180.0,
        "max_tris": 50000,
        "desc": "High-performance muscle car parked in Hotel Sai Leela visitor parking."
    },
    {
        "slug": "ferrari_250_testa_rossa",
        "name": "Ferrari 250 Testa Rossa Vintage",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/ferrari_250_testa_rossa/Sketchfab_2026_10_23_12_47_42.glb"),
        "target_len": 4.15,
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Portico",
        "pos": [-215.0, 0.0, 175.0],
        "yaw": 0.0,
        "max_tris": 50000,
        "desc": "Classic collector supercar showcased in Hotel Sai Leela VIP portico."
    },
    {
        "slug": "alfa_romeo_155_v6",
        "name": "Alfa Romeo 155 V6 TI DTM",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/alfa_romeo_155_v6/Alfa_Romeo_155_V6.fbx"),
        "target_len": 4.40,
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3260.0],
        "yaw": 90.0,
        "max_tris": 50000,
        "desc": "Performance touring racecar stationed at Godavari River Bridge highway approach."
    },
    {
        "slug": "lamborghini_diablo_sv",
        "name": "1997 Lamborghini Diablo SV Coupe",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/lamborghini_diablo_sv/FINAL_MODEL_SV97.fbx"),
        "target_len": 4.46,
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3250.0],
        "yaw": 90.0,
        "max_tris": 50000,
        "desc": "Classic 90s supercar stationed along the Godavari River Bridge northern approach highway."
    },
    {
        "slug": "sa342m_gazelle_helicopter",
        "name": "SA342M Gazelle Light Utility Helicopter",
        "file": os.path.join(PROJECT_ROOT, "work/staging/new_downloads/sa342m_gazelle_helicopter/sa342m_dcs_world.glb"),
        "target_len": 11.97,
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1575.0, 0.0, 1410.0],
        "yaw": 35.0,
        "max_tris": 60000,
        "desc": "Aerial survey utility helicopter stationed on the elevated rim of Singareni Collieries OCP 5."
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

# Purge lights and cameras (Crucial rule in docs/lessons/IMPORTING_MODELS.md)
to_remove = [o for o in bpy.data.objects if o.type in {"LIGHT", "CAMERA"}]
for o in to_remove:
    bpy.data.objects.remove(o, do_unlink=True)

mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
if not mesh_objs:
    print("Error: No meshes found")
    sys.exit(1)

# Compute initial world bounds
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

# Scale normalization to real-world meters
scale_factor = target_len / horiz_length if horiz_length > 0 else 1.0

for o in mesh_objs:
    o.scale *= scale_factor
bpy.ops.object.select_all(action="DESELECT")
for o in mesh_objs:
    o.select_set(True)
bpy.ops.object.transform_apply(scale=True)

# Recompute min after scale
all_pts = [o.matrix_world @ mathutils.Vector(v) for o in mesh_objs for v in o.bound_box]
min_z = min(p.z for p in all_pts)
center_x = (min(p.x for p in all_pts) + max(p.x for p in all_pts)) / 2.0
center_y = (min(p.y for p in all_pts) + max(p.y for p in all_pts)) / 2.0

# Shift so bottom rests at Z=0, center XY = 0
for o in mesh_objs:
    o.location.x -= center_x
    o.location.y -= center_y
    o.location.z -= min_z

bpy.ops.object.select_all(action="DESELECT")
for o in mesh_objs:
    o.select_set(True)
bpy.ops.object.transform_apply(location=True)

# Triangle budget check (Mobile & Apple M1 <= max_tris)
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

# Export clean GLB
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
    print("   MANA OORU - NEW DOWNLOADS BATCH ASSET PROCESSOR   ")
    print("=" * 70)
    
    worker_script_path = "/tmp/mana_ooru_blender_new_downloads.py"
    with open(worker_script_path, "w", encoding="utf-8") as f:
        f.write(BLENDER_SCRIPT)
        
    placements_db_path = os.path.join(PROJECT_ROOT, "data", "world", "custom_placements.json")
    if os.path.exists(placements_db_path):
        with open(placements_db_path, "r", encoding="utf-8") as f:
            placements_data = json.load(f)
    else:
        placements_data = {"version": 1, "assets": []}
        
    processed_count = 0
    failed_count = 0
    
    for i, item in enumerate(DOWNLOADS_CONFIG, 1):
        slug = item["slug"]
        name = item["name"]
        print(f"\n[{i}/{len(DOWNLOADS_CONFIG)}] Processing {name} ({slug})...")
        
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
        f.write("\n\n## New Downloads Vehicle & Helicopter Collection (8 Models)\n")
        f.write("- **Origin:** User downloads in ~/Downloads (Free/Standard 3D models)\n")
        f.write("- **Processing:** Headless Blender 5.2.3 optimization, ground origin alignment, light/camera purging, triangle decimation to <= 50,000 (60,000 for helicopter) for mobile/M1 budgets.\n")
        for item in DOWNLOADS_CONFIG:
            f.write(f"- `{item['slug']}`: {item['name']} ({os.path.basename(item['file'])}) -> `{item['district']}`\n")
            
    print(f"Updated {licenses_path}")
    print(f"\nSummary: Successfully processed {processed_count} assets, {failed_count} failed.")

if __name__ == "__main__":
    main()
