# Trees, ground cover and props: lessons

Anything placed on the ground: trees, stalls, carts, pickups, poles, drains, cover in the arena.

## Placing something on the ground

1. Probe the ground with a ray from above (after buildings and cars are in the physics world: wait two physics
   frames) and keep it only on level ground near the expected height.
2. Probe for overlap with a shape so it never ends up inside a building, a parked car or a wall.
3. Keep it static and identically placed on every device when it matters in a match (TDM cover).
4. Look at it from the street: not floating, not sunk, not blocking a doorway or the road.

## Entries

### Main thread tree scattering and unbatched street props caused draw call and frame spikes (2026-11-02)
- **Symptom:** Peak draw calls reached 2,160+ and frame times stuttered when entering tree-heavy arterial corridors at 120+ km/h on Xiaomi Pad 7.
- **Cause:**
  1. `TreeBuilder` evaluated tree points, road clearance envelope checks, and terrain elevation queries inside `_process()` on the main thread.
  2. Loose street props (384 utility poles, 491 shop facade backings) and distant font labels/pedestrian meshes were instanced as individual `MeshInstance3D` nodes without mobile distance culling.
- **Rule:**
  1. Move tree chunk filtering and transform generation to `WorkerThreadPool` worker threads (`TreeBuilder._worker_scatter_chunk`); commit `MultiMesh` instances on the main thread.
  2. Batch repeated street props into single `MultiMeshInstance3D` nodes (e.g. `UserShopPanelsMultiMesh` for facade boxes, `UtilityPolesMultiMesh` for street poles).
  3. Enforce mobile visibility culling (`visibility_range_end = 45.0`) on all `Label3D` roadside signs and ambient pedestrian limbs/hair meshes (`scripts/world/pedestrian.gd`).
- **Check:** `tools/performance/pad7_chowrasta_high_speed_probe.gd` on Xiaomi Pad 7 (`model: 2410CRP4CI`): p95 draw calls dropped from 1,579 to 806; idle draw calls dropped to 494; sustained 120+ km/h frame rate jumped from 16.5 FPS to 51.4 FPS (58.8 FPS post-drive).

### Tree generation continued across the entire district during play (2026-11-02)
- **Symptom:** M1 profiling found tree callbacks consuming about 553 ms per second, including a 49 ms callback, despite selecting a short view distance.
- **Cause:** `TreeBuilder._pending` contained every map cell. `_process()` only sorted that global queue and built whole chunks without yielding inside a chunk; distant foliage/trunk physics were never retired. The graphics distance control only affected existing meshes.
- **Rule:** Queue only cells near streaming focus, retire distant mesh/trunk ownership, recreate deterministic placements on return, and yield between source-tree evaluations under a 1.2 ms work budget. Apply distance settings to future chunks as well as existing foliage. Chunk commit remains a native allocation boundary and must still be profiled in dense areas.
- **Check:** `tree_streaming_regression.gd` checks bounded selection, trunk collision, unload, deterministic return and resumption. The rendered M1 probe records actual walking/driving distance and frame percentiles; short near-60 FPS results do not certify high-speed or long-session performance.

### Instantiated GLB node does not have visibility_range_end (2026-10-30)
- **Symptom:** Godot crashes with "Invalid assignment of property or key 'visibility_range_end' with value of type 'float' on a base object of type 'Node3D'".
- **Cause:** Instantiating a `.glb` or `.tscn` scene returns a base `Node3D`, but `visibility_range_end` is only defined on `GeometryInstance3D` (e.g. `MeshInstance3D`).
- **Rule:** Iterate over child `GeometryInstance3D` nodes using `root.find_children("*", "GeometryInstance3D")` and assign `visibility_range_end` to each mesh instance individually.
- **Check:** `tests/movement_regression.gd` verifies all world building scripts compile and run without runtime exceptions.

### Rifles appeared inside walls and cars, or floating (before 2026-10-29)
- **Rule:** see `_build_weapon_pickups()` in `city_gameplay.gd`: ray down for level ground within 2 m of the start
  height, sphere overlap test, skip the spot otherwise. `weapon_pickup_regression` checks every rifle rests on
  the ground.

### Drainage kept running after it was asked to stop (2026-10)
- **Cause:** `world_generator.gd` still builds `RoadsideDrainage` unless launched with `--no-drainage`.
- **Rule:** when the owner asks for a system to stop, switch it off in the default start-up, not behind a flag.

### Vidya Nagar street vegetation instanced individual node scenes causing draw call bloat (2026-10-30)
- **Symptom:** Every street tree and banana tree created individual `MeshInstance3D` or `Node3D` scenes with separate `StaticBody3D` nodes, causing high draw calls and node overhead on mobile.
- **Cause:** Repeated trees and banana plants were instantiated per spot rather than batched.
- **Rule:** Batch repeated street foliage using `MultiMeshInstance3D` (one instance for setback trees, one for banana plants) with a unified `StaticBody3D` containing the trunk shapes, reducing draw calls from N down to 1.
- **Check:** `tests/movement_regression.gd`, verify tree counts and trunk collisions remain active and regression tests pass.
