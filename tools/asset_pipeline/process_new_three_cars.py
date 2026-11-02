#!/usr/bin/env python3
"""
tools/asset_pipeline/process_new_three_cars.py
Processes the 3 newly downloaded Ford vehicles using headless Blender:
1. Ford Mustang Mach 40 (Mach_40.obj) -> target length 4.65m -> Godavari Bridge
2. Ford F-150 Lightning (Ford F-150 Lightning.FBX) -> target length 5.8m -> Hotel Sai Leela
3. Ford F150 Raptor 2021 (Ford F150 Raptor 2021.FBX) -> target length 5.9m -> Coal Mine OCP 5

Rules:
- Strip lights and cameras.
- Normalize scale to meters, center (0,0), ground Z=0.
- Triangle decimation to <= 50,000 triangles for Apple M1 & mobile budget.
- Export clean GLB to assets/models/vehicles/<slug>/<slug>.glb.
- Update data/world/custom_placements.json and ASSET_LICENSES.md.
"""
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER_BIN = "/opt/homebrew/bin/blender"

NEW_CARS = [
    {
        "slug": "ford_mustang_mach_40",
        "name": "Ford Mustang Mach 40 Custom",
        "file_path": "/Users/rahulpannati/WhatsApp Inbox Screens/new_three_cars_extracted/ford_mustang_mach_40/Ford Mustang Mach 40/Mach_40.obj",
        "target_len": 4.65,
        "location_key": "godavari_bridge",
        "district": "Godavari River Bridge Highway",
        "pos": [755.0, 0.0, -3270.0],
        "yaw": 90.0,
        "desc": "Custom classic muscle sports car stationed on the Godavari Bridge approach."
    },
    {
        "slug": "ford_f150_lightning",
        "name": "Ford F-150 Lightning Electric",
        "file_path": "/Users/rahulpannati/WhatsApp Inbox Screens/new_three_cars_extracted/ford_f150_lightning/4067226.6238063a5c1fb/Ford F-150 Lightning.FBX",
        "target_len": 5.80,
        "location_key": "sai_leela_hotel",
        "district": "Hotel Sai Leela Courtyard",
        "pos": [-235.0, 0.0, 185.0],
        "yaw": 180.0,
        "desc": "Modern electric full-size pickup parked in Hotel Sai Leela guest courtyard."
    },
    {
        "slug": "ford_f150_raptor_2021",
        "name": "2021 Ford F-150 Raptor SuperCrew",
        "file_path": "/Users/rahulpannati/WhatsApp Inbox Screens/new_three_cars_extracted/ford_f150_raptor_2021/3869978.61c40747111f0/Ford F150 Raptor 2021.FBX",
        "target_len": 5.90,
        "location_key": "coal_mine",
        "district": "Singareni Collieries OCP 5 Incline",
        "pos": [1560.0, 0.0, 1395.0],
        "yaw": 35.0,
        "desc": "Heavy-duty off-road pickup deployed at the Singareni Collieries OCP 5 mining worksite."
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
    print("   MANA OORU - NEW 3 FORD CARS BATCH PROCESSOR   ")
    print("=" * 70)
    
    worker_script_path = "/tmp/mana_ooru_blender_new_cars.py"
    with open(worker_script_path, "w", encoding="utf-8") as f:
        f.write(BLENDER_SCRIPT)
        
    placements_db_path = os.path.join(PROJECT_ROOT, "data", "world", "custom_placements.json")
    if os.path.exists(placements_db_path):
        with open(placements_db_path, "r", encoding="utf-8") as f:
            placements_data = json.load(f)
    else:
        placements_data = {"version": 1, "assets": []}
        
    for car in NEW_CARS:
        slug = car["slug"]
        name = car["name"]
        print(f"\nProcessing {name} ({slug})...")
        
        dest_glb = os.path.join(PROJECT_ROOT, "assets", "models", "vehicles", slug, f"{slug}.glb")
        
        cmd = [
            BLENDER_BIN,
            "-b",
            "--factory-startup",
            "--python", worker_script_path,
            "--",
            "--input", car["file_path"],
            "--dest", dest_glb,
            "--max-tris", "50000",
            "--target-len", str(car["target_len"]),
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
                "source_file": os.path.basename(car["file_path"]),
                "triangles": result_json["final_tris"],
                "dimensions": {
                    "width_x": result_json["dim_x"],
                    "depth_y": result_json["dim_y"],
                    "height_z": result_json["dim_z"]
                },
                "placement_reasoning": car["desc"]
            }
        }
        placements_data["assets"].append(new_entry)
        
    with open(placements_db_path, "w", encoding="utf-8") as f:
        json.dump(placements_data, f, indent=2)
    print(f"\nUpdated {placements_db_path} (Total assets: {len(placements_data['assets'])})")
    
    # Update ASSET_LICENSES.md
    licenses_path = os.path.join(PROJECT_ROOT, "ASSET_LICENSES.md")
    with open(licenses_path, "a", encoding="utf-8") as f:
        f.write("\n\n## Newly Downloaded Vehicle Collection (3 Ford Vehicles)\n")
        f.write("- **Origin:** Local WhatsApp Inbox Downloads (RAR archives)\n")
        f.write("- **Processing:** Headless Blender 5.2.3 optimization, ground origin alignment, light/camera purging, triangle decimation to <= 50,000 for mobile/M1 budgets.\n")
        for car in NEW_CARS:
            f.write(f"- `{car['slug']}`: {car['name']} ({os.path.basename(car['file_path'])}) -> `{car['district']}`\n")
            
    print(f"Updated {licenses_path}")

if __name__ == "__main__":
    main()

