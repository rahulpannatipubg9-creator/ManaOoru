# Traffic v1

Godot 4.7.2, GDScript, offline. Integrated through the existing
`WorldGenerator._create_traffic()` / `TrafficBuilder.build()` entry point.
Player scripts, camera scripts, city scenes and drivable vehicle physics are untouched
by this change. Branch: `feature/traffic-v1`.

## Runtime scene tree — no manual editor setup

```
ManaOoru
└── World
    └── Traffic                         TrafficBuilder / TrafficManager
        ├── Lanes                       Node3D (hidden organizational node)
        │   └── Lane_<index>             Path3D, directed road sections
        ├── Junctions                   Node3D (hidden organizational node)
        │   └── Junction01              TrafficLightController
        │       ├── StopNorth           TrafficStopPoint / Marker3D
        │       ├── StopSouth           TrafficStopPoint / Marker3D
        │       ├── StopEast            TrafficStopPoint / Marker3D
        │       ├── StopWest            TrafficStopPoint / Marker3D
        │       └── LaneStop_*          Additional approaches where mapped
        └── AmbientTraffic_<index>      TrafficVehicle / CharacterBody3D
            ├── CollisionShape3D
            ├── VisualRoot             Reserved visual attachment point
            ├── FrontRayCast3D
            └── <existing visual nodes>
```

The four-way junction is selected from actual mapped four-arm intersections near
spawn; one-way outbound-only arms are excluded. Existing signage materials are
shared townwide, so their cycle is synchronized to this controller. Other signal
visuals remain decorative in v1. Group 0 serves North/South and group 1 East/West, using the dominant
world axis for approaches rotated from geographic north.
Approach stop lines are 12 m before the intersection endpoint. Stop offsets propagate
upstream through short source-map sections. Vehicles already beyond their bumper
stop boundary clear the junction on yellow/red.

Directed sections use OSM shared node IDs, respect one-way direction, keep left,
and use short connectors between offset sections. Sections reaching real directed
cycles are eligible for spawning. No teleporting across dead ends or overpass
proximity connections. There is no overtaking or destination routing in v1.

The pool grows gradually to at most 25 bodies and reuses inactive bodies. Colliders,
physics and rendering are disabled while inactive. Visuals are retained when the
profile kind matches and rebuilt only when a reused body changes kind. This limits
memory while allowing mine/highway weighting to change when travelling. Bikes,
autos and buses reuse existing assets; cars, coal trucks and tractors use lightweight
procedural representations. Heavy drivable scenes and engines are not instantiated.

Spawn candidates are spatially indexed. Spawns use the controlled player's actual
position, not terrain-streaming lookahead: 40–90 m, at least 8 m between centres
(and extra body-length clearance), world collider check, and junction exclusion.
Beyond 110 m bodies return to the pool. A sparse or obstructed road area may have
fewer than 25 active vehicles. Weights describe random spawn probabilities, not
an exact composition guarantee for a small local fleet.

All vehicle speeds (m/s), accelerations (m/s²), lengths, spawn weights and district
multipliers are in `data/vehicles/traffic_profiles.json`. Defaults: bike 35%, auto
25%, car 20%, bus 8%, coal truck 7%, tractor 5%. The mine district uses the existing
OCP 5 Incline map anchor within 850 m. Rajeev/Rajiv-named roads and trunk/motorway
sections use the highway profile. These are editable gameplay approximations.

## Three tuning controls

1. `TrafficManager.max_active_vehicles`: default 25; lower this for lighter mobile traffic.
2. `TrafficManager.spawn_interval`: default 0.3 seconds; lower to fill available slots faster.
3. JSON `profiles[].max_speed`: increase for faster traffic; highway speed_scale is 1.4.

The manager is constructed by code, so change defaults in its script or set exported
values on the runtime Traffic node in the Remote inspector for a temporary trial.
Per-vehicle physics reuses nodes/curves and does not construct queries or arrays.
Spawn-time validation and infrequent profile changes can allocate.

## Files

Created:
- `scripts/world/traffic_manager.gd`: bounded fleet, local spawn/despawn, district selection and following gap.
- `scripts/world/traffic_lane_builder.gd`: directed left-hand paths, connectivity and cycle eligibility.
- `scripts/world/traffic_light_controller.gd`: green/amber alternating phases and phase signal.
- `scripts/world/traffic_stop_point.gd`: approach phase and stop progress metadata.
- `scenes/traffic/traffic_vehicle.tscn`: reusable body/collider/detector layout.
- `scenes/traffic/traffic_junction.tscn`: controller and four named stop markers.
- `data/vehicles/traffic_profiles.json`: single editable profile and district data file.
- `tests/traffic_manager_regression.gd`: annulus, clearance, cap, travel/return, and optional real-city integration.
- `docs/TRAFFIC_V1.md`: setup, tuning, limitations and validation.

Modified:
- `scripts/world/traffic_builder.gd`: preserves existing world entry point and delegates to manager.
- `scripts/world/traffic_vehicle.gd`: CharacterBody3D path movement, braking, collision and profile reuse.
- `scripts/world/signage_builder.gd`: synchronizes existing lamps to traffic controller.
- `tests/traffic_regression.gd`: following, smooth movement and lane stability.
- `tests/traffic_signal_regression.gd`: red/yellow stop, green release and junction clearance.
- `tests/test_drivable_and_missions.gd`: adapts ambient visual fixtures to physics paths (full combined suite not run).
- `tests/scooter_regression.gd`: occupants and physical obstacle braking/release.
- `tests/ambient_ground_contact_regression.gd`: baked lane relief and existing pedestrian contact.
- `tests/scene_regression.gd`: replaces fixed startup fleet assumptions with dynamic system invariants.
- `tests/test_godavarikhani_living_district.gd`: checks district traffic availability/cap without forcing startup bus names.
- `docs/lessons/VEHICLES.md`: traffic mistakes, prevention rules and regression evidence.

Godot generates `.uid` companions for the new GDScript files.

## Verification record (updated 2026-11-01)

Passed after the streaming cleanup fix:
- Required movement regression: WASD, diagonal normalization, idle stability,
  movement, parked input isolation, vehicle entry/exit and recovery.
- Traffic following/lane stability, red/yellow/green signal behaviour and junction commitment.
- Manager spawn annulus, clearance (including parked vehicles), pool cap and travel/return.
- City integration: movement, four stops, at most 25 active vehicles and 150 m focus travel/return.
- Scene, camera, engine sound and vehicle entry regression assertions.
- Streaming ownership regression: attached/detached roads and cached building chunks.

The earlier entry assertion no longer fails with the current checkout. No entry
or player code was changed in the cleanup task. The large scene shutdown leak
was traced to detached road sectors retained by `RoadBuilder`; its new teardown
frees those orphan sectors. Full city/movement/scene checks now release their
road mesh/material resources. The chase-camera fixture now stops engine audio
and frees its nodes before quitting; normal-speed audio teardown passes cleanly.

Cleanup files:
- `scripts/world/road_builder.gd`: free detached sector nodes during teardown.
- `tests/world_streaming_cleanup_regression.gd`: catch orphan sector/cache leaks.
- `tests/chase_camera_regression.gd`: retire live fixture audio and nodes before shutdown.
- `docs/lessons/BUILDINGS.md`: document sector ownership and teardown requirements.
- `docs/lessons/TESTING_AND_TOOLS.md`: document live audio fixture cleanup.
- `docs/lessons/VEHICLES.md`: update movement regression status.

Rendered integration is checked on Apple M1/OpenGL Compatibility; captures are
`/tmp/mana_ooru_traffic_v1.png` and `/tmp/mana_ooru_traffic_overview.png`.
This is not a measured mobile performance benchmark. No Android device was
connected (`adb devices` returned an empty device list). Manual walking/driving
150 m with live input and mobile hardware performance remain untested; the
integration test moves traffic focus 150 m and back, while movement/vehicle
regressions test actual movement and driving separately.
