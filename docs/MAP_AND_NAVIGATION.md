# Map and GPS Navigation

This document describes the minimap, full-screen map, OpenStreetMap import and
GPS routing in MANA OORU. Everything runs offline inside Godot; there are no
tile servers, map APIs or network calls.

## 1. Coordinate system

All systems share one conversion in
[`scripts/map/geo_projection.gd`](../scripts/map/geo_projection.gd).

| Item | Value |
|---|---|
| World origin | lon 79.513352, lat 18.751925 — the OSM way named `CHOWRASTHA` (Godavarikhani Chowrastha junction) |
| Axes | +X = east, −Z = north, +Y = up |
| Rotation | None (north is always −Z) |
| Scale | 1 world unit = 1 metre |
| Projection | Equirectangular around the origin |
| Playable radius | 3,000 m around the origin |

Conversion:

```text
x =  (lon − 79.513352) × 111,000 × cos(18.751925°)   ≈ (Δlon) × 105,100 m
z = −(lat − 18.751925) × 111,000
```

At a 3 km radius, the equirectangular distortion is far below 1%, which is
smaller than the positional accuracy of the community-mapped source data.

Longitudes and latitudes are always handled as 64-bit floats. They are
converted to metre offsets before being stored in `Vector2`, because a 32-bit
`Vector2` of raw degrees would lose about 1 m of precision.

The map plane used by the minimap and router is `Vector2(x, z)`. The 3D road
meshes, the building meshes and collision, the minimap and the router all read
the same projected points from
[`scripts/map/map_data.gd`](../scripts/map/map_data.gd). The regression test
checks that a rendered road mesh sits exactly on its map-data point.

## 2. Data pipeline

```text
data/osm/godavarikhani_core.json      every road + OSM building + named amenity within 3 km (Overpass)
data/osm/godavarikhani_features.json  shops, crossings, signals, barriers, railways, parks, water,
                                      named places/colonies, statues, health centres (Overpass)
data/buildings/godavarikhani_ms_buildings.json  Microsoft ML footprints missing from OSM (clipped)
data/local/traffic_signals.json       optional signals you know exist but OSM does not have yet
        │  parsed once per run
        ▼
MapData ── roads, buildings, POIs, crossings, signals, barriers, railways, areas, places, landmarks
   ├── RoadBuilder      carriageways, markings, zebras, medians, walls, rail, parks/water/pitches
   ├── BuildingBuilder  extruded footprints, merged per 160 m chunk, streamed nearest-first
   ├── SignageBuilder   name boards, locality boards, statues, crossing/rail signs, signals, dustbins
   ├── RoadNetwork      routable graph + 50 m spatial grid
   └── MapCanvas cache  road buckets + one building mesh for the minimap/full map
```

Refresh the data with `tools/fetch_osm.sh` (OSM), `tools/import_ms_buildings.py`
(Microsoft; instructions in the script), `tools/import_building_heights.py` and
`tools/import_terrain.py`. The tools use only the Python standard library and read
just the raster tiles they need. Nothing is downloaded at runtime.

### Roads
- 1,613 of the 1,620 highway ways in the extract have geometry inside the 3 km radius, and
  every one of them is rendered from its real centreline. (The previous extract held only
  650 roads and was missing most of the town.)
- Widths: OSM has no width tags here, so carriageways use the OSM lane count where tagged
  (3.5 m per lane), else typical widths per class (`scripts/map/road_style.gd`): trunk 7 m
  per direction, secondary 7.5 m, tertiary 6.5 m, residential 4.5 m, footpaths 1.8 m.
- Dual carriageways are two one-way OSM ways and are drawn as two carriageways with the
  real jersey-barrier median (40 mapped barrier lines) between them. Single roads get a
  dashed centre line; major roads get edge lines.
- Zebra crossings are drawn at the 20 mapped crossing nodes; railway lines (17) and their
  level crossings come from OSM.
- An automated test casts rays down along every road centreline and both carriageway
  edges (~25,000 points) and requires road surface under all of them.

### Terrain
- Real ground relief from the Copernicus DEM GLO-30 (30 m): the town slopes about 40 m
  from south-east to north, and the open-cast mine pit to the south-east is lower still.
- The DEM is a surface model (it includes buildings and trees), so `tools/import_terrain.py`
  removes them with a 45 m min/max filter and smooths the result. Heights are stored on a
  15 m grid relative to Chowrastha.
- Roads, markings, medians, walls, railways, parks, signs, statues, spawns, pedestrians
  and coins are all placed on the terrain surface; buildings stand on the lowest ground
  under their footprint. Terrain mesh and collision use the same triangles as
  `TerrainData.height_at`, and a test checks they match.

### Buildings
- 18,862 buildings: 6,544 from OSM and 12,319 from Microsoft Global ML Building Footprints
  (only where OSM has no building; footprints that overhang a road are trimmed back to the
  carriageway edge, and 710 that sit on a road are dropped).
- Every building is extruded from its exact footprint shape and position.
- **Heights are measured** for about 96% of buildings, from Google Open Buildings 2.5D
  (2023, satellite-derived, roughly ±1 floor). Most of the town comes out as 1–2 floors,
  with taller buildings along the main roads. The rest fall back to generated floor counts.
- **Not in the open data:** paint colours, windows and shopfronts. They are chosen
  deterministically per building (rolling shutters on ground floors along main roads,
  water tanks on many roofs).

### Places, signs and street furniture
- Name boards for 140+ mapped places (hospitals, schools incl. SCCL School, temples,
  masjids, banks, shops, theatres, police stations, the TGSRTC bus station), placed at the
  roadside in front of the mapped position. Unnamed mapped shops get a category board
  (e.g. TEA STALL, BAKERY).
- Green locality boards for the 13 mapped colony/locality names; statues at the mapped
  Jawaharlal Nehru, Mahatma Gandhi, Telugu Thalli and Ambedkar statue points.
- Jawaharlal Nehru Stadium uses its real OSM outline with a compound wall and name board.
- **Traffic signals:** OpenStreetMap has **no** traffic signals mapped in Godavarikhani
  (checked 2026-10-24), so by request the game puts signals at **every junction on a main
  road** (trunk, primary, secondary or tertiary meeting at least two other arms), about
  310 junctions. Roundabouts such as Chowrastha are left unsignalled; the two halves of a
  divided road count as one junction; poles stand on each inbound arm's left kerb and
  never on a carriageway. Lights cycle green → amber → red with crossing arms in opposite
  phases. These positions are generated, not surveyed. Signals mapped in OSM or listed in
  `data/local/traffic_signals.json` are added as well. Cars do not stop for them yet (there
  is no AI traffic).
- **Dustbins are ambience,** not mapped data: one municipal bin beside each commercial
  board.

### Gameplay placement
- The person spawns at Chowrastha; the five cars park on real road shoulders nearby, all
  chosen at start-up to be off every carriageway and clear of buildings (tested).
- The previous hand-placed props (start plaza, fake stadium, playground, bus stop, trees)
  were removed because they sat on top of real roads and buildings.

## 3. Minimap

Implemented in [`scripts/ui/minimap.gd`](../scripts/ui/minimap.gd) and drawn by
[`scripts/map/map_canvas.gd`](../scripts/map/map_canvas.gd).

- **Position:** bottom-left corner. On Android it sits above the joystick.
- **Follows:** the person on foot, or the occupied car from the moment of entry
  (`main.gd → tracked_body()`).
- **Shows:** roads (major, minor and path styles), buildings, landmarks, parked
  cars as blue icons, the GPS route in purple, and the destination marker. The
  marker is clamped to the minimap edge when it is off-screen. The player
  arrow points along the body's real forward axis (+Z).
- **Zoom:** five levels from 0.35 to 2.4 px/m.
- **Orientation:** north-up, or heading-up. Heading-up shows a rotating **N**
  compass marker.
- **Status strip:** destination, remaining distance and walk/drive mode, or the
  routing error.
- **Refresh:** capped at 30 Hz on desktop and 15 Hz on mobile, dropping to 8 Hz
  when FPS falls below 40. It redraws only when the tracked position or
  heading, the zoom, the orientation or the route changes.

## 4. Full-screen map

Implemented in [`scripts/ui/full_map.gd`](../scripts/ui/full_map.gd).

- North-up view with landmark labels; labels are hidden below 0.4 px/m to avoid
  clutter.
- A destinations list of the 12 nearest or most important places.
- Buttons: zoom −/+, **ME** (re-centre on the player), **CLEAR ROUTE** and
  **CLOSE**.
- The OpenStreetMap attribution is always visible on the map.
- While the map is open, the scene tree is paused, so the person, cars, camera
  and GPS freeze and resume exactly as they were. The 3D world is not
  rendered behind the map (`Viewport.disable_3d`), which cut frame time from
  25 ms to 8 ms in testing.

## 5. Routing

Implemented in [`scripts/map/road_network.gd`](../scripts/map/road_network.gd)
and [`scripts/map/gps_navigator.gd`](../scripts/map/gps_navigator.gd).

- **Graph:** 6,415 OSM nodes and 7,666 edges. Ways join only at shared OSM
  nodes, so flyovers and bridges do not connect to the roads below them.
- **Walking:** may use every road and path except motorways, in both
  directions.
- **Driving:** uses vehicle highway classes only, respects `oneway=yes/-1` and
  roundabouts, and prefers bigger roads. The cost per metre ranges from 0.8
  for trunk roads to 1.15 for residential roads and 2.0 for tracks.
- **Snapping:** the start and the destination snap to the nearest usable road
  segment, within 250 m, in the largest connected network. This prevents
  routing onto disconnected fragments.
- **Search:** A* with an admissible straight-line heuristic. Typical routes
  take about 3 ms.
- **Failure:** the GPS shows a readable error such as "No drivable road within
  250 m of that point". It never draws a straight line instead of a route.
- **Progress:** sampled 5 times per second over a 40-segment window ahead of
  the last position. The route behind the player is trimmed.
- **Rerouting:** happens when the player is more than 35 m (driving) or 25 m
  (walking) off the route for 1.5 s, at most once every 2 s. Switching between
  walking and driving also re-plans the route.
- **Arrival:** within 18 m (driving) or 10 m (walking) of the route end, the
  GPS shows "Destination reached" for 4 s and then clears the route.

## 6. Controls

| Action | Desktop | Android / tablet |
|---|---|---|
| Open the map | **M** or click the minimap | Tap the minimap or its **MAP** button |
| Close the map | **M**, **Esc** or **✕ CLOSE** | **✕ CLOSE** |
| Zoom the map | Mouse wheel, −/+ buttons | Pinch, −/+ buttons |
| Pan the map | Left-drag | One-finger drag |
| Set a waypoint | Left-click the map or a destination | Tap the map or a destination |
| Clear the waypoint | Right-click or **CLEAR ROUTE** | **CLEAR ROUTE** |
| Zoom the minimap | **=** / **−**, or the wheel over the minimap | **+** / **−** buttons |
| Switch north-up / heading-up | **N** | **N/H** button on the minimap |
| Pause | **Esc**, and **Esc** again to resume | — |

## 7. Licensing and ODbL compliance

The map data is © OpenStreetMap contributors and licensed under the
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
It was fetched via the Overpass API; the snapshot timestamp is in the file's
`osm3s.timestamp_osm_base` field (2026-10-24T19:23:47Z).

Obligations and how the game meets them:

1. **Attribution.** "Map data © OpenStreetMap contributors, ODbL 1.0 •
   openstreetmap.org/copyright" is always shown on the full map. It also
   appears in `ASSET_LICENSES.md`, and a store listing or credits screen must
   include it as well.
2. **Share-alike for the database.** The bundled JSON is an unmodified OSM
   extract. Distributing the game distributes this database, so it stays under
   ODbL and must be available to recipients; it ships readable inside the
   build. If the extract is ever modified (cleaned, merged or enriched), the
   modified database must be offered under ODbL as well.
3. **Produced work.** The game's rendered roads and buildings are a Produced
   Work. Only the attribution notice is required; the game itself does not
   have to be open-source.
4. **Microsoft building footprints** are also ODbL 1.0: "Building footprints © Microsoft".
5. **No proprietary sources.** No Google Maps, Bing or other proprietary
   imagery or road data was used.

## 8. What is verified and what is not

- **Verified by tests:** road surface covers every mapped centreline and both edges;
  buildings stand on their footprints; every mapped road is rendered; spawn and parked
  cars are clear of buildings; landmarks such as Jawaharlal Nehru Stadium, SCCL School,
  the TGSRTC bus station and Ram Mandir are present.
- **Not verified:** completeness of OSM/Microsoft data (some lanes, buildings and places
  may be missing or outdated), real road widths, building heights and colours, and any
  street furniture that is not mapped (signals, dustbins, sign text and styling).
