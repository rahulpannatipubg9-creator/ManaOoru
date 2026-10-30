#!/usr/bin/env python3
"""Build the game's terrain heightmap from the Copernicus GLO-30 DEM.

Build-time only (standard library only); the game never downloads anything.

    python3 tools/import_terrain.py

Copernicus GLO-30 is a surface model (it includes buildings and trees), so the
raw heights are opened with a 45 m minimum/maximum filter to strip buildings and
then smoothed, leaving a drivable ground surface. Heights are stored relative to
the Chowrastha junction (game origin = 0 m).

Licence: Copernicus DEM GLO-30, free for any use with attribution:
"© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided
under COPERNICUS by the European Union and ESA; all rights reserved".
"""

import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cog_reader import CogReader  # noqa: E402
from geo import map_to_lon_lat  # noqa: E402

SOURCE = ("https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N18_00_E079_00_DEM/"
          "Copernicus_DSM_COG_10_N18_00_E079_00_DEM.tif")
CELL = 15.0
HALF_EXTENT = 3120.0
OPENING_RADIUS_CELLS = 3
SMOOTHING_PASSES = 3
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "data", "terrain")


def main():
    reader = CogReader(SOURCE)
    ox, px, oy, py = reader.geotransform()
    lon_min, lat_max = map_to_lon_lat(-HALF_EXTENT - 100, -HALF_EXTENT - 100)
    lon_max, lat_min = map_to_lon_lat(HALF_EXTENT + 100, HALF_EXTENT + 100)
    x0 = int((lon_min - ox) / px)
    y0 = int((lat_max - oy) / py)
    width = int((lon_max - ox) / px) - x0 + 2
    height = int((lat_min - oy) / py) - y0 + 2
    dem = reader.read_window(x0, y0, width, height)

    def sample(lon, lat):
        fx = (lon - ox) / px - x0 - 0.5
        fy = (lat - oy) / py - y0 - 0.5
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        tx, ty = fx - ix, fy - iy
        ix = max(0, min(width - 2, ix))
        iy = max(0, min(height - 2, iy))
        top = dem[iy][ix] * (1 - tx) + dem[iy][ix + 1] * tx
        bottom = dem[iy + 1][ix] * (1 - tx) + dem[iy + 1][ix + 1] * tx
        return top * (1 - ty) + bottom * ty

    size = int(round(2 * HALF_EXTENT / CELL)) + 1
    grid = [[sample(*map_to_lon_lat(-HALF_EXTENT + col * CELL, -HALF_EXTENT + row * CELL))
             for col in range(size)] for row in range(size)]
    grid = _filter(grid, OPENING_RADIUS_CELLS, min)
    grid = _filter(grid, OPENING_RADIUS_CELLS, max)
    for _ in range(SMOOTHING_PASSES):
        grid = _blur(grid)
    centre = size // 2
    origin_elevation = grid[centre][centre]
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "godavarikhani_terrain.bin"), "wb") as handle:
        for row in grid:
            handle.write(struct.pack("<%df" % size, *[value - origin_elevation for value in row]))
    flat = [value - origin_elevation for row in grid for value in row]
    meta = {
        "source": "Copernicus DEM GLO-30 (tile N18 E079), buildings filtered out and smoothed",
        "attribution": "© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under "
                       "COPERNICUS by the European Union and ESA; all rights reserved",
        "format": "little-endian float32, row-major; row = z (north to south), column = x (west to east); "
                  "metres relative to the origin elevation",
        "size": size,
        "cell_size": CELL,
        "origin_x": -HALF_EXTENT,
        "origin_z": -HALF_EXTENT,
        "origin_elevation_m": round(origin_elevation, 2),
        "min_height": round(min(flat), 2),
        "max_height": round(max(flat), 2),
    }
    with open(os.path.join(OUTPUT, "godavarikhani_terrain.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
    print(f"terrain {size}x{size} at {CELL} m; origin {origin_elevation:.1f} m; "
          f"relative range {meta['min_height']} .. {meta['max_height']} m")


def _filter(grid, radius, pick):
    size = len(grid)
    rows = [[pick(row[max(0, c - radius):c + radius + 1]) for c in range(size)] for row in grid]
    return [[pick(rows[r][c] for r in range(max(0, i - radius), min(size, i + radius + 1)))
             for c in range(size)] for i in range(size)]


def _blur(grid):
    size = len(grid)
    out = []
    for i in range(size):
        row = []
        for c in range(size):
            total, count = 0.0, 0
            for r in range(max(0, i - 1), min(size, i + 2)):
                for k in range(max(0, c - 1), min(size, c + 2)):
                    total += grid[r][k]
                    count += 1
            row.append(total / count)
        out.append(row)
    return out


if __name__ == "__main__":
    main()
