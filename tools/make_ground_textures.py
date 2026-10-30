"""Packs CC0 Poly Haven ground and road textures into the vertical strips the ground and
road shaders import as Texture2DArray layers (one strip each for albedo, normal, AO/rough/metal).

Layers: 0 town ground (dirt_floor), 1 bare mining/dry land (dry_mud_field_001),
2 grass (leafy_grass), 3 woodland floor (brown_mud_leaves_01), 4 farm soil (farm_soil),
5 dry scrub (withered_grass), 6 red laterite soil (red_laterite_soil_stones).
All CC0 from https://polyhaven.com, 1K JPG maps (Diffuse, nor_gl, arm).
Road strips (road_*.jpg): 0 main-road asphalt (asphalt_02), 1 minor-road asphalt (asphalt_01).
Run: python tools/make_ground_textures.py <folder with the downloaded JPGs> assets/textures/ground
Needs Pillow.
"""
import os
import sys

from PIL import Image

LAYERS = ["dirt_floor", "dry_mud_field_001", "leafy_grass", "brown_mud_leaves_01", "farm_soil", "withered_grass",
          "red_laterite_soil_stones"]
ROAD_LAYERS = ["asphalt_02", "asphalt_01"]
MAPS = {"albedo": "Diffuse", "normal": "nor_gl", "arm": "arm"}
SIZE = 1024


def main() -> None:
    source, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for prefix, layers in (("ground", LAYERS), ("road", ROAD_LAYERS)):
        pack(source, out, prefix, layers)


def pack(source: str, out: str, prefix: str, layers: list[str]) -> None:
    for name, suffix in MAPS.items():
        strip = Image.new("RGB", (SIZE, SIZE * len(layers)))
        for index, layer in enumerate(layers):
            image = Image.open(os.path.join(source, f"{layer}_{suffix}.jpg")).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
            strip.paste(image, (0, SIZE * index))
        path = os.path.join(out, f"{prefix}_{name}.jpg")
        strip.save(path, quality=90)
        print(path, os.path.getsize(path))


main()
