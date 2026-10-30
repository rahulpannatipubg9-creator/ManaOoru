# Physics Overhaul

Status of the physics work requested in the "Complete physics system overhaul" brief.
Phases 1–5 below; the brief was cut off part-way through Phase 5.

## Phase 1 — findings in the existing game

| # | Question | Finding |
|---|---|---|
| 1 | Why are vehicle collisions unrealistic? | The playable cars are `CharacterBody3D` (kinematic). `move_and_slide()` slides along whatever it touches; it never exchanges momentum, so a car hitting another car behaves like hitting a wall. |
| 2 | Why are parked cars frozen or teleported? | `set_driving_enabled(false)` makes `_physics_process` return immediately, so a parked car has no gravity, no suspension and cannot be pushed. `main.gd` also sets the car's height to at least 1.2 m on entry (`global_position.y = maxf(y, 1.2)`), which teleports cars on low ground (the town has real terrain now). |
| 3 | How is vehicle physics enabled/disabled? | Through `driving_enabled` / `input_authority` flags; `main.gd` rewrites them every frame for all cars. |
| 4 | Correct collision shapes? | One upright box per car. The new rigid car's box is refitted to the Thar body's measured bounds (1.9 × 1.45 × 4.28 m, top at 1.9 m instead of 1.65 m). |
| 5 | Is movement done by writing transforms? | Yes: steering writes `rotation.y` directly; pitch/roll exist only on the visual chassis while the collision box stays upright, so it clips into slopes. |
| 6 | Frame-rate independent? | Yes: everything runs in `_physics_process` at the fixed 60 Hz step and uses `delta`. |
| 7 | Does the collision shape match the visuals? | Not quite: the original box was 0.27 m lower than the roof (fixed for the rigid car). |
| 8 | Do road and building collisions work? | Yes: terrain, buildings, medians and walls have trimesh collision; road surfaces sit on layer 2 so wheels can tell road from dirt. Tested in `tests/navigation_regression.gd`. |

## Phase 2 — vehicle model choice

Both were built and measured on the same track (`tests/vehicle_lab_regression.gd`, 1,800 kg Thar,
same geometry, project gravity 18 m/s²):

| Metric | RigidBody3D + raycast suspension | VehicleBody3D baseline |
|---|---|---|
| Drift at rest | 0.000 m | 0.000 m |
| 0–50 km/h | 4.2 s (real Thar driveline) | 1.4 s (constant engine force) |
| 60–0 km/h | 14.6 m | 10.6 m |
| Parked on 15% ramp | 0.000 m | 0.000 m |
| Lowest up-vector, full lock at 40 km/h | 0.999 | 0.976 |

Both are stable. **Chosen: `RigidBody3D` with custom raycast suspension** (`scripts/vehicle/rigid_vehicle.gd`) because:
- it drives the existing gearbox and drivetrain profiles (torque curve, gears) directly;
- the tyre model is ours: a per-wheel friction circle, handbrake rear lock, road vs dirt grip
  and parking-brake holding, which `VehicleWheel3D`'s single slip value can't express;
- impacts are under our control (momentum exchange with cars, knockback for people).

What the rigid car does: mass, centre of gravity, box inertia, damping, continuous collision
detection; 4 raycast wheels with spring, damper, travel limits and anti-roll bars; front
steering that narrows with speed and is rate-limited; drive force from the gearbox; progressive
brakes with a stop limiter, reverse via the gearbox, rolling resistance, aerodynamic drag,
lateral grip, handbrake slides, and road/dirt friction. Every force goes through
`apply_force`; the transform is only written by recovery (R).

## Phase 3 — car-to-car collisions

Tested in the lab with five parked cars and one driven car:
- only the driven car reacts to W/A/S/D;
- parked cars stay live rigid bodies, held by their parking brake;
- a 61 km/h hit shoves a parked car about 2 m, a slow nudge about 0.3 m;
- the shoved car settles, stays upright, stays where it was pushed, and no cars overlap.

## Phase 4 — character physics (`scripts/player/person_controller.gd`)

- Gravity, floor snapping and slope rules (walkable up to 46°, no sliding when standing).
- Stair/kerb stepping up to 0.4 m (checks the tread is walkable).
- Crouch (Ctrl) shrinks the capsule; standing up waits for headroom.
- Jump and landing; limited air control.
- Fall damage above a ~3.6 m drop, only in `combat_mode`.
- `apply_knockback()` with stagger, a lean-away reaction, optional damage, and
  `impacted` / `knocked_down` / `health_changed` signals for future combat and UI.
- Parked cars and walls are solid; a walking person can't shove a car.

## Phase 5 — car hits person

The rigid car detects the actual contact, takes the closing speed along the contact
normal, and maps it to a severity from 0 (1.5 m/s) to 1 (18 m/s, about 65 km/h). The person
is thrown along the car's path (further and higher at higher severity), staggers, and
in combat mode loses up to 100 health. The car loses the momentum it hands over. Severe
hits let the car pass through briefly so it does not snag; slow nudges keep colliding.
Tested: 12 km/h → severity 0.10, 5 damage, 1 m; 45 km/h → severity 0.63, 55 damage, 5.6 m.

## Not done yet (needs the files other sessions are editing)

The in-game cars are still the kinematic `player.tscn`. Switching them to the rigid car means
changing `scenes/main.tscn`, `main.gd` and `hud.gd` (type hints `CharacterBody3D`, the
1.2 m entry teleport, `velocity` usage) and `player.tscn`/the Porsche scene roots. Those files
were being edited by two other sessions at the time, so the switch-over is deferred until
they hand off. The rigid car already exposes the same control API (`set_driving_enabled`,
`set_input_authority`, `set_keyboard_input_enabled`, `set_touch_move_input`, `recover_vehicle`,
`current_speed`, `gearbox`, a `velocity` alias), so the switch is mostly a scene swap.

Also not started: movable crates/destructible props, shooting physics, multiplayer
authority, collision-layer naming (needs `project.godot`), and switching the physics engine
to Jolt.
