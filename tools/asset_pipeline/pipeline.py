#!/usr/bin/env python3
"""
tools/asset_pipeline/pipeline.py
The Complete 3D Asset Import & Placement Pipeline for ManaOoru.

Workflow:
1. Scans ~/Downloads (or a specified file/archive) and stages the asset.
2. Tests, cleans, normalizes, and optimizes the model in Blender (headless).
3. Strips cameras and lights (preventing scene washout).
4. Reasons about the optimal placement in Godavarikhani based on semantic tags and dimensions.
5. Updates data/world/custom_placements.json and ASSET_LICENSES.md.
6. Invokes Godot to import the asset and verifies placement via headless regression test.

Usage:
  python3 tools/asset_pipeline/pipeline.py [--input <path_or_filename>] [--location <district_key>]
"""
import os
import sys
import json
import argparse
import subprocess
from typing import Dict, Any

from scanner import scan_asset
from placement_engine import plan_and_apply_placement

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER_PATH = "/opt/homebrew/bin/blender"
GODOT_PATH = "godot"

def run_blender_processor(
    model_path: str,
    slug: str,
    category: str,
    auto_decimate: bool = True,
    max_tris: int = 0
) -> Dict[str, Any]:
    """Runs Blender processor script headlessly to clean, test, and export GLB."""
    dest_dir = os.path.join(PROJECT_ROOT, "assets", "models", category)
    os.makedirs(dest_dir, exist_ok=True)
    dest_glb = os.path.join(dest_dir, f"{slug}.glb")
    report_json = os.path.join(PROJECT_ROOT, "outputs", "asset_reports", f"{slug}_report.json")
    
    processor_script = os.path.join(os.path.dirname(__file__), "blender_processor.py")
    cmd = [
        BLENDER_PATH,
        "-b",
        "--factory-startup",
        "--disable-autoexec",
        "--python", processor_script,
        "--",
        "--input", model_path,
        "--slug", slug,
        "--dest-glb", os.path.relpath(dest_glb, PROJECT_ROOT),
        "--report-json", report_json,
    ]
    if auto_decimate:
        cmd.append("--auto-decimate")
    if max_tris > 0:
        cmd.extend(["--max-tris", str(max_tris)])
    
    print(f"\n--- Running Blender Validation & Export ---")
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        print("Blender processing failed:\n" + proc.stderr)
        raise RuntimeError(f"Blender failed with returncode {proc.returncode}")
    
    if not os.path.exists(report_json):
        raise FileNotFoundError(f"Blender did not generate expected report at {report_json}")
    
    with open(report_json, 'r') as f:
        report = json.load(f)
    return report

def run_godot_import():
    """Runs Godot headless import to generate .import file for the new GLB."""
    print("\n--- Registering Asset with Godot Engine ---")
    proc = subprocess.run([GODOT_PATH, "--headless", "--import"], cwd=PROJECT_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        print("Godot import warning/notice:\n" + proc.stdout[:500])

def run_godot_verification():
    """Runs headless verification test to prove asset spawned and grounded cleanly."""
    print("\n--- Verifying In-Game World Placement ---")
    test_script = "tests/test_custom_asset_placements.gd"
    proc = subprocess.run([GODOT_PATH, "--headless", "--path", ".", "--script", test_script], cwd=PROJECT_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        print("Godot verification failed:\n" + proc.stdout)
        raise RuntimeError("In-game placement verification failed.")
    print("In-Game Verification Passed: Asset is placed, grounded, collidable, and visible!")

def run_pipeline(
    input_target: str = None,
    location_hint: str = None,
    name_override: str = None,
    auto_decimate: bool = True,
    max_tris: int = 0
) -> Dict[str, Any]:
    print("======================================================================")
    print("         MANA OORU 3D ASSET IMPORT & SMART PLACEMENT PIPELINE         ")
    print("======================================================================")
    
    # Step 1: Scan & Stage
    print(f"Step 1: Scanning for downloaded 3D assets...")
    scan_info = scan_asset(input_target)
    slug = scan_info["slug"]
    print(f"  * Detected Asset:   {scan_info['asset_name']} ({slug})")
    print(f"  * Source File:      {scan_info['source_path']}")
    print(f"  * Model File:       {scan_info['primary_model_path']}")
    print(f"  * Is Archive:       {scan_info['is_archive']}")
    
    # Step 2: Blender Diagnostics, Cleaning & GLB Export
    # Preliminary category prediction from name
    prelim_category = "debris" if any(k in slug for k in ["brick", "debris", "stone"]) else (
        "foliage" if any(k in slug for k in ["tree", "plant", "palm", "banana"]) else (
            "vehicles" if any(k in slug for k in ["car", "suv", "auto", "bike", "truck"]) else (
                "market_street" if any(k in slug for k in ["stall", "cart", "chai", "tea"]) else (
                    "furniture" if any(k in slug for k in ["sofa", "chair", "table"]) else (
                        "city_props/road" if any(k in slug for k in ["barrier", "sign", "pylon"]) else "city_props"
                    )
                )
            )
        )
    )
    
    print(f"\nStep 2: Testing & Processing in Blender...")
    report = run_blender_processor(
        model_path=scan_info["primary_model_path"],
        slug=slug,
        category=prelim_category,
        auto_decimate=auto_decimate,
        max_tris=max_tris
    )
    
    dims = report["metrics"]["dimensions"]
    print(f"  * Dimensions:       {dims['width_x']}m (W) x {dims['depth_y']}m (D) x {dims['height_z']}m (H)")
    print(f"  * Triangle Count:   {report['metrics']['initial_triangles']} -> {report['metrics']['final_triangles']}")
    print(f"  * Performance Check:{report['budget']['status']}")
    print(f"  * Purged Cameras/Lamps: {report['metrics']['purged_lights_or_cameras']}")
    print(f"  * Clean GLB Export: {report['dest_glb']}")
    
    # Step 3: Smart World Placement Decision
    print(f"\nStep 3: Reasoning About Optimal Placement in Godavarikhani...")
    db_path = os.path.join(PROJECT_ROOT, "data", "world", "custom_placements.json")
    licenses_path = os.path.join(PROJECT_ROOT, "ASSET_LICENSES.md")
    
    placement_result = plan_and_apply_placement(
        report_path=os.path.join(PROJECT_ROOT, "outputs", "asset_reports", f"{slug}_report.json"),
        placements_db_path=db_path,
        licenses_md_path=licenses_path,
        location_hint=location_hint,
        custom_name=name_override or scan_info["asset_name"]
    )
    
    p = placement_result["placement"]
    print(f"  * Target District:  {p['district']}")
    print(f"  * Target Location:  {p['location_name']}")
    print(f"  * Coordinates:      Map X={p['position'][0]}, Z={p['position'][2]}")
    print(f"  * Orientation:      Yaw={p['rotation_y_deg']}°")
    print(f"  * Collision:        {p['collision_type']}")
    print(f"  * Visibility Range: {p['visibility_range_end']}m")
    print(f"\nPlacement Reasoning:\n  \"{placement_result['reasoning']}\"")
    
    # Step 4: Godot Import
    run_godot_import()
    
    # Step 5: In-game Verification
    run_godot_verification()
    
    print("\n======================================================================")
    print("                     PIPELINE COMPLETED SUCCESSFULLY!                 ")
    print(f"Asset '{scan_info['asset_name']}' is now live in ManaOoru at {p['location_name']}.")
    print("======================================================================")
    
    return {
        "scan": scan_info,
        "blender": report,
        "placement": placement_result
    }

def main():
    parser = argparse.ArgumentParser(description="ManaOoru 3D Asset Import & Placement Pipeline")
    parser.add_argument("--input", "-i", default=None, help="File path or name in ~/Downloads to process")
    parser.add_argument("--location", "-l", default=None, help="Optional location override key (e.g. market_street, coal_mine, vidyanagar_residential, ambedkar_park, etc.)")
    parser.add_argument("--name", "-n", default=None, help="Optional custom display name for asset")
    parser.add_argument("--no-decimate", action="store_true", help="Disable automatic polygon decimation")
    parser.add_argument("--max-tris", type=int, default=0, help="Explicit max triangle budget")

    args = parser.parse_args()
    run_pipeline(
        input_target=args.input,
        location_hint=args.location,
        name_override=args.name,
        auto_decimate=not args.no_decimate,
        max_tris=args.max_tris
    )

if __name__ == "__main__":
    main()
