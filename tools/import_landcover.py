"""Imports what covers the ground across the game area from ESA WorldCover 10 m 2021 v200
(trees, shrubs, grass, crops, built-up, bare soil, water, wetland), so the ground shader
can draw real grass, soil and water instead of one flat colour.

Source: ESA WorldCover 10 m 2021 v200, tile N18E078 (CC BY 4.0), read with HTTP range
requests from the public AWS bucket; only the game area is downloaded.
Output: data/landcover/godavarikhani_landcover.bin (uint8 class codes, row-major,
row = z north to south, column = x west to east) and godavarikhani_landcover.json.
Run: python tools/import_landcover.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cog_reader import CogReader  # noqa: E402
from geo import map_to_lon_lat  # noqa: E402

SOURCE = ("https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/"
          "ESA_WorldCover_10m_2021_v200_N18E078_Map.tif")
CELL = 10.0
HALF_EXTENT = 3120.0
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "data", "landcover")
CLASSES = {10: "tree cover", 20: "shrubland", 30: "grassland", 40: "cropland", 50: "built-up",
           60: "bare / sparse vegetation", 70: "snow and ice", 80: "permanent water", 90: "herbaceous wetland",
           95: "mangroves", 100: "moss and lichen"}


def main():
    reader = CogReader(SOURCE)
    ox, px, oy, py = reader.geotransform()
    lon_min, lat_max = map_to_lon_lat(-HALF_EXTENT - 50, -HALF_EXTENT - 50)
    lon_max, lat_min = map_to_lon_lat(HALF_EXTENT + 50, HALF_EXTENT + 50)
    x0 = int((lon_min - ox) / px)
    y0 = int((lat_max - oy) / py)
    width = int((lon_max - ox) / px) - x0 + 2
    height = int((lat_min - oy) / py) - y0 + 2
    raster = reader.read_window(x0, y0, width, height)
    size = int(round(2 * HALF_EXTENT / CELL))
    counts = {}
    out = bytearray()
    for row in range(size):
        for col in range(size):
            lon, lat = map_to_lon_lat(-HALF_EXTENT + (col + 0.5) * CELL, -HALF_EXTENT + (row + 0.5) * CELL)
            ix = min(width - 1, max(0, int((lon - ox) / px) - x0))
            iy = min(height - 1, max(0, int((lat - oy) / py) - y0))
            code = int(raster[iy][ix])
            out.append(code)
            counts[code] = counts.get(code, 0) + 1
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "godavarikhani_landcover.bin"), "wb") as handle:
        handle.write(out)
    meta = {
        "source": "ESA WorldCover 10 m 2021 v200 (tile N18E078)",
        "attribution": "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) "
                       "processed by ESA WorldCover consortium",
        "license": "CC BY 4.0",
        "format": "uint8 class codes, row-major; row = z (north to south), column = x (west to east)",
        "size": size, "cell_size": CELL, "origin_x": -HALF_EXTENT, "origin_z": -HALF_EXTENT,
        "classes": {str(code): name for code, name in CLASSES.items()},
        "share": {CLASSES.get(code, str(code)): round(count / len(out), 4) for code, count in sorted(counts.items())},
    }
    with open(os.path.join(OUTPUT, "godavarikhani_landcover.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
    print(f"land cover {size}x{size} at {CELL} m: {meta['share']}")


if __name__ == "__main__":
    main()
