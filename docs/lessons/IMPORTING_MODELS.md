# Importing Models & 3D Asset Pipeline Reference

This document is the standard operating reference for importing, testing, and placing 3D models into **ManaOoru** (BlenderKit, Sketchfab, CGTrader, custom downloads, or procedural models).

---

## 1. Quick Reference: "Setup this in our game"

Whenever you download a 3D asset to your laptop (usually saved in `~/Downloads` as a `.blend`, `.fbx`, `.obj`, `.gltf`, `.glb`, or `.zip` archive), simply say to the agent:

> **"Setup this in our game"**  
> *(or "Setup the downloaded asset", "Setup ~/Downloads/banana_plant.obj in our game")*

The automated pipeline executes the entire workflow:
1. **Intake & Unpack:** Finds the asset in `~/Downloads` and unpacks archives into `work/staging/`.
2. **Blender Testing & Optimization:** Runs headless Blender to validate geometry, enforce triangle budgets, purge lamps/cameras, align ground origin, and export a clean `.glb`.
3. **Smart District Reasoning:** Decides the most authentic Godavarikhani location based on asset tags, physical dimensions, and urban context.
4. **Game Integration:** Updates `data/world/custom_placements.json` and logs license in `ASSET_LICENSES.md`.
5. **Headless Verification:** Verifies placement, collision, and ground contact in Godot without regressions.

To run the pipeline manually via script:
```bash
# Auto-detect latest download in ~/Downloads
python3 tools/asset_pipeline/pipeline.py

# Or specify a file:
python3 tools/asset_pipeline/pipeline.py --input "broken bricks.fbx"

# Or override target district:
python3 tools/asset_pipeline/pipeline.py --input "my_bench.obj" --location ambedkar_park
```

---

## 2. Model Preparation & Blender Checklist

Every imported model must satisfy these rules before entering the game world:

1. **Licence first:** Record source, author, and licence in `ASSET_LICENSES.md` before using the model. No ripped game content.
2. **Purge all lights & cameras:** Untick and strip all `LIGHT` and `CAMERA` objects. *(Blender lamps in a GLB turn the entire Godot world blinding white!)*
3. **Enforce triangle budgets:**
   - **Props / Furniture / Debris:** $\le 15,000$ triangles (check `docs/PERFORMANCE_BUDGETS.md`).
   - **Vehicles:** $\le 50,000$ triangles.
   - **Buildings:** $\le 60,000$ triangles.
   - If over budget, the automated pipeline applies a Decimate modifier to safeguard Apple M1 (8 GB RAM) and mobile devices.
4. **Origin where it touches the world:**
   - **Ground props, buildings, foliage, vehicles:** Bottom rests at $Z=0$ (ground plane), centered at $(X=0, Y=0)$.
   - **Weapons:** Origin placed at pistol/rifle grip.
   - **Characters:** Origin placed at soles of feet.
5. **Real-world scale (Meters):** Apply all scale and rotation transforms in Blender ($1.0 = 1\text{ meter}$). glTF exporter handles Y-up automatically; do not counter-rotate in Godot.
6. **Standardized PBR Materials:** Ensure Principled BSDF with clean roughness/metallic ranges.

---

## 3. Intelligent World Placement System

The placement reasoner (`tools/asset_pipeline/placement_engine.py`) evaluates model geometry, dimensions $(W \times D \times H)$, and semantic tags to place the asset in its most authentic Godavarikhani district:

| District / Location Key | Description | Best Suited Assets | Target Coordinates & Orientation |
|---|---|---|---|
| **Market Street**<br>`market_street` | Saturday Market & commercial bazaar strip | Food stalls, fruit/vegetable carts, tea stalls, *haathgaadi*, panipuri stands, market umbrellas, produce crates | Near $(108, -32)$<br>Footpath facing street (Yaw $180^\circ$) |
| **Vidyanagar Residential**<br>`vidyanagar_residential` | Authentic Telangana residential colony (Road No. 2) | Banana trees, garden shrubs, residential houses, compound gates, domestic Sintex water tanks, parked family SUVs | Near $(318, -330)$<br>Driveway / front yard (Yaw $-45^\circ$) |
| **Coal Mine OCP 5 Incline**<br>`coal_mine` | Singareni Collieries open cast mining sector | Broken bricks, rock/rubble piles, mining haul trucks, winding/slippery warning signs, high-voltage pylons | Near $(1540, 1380)$<br>Quarry verge (Yaw $35^\circ$) |
| **Godavari River Bridge**<br>`godavari_bridge` | 4-lane arterial highway bridge spanning to Mancherial | Metal crash barriers, speed limit signs, highway trucks, bridge floodlights, road dividers | Near $(755, -3290)$<br>Bridge shoulder (Yaw $90^\circ$) |
| **Dr. B.R. Ambedkar Park**<br>`ambedkar_park` | Central civic recreation park | Park benches, ornamental trees, flowering bushes, stone fountains, sculptures, litter bins | Near $(-185, -120)$<br>Lawn / path border (Yaw $0^\circ$) |
| **Hotel Sai Leela**<br>`sai_leela_hotel` | Premier hospitality venue & restaurant | Modular sofas, lounge chairs, courtyard swimming pool items, patio tables, dining furniture | Near $(-220, 180)$<br>Lobby / courtyard (Yaw $0^\circ$) |
| **Chowrastha Junction**<br>`chowrasta` | Bustling central urban crossroads | Traffic police booths, auto rickshaws, municipal streetlights, commercial billboards, city benches | Near $(15, 12)$<br>Junction sidewalk (Yaw $90^\circ$) |
| **TGSRTC Bus Station**<br>`bus_station` | Intercity public transit hub | Passenger buses, waiting shed benches, route signage, ticket kiosks | Near $(-720, 240)$<br>Platform edge (Yaw $45^\circ$) |

---

## 4. Godot Runtime Integration & Safety Rules

Custom assets are recorded in [`data/world/custom_placements.json`](file:///Users/rahulpannati/Downloads/AI%20Agents%20Practice/ManaOoru/data/world/custom_placements.json) and dynamically instantiated at runtime by [`scripts/world/custom_asset_placements.gd`](file:///Users/rahulpannati/Downloads/AI%20Agents%20Practice/ManaOoru/scripts/world/custom_asset_placements.gd):

- **Terrain Height Probing:** Ground height is resolved dynamically using `world.ground_height(Vector2(x, z))` with a $+0.02\text{ m}$ safety offset. No asset is left floating in the air or buried in terrain.
- **Visibility Range Assignment:**
  > [!IMPORTANT]
  > Never assign `visibility_range_end` directly to the instantiated root `Node3D`. Always iterate through child `GeometryInstance3D` nodes using:
  > ```gdscript
  > for geom in instance.find_children("*", "GeometryInstance3D", true, false):
  >     (geom as GeometryInstance3D).visibility_range_end = 250.0
  > ```
- **Static Collision:** Automatically creates `trimesh` static colliders for props/debris, `BoxShape3D` for vehicles/furniture, or `CylinderShape3D` for tree trunks and poles.

---

## 5. Entries & Lessons Learned

### Decimating monolithic arena compounds for zero-lag open-world exploration (2026-11-01)
- **Symptom:** Community / Sketchfab map compounds (like PUBG/BGMI TDM warehouse arenas) exceed 1.3M - 1.5M triangles, creating severe frame-rate drops or out-of-memory crashes on Apple M1 (8GB) and budget mobile devices when placed in open-world city maps.
- **Cause:** Raw map assets contain high subdivision bevels on every corrugated sheet, fence post, bolt, and container ridge.
- **Rule:** Decimate monolithic arena compounds by 95%+ in Blender down to $\le 70,000$ triangles, strip internal cameras/lights, and set visibility distance limits (`visibility_range_end = 250.0m`). This allows players to roam seamlessly around adjacent areas (such as the Godavari River Bridge) with zero lag, while preserving full physical trimesh collision for exploration and tactical combat.
- **Check:** `tests/test_custom_asset_placements.gd` and `tests/movement_regression.gd`.

### Automated 3D asset import & smart placement pipeline (2026-10-30)
- **Problem:** Manual asset conversion required writing one-off scripts, manually stripping lamps, guessing ground origins, fixing mobile polygon budgets, and manually coding placement coordinates in Godot builders.
- **Solution:** Built automated pipeline in `tools/asset_pipeline/pipeline.py` (supported by `scanner.py`, `blender_processor.py`, and `placement_engine.py`) and runtime loader `scripts/world/custom_asset_placements.gd`.
- **Rule:** When downloading new assets to `~/Downloads`, run `python3 tools/asset_pipeline/pipeline.py` or tell the agent "setup this in our game". It purges lights/cameras, aligns ground origin ($Z=0$), enforces triangle budgets, reasons about authentic Godavarikhani district placement, logs to `ASSET_LICENSES.md`, and runs headless Godot verification.
- **Check:** `tests/test_custom_asset_placements.gd` and `tests/movement_regression.gd`.

### Unparenting hierarchies & clearing transforms before scale normalization (2026-10-31)
- **Problem:** In complex FBX models (e.g. Diablo SV, Ford Roush Mustang, Bajaj Avenger), mesh parts were parented to Armatures or Empties with fractional local transforms (`scale=(0.01, 0.01, 0.01)` or `(20, 20, 20)`). Applying transforms or scaling parent and child nodes simultaneously caused cascading exponential scale errors (producing 65-meter supercars).
- **Solution:** In Blender headless pipeline, execute `bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")` on all objects first, delete all non-mesh nodes (Armatures, Empties, Lights, Cameras), then execute `transform_apply(location=True, rotation=True, scale=True)`. Then compute world bounds, calculate true metric scaling factor, ground $Z=0$, and decimate.
- **Rule:** Never scale objects while nested under parent transforms or armatures. Always clear parent while preserving world transforms before measuring bounds or applying scale normalization.

### Pruning basement/staging accessory clusters (2026-10-31)
- **Problem:** The Bajaj Avenger Cruise FBX had 84 spare/duplicate parts staged in an extra empty (`B_Extra`) located at $Z=-6.0\text{ m}$ below the ground, expanding model bounding box from 1.4 m to 7.4 m height.
- **Solution:** Automated filter detects and prunes meshes whose vertices reside $>2.0\text{ m}$ below the lowest primary contact plane, isolating the authentic vehicle hull.

### Multi-level archive intake & .gdignore in staging (2026-10-31)
- **Problem:** Sketchfab downloads wrap models inside nested zip archives (up to 3 levels: `outer.zip` -> `source/inner.zip` -> `model.zip`), occasionally containing bundled `.exe` binaries. Furthermore, extracting large raw staging files directly into `work/staging/` caused the Godot Editor to freeze for minutes attempting to import 90MB uncompressed raw source models.
- **Solution:** Multi-tier zip extraction unzips only pure 3D formats (`.fbx`, `.obj`, `.glb`, `.gltf`) while rejecting binaries (`.exe`). Added `.gdignore` inside `work/` to completely exclude raw staging folders from Godot project import scans, ensuring only optimized game assets under `assets/models/` are processed.

### Blender lamps in a .glb turned the game white (2026-10-29)
- See [BUILDINGS.md](BUILDINGS.md). Untick lights in the exporter, and strip `Light3D` nodes in the loader anyway.

### Add-on that downloaded the AK-47 was a look-alike (2026-10-29)
- The installed "BlenderKit" add-on names itself "Blendkit" and talks to blendkit.com, not blenderkit.com.
- **Rule:** check where an asset really came from; until then its licence is "not confirmed" in `ASSET_LICENSES.md` and it must be replaced before any public release if it can't be confirmed.

### Ripped content rejected (2026-10-25)
- McLaren F1 (built from NFS/Forza assets) and the "Chubby magic girl" (Daz and Unreal parts) were rejected. A model's own files (info.txt, metadata, action names) often reveal where it came from: read them.

### Transformed/Centimeter FBX AABBs causing gigantic world-spanning colliders (2026-10-31)
- **Symptom:** In `tests/movement_regression.gd`, the player and tuk-tuk were launched into the void with assertion failure: `Player Tuk Tuk must start within interaction range`.
- **Cause:** Raw FBX models exported from 3ds Max/V-Ray often retain 0.001 scale transforms or centimeter mesh bounding boxes (e.g. 4,357 mm). When `custom_asset_placements.gd` calculated bounding boxes using raw un-transformed `mesh.get_aabb()`, the resulting BoxShape3D was 4,357 meters wide—spanning across the entire city and swallowing the spawn point.
- **Rule:** `_setup_collision` in `custom_asset_placements.gd` must prioritize verified real-world metric dimensions from `data.metadata.dimensions` (width_x, depth_y, height_z). When calculating AABB from child meshes, it must transform by the relative hierarchy transform to root (`t * box`) and clamp sizes to sane physical bounds ($\le 30\text{ m}$).
- **Check:** `tests/test_custom_asset_placements.gd` and `tests/movement_regression.gd`.
