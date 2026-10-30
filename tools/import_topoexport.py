#!/usr/bin/env python3
"""Convert TopoExport UTM GeoJSON into the game's local map coordinates.

The downloaded export uses WGS84 / UTM zone 44N (EPSG:32644).  The game uses
the existing GeoProjection origin, so the generated files can be loaded offline
without adding a projection dependency to the runtime.
"""

from __future__ import annotations

import argparse
import json
import math
import zipfile
from pathlib import Path


ORIGIN_LON = 79.513352
ORIGIN_LAT = 18.751925
METERS_PER_DEGREE_LAT = 111000.0
ZONE_CENTRAL_MERIDIAN = math.radians(81.0)


def utm_to_lon_lat(easting: float, northing: float) -> tuple[float, float]:
    """Inverse WGS84 UTM zone 44N, matching EPSG:32644."""
    semi_major = 6378137.0
    eccentricity_sq = 0.00669438
    scale = 0.9996
    eccentricity_prime_sq = eccentricity_sq / (1.0 - eccentricity_sq)
    x = easting - 500000.0
    y = northing
    meridional = y / scale
    mu = meridional / (semi_major * (1.0 - eccentricity_sq / 4.0
        - 3.0 * eccentricity_sq**2 / 64.0
        - 5.0 * eccentricity_sq**3 / 256.0))
    e1 = (1.0 - math.sqrt(1.0 - eccentricity_sq)) / (1.0 + math.sqrt(1.0 - eccentricity_sq))
    footpoint = mu
    footpoint += (3.0 * e1 / 2.0 - 27.0 * e1**3 / 32.0) * math.sin(2.0 * mu)
    footpoint += (21.0 * e1**2 / 16.0 - 55.0 * e1**4 / 32.0) * math.sin(4.0 * mu)
    footpoint += (151.0 * e1**3 / 96.0) * math.sin(6.0 * mu)
    footpoint += (1097.0 * e1**4 / 512.0) * math.sin(8.0 * mu)
    sin_fp = math.sin(footpoint)
    cos_fp = math.cos(footpoint)
    tan_fp = math.tan(footpoint)
    c1 = eccentricity_prime_sq * cos_fp**2
    t1 = tan_fp**2
    n1 = semi_major / math.sqrt(1.0 - eccentricity_sq * sin_fp**2)
    r1 = semi_major * (1.0 - eccentricity_sq) / (1.0 - eccentricity_sq * sin_fp**2)**1.5
    d = x / (n1 * scale)
    latitude = footpoint - (n1 * tan_fp / r1) * (
        d**2 / 2.0
        - (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1**2 - 9.0 * eccentricity_prime_sq) * d**4 / 24.0
        + (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1**2
           - 252.0 * eccentricity_prime_sq - 3.0 * c1**2) * d**6 / 720.0)
    longitude = ZONE_CENTRAL_MERIDIAN + (
        d - (1.0 + 2.0 * t1 + c1) * d**3 / 6.0
        + (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1**2
           + 8.0 * eccentricity_prime_sq + 24.0 * t1**2) * d**5 / 120.0) / cos_fp
    return math.degrees(longitude), math.degrees(latitude)


def to_map(point: list[float]) -> list[float]:
    lon, lat = utm_to_lon_lat(float(point[0]), float(point[1]))
    metres_per_degree_lon = METERS_PER_DEGREE_LAT * math.cos(math.radians(ORIGIN_LAT))
    return [round((lon - ORIGIN_LON) * metres_per_degree_lon, 3),
            round(-(lat - ORIGIN_LAT) * METERS_PER_DEGREE_LAT, 3)]


def read_geojson(source: Path, name: str) -> dict:
    if source.suffix.lower() == ".zip":
        with zipfile.ZipFile(source) as archive:
            return json.loads(archive.read(name))
    return json.loads((source / name).read_text(encoding="utf-8"))


def convert_roads(doc: dict) -> dict:
    kind_map = {"Major": "tertiary", "Minor": "residential", "Service": "service", "Footway": "footway"}
    roads = []
    for feature in doc.get("features", []):
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "LineString" or len(geometry.get("coordinates", [])) < 2:
            continue
        props = feature.get("properties") or {}
        source_kind = str(props.get("type", "Minor"))
        roads.append({
            "id": str(feature.get("id", "")),
            "kind": kind_map.get(source_kind, "residential"),
            "source_type": source_kind,
            "width": float(props.get("width", 3.5)),
            "points": [to_map(point) for point in geometry["coordinates"]],
        })
    return {"source": "TopoExport / Overture Transportation 2026", "crs": "EPSG:32644", "roads": roads}


def convert_trees(doc: dict) -> dict:
    trees = []
    for feature in doc.get("features", []):
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "Point" or len(geometry.get("coordinates", [])) < 2:
            continue
        props = feature.get("properties") or {}
        trees.append({
            "id": str(feature.get("id", "")),
            "point": to_map(geometry["coordinates"]),
            "height": max(1.0, float(props.get("height", 8.0))),
            "crown_diameter": max(1.0, float(props.get("crown_diameter", 6.0))),
        })
    return {"source": "TopoExport / Overture Base 2026 + Global Canopy Height Maps v2", "crs": "EPSG:32644", "trees": trees}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("export", type=Path, help="TopoExport ZIP or extracted directory")
    parser.add_argument("--output", type=Path, default=Path("data/topoexport"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    roads = convert_roads(read_geojson(args.export, "roads_Transportation_Overture.geojson"))
    trees = convert_trees(read_geojson(args.export, "trees_Trees_TPX.geojson"))
    (args.output / "roads.json").write_text(json.dumps(roads, indent=2) + "\n", encoding="utf-8")
    (args.output / "trees.json").write_text(json.dumps(trees, indent=2) + "\n", encoding="utf-8")
    print(f"TopoExport: {len(roads['roads'])} roads, {len(trees['trees'])} trees")


if __name__ == "__main__":
    main()
