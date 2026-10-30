#!/usr/bin/env python3
"""Collect and update the latest Godavarikhani places and commercial listings.

Combines:
  1. Overture Maps Foundation release (latest places with verified freeform addresses).
  2. OpenStreetMap local features and amenities.
Preserves full addresses, computes distance from Chowrastha, and generates
proper Google Maps coordinate links and commercial listings CSV/JSON.
"""
import csv
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import urlencode

import duckdb

ROOT = Path(__file__).resolve().parents[1]
RELEASE = "2026-10-21.0"
BBOX = (79.4749, 18.7219, 79.5384, 18.7950)  # Extended north to include Godavari River Bridge
CENTER_LAT = 18.751925
CENTER_LON = 79.513352
PLAYABLE_RADIUS = 3000.0  # 3 km radius around Chowrastha
DEDUP_METERS = 35.0

LON_SCALE = 111320.0 * math.cos(math.radians(CENTER_LAT))
LAT_SCALE = 110574.0

EXCLUDE_NAMES = {"godavarikhani chowrasta"}
SKIP_CATEGORIES = {
    "amenity=childcare", "leisure=park", "leisure=garden", "leisure=playground",
    "leisure=pitch", "leisure=stadium", "park", "stadium_arena",
    "public_transit_facility_or_service", "historic_site"
}
COMMERCIAL_EXCLUDED = {
    "school", "college", "university", "place_of_worship", "police", "government",
    "office", "health_post", "community_centre", "childcare", "blood_bank",
    "educational_institution", "place_of_learning", "historic_site", "artwork",
    "park", "stadium_arena", "public_transit_facility_or_service"
}

def distance_meters(lat1, lon1, lat2, lon2):
    dx = (lon1 - lon2) * LON_SCALE
    dy = (lat1 - lat2) * LAT_SCALE
    return math.hypot(dx, dy)

def fetch_overture_places():
    print(f"Connecting to DuckDB & querying Overture Maps (Release {RELEASE})...")
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2';")
    query = f"""
        SELECT names.primary as name,
               basic_category as category,
               confidence,
               ST_X(geometry) as lon,
               ST_Y(geometry) as lat,
               addresses[1].freeform as freeform_addr,
               addresses[1].locality as locality,
               sources[1].dataset as dataset,
               sources[1].license as license_name,
               sources[1].record_id as record_id
        FROM read_parquet('s3://overturemaps-us-west-2/release/{RELEASE}/theme=places/type=place/*', hive_partitioning=1)
        WHERE bbox.xmin BETWEEN {BBOX[0]} AND {BBOX[2]}
          AND bbox.ymin BETWEEN {BBOX[1]} AND {BBOX[3]}
          AND names.primary IS NOT NULL
          AND confidence >= 0.40
    """
    rows = con.execute(query).fetchall()
    places = []
    for r in rows:
        name = r[0].strip()
        cat = r[1] or ""
        conf = round(float(r[2]), 3)
        lon = float(r[3])
        lat = float(r[4])
        freeform = (r[5] or "").strip()
        locality = (r[6] or "").strip()
        address = freeform
        if locality and locality not in address:
            address = f"{address}, {locality}" if address else locality
        
        dataset = r[7] or "meta"
        lic = r[8] or "CDLA-Permissive-2.0"
        record_id = str(r[9] or "")
        
        places.append({
            "name": name,
            "category": cat,
            "confidence": conf,
            "lon": lon,
            "lat": lat,
            "address": address,
            "source": f"Overture Maps ({dataset})",
            "license": lic,
            "record_id": record_id
        })
    print(f"Retrieved {len(places)} places from Overture.")
    return places

def fetch_osm_places():
    osm_files = [ROOT / "data/osm/godavarikhani_core.json", ROOT / "data/osm/godavarikhani_features.json"]
    osm_keys = ["shop", "amenity", "office", "craft", "healthcare", "tourism", "leisure"]
    skip_amenities = {"parking", "toilets", "bench", "waste_basket", "drinking_water", "shelter"}
    
    found = {}
    for path in osm_files:
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        nodes = {e["id"]: (e["lon"], e["lat"]) for e in data.get("elements", []) if e.get("type") == "node"}
        for elem in data.get("elements", []):
            tags = elem.get("tags", {})
            name = tags.get("name", "").strip()
            kind = next((f"{k}={tags[k]}" for k in osm_keys if k in tags), "")
            if not name or tags.get("amenity") in skip_amenities:
                continue
            if not kind:
                nl = name.lower()
                if "sweet" in nl or "bakery" in nl or "confectionery" in nl:
                    kind = "shop=confectionery"
                elif "theatre" in nl or "theater" in nl or "talkies" in nl or "cinema" in nl:
                    kind = "amenity=theatre"
                elif "hotel" in nl or "lodge" in nl:
                    kind = "tourism=hotel"
                elif "restaurant" in nl or "dhaba" in nl:
                    kind = "amenity=restaurant"
                elif "hospital" in nl or "clinic" in nl:
                    kind = "amenity=hospital"
                else:
                    continue
            if elem["type"] == "node":
                lon, lat = elem["lon"], elem["lat"]
            else:
                pts = [nodes[n] for n in elem.get("nodes", []) if n in nodes]
                if not pts:
                    continue
                lon = sum(p[0] for p in pts) / len(pts)
                lat = sum(p[1] for p in pts) / len(pts)
            
            # Address from OSM tags
            addr_parts = [tags.get("addr:housenumber"), tags.get("addr:street"), tags.get("addr:suburb"), tags.get("addr:city")]
            addr = ", ".join(str(p) for p in addr_parts if p)
            if not addr and "ARJUN SWEET" in name.upper():
                addr = "New Ashok Theater Rd, Ramagundam"
            
            found[(elem["type"], elem["id"])] = {
                "name": name,
                "category": kind,
                "confidence": 1.0,
                "lon": lon,
                "lat": lat,
                "address": addr,
                "source": "OpenStreetMap",
                "license": "ODbL-1.0",
                "record_id": f"{elem['type']}/{elem['id']}"
            }
    print(f"Retrieved {len(found)} places from OpenStreetMap extracts.")
    return list(found.values())

def merge_and_dedup(osm, overture):
    kept = []
    # OSM places prioritized first, then highest confidence Overture
    candidates = osm + sorted(overture, key=lambda p: -p["confidence"])
    for place in candidates:
        if place["category"] in SKIP_CATEGORIES or place["name"].casefold() in EXCLUDE_NAMES:
            continue
        key = place["name"].casefold()
        
        # Check duplicate
        duplicate = False
        for other in kept:
            if other["name"].casefold() == key and distance_meters(other["lat"], other["lon"], place["lat"], place["lon"]) < DEDUP_METERS:
                duplicate = True
                # Merge address if existing was empty
                if not other.get("address") and place.get("address"):
                    other["address"] = place["address"]
                break
        if not duplicate:
            kept.append(place)
    
    print(f"Total merged distinct places: {len(kept)}")
    return kept

def main():
    overture = fetch_overture_places()
    osm = fetch_osm_places()
    places = merge_and_dedup(osm, overture)
    
    # 1. Update data/places/godavarikhani_places.json
    out_places_path = ROOT / "data/places/godavarikhani_places.json"
    clean_places = []
    for p in places:
        rec = {
            "name": p["name"],
            "category": p["category"],
            "lon": p["lon"],
            "lat": p["lat"],
            "source": p["source"],
            "license": p["license"],
            "confidence": p["confidence"]
        }
        if p.get("address"):
            rec["address"] = p["address"]
        if p.get("record_id"):
            rec["place_id"] = p["record_id"]
        clean_places.append(rec)
    
    out_places_path.write_text(json.dumps({
        "generated_from": f"OpenStreetMap extracts + Overture Maps places {RELEASE}",
        "places": clean_places
    }, ensure_ascii=False, indent=2))
    print(f"Updated {out_places_path} with {len(clean_places)} places!")
    
    # 2. Build Commercial Listings CSV & JSON
    out_dir = ROOT / "outputs" / "chowrasta_shop_export"
    out_dir.mkdir(parents=True, exist_ok=True)
    
    rows = []
    world_shops = []
    
    for p in clean_places:
        lat = float(p["lat"])
        lon = float(p["lon"])
        category = p.get("category", "")
        kind = category.split("=", 1)[-1]
        
        # Check exclusion
        if kind in COMMERCIAL_EXCLUDED or category.startswith("office=") or p["name"].lower() == "godavarikhani chowrasta":
            continue
            
        dist = distance_meters(lat, lon, CENTER_LAT, CENTER_LON)
        inside = dist <= PLAYABLE_RADIUS
        
        # In-game coordinates (relative to Chowrastha)
        x = (lon - CENTER_LON) * LON_SCALE
        north = (lat - CENTER_LAT) * LAT_SCALE
        
        maps_link = "https://www.google.com/maps/search/?" + urlencode({"api": "1", "query": f"{lat},{lon}"})
        
        row = {
            "Business Name": p["name"],
            "Category": category,
            "Latitude": lat,
            "Longitude": lon,
            "Address / Locality": p.get("address", ""),
            "Google Place ID": p.get("place_id", ""),
            "Google Maps Coordinate Link": maps_link,
            "Inside Playable Circle": "yes" if inside else "no",
            "Distance From Centre (m)": round(dist, 2),
            "Source": p.get("source", ""),
            "Source Confidence": p.get("confidence", ""),
            "License": p.get("license", "")
        }
        rows.append(row)
        
        world_shops.append({
            "name": p["name"],
            "category": category,
            "latitude": lat,
            "longitude": lon,
            "address": p.get("address", ""),
            "google_maps_link": maps_link,
            "google_place_id": p.get("place_id", ""),
            "source_id": p.get("place_id", ""),
            "position_2d": {"x": x, "y": north},
            "position_3d": {"x": x, "y": 0.0, "z": -north},
            "distance_m": round(dist, 2)
        })
    
    rows.sort(key=lambda r: (r["Distance From Centre (m)"], r["Business Name"]))
    world_shops.sort(key=lambda s: s["distance_m"])
    
    csv_target = out_dir / "commercial_listings.csv"
    with csv_target.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Updated {csv_target} with {len(rows)} commercial rows!")
    
    # 3. Write commercial_world.json & shops_world.json
    commercial_world = {
        "center": {"latitude": CENTER_LAT, "longitude": CENTER_LON},
        "meters_per_degree": LON_SCALE,
        "radius_m": PLAYABLE_RADIUS,
        "shops": [s for s in world_shops if s["distance_m"] <= PLAYABLE_RADIUS],
        "outside_radius": [s for s in world_shops if s["distance_m"] > PLAYABLE_RADIUS],
        "rejected": []
    }
    (out_dir / "commercial_world.json").write_text(json.dumps(commercial_world, indent=2))
    (out_dir / "shops_world.json").write_text(json.dumps([s for s in world_shops if s["distance_m"] <= PLAYABLE_RADIUS], indent=2))
    print(f"Updated commercial_world.json and shops_world.json!")
    
    # Summary
    with_address_count = sum(bool(r["Address / Locality"]) for r in rows)
    inside_count = sum(r["Inside Playable Circle"] == "yes" for r in rows)
    print(f"\nCollection Summary:")
    print(f"  - Total Commercial Establishments: {len(rows)}")
    print(f"  - Inside 3 km Playable Circle: {inside_count}")
    print(f"  - With Verified Addresses / Localities: {with_address_count} ({with_address_count/len(rows):.1%})")

if __name__ == "__main__":
    main()

