# Phase 1 QA and performance audit

Scope: current MANA OORU working tree, Godot 4.7.2 on the development Mac. This document distinguishes inspected coverage from tests actually executed for this audit. It is not release sign-off. No gameplay, source map, scenery or save data was changed for the audit.

## Highest-priority findings

1. **Dormant CityLife is a runtime integration blocker.** `scripts/main.gd` preloads `CityLifeController` and declares `city_life`, but `_ready()` never constructs, adds or calls `setup()` on it. Guarded interaction/save/journal/weather branches therefore remain inactive in the normal launch path. `scripts/world/city_life.gd` contains commerce, energy/fuel, discoveries, interiors and persistence, but code existence is not proof of a working player loop. The fallback shop interaction only spends a coin and shows a purchase message; it does not provide CityLife inventory/progress. Decide whether these modules belong in the next milestone, then enable deliberately behind a tested integration path; do not silently claim them as delivered.
2. **The CityLife test has an unsafe null dereference.** `tests/city_life_regression.gd` assigns `life = game.city_life`, then writes `life.save_enabled` before its later non-null check. Given the current launch path, this would produce a script error instead of a useful bounded test failure. The suite was not executed here to avoid starting an additional full-world instance and hanging on this known issue. A parent-run harness must impose a timeout and treat script errors as failure regardless of process exit code.
3. **Performance targets lack measured evidence.** `docs/PERFORMANCE_BUDGETS.md` explicitly labels its values acceptance targets, not measurements. A repository search found no continuous sampling harness using Godot `Performance`, render draw-call counters, memory counters or frame-time distributions. Static screenshots and headless build durations are not FPS/GPU measurements.
4. **Runtime place provenance is incomplete.** Curated place imports filter catalogue `confidence`, but `_add_chowrasta_reference_pin` stores newly added runtime POIs as name/kind/position, without carrying per-record source/confidence/observation age. Global OSM attribution/timestamp and original catalogues remain available, and other loaders retain some IDs/source fields, but there is no uniform provenance contract or user-visible trust status. A confident pin is not a verified shop entrance or verified facade.
5. **Fast-travel/streaming and camera-obstruction cases remain unproven.** Tests cover local movement and camera modes, but no repeatable high-speed multi-chunk traverse with readiness/frame-time/memory assertions was found. Camera tests exercise control behavior and configured collision masks, not a complete rendered obstacle/corner-clipping matrix.

## Tests actually run during this audit

Each command was executed serially with a 30-second external timeout:

```sh
godot --headless --path . --script tests/<name>.gd
```

| Test name | Observed result | Approximate wall time | What that establishes |
|---|---|---:|---|
| `ambient_ground_contact_regression` | PASS, exit 0, clean log | 1.17 s | Nonlinear lane terrain sampling, unchanged route progress, neutral/animated capsule sole support, road surface versus lowered visible terrain |
| `traffic_regression` | PASS, exit 0 | 0.75 s | Ambient mapped-route progress and end-of-route turnaround |
| `traffic_signal_regression` | PASS assertions, exit 0 **with cleanup warnings/errors** | 0.74 s | Red-light wait and green release; 7 ObjectDB instances and 2 resources reported remaining at exit, so this is not a clean resource-lifecycle pass |
| `storefront_allocation_regression` | PASS, exit 0 | 0.25 s | No nearest-building relocation, residential rejection, source retention, capacity/ownership and deterministic regeneration |
| `building_appearance_regression` | PASS, exit 0 | 0.25 s | Explicit metric height/paint, preserved shader encoding, rejection of invalid evidence, residential facade classification |
| `overture_buildings_regression` | PASS, exit 0 | 0.54 s | 11 supplemental source IDs, coordinate projection fidelity, no fabricated attributes |
| `chowrasta_pins_regression` | PASS, exit 0 | 0.55 s | 214 eligible user-export places; 96 added, 118 already represented, 2 outside; 66 reference pins in 1 km zone |

Durations are local command wall time, not in-game CPU frame time. These tests do not establish screen appearance, frame rate, Android performance or city-wide ground contact. Other agents/parent may run integration checks separately; their results must be recorded independently rather than inferred here.

## Existing suite inventory and limits

The following were inspected for intended assertions, **not rerun in this audit** unless listed above.

| Area | Existing suites | Intended coverage and remaining limits |
|---|---|---|
| Main walk/drive loop | `movement_regression` | Required by AGENTS after gameplay changes. Touch/keyboard displacement, camera-world-yaw stability, seven enterable vehicles, parked exclusivity, entering/driving/exiting, recovery and seating. Initial direction assertions compare literal expected vectors rather than exercising the real controller, so do not equate them to full camera-relative direction coverage. Run this once after integrated changes. |
| Character collision | `character_physics_regression`, `test_character_regression`, `character_scale_regression`, `male_locomotion_regression` | Slopes/grounding, stairs, walls, headroom/crouch, jump/landing, falls and vehicle impacts; isolated fixtures are useful but do not prove every city doorway or merged collision seam. |
| Vehicle dynamics | `handling_regression`, `suspension_regression`, `gearbox_regression`, `vehicle_lab_regression`, vehicle-specific suites | Ground contact, stability, acceleration/braking, slope hold, collisions and vehicle layouts. Lab measures physical handling metrics, not whole-city FPS. |
| Entry/exit | `vehicle_entry_regression`, `movement_regression`, `exploration_flow_regression` | Door approach, animations/audio invocation, driver pose/pedals, handoff and safe airborne-helicopter exit blocking. Add repeated blocked-door/low-ceiling/uneven-road scenarios and interrupted transitions. |
| Camera/control ownership | `camera_regression`, `chase_camera_regression`, `scene_regression`, `exploration_flow_regression` | First/third person, look-behind, stable movement yaw, chase lag, FOV, input suspension/focus notifications and UI blocking. Scene test checks spring-arm mask/margin, but that is not measured near-wall camera clipping. Synthetic focus events do not replace actual OS blur/resume testing. |
| Projection/routing/UI | `navigation_regression` | Projection round trip, graph-edge route fidelity, one-way behavior, no fake straight route on failure, geometry/collision alignment, minimap tracking, waypoint/progress/reroute/arrival, walk/drive handoff, map pause and touch interactions. It constructs full world and main scene sequentially; reserve for coordinated integration runs. Single-route A* <50 ms assertion is a latency guard, not p95/p99 navigation timing or a 16.7 ms rendered frame guarantee. |
| Source map geometry | `map_regression`, `vidya_nagar_2_regression`, `overture_buildings_regression`, `chowrasta_pins_regression` | Road render ID coverage, district density/preload, supplementary original rings and IDs, pins within radius. Real-world accuracy and source currency are not verified by matching a downloaded source. |
| Shop placement | `storefront_allocation_regression`, `signage_mount_regression`, `scene_regression` | Deterministic allocation, no invented relocation, mounting/clearance and expected signs. Does not verify current real shop operation, tenancy, exact entrances or every sign from street eye level. |
| Commerce/save/state | `city_life_regression` | Intended: day/night/rain, shelter, modal pause, purchases, fuel, discovery deduplication, versioned isolated persistence, malformed fields and safe indoor return. **Blocked by dormant module/null dereference** in current main. Test uses its own save path; preserve that isolation. |
| Drainage | Drainage-specific suites | Existing incidental tests are outside this visual/gameplay milestone. Their existence is not authorization to resume drainage implementation. |
| Performance/device/export | Documents and capture scripts | No automated measured city-streaming/long-session memory/GPU acceptance suite found. Physical Android/touch, current export and rendered profiler evidence are **NOT TESTED** here. |

## Navigation and map-data trust

Positive architectural evidence:

- `GeoProjection` defines the single Chowrastha origin and map/world axes.
- Roads preserve OSM way/node IDs; the route graph joins source node IDs and respects imported one-way direction.
- `RoadNetwork.find_route()` returns explicit failure rather than manufacturing a straight-line route.
- Buildings preserve OSM/Microsoft source markers; the supplemental Overture loader retains IDs and source records, with a passing source-geometry test.
- Storefront allocation keeps unplaceable businesses unplaced instead of attaching them to arbitrary nearby homes.

Limits requiring explicit product language and tests:

- Road widths without tags are class/lane estimates. Untagged colors, facade design and some heights are representative appearance, not surveyed facts.
- `RoadNetwork` infers walk/drive availability from highway class and one-way flags. It does not implement a comprehensive `access`, `motor_vehicle`, `foot`, turn-restriction relation or temporary-closure model. Routes are game navigation, not certified real-world directions.
- Runtime reference POIs do not uniformly retain source/confidence fields. Carry catalogue source IDs, license, snapshot date, confidence and geometry role (point/centroid/entrance) through import before presenting confidence UI.
- Largest-component snapping can reject a genuinely disconnected road; keep errors clear rather than bridging it speculatively. Max snap distance is 250 m and needs an obvious off-road waypoint explanation.
- A map pin, named building, inferred sign unit and actual interior doorway are distinct things. Acceptance checks should explicitly preserve this distinction.

## Performance architecture: bounded does not yet mean measured

`BuildingBuilder` has 160 m chunks, a nominal 4,000 µs generation budget per process pass, distance-prioritized pending work and visibility ranges. `build_around()` synchronously builds all qualifying chunks. `_process()` checks the time budget between whole chunk jobs, so one large chunk may exceed the budget. No eviction path was found: already built meshes/collisions remain allocated until rebuild/free; visibility distance hides rendering without releasing their memory. The world is finite, but memory can grow as more chunks are built.

Terrain and roads are also built across the district at startup. Therefore a promising local street capture cannot establish startup cost, worst-case chunk stalls, or long-session memory behavior. Ambient simulation distance and traffic/population limits help, but need profiling rather than stronger unmeasured claims.

Required measured evidence before calling the city polished/performance-safe:

1. Rendered desktop golden path through spawn street and Vidya Nagar 2, at fixed resolution and graphics settings; report frame-time median/p95/p99 and worst frame, CPU process/physics time and draw calls, with hardware/build/hash context.
2. A repeatable drive/fly route crossing several chunk boundaries and returning to spawn; sample pending/built chunks, first-visible readiness, frame spikes and memory. Separate first traversal from warmed traversal.
3. A bounded 30-minute rendered exploration soak. Track engine memory plus process resident memory and available render-memory counters; compare early/late plateaus and investigate growth after all relevant chunks have loaded. A shorter smoke run is not a soak pass.
4. Physical Android checks at the intended device tier: touch camera/movement, keyboard-independent input, low memory/resume, thermal throttling and 30 FPS target. The M1 desktop cannot substitute for them.
5. Export the actual target package and test its data/asset paths offline. Prior historical APK export is not proof the present working tree exports or performs correctly.

## Recommended execution order and bounded additions

**First resolve central gameplay availability:** confirm deliberate CityLife inclusion/exclusion, add a null-safe launch integration gate, then test walk → interact → enter → drive → map → exit → save/reload if save is enabled. Keep save tests on unique temporary paths and delete only those paths.

**Then run existing integration suites once:** movement, character physics, vehicle entry, camera, navigation and scene checks. Use a sequential runner with per-suite deadlines, require expected PASS text, and reject `SCRIPT ERROR`, failed assertions or unexpected cleanup errors even if the process exits 0. Never run several full-world renderers in parallel on the 8 GB M1.

**Useful new checks, limited in scope:**

- Table-driven launch smoke asserting required node/module existence before access; fail/quit predictably when unavailable.
- Camera ray/frustum tests approaching one wall, a narrow corner, a shop awning and a parked vehicle, including first/third-person transitions.
- Ten repeated entry/exit cycles with exactly one input owner, collision restoration, safe exit floor support and no accumulating transition nodes.
- Source-geometry fingerprint before/after appearance/streaming rebuild, with deterministic random seeds for scene probes.
- Corrupt/truncated save, unsupported version, failed write/rename, no duplicate rewards after reloading and interrupted indoor transitions. Save failure must be surfaced without destroying existing progress.
- Multi-chunk rendered traversal/profiler capture with explicit memory/frame budgets, rather than adding more static “count > 0” scenery tests.

No new tests or game code were added by this Phase 1 audit. The seven small suites above were executed; full integration, rendered performance, long soak, real OS focus and physical-device checks remain **NOT TESTED in this audit**.
