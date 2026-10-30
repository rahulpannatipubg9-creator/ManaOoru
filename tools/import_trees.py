"""Finds every real tree across the game area from the Meta / World Resources Institute
1 m global canopy-height map, so trees stand where they really grow, at their real height.

Source: "High Resolution Canopy Height Maps" by Meta and WRI (Tolan et al. 2024), tile
123310201 (CC BY 4.0), s3://dataforgood-fb-data/forests/v1/alsgedi_global_v6_float/chm/.
Only the rows covering the game area are downloaded.

The canopy is sampled on a CELL-metre grid: a cell where canopy at least MIN_HEIGHT tall
covers COVER_SHARE of the ground gets one tree at its tallest point, at that height, with a
crown sized from the height. Trees inside building footprints or on roads are dropped later
in the game (the map sometimes reads roofs as canopy).
Output: data/trees/godavarikhani_trees.bin (little-endian float32 x, z, height, crown radius
per tree, game metres) and godavarikhani_trees.json.
Run: python tools/import_trees.py   (needs numpy, scipy, rasterio)
"""

import json
import math
import os
import struct
import sys

import numpy as np
import rasterio
from rasterio.windows import from_bounds

sys.path.insert(0, os.path.dirname(__file__))
from geo import ORIGIN_LAT, ORIGIN_LON, METERS_PER_DEGREE_LAT, METERS_PER_DEGREE_LON, map_to_lon_lat  # noqa: E402

SOURCE = "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/123310201.tif"
HALF_EXTENT = 3120.0
MIN_HEIGHT = 5
CELL = 7.0
COVER_SHARE = 0.35
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "data", "trees")
EARTH = 6378137.0


def to_mercator(lon, lat):
    return EARTH * math.radians(lon), EARTH * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))


def from_mercator(x, y):
    return math.degrees(x / EARTH), math.degrees(2 * math.atan(math.exp(y / EARTH)) - math.pi / 2)


def main():
    lon_min, lat_max = map_to_lon_lat(-HALF_EXTENT, -HALF_EXTENT)
    lon_max, lat_min = map_to_lon_lat(HALF_EXTENT, HALF_EXTENT)
    left, bottom = to_mercator(lon_min, lat_min)
    right, top = to_mercator(lon_max, lat_max)
    with rasterio.open(SOURCE) as dataset:
        window = from_bounds(left, bottom, right, top, dataset.transform).round_offsets().round_lengths()
        canopy = dataset.read(1, window=window).astype(np.float32)
        transform = dataset.window_transform(window)
    pixel = transform.a
    # Mercator pixels are smaller on the ground by cos(latitude).
    ground_pixel = pixel * math.cos(math.radians(ORIGIN_LAT))
    # Continuous canopy rarely has clear peaks, so sample it on a grid of CELL-metre cells:
    # a cell whose canopy covers COVER_SHARE gets one tree at its tallest point.
    cell_px = max(2, int(round(CELL / ground_pixel)))
    rows = canopy.shape[0] // cell_px
    cols = canopy.shape[1] // cell_px
    blocks = canopy[:rows * cell_px, :cols * cell_px].reshape(rows, cell_px, cols, cell_px).transpose(0, 2, 1, 3)
    blocks = blocks.reshape(rows, cols, cell_px * cell_px)
    tallest = blocks.max(axis=2)
    where = blocks.argmax(axis=2)
    cover = (blocks >= MIN_HEIGHT).mean(axis=2)
    out = bytearray()
    count = 0
    heights = []
    for row, col in zip(*np.nonzero((cover >= COVER_SHARE) & (tallest >= MIN_HEIGHT))):
        offset = int(where[row, col])
        pixel_row = row * cell_px + offset // cell_px
        pixel_col = col * cell_px + offset % cell_px
        x, y = transform * (pixel_col + 0.5, pixel_row + 0.5)
        lon, lat = from_mercator(x, y)
        game_x = (lon - ORIGIN_LON) * METERS_PER_DEGREE_LON
        game_z = -(lat - ORIGIN_LAT) * METERS_PER_DEGREE_LAT
        if abs(game_x) > HALF_EXTENT or abs(game_z) > HALF_EXTENT:
            continue
        height = float(tallest[row, col])
        crown = min(7.0, max(2.5, 2.0 + height * 0.22))
        out += struct.pack("<4f", game_x, game_z, height, crown)
        heights.append(height)
        count += 1
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "godavarikhani_trees.bin"), "wb") as handle:
        handle.write(out)
    meta = {
        "source": "Meta and World Resources Institute, High Resolution Canopy Height Maps (tile 123310201)",
        "attribution": "Meta and World Resources Institute (WRI) 2024. High Resolution Canopy Height Maps by WRI and Meta.",
        "license": "CC BY 4.0",
        "format": "little-endian float32 per tree: x, z (game metres), height (m), crown radius (m)",
        "count": count, "min_height_m": MIN_HEIGHT,
        "mean_height_m": round(sum(heights) / count, 2) if count else 0.0, "cell_m": CELL, "cover_share": COVER_SHARE,
    }
    with open(os.path.join(OUTPUT, "godavarikhani_trees.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
    print(f"{count} trees, mean height {meta['mean_height_m']} m, window {canopy.shape}")


if __name__ == "__main__":
    main()
