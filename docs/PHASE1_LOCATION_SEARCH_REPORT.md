# Phase 1 location search and source inventory

Updated: 27 October 2026. Scope: offline location discovery and mapped-road topology for the existing Godavarikhani game map. No remote geocoding or gameplay world-generation changes were made. Drainage remains disabled in normal launches.

## Delivered

- Generated `data/locations/source_locations.json` from the bundled OSM core/features and user-export extracts, the existing Overture/OSM-derived place catalog, and existing curated pins. Every record retains its source file/record identity when available, license, snapshot timestamp when available, raw classification, and coordinate role. Missing upstream IDs remain missing.
- Added `data/locations/candidate_locations.json` for names from the master prompt. It contains **114 candidates**, all with null coordinates. **8** have exact-name source matches that are leads for review only; those matches do not place or route to a candidate.
- Generated `data/locations/junction_topology.json` with **2,520** shared-node road junction candidates inside the 3 km playable radius. Branch count is graph degree, not surveyed lane count or a confirmed named junction.
- Added offline full-map search across mapped names, aliases, categories, localities and streets. Source-backed points inside the playable boundary can be selected; out-of-area points, OSM `fixme` records and unlocated name candidates are disabled. Search labels distinguish source points, representative geometry centers, local assertions and unverified candidates.
- Corrected Overture place category fallback so unknown business/place categories are not silently converted into shops.
- Added regression coverage for candidate separation, mapped Vidya Nagar 2 entrance routing eligibility, review flags and full-map search. Fixed result-list cleanup when the search changes between results and an empty state.

## Inventory snapshot

The generated source catalog contains **547** mapped records, with **494** inside the playable radius. Categories: 365 amenity, 67 shop, 32 landmark, 27 other, 19 road, 14 locality, 13 food and 10 transport. These counts describe registry records, not unique real-world establishments or the number of visible game objects; overlapping OSM extracts are deduplicated by OSM object ID, while independently sourced records may still refer to the same place.

The Chowrastha origin comes directly from `GeoProjection`: 79.513352 E, 18.751925 N, 3,000 m radius. Source coordinates are projected through that same game projection. A mapped coordinate or a high source confidence does not mean field verification. Way centers are explicitly labeled representative geometry centers, not entrances. OSM warnings are retained and those records are not selectable as destinations.

The registry records the per-file source snapshot available locally. It does not recover underlying source IDs or update timestamps lost by the pre-existing `godavarikhani_places.json`; those rows are flagged with absent IDs and are not upgraded to field-confirmed status. Existing license strings remain source-specific. OSM-derived content retains ODbL attribution; Overture-derived rows retain their declared source license. Review `ASSET_LICENSES.md` before redistribution, especially for mixed databases and attribution placement.

## Accuracy and coverage limits

- Coverage is the bundled source map within a radial 3 km game boundary, not a complete business directory. Source records outside the boundary are retained but disabled in search.
- The 2,520 topology entries arise only from shared OSM road-node IDs. They do not join nearby geometric crossings, prove traffic control, determine official junction names, or report lane counts.
- User/shop Overpass rows can include non-shop amenities and way centers. Classifications are retained as source evidence and should be reviewed before using them for gameplay interactions.
- Exact-name matching for the 8 candidate leads does not prove entity identity. No candidate-only name receives a fabricated position.
- The game routes over its existing road graph. This catalog does not validate access restrictions, closures, turn restrictions, street entrances or legal real-world routing.
- OSM and Overture map data are not an on-site survey. No field-verified coordinates, shop operations, building entrances or street-side conditions are claimed.

## Test evidence

Executed on Godot 4.7.2:

- `godot --headless --path . --script tests/location_catalog_regression.gd` — PASS.
- `godot --headless --path . --script tests/navigation_regression.gd` — PASS, including source-backed and unlocated-candidate search states; world output reported **0 legacy drainage segments**.
- `godot --headless --path . --script tests/movement_regression.gd` — PASS.
- Godot `--check-only` for `scripts/ui/full_map.gd` and `scripts/map/map_data.gd` — PASS.
- `python3 -m py_compile tools/build_location_catalog.py` and generator rebuild from the attached master prompt — PASS; counts above reproduced.

These tests do not establish visible UI quality on the user's device, live-data freshness, field accuracy, mobile performance, export/install behavior or redistribution permission. Those checks remain outstanding.

## Recommended next step

Review the map-search experience and source rows around one neighborhood. Verify candidate identity and exact entrance/road position with free OSM editing/map sources or direct observation before making candidate rows navigable. Keep inferred facade art and procedural city dressing separate from mapped geometry. Do not activate CityLife modules or drainage as part of this location-search slice; the separate architecture and QA audits document those systems as dormant or intentionally excluded.
