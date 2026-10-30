#!/usr/bin/env python3
"""
tools/asset_pipeline/batch_process_all_cars.py
Processes all 26 extracted vehicle models using headless Blender:
1. Imports FBX / OBJ.
2. Strips cameras and lights.
3. Automatically normalizes scale to real-world meters (3m - 7m).
4. Sets ground origin (Z=0) and centers XY (X=0, Y=0).
5. Applies decimation if over 50,000 triangle budget for Apple Silicon / mobile.
6. Exports clean GLB to assets/models/vehicles/<slug>/<slug>.glb.
7. Registers placements in data/world/custom_placements.json and ASSET_LICENSES.md.
"""
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXTRACT_BASE = "/Users/rahulpannati/WhatsApp Inbox Screens/Cars collection/extracted"
BLENDER_BIN = "/opt/homebrew/bin/blender"

CARS_CONFIG = [
    # Supercars / Luxury -> Hotel Sai Leela Courtyard
    {
        "folder": "2802964.5e99ae2b62572",
        "slug": "lamborghini_aventador_svj",
        "name": "2019 Lamborghini Aventador SVJ",
        "file": "2019_Lamborghini_Aventador_SVJ.fbx",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Portico",
        "pos": [-220.0, 0.0, 175.0],
        "yaw": 0.0
    },
    {
        "folder": "2276695.5bf2e70bac3f6",
        "slug": "bmw_i8",
        "name": "2015 BMW i8 Hybrid",
        "file": "2015_BMW_i8_LOW.fbx",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Portico",
        "pos": [-225.0, 0.0, 175.0],
        "yaw": 0.0
    },
    {
        "folder": "2654440.5e04dd119b3d6",
        "slug": "mercedes_amg_gt63",
        "name": "Mercedes-Benz AMG GT 63",
        "file": "Mercedes-Benz AMG GT 63.FBX",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Portico",
        "pos": [-230.0, 0.0, 175.0],
        "yaw": 0.0
    },
    {
        "folder": "2574825.5d9dfd0a39308",
        "slug": "porsche_cayenne_s",
        "name": "2019 Porsche Cayenne S",
        "file": "Porsche Cayenne S 2019 VRAY.FBX",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Courtyard",
        "pos": [-220.0, 0.0, 185.0],
        "yaw": 180.0
    },
    {
        "folder": "2813156.5ea15149650d4",
        "slug": "porsche_boxster",
        "name": "Porsche Boxster Roadster",
        "file": "Porsche Boxster_vray.FBX",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Courtyard",
        "pos": [-225.0, 0.0, 185.0],
        "yaw": 180.0
    },
    {
        "folder": "2632066.5de93f288c3d8",
        "slug": "tesla_model_x",
        "name": "Tesla Model X",
        "file": "Tesla Model X.FBX",
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Courtyard",
        "pos": [-230.0, 0.0, 185.0],
        "yaw": 180.0
    },
    
    # Sports / Highway -> Godavari Bridge Approach
    {
        "folder": "2743403.5e681701ca66a",
        "slug": "toyota_supra_gr",
        "name": "Toyota Supra GR",
        "file": "Toyota_Supra_GR_.obj",
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3280.0],
        "yaw": 90.0
    },
    {
        "folder": "2803143.5e99c744b1b2c",
        "slug": "bmw_x4",
        "name": "2015 BMW X4",
        "file": "2015_BMW_X4_LOW.FBX",
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3300.0],
        "yaw": 90.0
    },
    {
        "folder": "2780769.5e89db1e6f5b5",
        "slug": "hydrospace_benelli_s4",
        "name": "Hydrospace Benelli S4 Watercraft",
        "file": "HSR Benelli S4.obj",
        "location_key": "godavari_bridge",
        "district": "Godavari River Pier",
        "pos": [765.0, 0.0, -3290.0],
        "yaw": 90.0
    },

    # Residential Colony -> Vidyanagar Road No. 2
    {
        "folder": "2287539.5bf92fa68df9c",
        "slug": "bmw_x5",
        "name": "2014 BMW X5",
        "file": "2014_BMW_X5_LOW.fbx",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [310.0, 0.0, -335.0],
        "yaw": -45.0
    },
    {
        "folder": "1755522.5aa03cf29e27f",
        "slug": "bmw_x6",
        "name": "BMW X6 xDrive50i",
        "file": "BMW X6 xDrive50i 03.obj",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [315.0, 0.0, -340.0],
        "yaw": -45.0
    },
    {
        "folder": "2318581.5c1ba494dd3b4",
        "slug": "mini_cooper_s",
        "name": "2015 Mini Cooper S",
        "file": "2015_Mini_Cooper_S_LOW.fbx",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [320.0, 0.0, -345.0],
        "yaw": -45.0
    },
    {
        "folder": "2573587.5d9c8fb3c75e7",
        "slug": "mazda_cx5",
        "name": "Mazda CX-5",
        "file": "MazdaCX5.obj",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [325.0, 0.0, -350.0],
        "yaw": -45.0
    },
    {
        "folder": "2613962.5dd3e8e757793",
        "slug": "volvo_xc40",
        "name": "Volvo XC40",
        "file": "Volvo XC40_vray.FBX",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [330.0, 0.0, -355.0],
        "yaw": -45.0
    },
    {
        "folder": "2589321.5db2abf40516a",
        "slug": "audi_q8",
        "name": "Audi Q8 2019",
        "file": "AudiQ8.obj",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [305.0, 0.0, -330.0],
        "yaw": -45.0
    },
    {
        "folder": "2785264.5e8cc35a6653f",
        "slug": "volkswagen_id",
        "name": "Volkswagen I.D.",
        "file": "Volkswagen_I_D.FBX",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [300.0, 0.0, -325.0],
        "yaw": -45.0
    },
    {
        "folder": "2583635.5daa2c4be87b1",
        "slug": "mercedes_sedan",
        "name": "Mercedes-Benz Luxury Sedan",
        "file": "mercedes Obj.obj",
        "location_key": "vidyanagar_residential",
        "district": "Vidyanagar Residential Quarter",
        "pos": [295.0, 0.0, -320.0],
        "yaw": -45.0
    },

    # Commercial & Mining -> Coal Mine OCP 5 Incline Worksite
    {
        "folder": "2655211.5e05f9d024326",
        "slug": "scania_haul_truck",
        "name": "Scania 2013 Commercial Truck",
        "file": "scania_2013__vray.fbx",
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1535.0, 0.0, 1375.0],
        "yaw": 35.0
    },
    {
        "folder": "2714700.5e4a9f1bb26a5",
        "slug": "ford_transit_camion",
        "name": "Ford Transit Utility Van/Truck",
        "file": "FordTransitCamion.obj",
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1545.0, 0.0, 1385.0],
        "yaw": 35.0
    },
    {
        "folder": "2600332.5dc15157a5c07",
        "slug": "can_am_maverick",
        "name": "Can-Am Maverick Buggy 2019",
        "file": "can-am maverick.FBX",
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1550.0, 0.0, 1390.0],
        "yaw": 35.0
    },

    # Central Urban -> Ambedkar Park & Bus Station Parking
    {
        "folder": "2598794.5dbeff0a7addf",
        "slug": "range_rover_evoque",
        "name": "Range Rover Evoque 2019",
        "file": "Range Rover Evoque 2019.FBX",
        "location_key": "ambedkar_park",
        "district": "Dr. B.R. Ambedkar Park Parking",
        "pos": [-180.0, 0.0, -110.0],
        "yaw": 0.0
    },
    {
        "folder": "2675676.5e20555f318df",
        "slug": "audi_q3_sportback",
        "name": "Audi Q3 Sportback",
        "file": "AUDI Q3 SPORTBACK.FBX",
        "location_key": "ambedkar_park",
        "district": "Dr. B.R. Ambedkar Park Parking",
        "pos": [-175.0, 0.0, -110.0],
        "yaw": 0.0
    },
    {
        "folder": "2717559.5e4d518349cdc",
        "slug": "mercedes_gla",
        "name": "Mercedes-Benz GLA",
        "file": "Mercedes-Benz GLA_VRAY.FBX",
        "location_key": "bus_station",
        "district": "TGSRTC Bus Station Depot",
        "pos": [-710.0, 0.0, 230.0],
        "yaw": 45.0
    },
    {
        "folder": "2725012.5e54f8c3464a9",
        "slug": "mercedes_amg_gla35",
        "name": "Mercedes-AMG GLA 35 4MATIC",
        "file": "Mercedes-AMG GLA 35 4MATIC.fbx",
        "location_key": "bus_station",
        "district": "TGSRTC Bus Station Depot",
        "pos": [-700.0, 0.0, 230.0],
        "yaw": 45.0
    },

    # Market Strip -> Saturday Bazaar & Market Street
    {
        "folder": "2673021.5e1da9a01d327",
        "slug": "range_rover_classic",
        "name": "Land Rover Range Rover",
        "file": "Range Rover FBX.FBX",
        "location_key": "market_street",
        "district": "Saturday Market & Commercial Strip",
        "pos": [130.0, 0.0, -60.0],
        "yaw": 180.0
    },
    {
        "folder": "2607201.5dcadeb70c9c3",
        "slug": "audi_q8_custom",
        "name": "Audi Q8 Custom",
        "file": "audi_q8.obj",
        "location_key": "market_street",
        "district": "Saturday Market & Commercial Strip",
        "pos": [140.0, 0.0, -60.0],
        "yaw": 180.0
    }
]

# Blender processing script template
BLENDER_WORKER_SCRIPT = """
import bpy, os, sys, json, mathutils

input_file = sys.argv[sys.argv.index("--input") + 1]
dest_glb = sys.argv[sys.argv.index("--dest") + 1]
max_tris = int(sys.argv[sys.argv.index("--max-tris") + 1])
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

# Determine realistic vehicle length target in meters
if "scania" in slug or "truck" in slug:
    target_len = 7.2
elif "transit" in slug:
    target_len = 5.3
elif "can_am" in slug or "maverick" in slug:
    target_len = 3.4
elif "mini" in slug:
    target_len = 3.86
elif "benelli" in slug or "jet" in slug:
    target_len = 3.1
elif "boxster" in slug or "supra" in slug:
    target_len = 4.35
elif "aventador" in slug:
    target_len = 4.85
elif "i8" in slug:
    target_len = 4.70
elif "tesla" in slug:
    target_len = 5.03
elif "x5" in slug or "x6" in slug or "q8" in slug:
    target_len = 4.95
else:
    target_len = 4.65

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

# Triangle budget check (Mobile & Apple M1 <= 50k triangles)
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

# Output summary JSON line
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
    print("   MANA OORU - FULL VEHICLE COLLECTION BATCH PROCESSOR   ")
    print("=" * 70)
    print(f"Vehicles to process: {len(CARS_CONFIG)}")
    
    worker_script_path = "/tmp/mana_ooru_blender_worker.py"
    with open(worker_script_path, "w", encoding="utf-8") as f:
        f.write(BLENDER_WORKER_SCRIPT)
        
    placements_db_path = os.path.join(PROJECT_ROOT, "data", "world", "custom_placements.json")
    if os.path.exists(placements_db_path):
        with open(placements_db_path, "r", encoding="utf-8") as f:
            placements_data = json.load(f)
    else:
        placements_data = {"version": 1, "assets": []}
        
    existing_ids = {a["id"] for a in placements_data["assets"]}
    
    processed_count = 0
    failed_count = 0
    
    for i, car in enumerate(CARS_CONFIG, 1):
        slug = car["slug"]
        name = car["name"]
        print(f"\n[{i}/{len(CARS_CONFIG)}] Processing {name} ({slug})...")
        
        # Locate file
        folder_path = os.path.join(EXTRACT_BASE, car["folder"])
        found_file = None
        for root, dirs, files in os.walk(folder_path):
            if car["file"] in files:
                found_file = os.path.join(root, car["file"])
                break
                
        if not found_file:
            print(f"  ERROR: File {car['file']} not found in {folder_path}!")
            failed_count += 1
            continue
            
        dest_glb = os.path.join(PROJECT_ROOT, "assets", "models", "vehicles", slug, f"{slug}.glb")
        
        # Run Blender worker
        cmd = [
            BLENDER_BIN,
            "-b",
            "--factory-startup",
            "--python", worker_script_path,
            "--",
            "--input", found_file,
            "--dest", dest_glb,
            "--max-tris", "50000",
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
            print("  Stdout preview:", res.stdout[-300:])
            print("  Stderr preview:", res.stderr[-300:])
            failed_count += 1
            continue
            
        print(f"  Exported: {os.path.relpath(dest_glb, PROJECT_ROOT)} ({os.path.getsize(dest_glb)/(1024*1024):.2f} MB)")
        print(f"  Polygons: {result_json['initial_tris']:,} -> {result_json['final_tris']:,}")
        print(f"  Dimensions: {result_json['dim_x']}m x {result_json['dim_y']}m x {result_json['dim_z']}m")
        
        # Register in custom_placements
        model_res_path = f"res://assets/models/vehicles/{slug}/{slug}.glb"
        
        # Remove existing if already present
        placements_data["assets"] = [a for a in placements_data["assets"] if a["id"] != slug]
        
        new_entry = {
            "id": slug,
            "name": name,
            "model_path": model_res_path,
            "category": "vehicles",
            "location_key": car["location_key"],
            "location_name": car["district"],
            "district": car["district"],
            "position": car["pos"],
            "use_ground_height": True,
            "ground_offset_y": 0.02,
            "rotation_y_deg": car["yaw"],
            "scale": [1.0, 1.0, 1.0],
            "collision_type": "box",
            "visibility_range_end": 250.0,
            "metadata": {
                "source_file": car["file"],
                "triangles": result_json["final_tris"],
                "dimensions": {
                    "width_x": result_json["dim_x"],
                    "depth_y": result_json["dim_y"],
                    "height_z": result_json["dim_z"]
                },
                "placement_reasoning": f"Authentic placement of {name} in {car['district']} ({car['location_key']}). Clean ground alignment with box collision."
            }
        }
        placements_data["assets"].append(new_entry)
        processed_count += 1
        
    # Save placements json
    with open(placements_db_path, "w", encoding="utf-8") as f:
        json.dump(placements_data, f, indent=2)
    print(f"\nUpdated {placements_db_path} with {len(placements_data['assets'])} total placements.")
    
    # Update ASSET_LICENSES.md
    licenses_path = os.path.join(PROJECT_ROOT, "ASSET_LICENSES.md")
    with open(licenses_path, "a", encoding="utf-8") as f:
        f.write("\n\n## Batch Vehicle Collection (26 Vehicles)\n")
        f.write("- **Origin:** Local WhatsApp Inbox 3D Vehicle Collection\n")
        f.write("- **Processing:** Headless Blender 5.2.3 optimization, ground origin alignment, light/camera purging, triangle decimation to <= 50,000 for mobile/M1 budgets.\n")
        for car in CARS_CONFIG:
            f.write(f"- `{car['slug']}`: {car['name']} ({car['file']}) -> `{car['district']}`\n")
            
    print(f"Updated {licenses_path}")
    print(f"\nSummary: Successfully processed {processed_count} vehicles, {failed_count} failed.")

if __name__ == "__main__":
    main()
