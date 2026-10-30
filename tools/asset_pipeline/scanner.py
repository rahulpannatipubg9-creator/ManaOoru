#!/usr/bin/env python3
"""
tools/asset_pipeline/scanner.py
Finds and extracts 3D assets from ~/Downloads (or a custom path).
Supports single model files (.blend, .fbx, .obj, .gltf, .glb, etc.) and
archives (.zip, .tar, etc.).
"""
import os
import sys
import re
import glob
import shutil
import zipfile
import tarfile
from typing import Dict, Any, Optional, List

SUPPORTED_3D_EXTS = {".blend", ".fbx", ".obj", ".gltf", ".glb", ".dae", ".stl", ".ply", ".usdz", ".usd"}
SUPPORTED_ARCHIVE_EXTS = {".zip", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar"}
TEXTURE_EXTS = {".png", ".jpg", ".jpeg", ".tga", ".webp", ".bmp", ".dds", ".exr", ".hdr"}

def slugify(text: str) -> str:
    """Creates a clean filesystem slug from a filename or title."""
    text = text.lower()
    text = re.sub(r'[\s\-_]+', '_', text)
    text = re.sub(r'[^a-z0-9_]', '', text)
    return text.strip('_') or "custom_asset"

def find_latest_in_directory(dir_path: str) -> Optional[str]:
    """Finds the most recently modified 3D model or archive in a directory."""
    if not os.path.exists(dir_path):
        return None
    candidates = []
    for root, dirs, files in os.walk(dir_path):
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in SUPPORTED_3D_EXTS or ext in SUPPORTED_ARCHIVE_EXTS:
                full_path = os.path.join(root, f)
                candidates.append((os.path.getmtime(full_path), full_path))
        # Don't recurse too deep in walk
        if root != dir_path:
            break
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]

def search_candidate(query: str, search_dir: str) -> Optional[str]:
    """Finds a candidate file matching the query string in search_dir."""
    full_path = os.path.expanduser(query)
    if os.path.exists(full_path):
        return full_path
    
    query_lower = query.lower().strip()
    # Direct match in search_dir
    target_direct = os.path.join(search_dir, query)
    if os.path.exists(target_direct):
        return target_direct

    # Search by prefix or substring
    matches = []
    for item in os.listdir(search_dir):
        ext = os.path.splitext(item)[1].lower()
        if (ext in SUPPORTED_3D_EXTS or ext in SUPPORTED_ARCHIVE_EXTS or os.path.isdir(os.path.join(search_dir, item))):
            if query_lower in item.lower():
                matches.append(os.path.join(search_dir, item))
    
    if matches:
        matches.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        return matches[0]
    return None

def extract_archive(archive_path: str, staging_root: str, slug: str) -> str:
    """Extracts a zip or tar archive into staging directory."""
    dest_dir = os.path.join(staging_root, slug)
    os.makedirs(dest_dir, exist_ok=True)
    ext = os.path.splitext(archive_path)[1].lower()
    
    if ext == ".zip":
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            zip_ref.extractall(dest_dir)
    elif ext in {".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2"}:
        with tarfile.open(archive_path, 'r:*') as tar_ref:
            tar_ref.extractall(dest_dir)
    return dest_dir

def scan_asset(input_path: Optional[str] = None, downloads_dir: Optional[str] = None, staging_root: Optional[str] = None) -> Dict[str, Any]:
    """
    Main scanner entry point.
    Resolves target asset file, stages it if necessary, finds textures and metadata.
    """
    if downloads_dir is None:
        downloads_dir = os.path.expanduser("~/Downloads")
    if staging_root is None:
        staging_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "work", "staging"))
    os.makedirs(staging_root, exist_ok=True)

    target_path = None
    if input_path:
        target_path = search_candidate(input_path, downloads_dir)
        if not target_path:
            raise FileNotFoundError(f"Could not locate 3D asset matching '{input_path}' in '{downloads_dir}' or filesystem.")
    else:
        target_path = find_latest_in_directory(downloads_dir)
        if not target_path:
            raise FileNotFoundError(f"No 3D asset or archive found in {downloads_dir}")

    base_name = os.path.basename(target_path)
    stem, ext = os.path.splitext(base_name)
    ext = ext.lower()
    slug = slugify(stem)

    is_archive = ext in SUPPORTED_ARCHIVE_EXTS
    staging_dir = None
    primary_model = None

    if is_archive:
        staging_dir = extract_archive(target_path, staging_root, slug)
        # Search for model files inside extracted directory
        found_models = []
        for root, _, files in os.walk(staging_dir):
            for f in files:
                m_ext = os.path.splitext(f)[1].lower()
                if m_ext in SUPPORTED_3D_EXTS:
                    full_p = os.path.join(root, f)
                    # Priority score: blend > fbx > glb/gltf > obj
                    priority = {".blend": 4, ".fbx": 3, ".glb": 3, ".gltf": 2, ".obj": 1}.get(m_ext, 0)
                    found_models.append((priority, full_p))
        if not found_models:
            raise ValueError(f"Extracted archive '{base_name}' but found no supported 3D models ({SUPPORTED_3D_EXTS})")
        found_models.sort(key=lambda x: x[0], reverse=True)
        primary_model = found_models[0][1]
    elif os.path.isdir(target_path):
        staging_dir = target_path
        found_models = []
        for root, _, files in os.walk(staging_dir):
            for f in files:
                m_ext = os.path.splitext(f)[1].lower()
                if m_ext in SUPPORTED_3D_EXTS:
                    full_p = os.path.join(root, f)
                    priority = {".blend": 4, ".fbx": 3, ".glb": 3, ".gltf": 2, ".obj": 1}.get(m_ext, 0)
                    found_models.append((priority, full_p))
        if not found_models:
            raise ValueError(f"Directory '{base_name}' contains no supported 3D models")
        found_models.sort(key=lambda x: x[0], reverse=True)
        primary_model = found_models[0][1]
    else:
        # Standalone model file
        primary_model = target_path
        staging_dir = os.path.dirname(target_path)

    # Search for license, readme, info text files
    search_dir_for_meta = staging_dir if is_archive else None
    license_files = []
    texture_files = []
    if search_dir_for_meta and os.path.exists(search_dir_for_meta):
        for root, _, files in os.walk(search_dir_for_meta):
            for f in files:
                f_lower = f.lower()
                f_ext = os.path.splitext(f)[1].lower()
                if any(k in f_lower for k in ["license", "licence", "readme", "info", "credit", "source"]):
                    license_files.append(os.path.join(root, f))
                if f_ext in TEXTURE_EXTS:
                    texture_files.append(os.path.join(root, f))

    license_snippet = None
    if license_files:
        try:
            with open(license_files[0], 'r', errors='ignore') as lf:
                license_snippet = lf.read(500).strip()
        except Exception:
            pass

    return {
        "asset_name": stem.replace('_', ' ').title(),
        "slug": slug,
        "source_path": target_path,
        "is_archive": is_archive,
        "staging_dir": staging_dir,
        "primary_model_path": primary_model,
        "model_ext": os.path.splitext(primary_model)[1].lower(),
        "license_files": license_files,
        "license_snippet": license_snippet,
        "texture_files": texture_files,
    }

if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else None
    result = scan_asset(query)
    print(f"Scanned Asset: {result['asset_name']} ({result['slug']})")
    print(f"Model File:    {result['primary_model_path']}")
    print(f"Textures:      {len(result['texture_files'])} found")
    print(f"License Files: {result['license_files']}")
