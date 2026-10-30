# Phase 2 central-area source coverage

Updated: 27 October 2026. This is a source-data readiness check for the next central Godavarikhani pass. “Mapped” means present in the bundled OSM-derived extracts; it does not mean field-surveyed or independently confirmed.

## Ready to use from existing data

| Area or feature | Local source evidence | Current treatment |
|---|---|---|
| Godavarikhani Chowrastha | OSM roundabout way `818565606`; OSM locality node `3384152837` about 3 m from the projection origin | Existing road geometry and locality marker; source map point, not a surveyed center |
| Laxmi Nagar | OSM locality node `2891164206`, approx. 658 m from the origin | Searchable destination; regression now verifies a walking route over the connected road graph |
| Lenin Nagar | OSM locality node `2891164207`, approx. 371 m from the origin | Searchable mapped locality point |
| Bus station and other mapped institutions | Existing named map objects and classified landmark records | Existing destinations and mapped road graph remain in the game |
| Central base roads/buildings | Bundled OSM roads plus Microsoft building footprints; current world build renders these into the common projection | Existing road network, collision and building generation remain intact |

Distances are approximate calculations using the project's existing projection. Locality points are not official boundary polygons.

## Not established by the bundled evidence

- No exact-name source record was found for the requested **Kalyan Nagar Centre** junction. Similar business-address text or a nearby road node is not enough to claim a junction location.
- The master-prompt priority junction names do not have reviewed, exact source records in the current location catalog. The **8** exact-name matches among all **114** prompt candidates are leads in other categories; matching text alone does not confirm entity identity.
- There is no evidence here for official lane counts, signal placement, median layout, current footpaths, active shops, or exact entrances around those candidate junctions.
- Candidate shop names remain unlocated unless a matching source record is separately reviewed. The existing storefront allocator only assigns mapped evidence; it leaves many records unplaced rather than moving them to a nearby facade.

## Next implementation slice

Use the existing Chowrastha/Laxmi Nagar mapped roads and building footprints for a bounded central-street visual review. Keep source geometry separate from inferred facade appearance. Add a named junction marker or change junction geometry only after an exact map record or user-provided observation supports it. The broad candidate list stays out of routeable gameplay until its identity and coordinate are established.

## Validation added

`tests/location_catalog_regression.gd` now checks that a Laxmi Nagar search returns the mapped OSM locality node and that its destination can route over the existing road graph. This is a data-to-navigation check, not evidence of on-site accuracy or road access policy completeness.
