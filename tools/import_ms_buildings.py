#!/usr/bin/env python3
"""Clip Microsoft Global ML Building Footprints to the MANA OORU play area.

Build-time only; the game never downloads anything. Reproduce the bundled file:

    curl -o tile.csv.gz "<Url column for Location=India, QuadKey=123310201 in
        https://minedbuildings.z5.web.core.windows.net/global-buildings/dataset-links.csv>"
    python3 tools/import_ms_buildings.py tile.csv.gz \
        data/osm/godavarikhani_core.json data/buildings/godavarikhani_ms_buildings.json

Rules (kept in sync with scripts/map/geo_projection.gd and world_generator.gd):
- keep footprints whose centroid lies within the 3 km playable radius;
- drop footprints that duplicate an OSM building (OSM is preferred);
- trim footprints that intrude more than 1 m into an OSM road carriageway back
  to the carriageway edge (ML footprints often include roof overhangs), and
  drop those whose centre is on the road or that lose over half their area,
  so every mapped road stays drivable.

Data licence: Microsoft building footprints are released under ODbL 1.0.
"""

import gzip
import json
import math
import sys
from collections import defaultdict

ORIGIN_LON = 79.513352
ORIGIN_LAT = 18.751925
METERS_PER_DEGREE_LAT = 111000.0
METERS_PER_DEGREE_LON = METERS_PER_DEGREE_LAT * math.cos(math.radians(ORIGIN_LAT))
PLAYABLE_RADIUS = 3000.0
DUPLICATE_DISTANCE = 4.0
ROAD_INTRUSION_TOLERANCE = 1.0
GRID = 50.0
# Must match scripts/map/road_style.gd.
LANE_WIDTH = 3.5
TWO_WAY_WIDTHS = {
    "motorway": 10.5, "trunk": 10.5, "primary": 9.0, "secondary": 7.5, "tertiary": 6.5,
    "motorway_link": 5.0, "trunk_link": 5.0, "primary_link": 5.0, "secondary_link": 5.0, "tertiary_link": 5.0,
    "unclassified": 5.0, "residential": 4.5, "living_street": 4.0, "road": 4.5,
    "service": 3.5, "track": 3.0,
    "footway": 1.8, "path": 1.8, "pedestrian": 3.0, "steps": 1.8, "cycleway": 1.8, "bridleway": 1.8,
}
ONE_WAY_WIDTHS = {"trunk": 7.0, "primary": 7.0, "secondary": 6.5, "tertiary": 5.5}


def project(lon, lat):
    return ((lon - ORIGIN_LON) * METERS_PER_DEGREE_LON, -(lat - ORIGIN_LAT) * METERS_PER_DEGREE_LAT)


def road_width(tags):
    kind = tags["highway"]
    lanes = tags.get("lanes", "")
    if lanes.isdigit() and int(lanes) > 0:
        return int(lanes) * LANE_WIDTH
    if tags.get("oneway") in ("yes", "1", "true", "-1") and kind in ONE_WAY_WIDTHS:
        return ONE_WAY_WIDTHS[kind]
    return TWO_WAY_WIDTHS.get(kind, 4.5)


def centroid(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def point_in_polygon(point, polygon):
    x, z = point
    inside = False
    for (ax, az), (bx, bz) in zip(polygon, polygon[1:] + polygon[:1]):
        if (az > z) != (bz > z) and x < (bx - ax) * (z - az) / (bz - az) + ax:
            inside = not inside
    return inside


def segment_distance(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dz * dz
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / length))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz)


def area(points):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1]))) * 0.5


def clip_to_road_edge(points, a, b, half):
    """Keeps the part of the polygon at least `half` metres from the infinite line a-b, on the polygon's side."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz)
    nx, nz = -dz / length, dx / length
    signed = lambda p: (p[0] - a[0]) * nx + (p[1] - a[1]) * nz
    side = 1.0 if signed(centroid(points)) >= 0 else -1.0
    keep = lambda p: signed(p) * side >= half
    result = []
    for current, following in zip(points, points[1:] + points[:1]):
        if keep(current):
            result.append(current)
        if keep(current) != keep(following):
            t = (half * side - signed(current)) / (signed(following) - signed(current))
            result.append((current[0] + (following[0] - current[0]) * t, current[1] + (following[1] - current[1]) * t))
    return result


def unproject(point):
    return (ORIGIN_LON + point[0] / METERS_PER_DEGREE_LON, ORIGIN_LAT - point[1] / METERS_PER_DEGREE_LAT)


def cells_for(points):
    xs = [p[0] for p in points]
    zs = [p[1] for p in points]
    for gx in range(int(math.floor(min(xs) / GRID)), int(math.floor(max(xs) / GRID)) + 1):
        for gz in range(int(math.floor(min(zs) / GRID)), int(math.floor(max(zs) / GRID)) + 1):
            yield gx, gz


def main(tile_path, osm_path, output_path):
    with open(osm_path, encoding="utf-8") as handle:
        osm = json.load(handle)
    nodes = {e["id"]: project(e["lon"], e["lat"]) for e in osm["elements"] if e["type"] == "node"}
    osm_buildings = defaultdict(list)
    road_segments = defaultdict(list)
    for element in osm["elements"]:
        if element["type"] != "way":
            continue
        tags = element.get("tags", {})
        points = [nodes[i] for i in element["nodes"] if i in nodes]
        if "building" in tags and len(points) >= 3:
            for cell in cells_for(points):
                osm_buildings[cell].append(points)
        elif "highway" in tags:
            half_width = road_width(tags) * 0.5
            for a, b in zip(points, points[1:]):
                for cell in cells_for([a, b]):
                    road_segments[cell].append((a, b, half_width))

    kept, duplicates, on_road, outside, trimmed = [], 0, 0, 0, 0
    with gzip.open(tile_path, "rt", encoding="utf-8") as handle:
        for line in handle:
            ring = json.loads(line)["geometry"]["coordinates"][0]
            points = [project(lon, lat) for lon, lat in ring[:-1]]
            if len(points) < 3:
                continue
            center = centroid(points)
            if math.hypot(*center) > PLAYABLE_RADIUS:
                outside += 1
                continue
            cells = list(cells_for(points))
            nearby = [b for cell in cells for b in osm_buildings[cell]]
            if any(point_in_polygon(center, b) or point_in_polygon(centroid(b), points)
                   or math.dist(center, centroid(b)) < DUPLICATE_DISTANCE for b in nearby):
                duplicates += 1
                continue
            segments = [s for cell in cells for s in road_segments[cell]]
            if any(segment_distance(center, a, b) < half for a, b, half in segments):
                on_road += 1
                continue
            original_area = area(points)
            changed = False
            for a, b, half in segments:
                if a != b and any(segment_distance(p, a, b) < half - ROAD_INTRUSION_TOLERANCE for p in points):
                    points = clip_to_road_edge(points, a, b, half)
                    changed = True
                    if len(points) < 3:
                        break
            if len(points) < 3 or area(points) < max(6.0, original_area * 0.5):
                on_road += 1
                continue
            if changed:
                trimmed += 1
                ring = [unproject(p) for p in points] + [None]
            kept.append([round(v, 7) for lon, lat in ring[:-1] for v in (lon, lat)])

    result = {
        "source": "Microsoft Global ML Building Footprints",
        "url": "https://github.com/microsoft/GlobalMLBuildingFootprints",
        "license": "ODbL 1.0",
        "attribution": "Building footprints © Microsoft, ODbL 1.0",
        "quadkey": "123310201",
        "format": "each building is a flat [lon, lat, lon, lat, ...] ring without the closing point",
        "buildings": kept,
    }
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(result, handle, separators=(",", ":"))
    print(f"kept {len(kept)} ({trimmed} trimmed back to the road edge); skipped {duplicates} OSM duplicates, "
          f"{on_road} on roads, {outside} outside radius")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
