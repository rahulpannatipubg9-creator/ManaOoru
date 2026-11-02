#!/usr/bin/env python3
"""Run Godot corridor captures sequentially for batch 030-135.
Keeps memory usage under 400 MB per run on Apple M1.
"""

import json
import subprocess
import sys
from pathlib import Path

CORRIDORS = ["c2", "c3", "c4", "c5", "c6"]

def run():
    print("Starting sequential corridor captures...")
    for c in CORRIDORS:
        cmd = ["godot", "--path", ".", "--script", "work/shop_labels/capture_corridor.gd", "--", f"--corridor={c}"]
        print(f"\n--- Launching Corridor {c} ---")
        res = subprocess.run(cmd, capture_output=True, text=True)
        # Filter and print essential lines
        lines = res.stdout.splitlines()
        for line in lines:
            if "CAPTURED:" in line or "done!" in line or "Storefront allocation:" in line or "Running Capture" in line:
                print(" ", line)
        if res.returncode != 0:
            print(f"ERROR: Corridor {c} exited with code {res.returncode}")
            print(res.stderr[-500:])
        else:
            print(f"Corridor {c} finished successfully.")

    # Combine all reports into summary.json
    all_reports = []
    out_dir = Path("outputs/shop-images/batch_030_135")
    for rep_file in sorted(out_dir.glob("report_*.json")):
        try:
            data = json.loads(rep_file.read_text())
            all_reports.extend(data)
        except Exception as e:
            print(f"Error reading {rep_file}: {e}")

    summary_file = out_dir / "summary.json"
    summary_file.write_text(json.dumps(all_reports, indent=2))
    print(f"\nCombined summary written to {summary_file} with {len(all_reports)} captures.")

if __name__ == "__main__":
    run()
