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

### Automated 3D asset import & smart placement pipeline (2026-10-30)
- **Problem:** Manual asset conversion required writing one-off scripts, manually stripping lamps, guessing ground origins, fixing mobile polygon budgets, and manually coding placement coordinates in Godot builders.
- **Solution:** Built automated pipeline in `tools/asset_pipeline/pipeline.py` (supported by `scanner.py`, `blender_processor.py`, and `placement_engine.py`) and runtime loader `scripts/world/custom_asset_placements.gd`.
- **Rule:** When downloading new assets to `~/Downloads`, run `python3 tools/asset_pipeline/pipeline.py` or tell the agent "setup this in our game". It purges lights/cameras, aligns ground origin ($Z=0$), enforces triangle budgets, reasons about authentic Godavarikhani district placement, logs to `ASSET_LICENSES.md`, and runs headless Godot verification.
- **Check:** `tests/test_custom_asset_placements.gd` and `tests/movement_regression.gd`.

### Blender lamps in a .glb turned the game white (2026-10-29)
- See [BUILDINGS.md](BUILDINGS.md). Untick lights in the exporter, and strip `Light3D` nodes in the loader anyway.

### Add-on that downloaded the AK-47 was a look-alike (2026-10-29)
- The installed "BlenderKit" add-on names itself "Blendkit" and talks to blendkit.com, not blenderkit.com.
- **Rule:** check where an asset really came from; until then its licence is "not confirmed" in `ASSET_LICENSES.md` and it must be replaced before any public release if it can't be confirmed.

### Ripped content rejected (2026-10-25)
- McLaren F1 (built from NFS/Forza assets) and the "Chubby magic girl" (Daz and Unreal parts) were rejected. A model's own files (info.txt, metadata, action names) often reveal where it came from: read them.
