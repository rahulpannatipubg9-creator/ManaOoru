# MANA OORU

[![Engine: Godot 4.x](https://img.shields.io/badge/Engine-Godot%204.7-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org)
[![Platform: Desktop & Android](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Android-green)](docs/PLATFORM_COMPATIBILITY_MATRIX.md)
[![License: MIT & CC-BY-NC 4.0](https://img.shields.io/badge/License-MIT%20%2F%20CC--BY--NC%204.0-blue.svg)](LICENSE)
[![Tests: Passing](https://img.shields.io/badge/Quality%20Gate-Regression%20Passing-success)](tests/movement_regression.gd)
[![Offline: 100%](https://img.shields.io/badge/Runtime-100%25%20Offline-brightgreen)](AGENTS.md)
[![Contributing: Guide](https://img.shields.io/badge/Team-AI%20Workflow-orange)](docs/TEAM_WORKFLOW.md)

## Godavarikhani Open World

MANA OORU is an offline, single-player, third-person exploration game set in a
procedural recreation of Godavarikhani, Telangana, India.

The first playable experience focuses on:

- Walking through a bounded Godavarikhani environment.
- Running, jumping, crouching, and exploring landmarks.
- Finding a parked vehicle.
- Entering and exiting the vehicle.
- Driving with keyboard or touch controls.
- Returning to on-foot exploration.
- Minimap, full-screen map and GPS waypoint routing over real OpenStreetMap roads
  (see [Map and GPS Navigation](docs/MAP_AND_NAVIGATION.md)).

There is no combat or mission system in the initial release.

## Current engine and technology

- **Engine:** Godot 4.7.2
- **Language:** GDScript
- **Renderer:** Compatibility / OpenGL
- **Runtime:** Offline; no backend, account, analytics, or network dependency
- **World:** Procedural geometry plus a local OpenStreetMap-derived JSON extract
- **Android architecture:** arm64-v8a
- **Primary desktop validation:** macOS Apple Silicon

Godot is being continued because the project already has working procedural
scenes, desktop input, touch input, Android export configuration, and a reusable
person/vehicle possession architecture. A migration would delay the playable
milestone without solving a current requirement.

## Run the game

1. Install Godot 4.x stable from [godotengine.org](https://godotengine.org/download/).
2. Open this folder in Godot.
3. Press **F6** to run the current scene or **F5** to run the project.
4. Click the game window to capture the mouse.
5. Press **Escape** to pause (and again to resume), or to close the map.

From a terminal:

```sh
godot --path .
```

## Desktop controls

### On foot

| Button | Action |
|---|---|
| W / A / S / D | Walk forward, left, backward, right |
| Mouse movement | Rotate the third-person camera |
| Left Shift | Sprint while held |
| Space | Jump |
| Left Ctrl | Crouch / move slowly |
| E | Enter a nearby vehicle |
| E | Interact with nearby objects |
| V | Switch first-person / third-person view |
| C (hold) | Look behind |
| Mouse wheel | Zoom camera (third person) |
| M | Open / close the full-screen map |
| = / − | Minimap zoom |
| N | Minimap north-up / heading-up |
| Tab | Quick information |
| Esc | Close map, or pause / resume |

### Driving

| Button | Action |
|---|---|
| W | Accelerate |
| S | Brake, then reverse when stopped |
| T | Switch gearbox Automatic / Manual |
| X / Z | Manual gear up / down (from Automatic, takes manual control) |
| A / D | Steer left / right |
| Space | Handbrake |
| F | Exit the vehicle |
| V | Switch first-person (driver's seat) / third-person view |
| C (hold) | Look behind (rear view) |
| Mouse movement | Move the driving camera independently |
| H | Horn |
| R | Recover a stuck vehicle |
| M | Open / close the full-screen map |
| Esc | Close map, or pause / resume |

### Vehicle ownership rule

The controls are exclusive:

- On foot, only the person moves.
- All parked vehicles remain stationary.
- After entering a vehicle, only that selected vehicle receives driving input.
- Other vehicles remain parked.
- On exit, the vehicle stops and remains at its last driven location.

## Android and tablet controls

The Android HUD provides:

- Left virtual joystick for movement, steering, throttle, and reverse.
- RUN control while on foot.
- JUMP control while on foot.
- ENTER control only when close to an enterable vehicle.
- EXIT control only while driving.
- RESET control for vehicle recovery.
- Right-side swipe for camera rotation.

The interface resizes for different viewport sizes. Safe-area handling,
customizable touch layout, pinch zoom, physical lifecycle testing, and
device-specific graphics presets are planned follow-up work.

## Godavarikhani environment

The town is built from real open data around the Chowrastha junction (3 km radius):
real ground relief (Copernicus DEM), every OpenStreetMap road at lane/class-based width with markings, dual carriageways with
their real medians, zebra crossings, railways, parks and water; 18,862 buildings at their
exact footprints (OSM + Microsoft ML footprints) with measured heights (Google Open
Buildings 2.5D); and name boards for 140+ mapped
hospitals, schools, temples, shops and colonies, including SCCL School and Jawaharlal
Nehru Stadium. Building colours, dustbins and sign styling are not in the open data and
are generated. OSM has no traffic signals mapped here yet; add known ones to
`data/local/traffic_signals.json`. Details: [Map and GPS Navigation](docs/MAP_AND_NAVIGATION.md).

## Project architecture

```text
scenes/main.tscn
  ├── Player          Person CharacterBody3D
  ├── Vehicle         Reusable car CharacterBody3D
  ├── ParkedVehicle*  Additional enterable vehicles
  └── World           Godavarikhani built from OSM + Microsoft footprints
```

Important runtime modules:

- [`scripts/main.gd`](scripts/main.gd): game state, vehicle possession,
  exclusive authority, camera target, and HUD mode.
- [`scripts/player/person_controller.gd`](scripts/player/person_controller.gd):
  walking, sprinting, jumping, crouch speed, and collision.
- [`scripts/player/player_controller.gd`](scripts/player/player_controller.gd):
  current car movement, braking, steering, recovery, suspension, and tyres.
- [`scripts/player/engine_sound.gd`](scripts/player/engine_sound.gd):
  procedural Thar-style diesel engine, gears, turbo, road noise, tyre squeal, horn.
- [`scripts/camera/camera_controller.gd`](scripts/camera/camera_controller.gd):
  mouse/touch orbit, first/third-person views, look-behind, pitch limits,
  shoulder camera, and zoom.
- [`scripts/ui/hud.gd`](scripts/ui/hud.gd): desktop/mobile controls, prompts,
  enter/exit buttons, speed, and status.
- [`scripts/world/world_generator.gd`](scripts/world/world_generator.gd):
  procedural roads, buildings, landmarks, pedestrians, and local map data.

Person and vehicles are separate sibling objects. The car is never the
permanent player object.

## Physics status

The current car uses a `CharacterBody3D` arcade controller with:

- A real driveline per car (`scripts/player/drivetrain_profile.gd`). The Thar
  default is the 2.2 mHawk diesel (130 hp, 300 Nm from 1600-2800 rpm) driving a
  6-speed torque-converter automatic (3.60 / 2.09 / 1.49 / 1.00 / 0.69 / 0.58,
  final drive 4.27). Every drive starts in first; Automatic shifts one gear at a
  time at pedal-dependent points, and Manual (T, then X/Z) holds your gear,
  refuses over-revving downshifts and still drops a gear before the engine
  lugs. The limiter cuts drive at 4200 rpm. The HUD shows gear and rpm (D3,
  M3 or R).
- 1800 kg mass, aerodynamic drag and rolling resistance: about 15 s to
  100 km/h and a top speed of about 140 km/h, like the real diesel Thar.
  Lifting off coasts with engine braking; S brakes at about 0.9 g.
- Speed-sensitive steering that eases off at motorway speed.
- Raycast spring-damper suspension on each wheel: the car rides on its springs,
  wheels follow the road within their bump/droop travel, and the body heaves,
  squats under acceleration, dives under braking, rolls in corners and bounces
  on landing.
- Load-sensitive tyre grip: each tyre's grip scales with the load its spring
  carries, braking/driving and cornering share one friction circle, and an
  airborne car has no throttle, braking or steering authority.
- Handbrake locks the rear tyres so the rear can slide out at speed.
- Recorded four-cylinder turbo-diesel engine: five real held-rev loops
  (913-3133 rpm, CC0) crossfaded and pitched to the gearbox rpm, so revs climb
  in each gear and drop at every upshift, louder under load than when coasting.
  A synthesised starter crank, turbo whistle, road noise, tyre squeal and a
  dual-tone horn (H) sit on top. Only the driven car's engine runs; it starts
  when you get in and switches off when you get out. Cars without a recording
  fall back to the synthesised engine.
- Parked cars settle onto their springs at ride height.
- Wheel rolling (rear wheels stop under handbrake) and front-wheel steering visuals.
- Vehicle recovery when stuck.

Suspension and tyre tuning are exported on the car (`Suspension` and `Tyres`
groups in the inspector). The root body stays upright for `move_and_slide`;
body pitch and roll are applied to the visual `Chassis` node. Full rigidbody
dynamics and motorcycles are still planned behind the same enter/exit
vehicle interface.

## Tests and validation

Run the existing offline checks from this directory:

```sh
godot --headless --editor --quit
godot --headless --path . --script tests/movement_regression.gd
godot --headless --path . --script tests/scene_regression.gd
godot --headless --path . --script tests/map_regression.gd
godot --headless --path . --script tests/navigation_regression.gd
godot --headless --path . --script tests/suspension_regression.gd
godot --headless --path . --script tests/camera_regression.gd
godot --headless --path . --script tests/engine_sound_regression.gd
godot --headless --path . --quit-after 8
```

Refresh map data (build time only; the game stays offline):

```sh
tools/fetch_osm.sh
python3 tools/import_ms_buildings.py <tile.csv.gz> data/osm/godavarikhani_core.json data/buildings/godavarikhani_ms_buildings.json
python3 tools/import_building_heights.py
python3 tools/import_terrain.py
```

The tests cover:

- WASD direction mapping.
- Diagonal input normalization.
- Idle movement stability.
- Person translation.
- Parked vehicles staying still while the person walks.
- Only the selected vehicle moving while driving.
- Person visibility and collision during possession.
- Vehicle stopping after exit.
- Camera collision and pitch bounds.
- One-to-one highway-way coverage between the local OSM extract and generated
  road geometry.
- Bounded world generation smoke loading.

## Platform status

| Platform | Status |
|---|---|
| macOS desktop | Tested; Godot game launches |
| Windows desktop | Not tested in this environment |
| Android phone | Debug APK export available; physical device not tested |
| Android tablet | Debug APK export available; physical device not tested |
| Game controller | Input map not implemented yet |

The latest debug APK, when rebuilt, is written to:

```text
builds/mana-ooru-debug.apk
```

An export succeeding does not prove compatibility on every Android device.
Physical phone/tablet testing and profiling remain release requirements.

## Performance targets

These are targets, not measured claims:

- Budget Android: stable 30 FPS.
- Mid-range Android: stable 30 FPS.
- High-end Android: 30–60 FPS subject to profiling.
- Desktop: target 60 FPS.
- No unbounded world generation or dynamic object growth.
- No memory growth during a 30-minute exploration soak.

The current world is bounded, but FPS, memory, draw calls, thermal behavior,
and device-tier frame times have not yet been measured with representative
hardware.

## Legal and asset policy

Use only:

- Original procedural geometry.
- Original artwork and code.
- Free assets with compatible redistribution rights.
- Geographic references and map data with documented attribution.

Do not import copyrighted game assets, ripped GTA assets, or unverified branded
vehicle models. Record every external asset in
[ASSET_LICENSES.md](ASSET_LICENSES.md) before use.

## Development documentation

The detailed design and engineering documents are in [`docs/`](docs/):

- [Audit report](docs/AUDIT_REPORT.md)
- [Game Design Document](docs/GAME_DESIGN_DOCUMENT.md)
- [Technical Design Document](docs/TECHNICAL_DESIGN_DOCUMENT.md)
- [Input Action Specification](docs/INPUT_ACTION_SPECIFICATION.md)
- [Vehicle Physics Specification](docs/VEHICLE_PHYSICS_SPECIFICATION.md)
- [Mobile UI Specification](docs/MOBILE_UI_SPECIFICATION.md)
- [Platform Compatibility Matrix](docs/PLATFORM_COMPATIBILITY_MATRIX.md)
- [3D Asset Import & Placement Pipeline](docs/3D_ASSET_PIPELINE.md)
- [Asset Requirements](docs/ASSET_REQUIREMENTS.md)
- [Performance Budgets](docs/PERFORMANCE_BUDGETS.md)
- [Testing and Release Checklist](docs/TESTING_AND_RELEASE_CHECKLIST.md)
- [Milestone Implementation Plan](docs/MILESTONE_IMPLEMENTATION_PLAN.md)

## Known limitations

- No motorcycle scene yet.
- No save/load system yet.
- No full pause/settings screen yet.
- No controller support yet.
- No streamed districts or LOD system yet.
- No authored animation state machine yet.
- No physical Android, Windows, controller, or long-session profiling evidence
  in this environment.
