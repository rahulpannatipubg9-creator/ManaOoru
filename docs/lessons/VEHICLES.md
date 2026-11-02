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

### A helicopter parked in mid-air stayed in the sky (2026-10-30)
- **Symptom:** dying in flight, or a match starting in flight, left the helicopter frozen in the air, out of reach.
- **Cause:** `helicopter.gd set_driving_enabled(false)` always freezes the body where it is.
- **Rule:** parking a craft with no ground under its skids sends it to `_safe_landing`.
- **Check:** `save_and_feedback_regression`.

### A wrecked helicopter kept a stale exit prompt (2026-10-30)
- **Symptom:** after a wreck the prompt stayed on "LAND TO EXIT" even on the ground, and a wreck falling out of the world was never recovered.
- **Cause:** `helicopter.gd _physics_process` returned on `condition <= 0.0` before the fall check and before updating `_grounded`.
- **Rule:** an early return in a vehicle's physics step must not skip the state the HUD reads.
- **Check:** `save_and_feedback_regression`.

### High-speed lookahead streaming and collision tunneling prevention at 120+ km/h (2026-11-02)
- **Symptom:** At high velocities (120–135 km/h), vehicle lead vector capped at 100 m trailed chunk extrusion, single-sided concave terrain/road meshes lacked backface collision response risking physics tunneling on high-velocity frame steps, suspension wheel raycasts ignored backfaces, and default `fall_limit = -10.0 m` triggered false teleports in deep sectors like the Godavari River Bridge (deck Y = -25.1 m to -26.3 m) or Coal Mine (-30 m).
- **Cause:** Lookahead lead wasn't scaled for high velocities (>33 m/s), `world.trees.focus` was unassigned in `main.gd`, `ConcavePolygonShape3D.backface_collision` defaults to `false` in Godot 4.7, suspension wheel ray queries had `hit_back_faces = false`, and `fall_limit` was hardcoded without checking the DEM elevation envelope (-30 m to +60 m).
- **Rule:** Velocity-aware streaming must scale lookahead up to 250 m at 130 km/h and assign focus to both `world.buildings` and `world.trees`. Always set `backface_collision = true` on road, bridge, and terrain concave polygon shapes. Set `hit_back_faces = true` on suspension wheel raycast queries so wheels retain upward spring force even during deep step penetrations. Set vehicle default `fall_limit = -80.0 m` to encompass all district DEM topography safely.
- **Check:** `tests/movement_regression.gd`, `tools/performance/pad7_chowrasta_high_speed_probe.gd` on physical Xiaomi Pad 7 (`tunneling_events: 0`, `fall_events: 0`, `collision_integrity_pct: 100.0%`, `pending_trees: 0`, `pending_buildings: 0.07 mean`).

### Input isolation must exclude ambient impacts and fixture overlap (2026-11-02)
- **Symptom:** Parked-car input checks reported centimetres of motion while walking near the spawn Tuk Tuk.
- **Cause:** The test retained its isolated ground pad beneath the city, sampled before streamed collision settled, and walked through the parked roster. Live ambient actors could also physically move unselected cars during entry/driving assertions.
- **Rule:** Remove isolated fixtures before city loading, await bounded startup settlement, and choose a swept clear path for input-isolation checks. Stop ambient callbacks while preserving world collision and every enterable vehicle subtree. Clear touch input before checking keyboard W. Keep live traffic and physical collisions in separate suites; do not freeze cars to satisfy ownership assertions.
- **Check:** `movement_regression.gd` keeps its 1 cm tolerance. `character_physics_regression.gd`, traffic, and vehicle-entry suites cover the physical interactions separately. An experimental parking guard was removed after the walking-person shove check regressed; the final fix leaves vehicle physics unchanged.

### Ambient traffic needs directed lanes and approach-specific stop lines (2026-11-01)
- **Symptom:** Ambient vehicles reversed into oncoming travel at road ends, had no general following gap, and assigned signal groups by vehicle index.
- **Cause:** `traffic_vehicle.gd` ping-ponged a single offset point array; `traffic_builder.gd` spawned fixed townwide traffic and used `index % 2` for signals.
- **Rule:** Use directed left-hand Path3D sections linked by shared map node IDs, excluding terminal spurs from spawning. Bound the reusable fleet to 25, spawn 40–90 m away, and release beyond 110 m. Brake using bumper distances and approach stop offsets; propagate stop lines through short map sections. Commit vehicles past the line so phase changes do not stop them inside the junction. Pool selection must reapply district profiles on reuse.
- **Check:** `traffic_regression.gd`, `traffic_signal_regression.gd`, `traffic_manager_regression.gd` (including `-- --city`), and `scooter_regression.gd`. On retest (2026-11-01), the current checkout passes the required movement regression including entry and recovery; no player/entry behaviour was changed by the traffic cleanup.


### Ambient bus route expansion broke rigid single-bus assertion in scene regression (2026-10-31)
- **Symptom:** `scene_regression` failed with `Assertion failed: Mapped TGSRTC service bus missing`.
- **Cause:** When TGSRTC service was expanded from a single route to two active loops (Route 1 Mining Loop + Route 2 Market Loop) in `traffic_builder.gd`, `scene_regression.gd` was still asserting `world.traffic.bus_vehicle_count == 1`.
- **Rule:** Assert capacity bounds (`bus_vehicle_count >= 1`) for extensible municipal transit services rather than exact single-unit equality.
- **Check:** `tests/scene_regression.gd`.

### Helicopter animated rotor node attached to visual model rather than body root (2026-10-31)
- **Symptom:** `helicopter_regression` failed with `Assertion failed: Animated main rotor missing`.
- **Cause:** In `scripts/vehicle/helicopter.gd`, `_create_visible_rotor()` attaches `AnimatedMainRotor` to `_model` (`Model/AnimatedMainRotor`) so the spinning blades tilt and bank naturally with the fuselage mesh, but test checks searched for a direct child of the root vehicle node.
- **Rule:** When probing procedural attachments on multi-part vehicle hierarchies, use recursive tree search (`find_child("AnimatedMainRotor", true, false)`) to locate nodes mounted on visual sub-rigs.
- **Check:** `tests/helicopter_regression.gd`.

### Vehicle damage smoke particles rendered as solid billiard-ball spheres (2026-10-31)
- **Symptom:** When a vehicle's health dropped, smoke emitted from the engine bay as solid, dark gray 3D billiard balls/spheres rising in the air.
- **Cause:** `vehicle_effects.gd` used a `SphereMesh` with standard lighting instead of billboarded particle quads with unshaded transparency.
- **Rule:** Volumetric smoke in real-time Godot 4.7 must use `QuadMesh` with `BILLBOARD_PARTICLES`, `SHADING_MODE_UNSHADED`, soft particle fading, and alpha fade over lifetime rather than solid 3D primitive geometry.
- **Check:** `scenes/main.tscn`, inspect vehicle damage smoke emitter.

### FPP windshield wireframe blockage, driver road sightline pitch, and missing paint_materials key (2026-10-31)
- **Symptom:** In first-person cockpit view ('V' key) in the `toyota_supra_gr`, a solid mint-green wireframe wall blocked the forward view of the road, the camera looked straight level into the dashboard/horizon rather than angled down at the road surface, and `imported_vehicle.gd` crashed on missing `paint_materials` keys in `vehicle_finishes.json`.
- **Cause:** Raw 3ds Max / FBX imports assign multiple wire materials to front windshields (e.g. `wire_027177088` on surface 14 of the Supra); omitted materials defaulted to opaque body finish. FPP camera had zero pitch angle ($0.0$ rad), losing road sightlines. Also `finish.paint_materials` threw an exception when the dictionary key was absent.
- **Rule:** Use `finish.get("paint_materials", [])` safely. Register all windshield wire materials in `data/vehicles/vehicle_finishes.json`. Set default vehicle FPP camera pitch in `camera_controller.gd` to $-0.06$ rad (~$3.5^\circ$ downward tilt) so the driver's eye naturally sees the hood and road ahead.
- **Check:** `tests/test_car_glass_fpp.gd`, `tests/movement_regression.gd`.

### Auto rickshaws and bikes appeared empty in ambient traffic (2026-10-31)
- **Symptom:** Roaming ambient auto rickshaws (Tuk-Tuk) and motorcycles in Godavarikhani had no visible drivers or passengers.
- **Cause:** `TrafficVehicle` instantiated the model mesh without adding driver and passenger figures.
- **Rule:** Ambient auto rickshaws must instantiate a front khaki-uniform driver and seated rear passengers; add `triple_ride` bike vehicle kind for authentic three-up teenager street traffic.
- **Check:** `tests/test_godavarikhani_living_district.gd`, `tests/traffic_regression.gd`.

### Opaque pink/white windshields and driver roof clipping in imported cars (2026-10-31)
- **Symptom:** In first-person perspective (FPP, 'V' key), `ford_mustang_mach_40` had a solid opaque pink windshield, `toyota_supra_gr` had an opaque white windshield, and the character's helmet poked out through the roof.
- **Cause:** Raw FBX/3ds Max imports assigned viewport wireframe materials (`wire_236160154`, `wire_255255255`) with `transparency = 0`. In `imported_vehicle.gd`, unmapped wireframe materials defaulted to opaque body finish. Additionally, `seat_hip.y` was set to $0.35$–$0.39$m; since the driver's torso and helmet extend $0.85$m above hips, the driver exceeded the $1.20$m interior cabin clearance.
- **Rule:** Register glass material names in `data/vehicles/vehicle_finishes.json` under `glass_materials`. `imported_vehicle.gd` assigns transparent tinted glass (`Color(0.20, 0.28, 0.35, 0.18)` with `TRANSPARENCY_ALPHA` and `CULL_BACK`), and dynamically sets alpha to `0.0` in FPP mode so cockpit view has 100% crystal-clear visibility. Keep sports car `seat_hip.y` at $0.18$–$0.22$m and adjust `first_person_offset`.
- **Check:** `tests/test_car_glass_fpp.gd`.

### Traffic motorcycle display slab baseplate and mannequin rider (2026-10-31)
- **Symptom:** Ambient traffic Royal Enfield Bullet motorcycle had a rectangular stone display slab attached to its base and a blocky mannequin dummy rider sitting rigidly on it.
- **Cause:** `BULLET_SCENE` in `traffic_vehicle.gd` pointed to raw imported download containing decorative showroom display plinth and dummy geometry, and `_build_bike_rider()` generated box mannequin riders.
- **Rule:** Use clean rigged `res://assets/models/vehicles/royal_enfield_bullet/bullet_motorcycle.scn`. Rotate wheels dynamically via `wheel.rotate_x(-step / wheel_radius)` so only the wheels spin while driving. Eliminate unnecessary camera recoil shake during vehicle travel.
- **Check:** `tests/bullet_motorcycle_regression.gd`.

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
