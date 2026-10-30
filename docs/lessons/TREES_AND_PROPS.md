# Trees, ground cover and props: lessons

Anything placed on the ground: trees, stalls, carts, pickups, poles, drains, cover in the arena.

## Placing something on the ground

1. Probe the ground with a ray from above (after buildings and cars are in the physics world: wait two physics
   frames) and keep it only on level ground near the expected height.
2. Probe for overlap with a shape so it never ends up inside a building, a parked car or a wall.
3. Keep it static and identically placed on every device when it matters in a match (TDM cover).
4. Look at it from the street: not floating, not sunk, not blocking a doorway or the road.

## Entries

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
