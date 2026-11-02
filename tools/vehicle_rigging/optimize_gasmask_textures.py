import bpy
import pathlib

BLEND_PATH = "/Users/rahulpannati/GameReadyLibrary/Characters/GasMask_SWAT/gas_mask_all_animations.blend"
OUT_ASSETS = pathlib.Path("/Users/rahulpannati/Downloads/AI Agents Practice/ManaOoru/assets/models/characters/gas_mask")
OUT_LIB = pathlib.Path("/Users/rahulpannati/GameReadyLibrary/Characters/GasMask_SWAT")

OUT_ASSETS.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)

print(f"Checking images in {BLEND_PATH}...")
downscaled = 0
for img in bpy.data.images:
    if img.size[0] > 2048 or img.size[1] > 2048:
        print(f"Downscaling {img.name}: {img.size[0]}x{img.size[1]} -> 2048x2048")
        img.scale(2048, 2048)
        downscaled += 1

print(f"Downscaled {downscaled} high-res textures to 2048x2048.")

# Save updated blend file
bpy.ops.wm.save_mainfile()
print("Saved optimized blend file.")

# Export game-ready T-pose GLB with compact textures
glb_assets = str(OUT_ASSETS / "gas_mask_tpose.glb")
glb_lib = str(OUT_LIB / "gas_mask_tpose.glb")

for p in [glb_assets, glb_lib]:
    bpy.ops.export_scene.gltf(
        filepath=p,
        export_format='GLB',
        export_animations=False,
        export_lights=False,
        export_cameras=False,
        export_image_format='AUTO'
    )
    print(f"Exported optimized GLB: {p}")

