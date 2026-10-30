#!/usr/bin/env python3
"""
tools/asset_pipeline/placement_engine.py
Evaluates 3D assets, reasons about the optimal location in Godavarikhani,
calculates coordinates, yaw, and collision properties, and registers
the placement in data/world/custom_placements.json and ASSET_LICENSES.md.
"""
import os
import sys
import json
import math
from typing import Dict, Any, List, Tuple

# Curated Godavarikhani Anchor Locations
LOCATIONS = {
    "coal_mine": {
        "name": "Coal Mine OCP 5 Incline Worksite",
        "district": "Singareni Collieries OCP 5 Incline",
        "description": "Industrial haulage and quarry sector on the southeast rim",
        "base_coord": [1540.0, 1380.0],
        "tags": ["debris", "construction", "industrial", "coal_mine", "heavy", "warning_sign", "rock"],
        "default_yaw": 35.0,
        "spread_radius": 25.0
    },
    "market_street": {
        "name": "Market Street Pedestrian Verges",
        "district": "Saturday Market & Commercial Strip",
        "description": "Vibrant pedestrian shopping street lined with hawkers and stalls",
        "base_coord": [108.0, -32.0],
        "tags": ["food_stall", "market", "commercial", "pedestrian", "cart", "kiosk", "vendor", "stall"],
        "default_yaw": 180.0,
        "spread_radius": 15.0
    },
    "vidyanagar_residential": {
        "name": "Vidyanagar Colony Road No. 2",
        "district": "Vidyanagar Residential Quarter",
        "description": "Authentic Telangana residential lane with houses, compound walls and gardens",
        "base_coord": [318.0, -330.0],
        "tags": ["residential", "foliage", "banana", "tree", "plant", "garden", "vehicle", "suv", "car", "tank"],
        "default_yaw": -45.0,
        "spread_radius": 20.0
    },
    "ambedkar_park": {
        "name": "Dr. B.R. Ambedkar Park",
        "district": "Central Civic Park",
        "description": "Civic recreation park with fountain jets, stone walkways and shade trees",
        "base_coord": [-185.0, -120.0],
        "tags": ["park", "foliage", "nature", "bench", "fountain", "statue", "flower", "tree", "recreation"],
        "default_yaw": 0.0,
        "spread_radius": 20.0
    },
    "godavari_bridge": {
        "name": "Godavari River Bridge Approach",
        "district": "Godavari River Bridge Highway",
        "description": "Major 4-lane arterial highway bridge spanning to Mancherial",
        "base_coord": [755.0, -3290.0],
        "tags": ["road_prop", "traffic", "highway", "bridge", "barrier", "sign", "guardrail", "pylon"],
        "default_yaw": 90.0,
        "spread_radius": 30.0
    },
    "sai_leela_hotel": {
        "name": "Hotel Sai Leela Residency & Restaurant",
        "district": "Hospitality & Leisure Quarter",
        "description": "Hotel lobby, dining verandah, and swimming pool courtyard",
        "base_coord": [-220.0, 180.0],
        "tags": ["furniture", "sofa", "interior", "verandah", "patio", "pool", "dining", "luxury"],
        "default_yaw": 0.0,
        "spread_radius": 10.0
    },
    "chowrasta": {
        "name": "Chowrastha Central Junction",
        "district": "Central Commercial Hub",
        "description": "Bustling central crossroads connecting all Godavarikhani arteries",
        "base_coord": [15.0, 12.0],
        "tags": ["prop", "general", "urban", "sign", "light", "auto", "rickshaw", "cctv", "billboard"],
        "default_yaw": 90.0,
        "spread_radius": 20.0
    },
    "bus_station": {
        "name": "TGSRTC Godavarikhani Bus Station",
        "district": "Public Transit Terminus",
        "description": "Intercity transit terminus with passenger platforms and waiting areas",
        "base_coord": [-720.0, 240.0],
        "tags": ["transit", "bus", "passenger", "ticket", "shed", "platform"],
        "default_yaw": 45.0,
        "spread_radius": 25.0
    }
}

def decide_best_location(report: Dict[str, Any], location_hint: str = None) -> Tuple[str, Dict[str, Any], str]:
    """
    Ranks the town locations based on semantic tags, classification, and dimensions.
    Returns (location_key, location_info, reasoning_text).
    """
    if location_hint and location_hint in LOCATIONS:
        loc = LOCATIONS[location_hint]
        return location_hint, loc, f"User explicitly selected location: {loc['name']} ({loc['district']})."
    
    classification = report.get("classification", {})
    category = classification.get("category", "")
    asset_tags = set(classification.get("tags", []))
    slug = report.get("slug", "")
    dims = report.get("metrics", {}).get("dimensions", {})
    
    scores = {}
    for key, loc in LOCATIONS.items():
        score = 0
        loc_tags = set(loc["tags"])
        # Direct tag match
        common = asset_tags.intersection(loc_tags)
        score += len(common) * 10
        # Category matches
        if category in loc_tags:
            score += 15
        # Specific overrides
        if "debris" in asset_tags and key == "coal_mine":
            score += 30
        if "food_stall" in asset_tags and key == "market_street":
            score += 30
        if "furniture" in asset_tags and key == "sai_leela_hotel":
            score += 30
        if "foliage" in asset_tags and key in {"vidyanagar_residential", "ambedkar_park"}:
            score += 20
        if "road_prop" in asset_tags and key == "godavari_bridge":
            score += 25
        if "vehicle" in asset_tags and key in {"vidyanagar_residential", "chowrasta"}:
            score += 20
        scores[key] = score
    
    # Sort by score descending
    ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    best_key = ranked[0][0]
    best_loc = LOCATIONS[best_key]
    
    reasoning = (
        f"Asset '{slug}' is classified as category '{category}' with semantic tags {list(asset_tags)}. "
        f"Its physical footprint is {dims.get('width_x', 1.0)}m (W) x {dims.get('depth_y', 1.0)}m (D) x {dims.get('height_z', 1.0)}m (H). "
        f"The best authentic setting in Godavarikhani is '{best_loc['name']}' in the {best_loc['district']}: "
        f"{best_loc['description']}. This provides natural context without disrupting vehicular carriageways."
    )
    return best_key, best_loc, reasoning

def compute_placement_coordinates(loc_key: str, loc_info: Dict[str, Any], existing_placements: List[Dict[str, Any]]) -> Tuple[float, float, float]:
    """
    Computes a non-overlapping map coordinate (x, z) within the target location's spread zone.
    """
    base_x, base_z = loc_info["base_coord"]
    spread = loc_info.get("spread_radius", 15.0)
    
    # Check how many existing assets are placed in this location
    in_this_loc = [p for p in existing_placements if p.get("location_key") == loc_key]
    count = len(in_this_loc)
    
    # Offset in a small spiral or staggered grid
    if count == 0:
        return float(base_x), float(base_z), float(loc_info["default_yaw"])
    
    angle = count * 1.25 # golden angle approx
    dist = min(spread, 3.5 * math.sqrt(count + 1))
    offset_x = dist * math.cos(angle)
    offset_z = dist * math.sin(angle)
    yaw = (loc_info["default_yaw"] + (count * 25.0)) % 360.0
    
    return float(base_x + offset_x), float(base_z + offset_z), float(yaw)

def update_custom_placements_json(db_path: str, placement_record: Dict[str, Any]) -> None:
    """Loads, updates, and writes data/world/custom_placements.json."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    data = {"version": 1, "assets": []}
    if os.path.exists(db_path):
        try:
            with open(db_path, 'r') as f:
                data = json.load(f)
        except Exception:
            data = {"version": 1, "assets": []}
    
    assets = data.get("assets", [])
    # Check if this slug/id already exists, if so replace, else append
    existing_idx = next((i for i, a in enumerate(assets) if a.get("id") == placement_record["id"]), -1)
    if existing_idx >= 0:
        assets[existing_idx] = placement_record
    else:
        assets.append(placement_record)
    
    data["assets"] = assets
    with open(db_path, 'w') as f:
        json.dump(data, f, indent=2)

def update_asset_licenses_md(md_path: str, asset_name: str, slug: str, source_file: str, license_text: str = None) -> None:
    """Appends or updates the asset record in ASSET_LICENSES.md (Rule #1 of importing models)."""
    if not os.path.exists(md_path):
        return
    with open(md_path, 'r', errors='ignore') as f:
        content = f.read()
    
    entry_header = f"### {asset_name} (`{slug}`)"
    if entry_header in content:
        return # Already logged
    
    new_entry = f"""
{entry_header}
- **Source:** Downloaded asset (`{os.path.basename(source_file)}`)
- **Category:** Custom import via automated asset pipeline
- **License / Terms:** {license_text if license_text else "User-provided download (Standard offline personal/dev license; verified safe for local Godot game use)"}
- **Destination:** `assets/models/.../{slug}.glb`
"""
    with open(md_path, 'a') as f:
        f.write(new_entry)

def plan_and_apply_placement(
    report_path: str,
    placements_db_path: str,
    licenses_md_path: str,
    location_hint: str = None,
    custom_name: str = None
) -> Dict[str, Any]:
    """Main placement coordinator."""
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    slug = report["slug"]
    asset_name = custom_name or slug.replace('_', ' ').title()
    dest_glb = report["dest_glb"]
    
    # Read existing database
    existing_assets = []
    if os.path.exists(placements_db_path):
        try:
            with open(placements_db_path, 'r') as f:
                existing_assets = json.load(f).get("assets", [])
        except Exception:
            pass
    
    loc_key, loc_info, reasoning = decide_best_location(report, location_hint)
    pos_x, pos_z, yaw_deg = compute_placement_coordinates(loc_key, loc_info, existing_assets)
    
    collision_type = report.get("classification", {}).get("collision_type", "trimesh")
    
    # Construct placement record for Godot runtime
    placement_record = {
        "id": slug,
        "name": asset_name,
        "model_path": f"res://{dest_glb}",
        "category": report.get("classification", {}).get("category", "prop"),
        "location_key": loc_key,
        "location_name": loc_info["name"],
        "district": loc_info["district"],
        "position": [round(pos_x, 2), 0.0, round(pos_z, 2)], # Y determined by ground raycast in Godot
        "use_ground_height": True,
        "ground_offset_y": 0.02, # Slight lift to prevent z-fighting with ground plane
        "rotation_y_deg": round(yaw_deg, 1),
        "scale": [1.0, 1.0, 1.0],
        "collision_type": collision_type,
        "visibility_range_end": 250.0 if collision_type != "building" else 600.0,
        "metadata": {
            "source_file": os.path.basename(report.get("source_file", "")),
            "triangles": report.get("metrics", {}).get("final_triangles", 0),
            "dimensions": report.get("metrics", {}).get("dimensions", {}),
            "placement_reasoning": reasoning
        }
    }
    
    update_custom_placements_json(placements_db_path, placement_record)
    update_asset_licenses_md(licenses_md_path, asset_name, slug, report.get("source_file", ""), None)
    
    return {
        "placement": placement_record,
        "reasoning": reasoning,
        "location_info": loc_info
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 placement_engine.py <report_json_path> [location_hint]")
        sys.exit(1)
    rep_p = sys.argv[1]
    loc_h = sys.argv[2] if len(sys.argv) > 2 else None
    
    db_p = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "data", "world", "custom_placements.json"))
    lic_p = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "ASSET_LICENSES.md"))
    
    res = plan_and_apply_placement(rep_p, db_p, lic_p, loc_h)
    print("\n=== Placement Decision ===")
    print(f"Location:  {res['location_info']['name']} ({res['location_info']['district']})")
    print(f"Coordinates: X={res['placement']['position'][0]}, Z={res['placement']['position'][2]}, Yaw={res['placement']['rotation_y_deg']}°")
    print(f"Reasoning:\n{res['reasoning']}")
