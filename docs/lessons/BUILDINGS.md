# Buildings, shops and landmarks: lessons

Code: `scripts/world/building_builder.gd`, `imported_city_buildings.gd`, `godavari_bridge_builder.gd`,
storefront allocation (`docs/STOREFRONT_ALLOCATION_FIX.md`), imported exteriors (`docs/imported_city_buildings.md`).

## Adding a building or landmark model

1. Follow [IMPORTING_MODELS.md](IMPORTING_MODELS.md) (no lights or cameras from Blender, real scale, licence).
2. Place it on its real footprint. If the location is not confirmed, keep it in the review scene; don't guess it
   into the city.
3. Give it collision and check the player cannot walk through walls or fall through floors.
4. Look at it in the game from the street at day and night.

## Entries

### Whole game turned white after the bridge was re-exported (2026-10-29)
- **Symptom:** every surface white in the city and in the bridge driving scene.
- **Cause:** `Godavarikhani_Bridge.glb` was exported with Blender's sun lamps (`Sun_KeyLight` 3,551 and
  `Sun_FillLight` 956). A directional light in Godot lights the whole world; the city's own sun is 0.38.
- **Rule:** never export lights or cameras with a model. Both loaders (`godavari_bridge_builder.gd`,
  `godavari_bridge_driving.gd`) now delete any `Light3D` in the bridge; do the same for any new landmark loader.
- **Check:** count the `DirectionalLight3D` nodes after start-up (should be 1, `/root/ManaOoru/Sun`) and take a
  screenshot.

### Bridge vehicle test went stale after the re-export (2026-10-29)
- **Cause:** `tests/test_vehicle_on_bridge.gd` hard-codes the deck height (12.43 m) while the builder now uses
  11.41 m.
- **Rule:** tests read shared numbers from the builder's constants instead of copying them.

### Shop sign floating above a low roof (before 2026-10-29)
- **Rule:** a sign band too short to mount safely is rejected; never place a sign higher than the wall.
  Upper floors never add shop capacity, and unassigned businesses stay map records, not roadside pole signs.

### Placed exteriors are estimates (2026-10-27)
- The five placed Godavarikhani exteriors are matched to footprints by containment or nearest centroid within
  45 m and fitted by uniform scaling: positions and orientation still need a visual check. Dolphin shop row,
  Singareni Super Market and the stadium wait for a confirmed location; don't place them by guesswork.

### City-wide road and building streaming & distant skyline (2026-10-30)
- **Symptom:** Keeping 18,857 buildings and 1,620 road meshes active simultaneously risked mobile Out-Of-Memory (OOM) and massive draw call overhead.
- **Rule:** Road and city streaming uses 250m × 250m spatial grid sectors (GTA Sector System), keeping only the active 3×3 grid around the player mounted in the scene tree. Far distance skyline (500m to 2km) is drawn by a unified low-poly single-mesh town silhouette taking only 1 draw call. Copernicus DEM elevation mesh is chunked with distance and frustum culling.
- **Check:** `movement_regression.gd`, confirm sector streaming mounts roads under player and spawn seamlessly.

### High-speed vehicle driving (130+ km/h) caused streaming hitching and trimesh collision stalls (2026-10-30)
- **Symptom:** Driving at 130 km/h (36 m/s) in vehicles (Thar 4x4, Porsche 911) caused 42ms–48ms micro-stutter spikes on mobile tablets (Xiaomi Pad 7).
- **Cause:** At 36 m/s, vehicles crossed 160m chunk boundaries every 4.4 seconds. Static radial focus meant upcoming chunks were only requested after entering the boundary; building trimesh `ConcavePolygonShape3D` generation and OpenGL buffer uploads choked the main thread. Additionally, unloaded chunks were immediately freed (`queue_free`), causing expensive mathematical re-extrusions on U-turns.
- **Rule:** Streaming focus must be velocity-aware: project focus ahead along the linear velocity vector ($t_{\text{lead}} \le 2.5\text{s}$, up to 100m) so upcoming chunks build in advance. Unloaded chunks are cached in a 50-chunk LRU pool (instantaneous 0.01ms re-attachment via `add_child`), and chunk builds are throttled to at most 1 chunk per frame ($\le 1200\mu\text{s}$).
- **Check:** `tests/movement_regression.gd`, verify streaming lookahead and high-speed driving stability.
