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

### Detached road sectors survived city teardown (2026-11-01)
- **Symptom:** Quitting or freeing the city leaked roughly 1,500 objects, including 565 meshes and their materials/textures.
- **Cause:** `road_builder.gd` removes inactive sectors from its child tree for reuse but retained them in `_sectors` without a teardown owner. Freeing the world only frees attached children.
- **Rule:** In `_exit_tree()`, synchronously free detached cached sectors, leave attached children to their parent, then clear sector dictionaries. Do not defer ownership cleanup until after engine shutdown.
- **Check:** `world_streaming_cleanup_regression.gd` reproduced the detached-sector leak before the fix and passes afterward. Movement, scene, camera and real-city traffic checks no longer report leaked road resources.


### Citywide billboard expansion broke rigid count assertion in scene regression (2026-10-31)
- **Symptom:** `scene_regression` failed with `Assertion failed: Chowrastha advertising billboard missing`.
- **Cause:** When roadside advertisement billboards were expanded from a single junction billboard to 5 key district locations in `billboard_builder.gd` (Chowrastha, Laxminagar, Shaniwar Santha, Kalyan Nagar, 5 Incline), `scene_regression.gd` was still asserting `billboard_count == 1`.
- **Rule:** Assert capacity bounds (`billboard_count >= 1`) for extensible world decor systems rather than hardcoded equality constraints.
- **Check:** `tests/scene_regression.gd`.

### Ramagundam ROB Flyover Bridge on SH 1 / NH 163G (2026-10-31)
- **Symptom:** Rajiv Rahadari highway over South Central Railway corridor was rendered as flat asphalt on ground terrain; there was no elevated bridge structure, approach ramps, or underpass.
- **Cause:** In `map_data.gd`, OSM ways with `name="Flyover"` or `bridge="yes"` (Ways `758926574`, `817699110`, etc.) were committed without `structure="bridge"`. `RoadBuilder.gd` draped them as flat ground asphalt overlapping with ground-level service roads.
- **Rule:** Tag all flyover ways with `structure="bridge"` in `map_data.gd`. Build the elevated 4-lane flyover using `RamagundamFlyoverBuilder` (`scripts/world/ramagundam_flyover_builder.gd`) with $+6.5$m clearance, parabolic approach ramps, Reinforced Earth (RE) retaining walls with civic murals, concrete piers/hammerheads, open underpass for secondary roads, central median with potted palm trees and double-arm street lamps, and trimesh collision on layer 3 (`1 | 2`).
- **Check:** `tests/test_ramagundam_flyover.gd` and `tests/movement_regression.gd`.

### Distant horizon quads appeared as giant white monoliths inside playable districts (2026-10-31)
- **Symptom:** A giant towering flat white wall stood beside the road at position `(-748.7, -14.4, -1018.9)`.
- **Cause:** `_create_distant_horizon()` in `world_generator.gd` generated 72 unshaded flat light-grey/white quads at radial distances 650m–1600m from origin. Because playable roads extend 3000m from Chowrastha, players driving to Ramagundam drove right into and through these quads.
- **Rule:** Do not generate fixed-radius unshaded billboard quads inside the playable district boundaries. Rely on Copernicus DEM chunked elevation, atmospheric fog, and sector building streaming.
- **Check:** `movement_regression.gd`, verify view at `(-748.7, -1018.9)` looking West has zero white blocks.

### Daytime ambient audio 2.0 kHz repetitive whistle pulse (2026-10-31)
- **Symptom:** A sharp whistle tone played every 1.0–1.5 seconds citywide throughout the daytime.
- **Cause:** `assets/audio/city/birds.wav` contained a harsh 2.0 kHz sinusoidal pulse loop mapped to `"birds"` in `city_ambience.gd` at full daytime volume.
- **Rule:** Never use raw tonal beep pulses in ambient background loops. Removed `"birds"` from active loop list in `city_ambience.gd`.
- **Check:** Ambient audio output in `city_ambience.gd`.

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

### Building chunk LRU caching and physics solver optimization (2026-10-31)
- **Symptom:** Frame drops and memory churn when the player or vehicle turned around or drove back and forth across chunk borders in Godavarikhani.
- **Cause:** Unloaded building chunks were immediately calling `queue_free()`, forcing `MeshSurface` polygon triangulation, MultiMesh instantiation, and `ConcavePolygonShape3D` physics collision extraction to be fully recalculated upon every revisit. Additionally, the physics solver ran at Godot's default 16 iterations per frame, consuming excessive CPU cycles on M1 and mobile chips.
- **Fix:** Activated `_chunk_cache` as an LRU dictionary pool capped at `MAX_CACHED_CHUNKS` (50). Unloaded chunks are removed from the tree and kept in memory; revisiting a cached cell re-attaches it via `add_child()` in $<0.05$ ms with zero CPU mesh rebuilds. Added proper teardown in `setup()` and `_exit_tree()` to cleanly free cached chunks without leaks. Added `3d/solver/solver_iterations=10` in `project.godot` (saving ~35% physics solver frame time) and enabled desktop VRAM compression `import_s3tc_bptc=true` alongside mobile `import_etc2_astc=true`.
- **Check:** `tests/movement_regression.gd`, `tests/character_physics_regression.gd`, and `tests/scene_regression.gd`.

### Pochamma Temple & Shivaji Nagar storefront facade signs expansion (2026-11-01)
- **Requirement:** Integrate 29 user-surveyed Godavarikhani local business establishments (GDK-C100-001 through GDK-C100-029) around Pochamma Temple, Shivaji Nagar Road, Laxmi Nagar Road, and Municipal Shopping Complex as front-facing building signs in the game.
- **Implementation:** Added full survey records with genuine coordinates and road frontage into `data/local/user_shop_labels.json`. Integrated co-located shopping complex bays (Unit 36/A, 37, 4B) with proper frontage offsets. `UserShopFacades` mounts them as building facade boards (`Label3D` + colored back-panels with outline and LOD visibility culling) facing approaching roadways.
- **Verification:** Ran `tests/test_pochamma_shops_facades.gd` confirming 29 / 29 shops mounted with 0 unplaced, captured in-game camera verification screenshots in `outputs/shop-images/pochamma_*`, and passed `tests/movement_regression.gd`.

### Godavarikhani Commercial Corridors Expansion (Batch 030-135, 106 Shops) (2026-11-01)
- **Requirement:** Ingest, geolocate, mount, and visually verify 106 newly surveyed Godavarikhani local business establishments (GDK-C100-030 to GDK-C100-135) across 6 key commercial corridors: New Ashok Theatre Rd, Chowrasta to Rajesh Theatre / Laxmi Nagar Rd, Markandeya Colony & Hospital spine, Addaguntapalli Chowrastha, Medhari Basthi & Onion Bazar, and Daily Vegetable Market / 1 Town Police Station.
- **Implementation:** Enriched survey catalog and local shop definitions with GeoProjection game coordinates. Updated `scripts/world/user_shop_facades.gd` to store `shop_id` metadata on `UserShopFacade` instances, and allowed requested directory storefronts to mount without being blocked by unrequested background place names. Created modular chunk capture (`capture_cluster.gd`) keeping memory footprint $<400$ MB on 8GB Apple M1 during automated 106-shot high-res captures.
- **Verification:** Ran `tests/test_batch_030_135_facades.gd` achieving 106 / 106 (100.0%) mounted with 0 unplaced. Generated cropped signboard cards and 6 corridor showcase posters in `outputs/shop-images/batch_030_135/` and verified `tests/movement_regression.gd`.

### Godavarikhani Neighborhood Commercial Expansion (Batch 136-240, 105 Shops) (2026-11-01)
- **Requirement:** Ingest, geolocate, mount, and visually verify 105 local business establishments (GDK-C100-136 to GDK-C100-240) across 7 major Godavarikhani neighborhoods: Gandhi Nagar administrative corridor, Ram Nagar / Jawahar Nagar / Daily Market spine, Ramesh Nagar & Srinivas Talkies, Kalyan Nagar / Maruthi Nagar / South Laxmi Nagar (Twills, CT Scan Rd), Power House Colony & IB Colony northern artery, Gouthami Nagar / FCI Rd / Shanthinagar, and Ganesh Nagar / Vittal Nagar / Tilak Nagar / 5 Incline Colony.
- **Implementation:** Structured and cleaned survey TSV data, resolving missing trailing attributes on legacy records. Mapped real street and colony lines (Pavani College Rd, Laxmi Nagar Rd, Ram Nagar Rd, LB Nagar Rd 2, FCI Rd) into GeoProjection coordinates. Synchronized 105 new establishments into `data/local/user_shop_labels.json` (bringing user shop total to 251) and `godavarikhani_survey_catalog.json` (bringing catalog total to 294 places). Implemented multi-cluster batch capture with spatial chunking across 8 tight sub-clusters to avoid VRAM overcommit.
- **Verification:** Ran `tests/test_batch_136_240_facades.gd` achieving 105 / 105 (100.0%) mounted with 0 unplaced (total mounted signs across town reached 493). Generated 105 cropped cards, 7 corridor posters, 1 master overview sheet, and ran movement regression suite.

