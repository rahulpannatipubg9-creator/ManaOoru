"""Packs CC0 Poly Haven wall textures into the vertical strips the building shader
imports as Texture2DArray layers (one strip each for albedo, normal and AO/rough/metal).

Layers: 0 painted plaster, 1 peeling paint, 2 exposed brick, 3 bare concrete, 4 rolling shutter.
Sources (all CC0, https://polyhaven.com): painted_plaster_wall, peeling_painted_wall,
brick_wall_001, concrete_wall_008, painted_metal_shutter, 1K JPG maps (Diffuse, nor_gl, arm).
Run: python tools/make_facade_textures.py <folder with the downloaded JPGs> assets/textures/facade
Needs Pillow.
"""
import os
import sys

from PIL import Image

LAYERS = ["painted_plaster_wall", "peeling_painted_wall", "brick_wall_001", "concrete_wall_008", "painted_metal_shutter"]
MAPS = {"albedo": "Diffuse", "normal": "nor_gl", "arm": "arm"}
SIZE = 1024


def main() -> None:
    source, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name, suffix in MAPS.items():
        strip = Image.new("RGB", (SIZE, SIZE * len(LAYERS)))
        for index, layer in enumerate(LAYERS):
            image = Image.open(os.path.join(source, f"{layer}_{suffix}.jpg")).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
            strip.paste(image, (0, SIZE * index))
        path = os.path.join(out, f"facade_{name}.jpg")
        strip.save(path, quality=92)
        print(path, os.path.getsize(path))


main()
