# Imported city exteriors

The main world now loads `scripts/world/imported_city_buildings.gd` before procedural building generation. Five user-created Blender exteriors replace their matched generic footprints: Srinivasa Theatre, Mythri Rajesh Theatre, Sai Leela Residency, Destination Restaurant, and Godavarikhani bus station.

Locations use the bundled OSM/Overture catalogue. Footprints are selected by containment or nearest centroid within 45 m; this association and road-facing orientation are estimates requiring visual review. Model dimensions are estimated from user photographs. Fit uses uniform scaling inside the footprint envelope. Mesh collisions are static triangle meshes; distant meshes are culled. Collision correctness in gameplay, photographic fidelity and M1/mobile performance still need visual testing. Existing procedural bus-terminal interaction geometry remains separate.

Dolphin shop row, Singareni Super Market, and the stadium/pool models remain in the review scene pending reliable location identification. The stadium and stadium-with-pool exports represent variants, not two separate landmarks.

Provenance: locally authored geometry based on user-supplied reference photographs. No Google Maps imagery is bundled as textures; underlying photo/trademark rights are not independently cleared. Geographic source licences are recorded in the place catalogue. Source .blend files are preserved.

Validation performed: Godot editor import; main-world startup (5 placed instances); movement regression including diagonal normalization and idle stability. See data/asset_sync logs for camera regression output.
