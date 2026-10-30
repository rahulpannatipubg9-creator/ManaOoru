#!/usr/bin/env python3
"""
tools/asset_pipeline/extract_new_downloads.py
Extracts 3D model files from downloaded archives in ~/Downloads into work/staging/new_downloads/
"""
import os
import zipfile
import io

DOWNLOADS = os.path.expanduser("~/Downloads")
STAGING = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "work", "staging", "new_downloads"))
os.makedirs(STAGING, exist_ok=True)

TARGET_DOWNLOADS = [
    {
        "slug": "royal_enfield_bullet",
        "zip_name": "bike-royal-enfield.zip",
        "inner_path": "source/Bike_RE.fbx",
        "tex_path": "textures/DiffuseMap_0.jpeg"
    },
    {
        "slug": "bajaj_avenger_cruise",
        "zip_name": "bajaj-avenger-cruise-200.zip",
        "inner_path": "source/Avenger 2.fbx",
        "tex_dir": "textures"
    },
    {
        "slug": "indian_tgsrtc_bus",
        "zip_name": "indian-bus.zip",
        "inner_path": "source/indian gsrtc bus.fbx"
    },
    {
        "slug": "dodge_charger_f8",
        "zip_name": "dodge-charger-fast-furious-8.zip",
        "inner_path": "source/998.glb"
    },
    {
        "slug": "ferrari_250_testa_rossa",
        "zip_name": "ferrari-250-testa-rossa-wwwvecarzcom.zip",
        "inner_path": "source/Sketchfab_2026_10_23_12_47_42.glb"
    },
    {
        "slug": "alfa_romeo_155_v6",
        "zip_name": "ac-alfa-romeo-155-v6-ti-free.zip",
        "inner_path": "source/Alfa_Romeo_155_V6.fbx"
    },
    {
        "slug": "lamborghini_diablo_sv",
        "zip_name": "1997-lamborghini-diablo-sv-coupe.zip",
        "nested_zip": "source/FINAL_MODEL_SV97.zip",
        "inner_path": "FINAL_MODEL_SV97.fbx"
    },
    {
        "slug": "sa342m_gazelle_helicopter",
        "zip_name": "sa342m-gazelle.zip",
        "inner_path": "source/sa342m_dcs_world.glb"
    }
]

def main():
    print("=" * 70)
    print("   EXTRACTING NEW DOWNLOADED 3D ASSETS FROM ~/Downloads   ")
    print("=" * 70)
    
    extracted = []
    for item in TARGET_DOWNLOADS:
        slug = item["slug"]
        zpath = os.path.join(DOWNLOADS, item["zip_name"])
        if not os.path.exists(zpath):
            print(f"[-] Archive not found: {item['zip_name']}")
            continue
            
        target_dir = os.path.join(STAGING, slug)
        os.makedirs(target_dir, exist_ok=True)
        
        with zipfile.ZipFile(zpath, 'r') as z:
            if "nested_zip" in item:
                nested_data = z.read(item["nested_zip"])
                with zipfile.ZipFile(io.BytesIO(nested_data), 'r') as nz:
                    out_path = os.path.join(target_dir, os.path.basename(item["inner_path"]))
                    with open(out_path, 'wb') as f:
                        f.write(nz.read(item["inner_path"]))
            else:
                out_path = os.path.join(target_dir, os.path.basename(item["inner_path"]))
                with open(out_path, 'wb') as f:
                    f.write(z.read(item["inner_path"]))
                    
            # Extract textures if specified
            if "tex_path" in item and item["tex_path"] in z.namelist():
                tex_out = os.path.join(target_dir, os.path.basename(item["tex_path"]))
                with open(tex_out, 'wb') as f:
                    f.write(z.read(item["tex_path"]))
            if "tex_dir" in item:
                for n in z.namelist():
                    if n.startswith(item["tex_dir"] + "/") and not n.endswith("/"):
                        tex_out = os.path.join(target_dir, os.path.basename(n))
                        with open(tex_out, 'wb') as f:
                            f.write(z.read(n))
                            
        print(f"[+] Extracted {slug}: {os.path.basename(out_path)} ({os.path.getsize(out_path)/(1024*1024):.2f} MB)")
        item["extracted_model"] = out_path
        extracted.append(item)
        
    print(f"\nTotal extracted: {len(extracted)} assets staged at {STAGING}")

if __name__ == "__main__":
    main()
