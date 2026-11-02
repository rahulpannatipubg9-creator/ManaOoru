#!/usr/bin/env python3
"""Run Godot cluster captures sequentially for batch 136-240.
Keeps memory usage under 400 MB per run on Apple M1 with 8 GB RAM.
"""

import json
import subprocess
import sys
from pathlib import Path

CLUSTERS = ["1", "2", "3", "4", "5", "6", "7", "8"]

def run():
    print("Starting sequential cluster captures for Batch 136-240...")
    out_dir = Path("outputs/shop-images/batch_136_240")
    out_dir.mkdir(parents=True, exist_ok=True)

    for c in CLUSTERS:
        cmd = ["godot", "--disable-vsync", "--path", ".", "--script", "work/shop_labels/capture_cluster_batch_136_240.gd", "--", f"--cluster={c}"]
        print(f"\n--- Launching Batch 136-240 Cluster {c} ---")
        res = subprocess.run(cmd, capture_output=True, text=True)
        lines = res.stdout.splitlines()
        captured_lines = [l for l in lines if "CAPTURED:" in l or "completed!" in l or "Running Capture" in l]
        for l in captured_lines:
            print(" ", l)

        if res.returncode != 0:
            print(f"ERROR: Cluster {c} exited with code {res.returncode}")
            print("\n".join(lines[-15:]))
            print(res.stderr[-500:])
        else:
            print(f"Cluster {c} finished successfully.")

    # Combine all reports into summary.json
    all_reports = []
    for rep_file in sorted(out_dir.glob("report_cluster_*.json")):
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
