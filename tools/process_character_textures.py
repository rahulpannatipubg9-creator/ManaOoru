import os
from PIL import Image, ImageEnhance, ImageOps

base_dir = os.path.abspath(".")
ref_dir = os.path.join(base_dir, "assets/models/characters/references")
orig_diffuse_path = os.path.join(base_dir, "assets/models/characters/gdk_realistic_male_rigged_Material_001_Pbr_Diffuse.jpg")
output_diffuse = os.path.join(base_dir, "assets/models/characters/player_character_diffuse.jpg")

face_ref_path = os.path.join(ref_dir, "user_face_ref.png")
polo_ref_path = os.path.join(ref_dir, "Screenshot 2026-10-27 at 5.45.08 AM.png")

print("Processing textures for user replica...")

base_tex = Image.open(orig_diffuse_path).convert("RGBA")
bw, bh = base_tex.size

# Target colors from user's photos:
# Skin tone: Warm medium South Asian tone
# Polo shirt: Sandy beige / cream (#CDB89E / RGB: 205, 184, 158)
# Joggers: Washed black / dark charcoal (#252528)

# 1. Warm South Asian skin tint overlay
skin_layer = Image.new("RGBA", (bw, bh), (165, 115, 85, 65))
blended = Image.alpha_composite(base_tex, skin_layer)

# 2. Polo shirt tint overlay
polo_layer = Image.new("RGBA", (bw, bh), (208, 186, 158, 60))
blended = Image.alpha_composite(blended, polo_layer)

# 3. Enhance overall contrast and warmth
rgb_result = blended.convert("RGB")
enhancer = ImageEnhance.Color(rgb_result)
rgb_result = enhancer.enhance(1.15)
enhancer = ImageEnhance.Contrast(rgb_result)
rgb_result = enhancer.enhance(1.08)

rgb_result.save(output_diffuse, quality=94)
print(f"Texture generated at: {output_diffuse} ({bw}x{bh})")
