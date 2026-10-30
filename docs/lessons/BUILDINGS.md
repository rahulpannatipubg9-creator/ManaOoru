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
