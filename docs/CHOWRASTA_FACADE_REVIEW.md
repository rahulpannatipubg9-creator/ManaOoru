# Chowrasta facade increment — 27 October 2026

This increment adds evidence-aware appearance handling, not a completed Mapillary
replica. The other chat's 11 Overture additions are retained without duplication.

The offline inventory in `outputs/facade_review/chowrasta_inventory.json` contains
78 buildings within 50 m of the straight line between Chowrasta and the verified
New Ashok Theatre pin. This is a study envelope, not the exact road boundary.
None has an explicit colour, height or floor-count source attribute. The available
June 2020 Mapillary notes have no reliably matched individual facade. Consequently
no real-world facade colour, entrance or window arrangement was invented.

Changes:
- BuildingBuilder honours valid explicit hexadecimal building colour and metric
  height tags. Exact height is used by both mesh and collision construction.
- Explicit residential buildings no longer receive random commercial shutters.
- Building metadata records appearance evidence, separate from illustrative paint.
- Storefront allocation respects explicit wall height and rejects a sign band too
  short to mount safely, instead of floating above a low roof.
- The repeatable offline audit records building IDs, source tags, assigned signs,
  coordinates and missing photo bindings. It does not mutate map data.

No new assets or runtime network dependency. No changes to roads, footprints,
character controllers, flight controls or vehicle handling. Existing unsourced
buildings keep their procedural appearance. Width/depth are deliberately not
rescaled from camera GPS or uncertain images.

Next evidence required: image ID/date, a confidently matched source building ID,
and individually reviewed appearance attributes. Nearby imagery alone is not a
valid match. The inventory is the worklist for that review, not a fabricated survey.

## Historical photo pilot

One adjoining roadside strip, OSM way 599199178, now has an interpreted visual
binding to geomannar's 11 June 2020 panoramas 518945536129912 and 974874736621788.
The observed two storeys and approximate muted salmon paint are recorded in
`data/local/building_appearance_references.json`, with match reasoning and limits.
This is not a current-condition or survey-grade claim. No imagery is bundled;
the source footprint, business assignments, roads and controls remain unchanged.
Window layout, shutters and exact metric height remain procedural/approximate.

Reference: https://www.mapillary.com/app/?pKey=974874736621788&focus=photo
Attribution: Mapillary / geomannar, 11 June 2020, CC BY-SA 4.0 imagery;
changes: interpreted storey count and approximate colour, no image texture reuse.

Validation performed: building appearance regression, signage mount regression,
movement regression and native rendered pilot capture all passed. Screenshot:
`outputs/facade_review/photo_pilot.png`. No physical mobile test performed.
