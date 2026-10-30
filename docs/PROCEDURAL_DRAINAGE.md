# Representative roadside drainage

The main city now loads original procedural drainage scenery. It does not use the TGRAC, Bhuvan or WRIS research extracts and makes no claim of surveyed drainage alignment. The existing synthetic drainage demo and its physics remain separate and unchanged.

## Appearance and integration

`world_generator.gd` creates `RoadsideDrainageBuilder` after the existing world assets, vehicle spawns and shop interactions. It derives candidate paths from the same `MapData` road coordinates and `RoadStyle` widths used by the game. No road, building, terrain, minimap, vehicle, camera or movement geometry/behaviour is changed.

- Covered sections include procedural concrete slab joints, inset grate patterns and inspection-cover patterns.
- Open sections are reserved for local streets with generous foundation/entrance clearance. Water animates through an opaque lightweight shader, without downloaded textures, reflections, particles or fluid simulation.
- Channels are 0.64 m wide, with their inner edge 1.35 m beyond the carriageway. The one-metre shoulder is retained.
- Building footprints, every road corridor, railways, mapped barriers, blocking land-use areas, street-life occupancy, vehicle/player/helicopter spawns and bus/shop activity areas exclude conflicting candidates.
- Full swept-segment checks reject foundation/road intersections, including crossings between sample points. Unknown entrances are protected through building setbacks; storefront anchors add a 9 m zone in which open channels become covered sections.
- Endpoints remain inside the 3 km playable boundary with a half-width allowance. Steep or insufficiently planar sections are omitted. Tight bends and junctions may have deliberate gaps; drains are never forced through conflicts.

## Physics and limits

This first city version is visual scenery and creates **no collision bodies, shapes or areas**. The existing terrain collision stays intact, including across shallow water. Characters and vehicles cannot fall into these channels. Open sections are therefore not excavated trenches or a hydraulic network.

The bed is 0.14 m below the terrain collision reference, the water 0.085 m below it, and the rim 0.018 m above it. The project's visible terrain is already 0.20 m below its collision reference, so the shallow visuals fit above that terrain without cutting it. Validation rejects sections where local ground curvature would hide the bed. Covers are visual access details, not new physical slabs.

There are no underground connections or rainfall-driven water levels in this release. Water motion is an appearance effect, not evidence of drainage direction. Existing geometry can be extended later if physical trenches or rain behaviour are wanted.

## Performance and controls

- Candidate budget: 12,000 sections on desktop and 6,000 on mobile; rejected sections are not replaced by unsafe placements.
- A deterministic mix of source runs prioritises the immediate Chowrastha area and distributes the remaining candidates across the city. It intentionally does not cover every street.
- Geometry is merged into 160 m chunks, normally one concrete and one water mesh per occupied chunk. Shadows are disabled for these meshes.
- Generation processes short jobs within a 3 ms loop budget each frame. A job/mesh commit is indivisible and can exceed that target; this is not a hard frame-time guarantee. Chunk priorities follow the existing building focus callable.
- Render distance: 300 m desktop, 180 m mobile.
- `world.drainage.enabled = false` hides and pauses the system. `water_enabled = false` hides water meshes. These are developer controls; no new player-facing menu is added.
- Launch with `-- --no-drainage` to disable the city generator, or `-- --drainage-debug` for orange placement geometry.

The captured desktop world contains 1,663 covered and 4,225 open sections: 5,888 total, 284 meshes and approximately 77,578 triangles. Forcing all drainage generation synchronously took about 3.1 seconds in the follow-up headless verification run; normal play spreads that work across frames. This is not an FPS measurement, mobile benchmark or claim of a citywide performance target being met.

## Files

- `scripts/world/roadside_drainage_builder.gd`: placement, exclusions, bounded chunk generation and quality controls.
- `shaders/roadside_drainage.gdshader`: original procedural concrete, seams, grates and inspection covers.
- `shaders/roadside_drainage_water.gdshader`: opaque animated shallow water.
- `scripts/world/world_generator.gd`: main-world integration only.
- `tests/roadside_drainage_regression.gd`: isolated placement tests and optional full-world/capture checks.
- `outputs/drainage/preview.png`: actual city render captured with the OpenGL Compatibility renderer on Apple M1.

## Validation

Run the isolated/full-world checks:

```
godot --headless --path . --script tests/roadside_drainage_regression.gd -- --full-world
```

Capture the actual city with a graphics-enabled run:

```
godot --path . --script tests/roadside_drainage_regression.gd -- --full-world --capture
```

The capture script saves `/tmp/mana_ooru_city_drainage.png`. A checked copy is retained in `outputs/drainage/preview.png`.

Tests cover road/junction/foundation clearance, protected vehicle space, covered entrance approaches, boundary limits, no added collision, deterministic regeneration, quality switches, both appearance types in the actual city, unchanged road/building coordinates and placement reaching beyond 2.5 km from the origin.

Actual validation on Godot 4.7.2 / Apple M1:

- PASS: roadside drainage regression, including full-city coordinates unchanged and coverage beyond 2.5 km.
- PASS: required movement regression (final retry; one preceding run reached the 100-second test-runner timeout).
- PASS: camera regression.
- PASS: scene regression.
- PASS: existing synthetic drainage regression.
- PASS: vehicle suspension regression. That existing test emitted ObjectDB/resource cleanup warnings at exit; no physics changes were made in this work.
- PASS: graphics-enabled city capture and visual inspection; no shader errors in the capture log.
- Not measured: gameplay FPS, mobile FPS and long exploration memory soak.

Follow-up visual review: covered drains were partly hidden by existing 1.8 m shopfront aprons. The drainage generator now reserves apron depth plus 0.55 m around building footprints (2.35 m margin before channel half-width), even before building chunks render. Buildings and their platforms are unchanged. Added a regression for apron space outside a source footprint; full-city drainage and required movement regressions passed again. Fresh close-up, covered, street and overhead captures are in `/Users/rahulpannati/Documents/New project/drainage-gallery/`.

Weathering pass: original procedural shaders now add multiscale concrete mottling, pores, sparse irregular hairline fractures, worn/chipped slab edges, rusty iron grates and inspection covers. Wall UVs carry relative height for damp/algae staining; channel beds use a separate silt material classification. Water is darker and less glossy with slow variation and stationary sediment along the banks. Only material attributes/UV metadata changed: no vertices, placement, roads, terrain, physics or draw-call/triangle counts changed. The full-city drainage regression passed with the same 5,888 sections and 77,578 triangles. Graphics-enabled close-ups were checked on the M1 Compatibility renderer. Before/after captures are stored outside the project in `/Users/rahulpannati/Documents/New project/drainage-weathered/`. No FPS benchmark was performed for this material pass.
