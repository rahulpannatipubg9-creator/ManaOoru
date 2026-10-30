"""Convert CSV, JSON lists, or Overpass JSON to spawnable shop coordinates.

python3 tools/shop_coordinates.py input.json --output shops_world.json
Uses the requested 111320 m/degree formula; latitude angles are in radians.
Godot's existing city uses 111000, so use --meters-per-degree 111000 when
overlaying markers on that city. North is positive Y in 2D, negative Z in Godot.
"""
import argparse
import csv
import json
import math
from pathlib import Path

CENTER_LAT = 18.751925
CENTER_LON = 79.513352


def pick(row, *keys, default=""):
    normalized = {str(k).lower().replace(" ", "").replace("_", ""): v for k, v in row.items()}
    for key in keys:
        value = normalized.get(key.lower().replace(" ", "").replace("_", ""))
        if value is not None and str(value).strip():
            return value
    return default


def convert(row, meters_per_degree=111320.0):
    tags = row.get("tags", row)
    coordinates = row.get("center", row)
    lat = float(pick(coordinates, "latitude", "lat"))
    lon = float(pick(coordinates, "longitude", "lon", "lng"))
    if not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
        raise ValueError("Invalid latitude or longitude")
    x = (lon - CENTER_LON) * meters_per_degree * math.cos(math.radians(CENTER_LAT))
    north = (lat - CENTER_LAT) * meters_per_degree
    category = pick(tags, "category", "shop", "amenity", "office", "healthcare", default="place")
    address = pick(tags, "address", "address/locality", "addr:full")
    if not address:
        address = ", ".join(str(tags[k]) for k in ["addr:housenumber", "addr:street", "addr:suburb", "addr:city"] if tags.get(k))
    return {"name": str(pick(tags, "name", "businessname", "shop/businessname", default=str(category).replace("_", " ").title())),
            "category": str(category), "latitude": lat, "longitude": lon,
            "address": address,
            "google_maps_link": pick(tags, "googlemapslink", "googlemapsplacelink", "googlemapscoordinatelink", "mapslink"),
            "google_place_id": pick(tags, "googleplaceid", "placeid"),
            "source_id": f"{row.get('type', 'record')}/{row.get('id', '')}",
            "position_2d": {"x": x, "y": north},
            "position_3d": {"x": x, "y": 0.0, "z": -north},
            "distance_m": math.hypot(x, north)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--meters-per-degree", type=float, default=111320.0)
    parser.add_argument("--radius", type=float, default=3000.0)
    args = parser.parse_args()
    if args.meters_per_degree <= 0 or args.radius <= 0:
        parser.error("Scale and radius must be positive")
    with args.input.open(encoding="utf-8-sig", newline="") as f:
        if args.input.suffix.lower() == ".csv":
            rows = list(csv.DictReader(f))
        else:
            parsed = json.load(f)
            rows = parsed if isinstance(parsed, list) else parsed.get("elements", parsed.get("shops", parsed.get("places", [])))
    shops, rejected, outside = [], [], 0
    for index, row in enumerate(rows):
        try:
            shop = convert(row, args.meters_per_degree)
            if shop["distance_m"] > args.radius:
                outside += 1
                continue
            shops.append(shop)
        except (ValueError, TypeError, AttributeError) as error:
            rejected.append({"row": index + 1, "reason": str(error)})
    result = {"center": {"latitude": CENTER_LAT, "longitude": CENTER_LON},
              "meters_per_degree": args.meters_per_degree, "radius_m": args.radius,
              "shops": shops, "outside_radius": outside, "rejected": rejected}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Exported {len(shops)} shops; outside radius: {outside}; invalid: {len(rejected)}")


if __name__ == "__main__":
    main()
