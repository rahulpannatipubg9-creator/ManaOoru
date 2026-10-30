#!/usr/bin/env python3
"""Build the game's building-height raster from Google Open Buildings 2.5D Temporal.

Build-time only (standard library only); the game never downloads anything.

    python3 tools/import_building_heights.py

Reads only the needed 2 m overview tiles of the 2023 rasters over HTTP range
requests and writes a gzip-compressed 8-bit raster on the game's map grid
(x east, z south, 2 m cells, value = height in 0.25 m steps). The game reads
the height inside each building footprint from it.

Licence: Open Buildings 2.5D Temporal Dataset, CC BY 4.0 — "Google Open Buildings 2.5D".
"""

import array
import gzip
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cog_reader import CogReader  # noqa: E402
from geo import map_to_utm_affine  # noqa: E402

BUCKET = "https://storage.googleapis.com/open-buildings-temporal-data/v1/geotiffs/"
# 12.5 km UTM 44N tiles (2023-06-30 inference) covering the play area; found via
# v1/manifests/3b_EPSG_32644_2023_06_30.json.
TILES = ["3a32c_2023_06_30/tile_43IjAmy2W0Y.tif", "3a32c_2023_06_30/tile_MI3jylLm5cA.tif"]
HEIGHT_BAND = 1
OVERVIEW_METERS = 2.0
CELL = 2.0
HALF_EXTENT = 3050.0
UNITS_PER_METER = 4.0
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "data", "buildings")


def main():
    size = int(2 * HALF_EXTENT / CELL)
    e0, ex, ez, n0, nx, nz = map_to_utm_affine()
    raster = bytearray(size * size)
    for tile in TILES:
        reader = CogReader(BUCKET + tile)
        ox, px, oy, py = reader.geotransform()
        level = next(i for i in range(len(reader.ifds)) if abs(reader.size(i)[0] * OVERVIEW_METERS - reader.size(0)[0] * px) < 1)
        width, height = reader.size(level)
        scale = reader.size(0)[0] / width
        pixel = px * scale
        tags = reader.ifds[level]
        tile_size = tags[322][0]
        tiles_across = (width + tile_size - 1) // tile_size
        # Pixel bounds of the play area in this raster (generous, the affine is rotated slightly).
        corners = [(e0 + ex * x + ez * z, n0 + nx * x + nz * z) for x in (-HALF_EXTENT, HALF_EXTENT) for z in (-HALF_EXTENT, HALF_EXTENT)]
        col_min = max(0, int((min(c[0] for c in corners) - ox) / pixel) - 2)
        col_max = min(width - 1, int((max(c[0] for c in corners) - ox) / pixel) + 2)
        row_min = max(0, int((oy - max(c[1] for c in corners)) / pixel) - 2)
        row_max = min(height - 1, int((oy - min(c[1] for c in corners)) / pixel) + 2)
        if col_min > col_max or row_min > row_max:
            continue
        values = array.array("f", [0.0]) * ((col_max - col_min + 1) * (row_max - row_min + 1))
        window_w = col_max - col_min + 1
        fetched = 0
        for tile_row in range(row_min // tile_size, row_max // tile_size + 1):
            for tile_col in range(col_min // tile_size, col_max // tile_size + 1):
                block = reader.read_window(tile_col * tile_size, tile_row * tile_size, tile_size, tile_size,
                                           band=HEIGHT_BAND, level=level)
                fetched += 1
                for r, row in enumerate(block):
                    y = tile_row * tile_size + r
                    if not row_min <= y <= row_max:
                        continue
                    base = (y - row_min) * window_w
                    for c, value in enumerate(row):
                        x = tile_col * tile_size + c
                        if col_min <= x <= col_max and value > 0:
                            values[base + x - col_min] = value
        print(f"{tile}: {fetched} tiles read at {pixel:.1f} m")
        for row in range(size):
            z = -HALF_EXTENT + (row + 0.5) * CELL
            for col in range(size):
                x = -HALF_EXTENT + (col + 0.5) * CELL
                c = int((e0 + ex * x + ez * z - ox) / pixel) - col_min
                r = int((oy - (n0 + nx * x + nz * z)) / pixel) - row_min
                if 0 <= c < window_w and 0 <= r <= row_max - row_min:
                    value = values[r * window_w + c]
                    if value > 0:
                        encoded = min(255, int(round(value * UNITS_PER_METER)))
                        index = row * size + col
                        raster[index] = max(raster[index], encoded)
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "godavarikhani_building_heights.bin.gz"), "wb") as handle:
        handle.write(gzip.compress(bytes(raster), 9))
    meta = {
        "source": "Google Open Buildings 2.5D Temporal Dataset (2023-06-30), building_height band",
        "license": "CC BY 4.0",
        "attribution": "Building heights: Google Open Buildings 2.5D (CC BY 4.0)",
        "format": "gzip of size*size uint8; row = z (north to south), column = x (west to east); value / units_per_meter = metres",
        "size": size,
        "cell_size": CELL,
        "origin_x": -HALF_EXTENT,
        "origin_z": -HALF_EXTENT,
        "units_per_meter": UNITS_PER_METER,
    }
    with open(os.path.join(OUTPUT, "godavarikhani_building_heights.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
    covered = sum(1 for value in raster if value)
    print(f"wrote {size}x{size} raster; {covered * CELL * CELL / 1e6:.2f} km² with building height")


if __name__ == "__main__":
    main()
