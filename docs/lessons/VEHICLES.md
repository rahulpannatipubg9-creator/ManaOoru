# Vehicles: lessons

Code: `scripts/vehicle/` (`vehicle_entry.gd` for getting in and out and the seat), `scripts/main.gd`
(who controls what), vehicle scenes in `scenes/vehicles/`. Physics background: `docs/PHYSICS_OVERHAUL.md`.

## Adding a new vehicle

1. Measure the driver's **hip point on the seat cushion** and the **heel point at the pedals** in the car's own
   space (raycast the body mesh) and add them to `SEATS` in `vehicle_entry.gd`, or give the car `seat_hip` /
   `pedal_point`. Note which side the wheel is on (the Thar is right-hand drive, x −0.36; the Porsche is
   left-hand drive, x +0.32).
2. If the car has a modelled wheel, give it `left_hand_grip` / `right_hand_grip`; otherwise the hands go to a
   default wheel 0.40 m above and 0.42 m ahead of the hips.
3. Get in and render the driver from both sides and the front (see [TESTING_AND_TOOLS.md](TESTING_AND_TOOLS.md)):
   nothing may poke through the roof, doors or floor.
4. Run `vehicle_entry_regression` and `movement_regression`.

## Entries

### Motorcycle roll chatter and off-center visual wheels (2026-10-31)
- **Symptom:** The Royal Enfield Bullet motorcycle shivered and chattered continuously at rest and low speeds, and the front wheel appeared visibly offset to the left of the fork.
- **Cause:** `motorcycle.gd` ran an explicit PD roll torque controller with natural frequency $f = 30.0$ Hz. On 60 Hz physics, $(30)^2 = 900$ stiffness multiplier reversed roll error against the 5 cm spaced suspension probes ($x = \pm 0.025$). Additionally, reparenting `FrontWheelMesh` to `FrontLeftWheel` ($x = -0.025$) left its local position at $(0, 0, 0)$, placing the visual wheel 2.5 cm to the left of the bike centerline.
- **Rule:** Keep roll balance assist frequency critically damped at $11.0$ Hz. Offset reparented wheel meshes by $+0.025$ along $X$ so visuals sit precisely on the centerline ($x = 0.0$).
- **Check:** `tests/bullet_motorcycle_regression.gd`.

### Vehicle pedestrian impact penetration at low speeds (2026-10-31)
- **Symptom:** In `character_physics_regression.gd`, at 12 km/h vehicle impact speed, the character landed inside the vehicle bounding box.
- **Cause:** `rigid_vehicle.gd` computed forward throw as $v_{throw} = v_{car} \times \text{lerp}(0.6, 1.1, \text{severity})$. At low severity ($0.11$), throw velocity was only $0.65 v_{car}$, causing the coasting 1.8-ton car to overtake and engulf the airborne character. Furthermore, collisions below severity 0.3 omitted collision exceptions without braking the car.
- **Rule:** Forward throw impulse must exceed closing vehicle speed ($v_{throw} \ge 1.15 v_{car}$, minimum 4.2 m/s), and the impacting vehicle must exchange momentum and add temporary collision exception so it never rolls over the thrown pedestrian.
- **Check:** `tests/character_physics_regression.gd`.

### Imported road models must become real vehicle scenes (2026-10-31)
- **Symptom:** Imported cars looked parked but could not be entered; source alpha modes hid body panels, old transforms shrank individual parts, multi-car variant packs created oversized colliders, and generic seat fits clipped drivers through roofs.
- **Cause:** `custom_asset_placements.gd` only loaded decorative GLBs and static collision, ignoring `drivable_scene`. Source mesh coordinates were sometimes already normalized while stale parent transforms remained.
- **Rule:** Measure wheel stations and source orientation for each model; preserve actual tyre/rim geometry, build the shared RigidVehicle layout with individual tuning, load the vehicle scene without static collision, retain district spawns without consuming original roadside slots, and validate driver poses in rendered views. Never call gearbox-dependent parking code before `_ready` without a guard. Never claim that estimated handling values are factory measurements or that source geometry QA has passed when it has not.
- **Check:** `tests/imported_vehicle_regression.gd`, `tests/imported_world_vehicle_regression.gd`, `tests/movement_regression.gd`, `tests/vehicle_entry_regression.gd`, and `tools/capture_imported_vehicle_seats.gd`. See `docs/IMPORTED_VEHICLE_RIGS.md` for limitations and results.

### Driver hanging out of the Porsche window (2026-10-29)
- **Symptom:** body half outside the car, an arm out of the window, legs through the floor.
- **Cause:** the character's fixed-angle driving pose, not the seat numbers: the seat put the hips exactly on
  the cushion. Details in [CHARACTERS.md](CHARACTERS.md).
- **Rule:** when a driver looks wrong, first probe where the hips, hands and feet are in the car's space
  against `seat_points()`; that tells you whether the seat or the pose is at fault.
- **Check:** `vehicle_entry_regression` plus side and front renders in every car type.

### Cars behave like walls when they hit each other (before 2026-10-29)
- **Cause:** kinematic `CharacterBody3D` cars and `move_and_slide()` exchange no momentum; parked cars had
  physics switched off, and entering a car lifted it to at least 1.2 m (teleporting cars on low ground).
- **Rule:** never write a car's height or rotation directly to "fix" it; use the rigid car and its suspension.
  See `docs/PHYSICS_OVERHAUL.md`.

### All parked cars moved with the player's input (early prototype)
- **Cause:** every car read the same input.
- **Rule:** exactly one thing has input authority at a time; `main.gd` assigns it and parked cars keep their
  stored transforms.

### Parked vehicle suspension draining mobile CPU (2026-10-30)
- **Symptom:** Running 4 suspension raycasts and Pacejka tyre friction calculations per car on every parked Thar, Tuk Tuk, and Porsche drained CPU on mobile.
- **Rule:** Parked vehicles sleep on their simple box collider with zero raycasts running. Full suspension, drivetrain and tyre calculations wake up only when `driving_enabled` is handed to the car by `main.gd`. Tire raycasts strictly query Layer 1 (Roads/Terrain), ignoring buildings, pedestrians and props. Engine audio is strictly voice-capped: only the active driven vehicle plays engine audio, while parked cars are completely muted.
- **Check:** `movement_regression.gd`, verify parked cars sleep at rest, zero audio playback when parked, and wake up smoothly on entry.

### High-speed driving (130+ km/h) outrunning world streaming (2026-10-30)
- **Symptom:** Driving at 130 km/h (36 m/s) in the Porsche 911 or Thar 4x4 caused stutter and dropped frames as new sectors and building chunks were entered.
- **Rule:** Streaming focus (`player_focus`) projects ahead along vehicle linear velocity ($t_{\text{lead}} \le 2.5\text{s}$, up to 100m) so chunks ahead begin generation before the car arrives. Chunk creation is throttled to $\le 1200\mu\text{s}$ per frame with an LRU cache of 50 chunks for zero-latency turnarounds.
- **Check:** `tests/movement_regression.gd`, verify high-speed vehicle translation and lookahead.

### Batch vehicle placement collision clearance & spawn isolation (2026-10-31)
- **Symptom:** In `tests/movement_regression.gd`, `Tuk Tuk` was knocked away from interaction range or launched into the void on startup.
- **Cause:** Two causes: (1) Un-transformed FBX mesh AABBs generated multi-kilometer box colliders, enveloping player spawn; (2) Placing decorative custom vehicles directly inside the 30 m `SPAWN_CENTER` radius collided with `roadside_spots()` vehicle search during settlement.
- **Rule:** Keep custom vehicle placements at least 50 m away from `(0, 0)` Chowrastha spawn point. Distribute authentic collections across actual regional hubs (Hotel Sai Leela, Vidyanagar Road 2, Coal Mine OCP 5 Incline, Godavari Bridge, TGSRTC Bus Station). Use verified metric dimensions for static box colliders with ground origin $Y=0$.
- **Check:** `tests/movement_regression.gd` and `tests/test_custom_asset_placements.gd`.

### Distant decorative placements have no streamed ground (2026-10-31)
- **Symptom:** Newly drivable imported cars drifted or fell while the player walked elsewhere; Range Rover fell through an unloaded sector.
- **Cause:** Decorative positions were activated as rigid bodies before distant terrain existed; some also overlapped buildings or lacked support under every wheel.
- **Rule:** Hold distant unoccupied imported vehicles until streamed collision is present; before activation validate chassis clearance and ground support at every wheel, with a bounded nearby parking search. Nearby activated vehicles still use the shared live rigid-body simulation.
- **Check:** movement_regression.gd; the original failure identified Aventador drift of 0.6636m, and the streaming safeguard passed the existing parked-input isolation checks.

### Bullet must be a motorcycle, and entry must move visible geometry (2026-10-31)
- **Symptom:** Bullet did not move, its rider/frame/wheels were misaligned, car paint was missing, and entry played sounds without opening a visible door or bending through the doorway.
- **Cause:** Bullet inherited hidden Thar geometry and the loader froze it without a release path; suspension rest length mismatched the wheel radius. The source bike was a diagonal scan with a display base, not a clean articulated motorcycle. Imported paint slots were not mapped, and vehicle_entry.gd only interpolated the root.
- **Rule:** Use a separate motorcycle controller and clean two-wheel visual assemblies, measured grips/footrests, rear drive, gearing, assisted balance, stand parking and release on entry. Keep the original scan preserved. Animate door geometry and character bend with entry phases, hold doors open while crossing, and close only after sitting or stepping clear. Bikes use leg-over mount/dismount and no car-door sound. Fit paints to explicit exterior slots; do not color the tires or interior globally. Clip fitted door boundaries exactly, interpolating UVs/normals, rather than moving whole triangles by their centres.
- **Check:** bullet_motorcycle_regression.gd, visible_vehicle_entry_regression.gd, vehicle_entry_regression.gd, movement_regression.gd, and rendered sequences from tools/capture_vehicle_entry_animation.gd. Source meshes with welded panels use fitted door regions and need per-model visual review.

### Grip targets must follow the character's left/right convention (2026-10-31)
- **Symptom:** The bike rider crossed arms and missed both grips by roughly 29cm despite inverse kinematics being enabled.
- **Cause:** Scene targets called negative-X "left" although Rahul's CC rig has left shoulder on positive X. The bars were also farther forward than the seated arm reach.
- **Rule:** Measure the visible shoulder/wrist bones; left grips are positive X relative to the vehicle centreline, right grips negative X. Validate both wrist contacts after pose settling. Never change the body scale or arm lengths to hide an unreachable grip. Passenger simulation following must also update during physics steps; render-time interpolation alone can trail at low frame rates.
- **Check:** visible_vehicle_entry_regression requires both wrists within 5cm; final measured gaps 1.2cm/2.8cm. movement_regression passed after the seat-follow correction.
