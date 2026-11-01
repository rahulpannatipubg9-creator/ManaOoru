#!/usr/bin/env python3
"""Ingest and geolocate Godavarikhani survey batch 030-135.

Maps 106 commercial and institutional establishments across 6 distinct corridors:
1. Chowrasta to New Ashok Theatre
2. Chowrasta to Rajesh Theatre
3. Rajesh Theatre to Markandeya Colony
4. Addaguntapalli Chowrastha
5. Medhari Basthi & Onion Bazar
6. Chowrasta to Daily Market & 1 Town Police Station

Projects to Godot coordinates, updates data/survey/godavarikhani_survey_catalog.json,
and syncs into data/local/user_shop_labels.json.
"""

import csv
import json
import math
from pathlib import Path

# GeoProjection standards from scripts/map/geo_projection.gd
ORIGIN_LON = 79.513352
ORIGIN_LAT = 18.751925
METERS_PER_DEGREE_LAT = 111000.0

def lon_lat_to_godot(lon: float, lat: float) -> tuple[float, float]:
    meters_lon = METERS_PER_DEGREE_LAT * math.cos(math.radians(ORIGIN_LAT))
    x = (lon - ORIGIN_LON) * meters_lon
    z = -(lat - ORIGIN_LAT) * METERS_PER_DEGREE_LAT
    return round(x, 2), round(z, 2)

CATEGORY_KIND_MAP = {
    "bakery": "bakery",
    "cinema": "theatre",
    "grocery": "supermarket",
    "super market": "supermarket",
    "xerox": "copyshop",
    "pharmacy": "chemist",
    "tailoring": "tailor",
    "meat": "butcher",
    "auto services": "car_repair",
    "furniture": "furniture",
    "restaurant": "restaurant",
    "clothing": "clothes",
    "batteries": "electronics",
    "electronics": "electronics",
    "sweets": "confectionery",
    "landmark": "monument",
    "printing": "copyshop",
    "salon": "hairdresser",
    "beauty parlour": "beauty",
    "optician": "optician",
    "diagnostic center": "health_centre",
    "hospital": "hospital",
    "computer repair": "electronics",
    "books and stationery": "books",
    "photography": "photo",
    "tiles and sanitaryware": "hardware",
    "fruit wholesale": "greengrocer",
    "vegetables": "greengrocer",
    "hardware": "hardware",
    "electrical": "electronics",
    "market": "marketplace",
    "police station": "police",
    "pan shop": "kiosk",
    "tyres": "tyres",
    "courier": "post_office"
}

def get_kind(category: str) -> str:
    cat_lower = category.strip().lower()
    for k, v in CATEGORY_KIND_MAP.items():
        if k in cat_lower:
            return v
    return "shop"

def process_batch():
    tsv_path = Path("data/survey/survey_batch_030_135.tsv")
    with open(tsv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        rows = list(reader)

    print(f"Loaded {len(rows)} shops from {tsv_path}")

    # Corridor interpolations
    # 1. Chowrasta_to_New_Ashok_Theatre (15 shops: 030-044)
    # Start: near Chowrastha / Shivaji Nagar entry (18.75185, 79.51325)
    # End: New Ashok Theatre / Singareni Super Market (18.75415, 79.51555)
    c1_shops = [r for r in rows if "Chowrasta_to_New_Ashok_Theatre" in r["notes"]]
    for i, r in enumerate(c1_shops):
        if not r["latitude"]:
            # Interpolate along New Ashok Theater Road
            t = (i + 1) / (len(c1_shops) + 1)
            # Slight S-curve curve along road
            lat = 18.75185 + t * (18.75415 - 18.75185) + 0.00015 * math.sin(t * math.pi)
            lon = 79.51325 + t * (79.51555 - 79.51325)
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_new_ashok_rd"

    # 2. Chowrasta_to_Rajesh_Theatre_candidate (18 shops: 045-062)
    # 045-051: Rajesh Theatre / Gemini Hospital / Bus Stand Colony junction
    # 052-058: Laxmi Nagar Road from Chowrastha west to Old Ashok Circle
    # 059-062: Old Ashok Theatre Circle
    c2_shops = [r for r in rows if "Chowrasta_to_Rajesh_Theatre_candidate" in r["notes"]]
    for i, r in enumerate(c2_shops):
        sid = r["shop_id"]
        if not r["latitude"]:
            idx = int(sid.split("-")[-1])
            if 45 <= idx <= 51:
                # Rajesh Theatre cluster (lat: 18.7548 to 18.7554, lon: 79.5058 to 79.5068)
                t = (idx - 45) / 7.0
                lat = 18.75480 + t * 0.00060 + (0.00010 if idx % 2 == 0 else -0.00010)
                lon = 79.50660 - t * 0.00080
            elif 52 <= idx <= 58:
                # Laxmi Nagar Road (lat: 18.75128 to 18.75095, lon: 79.51260 to 79.51115)
                t = (idx - 52) / 7.0
                lat = 18.75128 - t * 0.00033
                lon = 79.51255 - t * 0.00140
            else: # 062 Saptha Varnam Ads
                lat = 18.75108
                lon = 79.51085
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_rajesh_theatre_axis"

    # 3. Rajesh_Theatre_to_Markandeya_Colony (28 shops: 063-090)
    # Clustered in Markandeya Colony commercial center (lat: 18.7545 to 18.7570, lon: 79.5042 to 79.5068)
    c3_shops = [r for r in rows if "Rajesh_Theatre_to_Markandeya_Colony" in r["notes"]]
    for i, r in enumerate(c3_shops):
        sid = r["shop_id"]
        if not r["latitude"]:
            idx = int(sid.split("-")[-1])
            t = (idx - 63) / 28.0
            # Distribute along Markandeya Colony spine and side streets
            lat = 18.75460 + t * 0.00220 + (0.00020 if idx % 3 == 0 else (-0.00015 if idx % 3 == 1 else 0.00005))
            lon = 79.50430 + (t * 0.00220) + (0.00030 if idx % 2 == 0 else -0.00020)
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_markandeya_colony"

    # 4. Addaguntapalli (6 shops: 091-096)
    # Near AMULYA MEDICAL STORE (18.74763750, 79.50954687)
    c4_shops = [r for r in rows if "Addaguntapalli" in r["notes"]]
    for i, r in enumerate(c4_shops):
        sid = r["shop_id"]
        if not r["latitude"]:
            idx = int(sid.split("-")[-1])
            t = (idx - 91) / 5.0
            lat = 18.74730 + t * 0.00060
            lon = 79.50920 + (0.00040 if idx % 2 == 0 else -0.00030)
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_addaguntapalli"

    # 5. Medhari_Basthi_and_Onion_Bazar (23 shops: 097-119)
    # Along Medhari Basthi Rd / Onion Bazar (lat: 18.7465 to 18.7482, lon: 79.5110 to 79.5152)
    c5_shops = [r for r in rows if "Medhari_Basthi_and_Onion_Bazar" in r["notes"]]
    for i, r in enumerate(c5_shops):
        sid = r["shop_id"]
        if not r["latitude"]:
            idx = int(sid.split("-")[-1])
            t = (idx - 97) / 23.0
            lat = 18.74780 - t * 0.00110 + (0.00015 if idx % 2 == 0 else -0.00015)
            lon = 79.51120 + t * 0.00380
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_medhari_basthi"

    # 6. Chowrasta_to_Market_and_1_Town_PS_candidate (16 shops: 120-135)
    # Clustered near Daily Market, 1 Town Police Station, Jawahar Nagar / Ram Nagar
    # (lat: 18.7480 to 18.7505, lon: 79.5145 to 79.5165)
    c6_shops = [r for r in rows if "Chowrasta_to_Market_and_1_Town_PS_candidate" in r["notes"]]
    for i, r in enumerate(c6_shops):
        sid = r["shop_id"]
        if not r["latitude"]:
            idx = int(sid.split("-")[-1])
            t = (idx - 120) / 16.0
            lat = 18.74980 - t * 0.00160 + (0.00012 if idx % 2 == 0 else -0.00012)
            lon = 79.51480 + t * 0.00160
            r["latitude"] = f"{lat:.8f}"
            r["longitude"] = f"{lon:.8f}"
            gx, gz = lon_lat_to_godot(lon, lat)
            r["godot_x_m"] = f"{gx:.2f}"
            r["godot_z_m"] = f"{gz:.2f}"
            r["gps_basis"] = "corridor_interpolated_daily_market_1town"

    # Recalculate Godot coordinates for all rows
    for r in rows:
        lat = float(r["latitude"])
        lon = float(r["longitude"])
        gx, gz = lon_lat_to_godot(lon, lat)
        r["godot_x_m"] = f"{gx:.2f}"
        r["godot_z_m"] = f"{gz:.2f}"
        r["kind"] = get_kind(r["category"])

    # Update user_shop_labels.json
    labels_path = Path("data/local/user_shop_labels.json")
    labels_data = {"shops": []}
    if labels_path.exists():
        try:
            labels_data = json.loads(labels_path.read_text(encoding="utf-8"))
        except Exception as e:
            print("Error reading user_shop_labels.json:", e)

    existing_ids = {s.get("shop_id") for s in labels_data["shops"] if s.get("shop_id")}
    existing_names = {s.get("name", "").strip().lower() for s in labels_data["shops"]}

    added_count = 0
    for r in rows:
        sid = r["shop_id"]
        name = r["name"].strip()
        if sid in existing_ids:
            continue
        
        route = ""
        for part in r["notes"].split(";"):
            if part.startswith("route="):
                route = part.split("=")[1]

        entry = {
            "shop_id": sid,
            "name": name,
            "category": r["category"],
            "address": r["address"],
            "lat": float(r["latitude"]),
            "lon": float(r["longitude"]),
            "kind": r["kind"],
            "placement_status": r.get("placement_status", "provisional_corridor_surveyed"),
            "source": r.get("source_url", "Field survey catalog batch 030-135"),
            "source_place_id": r.get("source_place_id", ""),
            "notes": r.get("notes", ""),
            "zone": route
        }
        labels_data["shops"].append(entry)
        existing_ids.add(sid)
        existing_names.add(name.lower())
        added_count += 1

    labels_path.write_text(json.dumps(labels_data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Updated {labels_path}: added {added_count} shops (total now {len(labels_data['shops'])})")

    # Update data/survey/godavarikhani_survey_catalog.json
    catalog_path = Path("data/survey/godavarikhani_survey_catalog.json")
    if catalog_path.exists():
        try:
            catalog_data = json.loads(catalog_path.read_text(encoding="utf-8"))
            cat_shop_ids = {s.get("shop_id") for s in catalog_data.get("shops", []) if s.get("shop_id")}
            for r in rows:
                if r["shop_id"] not in cat_shop_ids:
                    route = ""
                    for part in r["notes"].split(";"):
                        if part.startswith("route="):
                            route = part.split("=")[1]
                    catalog_data["shops"].append({
                        "shop_id": r["shop_id"],
                        "zone": route,
                        "name": r["name"],
                        "category": r["category"],
                        "address": r["address"],
                        "latitude": float(r["latitude"]),
                        "longitude": float(r["longitude"]),
                        "coordinate_quality": r.get("gps_basis", "corridor_interpolated"),
                        "plus_code": r.get("full_plus_code", ""),
                        "approximate_distance_m": float(r["approximate_distance_m_from_temple"]) if r["approximate_distance_m_from_temple"] else None,
                        "within_100m_verified": "no",
                        "import_ready": "yes",
                        "listing_status": r.get("listing_status", "online_listed_unverified"),
                        "requires_field_survey": r.get("requires_field_survey", "true"),
                        "source_url": r.get("source_url", ""),
                        "google_place_id": r.get("source_place_id", ""),
                        "notes": r.get("notes", ""),
                        "godot_coord": [float(r["godot_x_m"]), float(r["godot_z_m"])],
                        "playable_radius_ok": True
                    })
                    cat_shop_ids.add(r["shop_id"])
            catalog_data["metadata"]["total_shops"] = len(catalog_data["shops"])
            catalog_path.write_text(json.dumps(catalog_data, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"Updated {catalog_path} (total catalog shops now {len(catalog_data['shops'])})")
        except Exception as e:
            print("Error updating survey catalog:", e)

    # Also save back enriched TSV
    with open(tsv_path, "w", encoding="utf-8", newline="") as f:
        fieldnames = [
            "shop_id", "name", "category", "address", "approximate_distance_m_from_temple",
            "latitude", "longitude", "godot_x_m", "godot_z_m", "gps_basis", "full_plus_code",
            "placement_status", "listing_status", "is_individual_shop", "requires_field_survey",
            "source_url", "source_place_id", "notes"
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for r in rows:
            row_dict = {k: r.get(k, "") for k in fieldnames}
            writer.writerow(row_dict)
    print(f"Saved enriched TSV to {tsv_path}")

if __name__ == "__main__":
    process_batch()
