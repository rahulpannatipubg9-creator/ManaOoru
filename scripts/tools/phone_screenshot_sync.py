#!/usr/bin/env python3
"""
Real-time Moto Phone Screenshot Watcher for MANA OORU
Watches Moto phone (ZA2237Q7B7) for NEW screenshots taken from this moment onward.
- Ignores all past screenshots.
- Pulls new screenshots into game assets: assets/test_only/device_screenshots/
- Also imports them into chat artifacts so they render directly in conversation.
"""

import os
import sys
import time
import json
import shutil
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEST_DIR = PROJECT_ROOT / "assets" / "test_only" / "device_screenshots"
MANIFEST_FILE = DEST_DIR / ".synced_manifest.json"

# Artifact directory for this conversation
CHAT_ARTIFACT_DIR = Path("/Users/rahulpannati/.gemini/antigravity/brain/b310976b-c9c0-4231-b74b-ed0af0fd6d7c")
CHAT_IMAGE_DIR = CHAT_ARTIFACT_DIR / "moto_screenshots"
CHAT_MD_FILE = CHAT_ARTIFACT_DIR / "live_screenshots.md"

MOTO_DEVICE = "ZA2237Q7B7"
SCREENSHOT_DIR = "/sdcard/Pictures/Screenshots"

def run_adb(args, device=MOTO_DEVICE):
    cmd = ["adb", "-s", device] + args
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def load_manifest():
    if MANIFEST_FILE.exists():
        try:
            with open(MANIFEST_FILE, "r") as f:
                return set(json.load(f))
        except Exception:
            return set()
    return set()

def save_manifest(synced_set):
    try:
        with open(MANIFEST_FILE, "w") as f:
            json.dump(sorted(list(synced_set)), f, indent=2)
    except Exception as e:
        print(f"[Watcher] Warning: Failed to save manifest: {e}", flush=True)

def list_device_screenshots():
    success, out, _ = run_adb(["shell", f"ls -1 '{SCREENSHOT_DIR}' 2>/dev/null"])
    if success and out:
        return [f.strip() for f in out.splitlines() if f.strip().lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))]
    return []

def update_chat_artifact(new_files):
    """Updates the chat artifact markdown file with the latest screenshots"""
    CHAT_MD_FILE.parent.mkdir(parents=True, exist_ok=True)
    slides = []
    for f in new_files:
        p = CHAT_IMAGE_DIR / f
        if p.exists():
            slides.append(f"![{f}]({p})")
    
    if not slides:
        return

    carousel_content = "\n<!-- slide -->\n".join(slides)
    content = f"""# 📱 Live Moto Phone Screenshots

New screenshot(s) pulled in real-time from your **moto g86 power 5G**:

````carousel
{carousel_content}
````

### Saved Locations:
- **Game Testing Assets:** `ManaOoru/assets/test_only/device_screenshots/`
- **Chat Gallery:** `moto_screenshots/`
"""
    try:
        with open(CHAT_MD_FILE, "w") as f:
            f.write(content)
    except Exception as e:
        print(f"[Watcher] Error updating artifact: {e}", flush=True)

def watch_loop(poll_interval=1.5):
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    CHAT_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    
    print("=" * 65, flush=True)
    print("🚀 MOTO REAL-TIME SCREENSHOT WATCHER STARTED", flush=True)
    print(f"📱 Target Device: Motorola moto g86 ({MOTO_DEVICE})", flush=True)
    print(f"📁 Game Asset Dir: {DEST_DIR}", flush=True)
    print(f"💬 Chat Artifact Dir: {CHAT_IMAGE_DIR}", flush=True)
    print("=" * 65, flush=True)

    # 1. Baseline: record all existing screenshots so they are IGNORED
    current_shots = list_device_screenshots()
    synced = load_manifest()
    newly_ignored = 0
    for s in current_shots:
        if s not in synced:
            synced.add(s)
            newly_ignored += 1
    save_manifest(synced)

    print(f"[Watcher] Baseline set: {len(current_shots)} existing screenshots ignored.", flush=True)
    print("[Watcher] 🟢 ACTIVE & READY: Take a screenshot on your Moto phone now!\n", flush=True)

    captured_this_session = []

    while True:
        try:
            shots = list_device_screenshots()
            for fname in shots:
                if fname not in synced:
                    remote_path = f"{SCREENSHOT_DIR}/{fname}"
                    local_game_path = DEST_DIR / fname
                    local_chat_path = CHAT_IMAGE_DIR / fname
                    
                    print(f"\n[Watcher] 📸 NEW SCREENSHOT DETECTED: {fname}", flush=True)
                    success, _, err = run_adb(["pull", remote_path, str(local_game_path)])
                    if success:
                        print(f"          ✅ Saved to Game Assets: assets/test_only/device_screenshots/{fname}", flush=True)
                        shutil.copy2(local_game_path, local_chat_path)
                        captured_this_session.append(fname)
                        update_chat_artifact(captured_this_session)
                        print(f"          🖼️ Added to Chat: {local_chat_path}", flush=True)
                        synced.add(fname)
                        save_manifest(synced)
                    else:
                        print(f"          ❌ Error pulling screenshot: {err}", flush=True)
            time.sleep(poll_interval)
        except KeyboardInterrupt:
            print("\n[Watcher] Stopped.", flush=True)
            break
        except Exception as e:
            print(f"[Watcher] Error: {e}", flush=True)
            time.sleep(poll_interval)

if __name__ == "__main__":
    watch_loop()
