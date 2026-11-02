import pathlib
import shutil
import struct
import subprocess
import zipfile

SOURCE = pathlib.Path("builds/ManaOoru-pad7-benchmark-unsigned.apk")
ALIGNED_TMP = pathlib.Path("builds/ManaOoru-pad7-aligned-tmp.apk")
ALIGNED = pathlib.Path("builds/ManaOoru-pad7-aligned.apk")
FINAL = pathlib.Path("builds/ManaOoru-pad7-benchmark.apk")
ZIPALIGN = "/Users/rahulpannati/Library/Android/sdk/build-tools/35.0.0/zipalign"
APKSIGNER = "/Users/rahulpannati/Library/Android/sdk/build-tools/35.0.0/apksigner"
KEYSTORE = pathlib.Path("builds/manaooru-release.keystore")

# Build new _cl_ containing the android_probe_boot.tscn scene
raw_args = [
    b"res://scenes/performance/android_probe_boot.tscn",
    b"--xr_mode_regular",
    b"--xr-mode",
    b"off",
    b"--fullscreen",
    b"--background_color",
    b"#000000"
]
cl_data = struct.pack("<I", len(raw_args)) + b"".join(struct.pack("<I", len(a)) + a for a in raw_args)

replacements = {
    "assets/_cl_": cl_data,
    "assets/scripts/world/custom_asset_placements.gd": pathlib.Path("scripts/world/custom_asset_placements.gd").read_bytes(),
}

print("Creating patched unsigned APK...")
with zipfile.ZipFile(SOURCE, "r") as old_zip, zipfile.ZipFile(ALIGNED_TMP, "w", allowZip64=False) as new_zip:
    for item in old_zip.infolist():
        if item.filename in replacements:
            continue
        if item.filename.startswith("META-INF/") and item.filename.endswith((".RSA", ".DSA", ".EC", ".SF", ".MF")):
            continue
        with old_zip.open(item) as s, new_zip.open(item, "w") as d:
            shutil.copyfileobj(s, d, 1024 * 1024)
    
    for name, data in replacements.items():
        comp = zipfile.ZIP_STORED if name == "resources.arsc" else zipfile.ZIP_DEFLATED
        new_zip.writestr(name, data, compress_type=comp)

print("Running zipalign...")
subprocess.run([ZIPALIGN, "-p", "-f", "4", str(ALIGNED_TMP), str(ALIGNED)], check=True)
ALIGNED_TMP.unlink(missing_ok=True)

print("Signing with apksigner...")
subprocess.run([
    APKSIGNER, "sign",
    "--ks", str(KEYSTORE),
    "--ks-pass", "pass:manaooru2026",
    "--ks-key-alias", "manaooru",
    "--out", str(FINAL),
    str(ALIGNED)
], check=True)
ALIGNED.unlink(missing_ok=True)

print("Verifying final APK...")
subprocess.run([APKSIGNER, "verify", str(FINAL)], check=True)
print("SUCCESS: Benchmark APK ready at", FINAL)
