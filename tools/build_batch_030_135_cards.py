#!/usr/bin/env python3
"""Build showcase cards and corridor posters for Batch 030-135 shops.
Crops high-contrast signboard text, attaches metadata badges,
generates corridor showcase sheets, and copies to artifacts.
"""

import csv
import json
import os
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ARTIFACT_DIR = Path("/Users/rahulpannati/.gemini/antigravity/brain/0ed1dfb8-1e90-4ece-a247-5639e10fde6d")
OUT_DIR = Path("outputs/shop-images/batch_030_135")
CROPS_DIR = OUT_DIR / "crops"
CARDS_DIR = OUT_DIR / "cards"
POSTERS_DIR = OUT_DIR / "posters"

CROPS_DIR.mkdir(parents=True, exist_ok=True)
CARDS_DIR.mkdir(parents=True, exist_ok=True)
POSTERS_DIR.mkdir(parents=True, exist_ok=True)

# Load metadata from TSV
tsv_path = Path("data/survey/survey_batch_030_135.tsv")
meta_map = {}
with open(tsv_path, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    for row in reader:
        sid = row["shop_id"].strip()
        route = ""
        for p in row.get("notes", "").split(";"):
            if p.startswith("route="):
                route = p.replace("route=", "").strip()
        meta_map[sid] = {
            "shop_id": sid,
            "name": row["name"].strip(),
            "category": row["category"].strip(),
            "address": row["address"].strip(),
            "lat": float(row["latitude"]) if row["latitude"] else 0.0,
            "lon": float(row["longitude"]) if row["longitude"] else 0.0,
            "godot_x": float(row["godot_x_m"]) if row["godot_x_m"] else 0.0,
            "godot_z": float(row["godot_z_m"]) if row["godot_z_m"] else 0.0,
            "route": route
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
        "route": "Godavarikhani",
        "godot_x": 0.0,
        "godot_z": 0.0
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
    route_name = meta["route"].replace("_", " ")
    pos_str = f"Godot World: ({meta['godot_x']:.1f}m, {meta['godot_z']:.1f}m) | Corridor: {route_name} | {meta['address'][:45]}"
    draw.text((25, footer_y + 8), pos_str, fill="#94a3b8", font=font_sub)

    card_path = CARDS_DIR / f"{sid}.png"
    card.save(card_path)
    all_cards.append((sid, card_path, meta))
    cards_by_corridor.setdefault(meta["route"], []).append((sid, card_path, meta))

    # Copy card to artifacts
    shutil.copy(card_path, ARTIFACT_DIR / f"{sid}.png")

print(f"Generated {len(all_cards)} individual shop cards and copied to artifacts.")

# Build Corridor Showcase Posters
CORRIDOR_TITLES = {
    "Chowrasta_to_New_Ashok_Theatre": "Corridor 1: Chowrasta to New Ashok Theatre (15 Shops)",
    "Chowrasta_to_Rajesh_Theatre_candidate": "Corridor 2: Chowrasta to Old Ashok & Rajesh Theatre Axis (18 Shops)",
    "Rajesh_Theatre_to_Markandeya_Colony": "Corridor 3: Markandeya Colony & Hospital Commercial Spine (28 Shops)",
    "Addaguntapalli": "Corridor 4: Addaguntapalli & FCI X Road Hub (6 Shops)",
    "Medhari_Basthi_and_Onion_Bazar": "Corridor 5: Medhari Basthi & Onion Bazar Commercial Line (23 Shops)",
    "Chowrasta_to_Market_and_1_Town_PS_candidate": "Corridor 6: Daily Market, 1 Town Police Station & Ram Nagar (16 Shops)"
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

# Build Master Multi-Corridor Overview Sheet (1 card representative per cluster / master summary)
master_w, master_h = 3040, 2400
master = Image.new("RGB", (master_w, master_h), "#0b0d11")
mdraw = ImageDraw.Draw(master)
mdraw.text((50, 40), "MANA OORU - GODAVARIKHANI 106 LOCAL BUSINESSES OVERVIEW", fill="#38bdf8", font=font_h2)
mdraw.text((50, 80), "Batch 030-135: 106 Storefront Signs Mounted Across 6 Godavarikhani Corridors", fill="#ffffff", font=font_h1)

sample_sids = [
    "GDK-C100-030", "GDK-C100-031", "GDK-C100-032", # C1 New Ashok
    "GDK-C100-052", "GDK-C100-055", "GDK-C100-059", # C2 Old Ashok & Laxmi Nagar
    "GDK-C100-045", "GDK-C100-064", "GDK-C100-085", # C3 Markandeya & Rajesh
    "GDK-C100-091", "GDK-C100-093", "GDK-C100-096", # C4 Addaguntapalli
    "GDK-C100-099", "GDK-C100-101", "GDK-C100-104", # C5 Medhari Basthi
    "GDK-C100-120", "GDK-C100-121", "GDK-C100-125"  # C6 Daily Market & 1 Town
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

master_path = POSTERS_DIR / "master_batch_030_135_showcase.png"
master.save(master_path)
shutil.copy(master_path, ARTIFACT_DIR / "master_batch_030_135_showcase.png")
print(f"Saved master showcase poster: {master_path} ({master.size})")

print("All visual cards and posters generated and copied to artifact directory!")
