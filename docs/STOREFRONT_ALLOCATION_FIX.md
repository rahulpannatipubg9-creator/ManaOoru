# Storefront ownership and stacking fix

## Root cause

The previous allocator selected the nearest building within 18 metres for every
atlas entry, regardless of building use, source identity, entrance or ownership.
The renderer then multiplied horizontal sign capacity by the number of vertical
rows available below the roof. This let unrelated businesses accumulate across
upper floors. Randomly chosen commercial-looking facade finishes were not evidence
of actual retail use. Repeated assignment calls also accumulated state.

## Implemented ownership model

`storefront_allocator.gd` retains business source records and connects each rendered
panel to one business ID, storefront ID and building ID. OSM identifiers are kept
when supplied; other records use stable name/GPS identifiers. Aliases retain their
original names, coordinates and source records without adding another panel.

Business pins must lie inside exactly one footprint, with only a 10 cm boundary
tolerance. Nearby buildings are never used as spare capacity. Explicit residential
building types reject inferred shops. A generic footprint with several unrelated
occupants remains unresolved unless the building has an exact named occupant.

Multi-unit frontage is permitted for source-tagged retail, commercial or mixed-use
buildings. Capacity derives from frontage width and the configured 3.2 m minimum
unit width. Unit entrances are frontage anchors, explicitly recorded as inferred;
they are not surveyed doors. Each business projects onto its own frontage unit.
Conflicting demand leaves all competing records unplaced rather than choosing an
arbitrary winner or moving a shop to an empty unit.

Signs occupy one band 2.45–3.15 m above the building base, preserve the atlas aspect
ratio, fit within their wall and face the mapped road. Complete panel segments are
checked against road widths. Upper floors never increase shop capacity. Unassigned
named businesses remain map records and do not turn into roadside pole signs.

The allocator clears all ownership state each pass; BuildingBuilder setup replaces
generated children, footprint state and spatial indexes. Assignment is deterministic.
Checks happen during generation, not per frame. Existing merged chunk rendering
and streaming remain in use.

## Files

| File | Change |
|---|---|
| scripts/world/storefront_allocator.gd | Ownership, building use, capacity, conflicts, unplaced reasons |
| scripts/world/building_builder.gd | Allocator integration, safe sign band, road corridor check, repeatable setup, report/debug view |
| scripts/world/signage_builder.gd | No pole-sign fallback for unresolved named businesses |
| scripts/map/map_data.gd | Keep original OSM building IDs alongside existing geometry |
| tools/signboards/make_signboards.gd | Preserve source metadata and OSM feature records in atlas metadata |
| assets/textures/signboards/boards.json and signboards.png | Regenerated existing name atlas with provenance |
| tests/storefront_allocation_regression.gd | Crowding, residential, geometry, rotated frontage, deduplication, regeneration cases |
| tests/signage_mount_regression.gd | Ownership consistency, band limits, overlaps, road facing, full regeneration, reference capture |

## Validation and before/after

The synthetic 15-business single-building case now leaves all 15 unresolved.
The same collocated pins on a retail building also remain unresolved; no unit
relocation occurs. Separate retail frontage pins receive separate units.

The bundled world produces 120 valid facade assignments and 307 unplaced canonical
records. No building currently receives more than one rendered business panel.
Unplaced reasons are: 232 without a containing footprint; 10 overlapping-footprint
ambiguities; 26 without verified multiple units; 32 road-corridor conflicts;
5 not belonging to the named building; 2 without valid road-facing frontage.

Passed: storefront allocation regression, complete world signage mount regression
(including identical results after rebuilding), scene regression, movement
regression, and Godot editor import. The latter two cover camera collision and
clamping, vehicle enter/exit, movement and recovery. Existing ObjectDB exit leak
warnings remain in the scene test; this change does not claim to repair them.

The NEW ASHOK/NEW ASHOKA source aliases render as one complete facade panel, verified
in a rendered close-up. This is a reference visual check, not a visual survey of
every road in the town. Automated allocation/mount checks cover the complete data.

## Reports, debug mode and limits

Every generation writes `user://signage_placement_report.json`, containing source
records, numeric coordinates, unit ownership, assignments and unplaced reasons.
Run with `-- --signage-debug` for green facade normals and red unplaced-pin markers.
This mode is disabled by default.

Unresolved records need building ownership/entrance data or surveyed corrections.
An OSM/Overture pin is not proof of the precise entrance. No verified multi-tenant
directory layout was supplied, so no directory is invented or generated from a
stack of storefront panels. Verified directories need explicit tenant/entrance
configuration and a dedicated layout in a later pass.

This change addresses the critical ownership/stacking request and signage road
clearance. It does not rebuild buildings or alter roads, vehicle physics, player
controls, traffic, landmarks, poles or wires. The wider environmental phases in
the attached master document remain separate work, not claimed complete here.
