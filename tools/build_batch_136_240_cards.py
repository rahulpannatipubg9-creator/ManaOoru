#!/usr/bin/env python3
"""Build showcase cards and corridor posters for Batch 136-240 shops.
Crops high-contrast signboard text, attaches metadata badges,
generates corridor showcase sheets, and copies to artifacts.
"""

import csv
import json
import os
import shutil
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ARTIFACT_DIR = Path("/Users/rahulpannati/.gemini/antigravity/brain/0ed1dfb8-1e90-4ece-a247-5639e10fde6d")
OUT_DIR = Path("outputs/shop-images/batch_136_240")
CROPS_DIR = OUT_DIR / "crops"
CARDS_DIR = OUT_DIR / "cards"
POSTERS_DIR = OUT_DIR / "posters"

CROPS_DIR.mkdir(parents=True, exist_ok=True)
CARDS_DIR.mkdir(parents=True, exist_ok=True)
POSTERS_DIR.mkdir(parents=True, exist_ok=True)

# Load metadata from TSV
tsv_path = Path("data/survey/survey_batch_136_240.tsv")
meta_map = {}
with open(tsv_path, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    for row in reader:
        sid = row["shop_id"].strip()
        area = ""
        for p in row.get("notes", "").split(";"):
            p = p.strip()
            if p.startswith("area="):
                area = p.replace("area=", "").strip()

        sid_num = int(sid.split("-")[-1])
        if 136 <= sid_num <= 152:
            corridor_key = "Gandhi_Nagar_Corridor"
        elif sid_num in (set(range(153, 165)) | {195, 196, 217}):
            corridor_key = "Ram_Nagar_Jawahar_Nagar"
        elif 165 <= sid_num <= 172:
            corridor_key = "Ramesh_Nagar"
        elif 173 <= sid_num <= 194:
            corridor_key = "Kalyan_Maruthi_Nagar"
        elif 197 <= sid_num <= 205:
            corridor_key = "Power_House_IB_Colony"
        elif sid_num in (set(range(206, 217)) | {218, 219, 220}):
            corridor_key = "Gouthami_Nagar_FCI"
        else:
            corridor_key = "Vittal_Nagar_5Incline"

        meta_map[sid] = {
            "shop_id": sid,
            "name": row["name"].strip(),
            "category": row["category"].strip(),
            "address": row["address"].strip(),
            "lat": float(row["latitude"]) if row["latitude"] else 0.0,
            "lon": float(row["longitude"]) if row["longitude"] else 0.0,
            "godot_x": float(row["godot_x_m"]) if row["godot_x_m"] else 0.0,
            "godot_z": float(row["godot_z_m"]) if row["godot_z_m"] else 0.0,
            "area": area,
            "corridor": corridor_key
        }

# Fonts
try:
    font_title = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    font_bold = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    font_sub = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
    font_h1 = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40)
    font_h2 = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
except Exception:
    font_title = ImageFont.load_default()
    font_bold = ImageFont.load_default()
    font_sub = ImageFont.load_default()
    font_h1 = ImageFont.load_default()
    font_h2 = ImageFont.load_default()

# Find all captured PNGs
png_files = sorted(OUT_DIR.glob("GDK-C100-*.png"))
print(f"Processing {len(png_files)} captured shop PNG images...")

cards_by_corridor = {}
all_cards = []

for png_path in png_files:
    sid = png_path.name.split("_")[0]
    meta = meta_map.get(sid, {
        "shop_id": sid,
        "name": png_path.stem.replace(f"{sid}_", ""),
        "category": "Commercial",
        "area": "Godavarikhani",
        "corridor": "General_Godavarikhani",
        "godot_x": 0.0,
        "godot_z": 0.0,
        "address": ""
    })

    im = Image.open(png_path)
    w, h = im.size

    # Central crop focusing on sign and facade
    crop_w = int(w * 0.72)
    crop_h = int(h * 0.42)
    cx, cy = w // 2, int(h * 0.48)

    x0 = max(0, cx - crop_w // 2)
    y0 = max(0, cy - crop_h // 2)
    x1 = min(w, x0 + crop_w)
    y1 = min(h, y0 + crop_h)

    sign_crop = im.crop((x0, y0, x1, y1))
    crop_path = CROPS_DIR / f"{sid}.png"
    sign_crop.save(crop_path)

    # Individual shop card
    card_w, card_h = 960, 560
    card = Image.new("RGB", (card_w, card_h), "#181b20")
    draw = ImageDraw.Draw(card)

    # Top header bar
    draw.rectangle([(0, 0), (card_w, 75)], fill="#23272f")
    # Accent pill for Shop ID
    draw.rounded_rectangle([(20, 16), (195, 56)], radius=6, fill="#0d6efd")
    draw.text((28, 24), sid, fill="#ffffff", font=font_bold)

    # Category badge
    cat_str = meta["category"]
    draw.rounded_rectangle([(210, 16), (395, 56)], radius=6, fill="#343a46")
    draw.text((220, 25), cat_str[:22], fill="#cbd5e1", font=font_sub)

    # Prominent Shop Name in Header
    name_str = meta["name"]
    disp_name = name_str if len(name_str) <= 34 else name_str[:32] + "..."
    draw.text((415, 22), disp_name, fill="#f8fafc", font=font_title)

    # Resize sign crop to fit card width
    target_img_w = card_w - 40
    target_img_h = int(target_img_w * (crop_h / crop_w))
    resized_crop = sign_crop.resize((target_img_w, target_img_h), Image.Resampling.LANCZOS)
    card.paste(resized_crop, (20, 85))

    # Bottom footer with coordinates
    footer_y = 85 + target_img_h + 10
    draw.line([(20, footer_y), (card_w - 20, footer_y)], fill="#2d333b", width=1)
    c_name = meta["corridor"].replace("_", " ")
    pos_str = f"Godot World: ({meta['godot_x']:.1f}m, {meta['godot_z']:.1f}m) | Corridor: {c_name} | {meta['address'][:45]}"
    draw.text((25, footer_y + 8), pos_str, fill="#94a3b8", font=font_sub)

    card_path = CARDS_DIR / f"{sid}.png"
    card.save(card_path)
    all_cards.append((sid, card_path, meta))
    cards_by_corridor.setdefault(meta["corridor"], []).append((sid, card_path, meta))

    # Copy card to artifacts
    shutil.copy(card_path, ARTIFACT_DIR / f"{sid}.png")

print(f"Generated {len(all_cards)} individual shop cards and copied to artifacts.")

# Build Corridor Showcase Posters
CORRIDOR_TITLES = {
    "Gandhi_Nagar_Corridor": "Corridor 1: Gandhi Nagar Commercial & Administrative Corridor (17 Shops)",
    "Ram_Nagar_Jawahar_Nagar": "Corridor 2: Ram Nagar, Jawahar Nagar & Market Spine (15 Shops)",
    "Ramesh_Nagar": "Corridor 3: Ramesh Nagar & Srinivas Talkies Corridor (8 Shops)",
    "Kalyan_Maruthi_Nagar": "Corridor 4: Kalyan Nagar, Maruthi Nagar & South Laxmi Nagar (22 Shops)",
    "Power_House_IB_Colony": "Corridor 5: Power House Colony & IB Colony Northern Artery (9 Shops)",
    "Gouthami_Nagar_FCI": "Corridor 6: Gouthami Nagar, FCI Road & Western Suburbs (14 Shops)",
    "Vittal_Nagar_5Incline": "Corridor 7: Ganesh Nagar, Vittal Nagar, Tilak Nagar & 5 Incline Colony (20 Shops)"
}

generated_posters = []
for c_route, c_cards in cards_by_corridor.items():
    cols = 3
    rows = (len(c_cards) + cols - 1) // cols
    cell_w, cell_h = 960, 560
    sheet_w = cell_w * cols + 40 * (cols + 1)
    sheet_h = 130 + cell_h * rows + 30 * (rows + 1)

    poster = Image.new("RGB", (sheet_w, sheet_h), "#0f1115")
    pdraw = ImageDraw.Draw(poster)

    title_text = CORRIDOR_TITLES.get(c_route, f"Corridor: {c_route} ({len(c_cards)} Shops)")
    pdraw.text((40, 25), "MANA OORU - GODAVARIKHANI COMMERCIAL STOREFRONTS", fill="#38bdf8", font=font_h2)
    pdraw.text((40, 55), title_text, fill="#ffffff", font=font_h1)

    for idx, (csid, cpath, cmeta) in enumerate(c_cards):
        r = idx // cols
        c = idx % cols
        x = 40 + c * (cell_w + 40)
        y = 130 + r * (cell_h + 30)
        cim = Image.open(cpath)
        poster.paste(cim, (x, y))

    poster_file = POSTERS_DIR / f"showcase_{c_route}.png"
    poster.save(poster_file)
    print(f"Saved corridor poster: {poster_file} ({poster.size})")
    shutil.copy(poster_file, ARTIFACT_DIR / f"showcase_{c_route}.png")
    generated_posters.append(poster_file)

# Build Master Multi-Corridor Overview Sheet
master_w, master_h = 3040, 2800
master = Image.new("RGB", (master_w, master_h), "#0b0d11")
mdraw = ImageDraw.Draw(master)
mdraw.text((50, 40), "MANA OORU - GODAVARIKHANI 105 LOCAL BUSINESSES OVERVIEW", fill="#38bdf8", font=font_h2)
mdraw.text((50, 80), "Batch 136-240: 105 Storefront Signs Mounted Across 7 Major Town Neighborhoods", fill="#ffffff", font=font_h1)

sample_sids = [
    "GDK-C100-136", "GDK-C100-141", "GDK-C100-148", # Gandhi Nagar
    "GDK-C100-153", "GDK-C100-156", "GDK-C100-164", # Ram Nagar / Market
    "GDK-C100-165", "GDK-C100-166", "GDK-C100-170", # Ramesh Nagar
    "GDK-C100-174", "GDK-C100-176", "GDK-C100-189", # Kalyan Nagar / Maruthi Nagar
    "GDK-C100-197", "GDK-C100-201", "GDK-C100-204", # Power House / IB Colony
    "GDK-C100-206", "GDK-C100-209", "GDK-C100-214", # Gouthami Nagar / FCI / GM Office
    "GDK-C100-221", "GDK-C100-228", "GDK-C100-234"  # Ganesh Nagar / Vittal Nagar / 5 Incline
]

m_cols = 3
m_cell_w, m_cell_h = 960, 560
for idx, sid in enumerate(sample_sids):
    cpath = CARDS_DIR / f"{sid}.png"
    if not cpath.exists(): continue
    r = idx // m_cols
    c = idx % m_cols
    x = 40 + c * (m_cell_w + 30)
    y = 160 + r * (m_cell_h + 30)
    cim = Image.open(cpath).resize((m_cell_w, m_cell_h), Image.Resampling.LANCZOS)
    master.paste(cim, (x, y))

master_path = POSTERS_DIR / "master_batch_136_240_showcase.png"
master.save(master_path)
shutil.copy(master_path, ARTIFACT_DIR / "master_batch_136_240_showcase.png")
print(f"Saved master showcase poster: {master_path} ({master.size})")

# Launch posters in macOS Preview
try:
    poster_paths = [str(p) for p in generated_posters] + [str(master_path)]
    subprocess.run(["open"] + poster_paths[:4], check=False)
except Exception as e:
    print("Could not auto-open Preview:", e)

print("All visual cards and posters generated and copied to artifact directory!")
