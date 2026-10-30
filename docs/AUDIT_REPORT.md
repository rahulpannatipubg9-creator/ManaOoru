# Godavarikhani Open World - Existing Codebase Audit

## 1. Engine and project

- Engine: Godot 4.7.2 stable, Compatibility renderer.
- Language: GDScript.
- Main scene: `scenes/main.tscn`.
- Runtime is offline and uses procedural geometry plus a local OSM JSON extract.
- Android preset: arm64-v8a, landscape orientation, immersive mode.

## 2. Input implementation

- Named actions are declared in `project.godot`.
- Keyboard movement uses W/A/S/D with held-key polling.
- F enters/exits vehicles; E is reserved for interaction.
- Space jumps on foot and handbrakes the car.
- Shift runs on foot.
- Mouse motion and right-side touch drags control the orbit camera.
- Touch controls are routed to the active controller through `hud.gd`.
- Controller support, remapping UI, pinch zoom, and complete lifecycle cleanup
  are not implemented.

## 3. Character controller

`person_controller.gd` is a `CharacterBody3D` controller with camera-relative
movement, acceleration, gravity, jump, sprint, crouch speed reduction, collision
enable/disable, and procedural stride animation.

Risks: no authored animation state machine, no slope/stair-specific handling,
and no dedicated crouch pose or capsule resizing.

## 4. Vehicle implementation

`player_controller.gd` is a reusable procedural car scene using
`CharacterBody3D`, arcade throttle/brake/reverse/steering/traction, wheel visual
rolling, steering visuals, recovery, and generated engine audio.

`main.gd` keeps person and vehicles as separate siblings and assigns exclusive
input/physics authority. Parked transforms are stored and restored while the
person is on foot. This directly addresses the reported all-cars-moving bug.

Risks: it is not yet rigidbody/wheel-suspension physics. Motorcycle support,
signals, headlights, indicators, horn, and a full vehicle camera system are not
implemented.

## 5. Camera

The orbit camera uses a spring arm with collision, pitch limits, mouse motion,
touch look, shoulder switching, and wheel zoom. Reverse-look and per-vehicle
camera cycling are not yet implemented.

## 6. Rendering and asset pipeline

The project uses procedural meshes and flat/material colors with no external
runtime asset dependency. This is legally simple and mobile-friendly, but it
does not yet meet the visual target of textured modular buildings, authentic
signage, or authored vehicle/pedestrian assets.

## 7. Mobile compatibility

An Android debug APK has been exported previously. No Android phone or tablet
was connected through ADB during this audit. Safe areas, physical lifecycle
testing, dynamic resolution, graphics presets, and thermal profiling are
unverified.

## 8. World and performance

The generator creates a bounded 360 m procedural town plus a 3 km local map
extract. The local OSM extract contains 650 highway ways and 2,446 building
ways; the generator now renders all 650 highway ways and processes all 2,446
building ways. A dedicated headless map regression verifies one-to-one highway-way
coverage by source way ID. This is source-data coverage, not a claim of
survey-grade real-world accuracy or complete locality connectivity beyond the
supplied extract. There is no chunk streaming, LOD system, profiler capture,
or measured device-tier budget evidence yet.

## 9. Tests and evidence

Existing tests cover input vectors, movement translation, camera collision and
pitch bounds, exclusive person/vehicle behavior, and one-to-one highway-way
coverage against the local OSM extract. Headless smoke, movement, scene, and
map regressions have passed in this environment. Visual desktop testing is
possible; physical Android, Windows, controller, long-session, and profiler
testing remain unavailable.
