"""Export existing commercial reference records inside the playable bounding box."""
import csv
import json
import math
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
LAT, LON, RADIUS = 18.751925, 79.513352, 3000.0
LON_SCALE = 111000.0 * math.cos(math.radians(LAT))
SOUTH, NORTH = LAT - RADIUS / 111000.0, LAT + RADIUS / 111000.0
WEST, EAST = LON - RADIUS / LON_SCALE, LON + RADIUS / LON_SCALE
OUT = ROOT / "outputs" / "chowrasta_shop_export"
OUT.mkdir(parents=True, exist_ok=True)
records = json.loads((ROOT / "data/places/godavarikhani_places.json").read_text())["places"]
excluded = {"school", "college", "university", "place_of_worship", "police", "government",
            "office", "health_post", "community_centre", "childcare", "blood_bank",
            "educational_institution", "place_of_learning", "historic_site", "artwork",
            "park", "stadium_arena", "public_transit_facility_or_service"}
rows = []
for p in records:
    lat, lon = float(p["lat"]), float(p["lon"])
    category = p.get("category", "")
    kind = category.split("=", 1)[-1]
    if not (SOUTH < lat < NORTH and WEST < lon < EAST):
        continue
    if kind in excluded or category.startswith("office=") or p["name"].lower() == "godavarikhani chowrasta":
        continue
    distance = math.hypot((lon - LON) * LON_SCALE, (lat - LAT) * 111000.0)
    rows.append({"Business Name": p["name"], "Category": category,
                 "Latitude": lat, "Longitude": lon,
                 "Address / Locality": p.get("address", ""),
                 "Google Place ID": p.get("place_id", ""),
                 "Google Maps Coordinate Link": "https://www.google.com/maps/search/?" + urlencode({"api": "1", "query": f"{lat},{lon}"}),
                 "Inside Playable Circle": "yes" if distance <= RADIUS else "no",
                 "Distance From Centre (m)": round(distance, 2),
                 "Source": p.get("source", ""), "Source Confidence": p.get("confidence", ""),
                 "License": p.get("license", "")})
rows.sort(key=lambda r: (r["Distance From Centre (m)"], r["Business Name"]))
assert rows
target = OUT / "commercial_listings.csv"
with target.open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps({"file": str(target), "records": len(rows),
                  "inside_circle": sum(r["Inside Playable Circle"] == "yes" for r in rows),
                  "addresses_available": sum(bool(r["Address / Locality"]) for r in rows),
                  "place_ids_available": sum(bool(r["Google Place ID"]) for r in rows),
                  "south": SOUTH, "north": NORTH, "west": WEST, "east": EAST}, indent=2))
