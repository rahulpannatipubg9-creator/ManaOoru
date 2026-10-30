# Asset licenses

## OpenStreetMap data

`data/osm/godavarikhani_core.json` is an unmodified Overpass API extract of
OpenStreetMap (snapshot 2026-10-24T19:23:47Z).

- Map data © OpenStreetMap contributors, available under the
  [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
  See <https://www.openstreetmap.org/copyright>.
- The attribution is shown on the in-game full-screen map and must also appear
  in store listings and credits.
- The extract ships readable inside the build and stays under ODbL. Any
  modified version of the database must also be offered under ODbL.
- No Google Maps or other proprietary map imagery or road data is used.

`data/osm/godavarikhani_features.json` is a second Overpass extract (shops,
crossings, barriers, railways, parks, places), same licence and attribution.

## Microsoft building footprints

`data/buildings/godavarikhani_ms_buildings.json` is derived from
[Microsoft Global ML Building Footprints](https://github.com/microsoft/GlobalMLBuildingFootprints)
(quadkey 123310201, release 2026-02-03), clipped to the play area, de-duplicated
against OSM and trimmed back from road edges by `tools/import_ms_buildings.py`.

- Licence: ODbL 1.0. Attribution: "Building footprints © Microsoft".
- This is a modified database, so it must be offered under ODbL; it ships
  readable inside the build together with the script that produced it.

## Building heights

`data/buildings/godavarikhani_building_heights.bin.gz` is derived from the
[Google Open Buildings 2.5D Temporal Dataset](https://sites.research.google/gr/open-buildings/temporal/)
(2023-06-30, `building_height` band), resampled to the game grid by
`tools/import_building_heights.py`.

- Licence: CC BY 4.0. Attribution: "Building heights: Google Open Buildings 2.5D".
- This is an open research dataset, not Google Maps imagery or map data.

## Terrain

`data/terrain/godavarikhani_terrain.bin` is derived from the Copernicus DEM
GLO-30 (tile N18 E079) by `tools/import_terrain.py` (buildings filtered out,
smoothed, heights relative to Chowrastha).

- Free for any use under the Copernicus DEM licence. Required notice:
  "© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided
  under COPERNICUS by the European Union and ESA; all rights reserved".

Details: [docs/MAP_AND_NAVIGATION.md](docs/MAP_AND_NAVIGATION.md#7-licensing-and-odbl-compliance).

## Mahindra Thar vehicle model

`assets/models/thar/thar_body.glb`, `thar_tyre.glb` and `thar_rim.glb` are
derived from ["Mahindra Thar 3D Model"](https://www.blendswap.com/blend/31849)
by aakash2, licensed [CC-BY](https://creativecommons.org/licenses/by/4.0/).

- Attribution: "Mahindra Thar 3D Model by aakash2 (BlendSwap), CC-BY". It must
  appear in store listings and credits.
- Changes: modifiers applied, decimated to about 97k triangles per car, rescaled
  to real 255/65 R18 wheel size, wheels split out, procedural materials replaced
  with flat PBR colours, and the tyre sidewall texture dropped (its source was
  not covered by the model's licence). Reproduce with `tools/export_thar.py`.
- The CC-BY licence covers the 3D model only. "Mahindra", "Thar", the logos and
  the vehicle design are Mahindra & Mahindra trademarks and design rights. Get
  permission or remove the badges before a public or commercial release.

## Porsche 911 Carrera 4S (992) vehicle model

`assets/models/porsche_911/porsche_body.glb`, `porsche_tyre.glb` and
`porsche_rim.glb` are derived from "Realistic new 2020 porsche 911 carrera 4s
992 with materials", Blend Swap #93636
(<https://www.blendswap.com/blends/view/93636>), licensed
[CC BY-NC 3.0](https://creativecommons.org/licenses/by-nc/3.0/).

- **Non-commercial only.** This model must be removed or replaced before any
  paid, ad-supported or otherwise commercial release of MANA OORU.
- Attribution: "Porsche 911 Carrera 4S (992) model, Blend Swap #93636,
  CC BY-NC 3.0". The downloaded licence file does not name the author, and
  the Blend Swap page could not be reached on 2026-10-25; add the author's
  name before any public release.
- Changes: decimated from about 2 million to about 125k triangles, rescaled to
  real 305/30 ZR21 wheel size, wheels split out, Cycles materials replaced with
  flat PBR colours, badge and number-plate textures (not included in the
  download) replaced with flat colours. Reproduce with `tools/export_porsche.py`.
- The licence covers the 3D model only. "Porsche", "911", the crest and the
  vehicle design are trademarks and design rights of Dr. Ing. h.c. F. Porsche
  AG.

## Jeep Compass 2022 (`assets/models/jeep_compass/`)

`compass_body.glb`, `compass_tyre.glb` and `compass_rim.glb` were converted by
`tools/export_compass.py` from "FBX low poly.fbx" in the user's download
"car jeep compad.zip" (Jeep Compass 2022, 3ds Max scene + FBX/OBJ exports).
Geometry was rotated, rescaled to a real 225/55 R18 tyre, split by material and
decimated (body ~112k triangles); materials were replaced with flat colours and
no textures from the download are used.

- **Source and licence: unknown.** No licence file or source page came with the
  download. Confirm where it was downloaded from and that its licence allows
  redistribution in a game before any public release (store, APK sharing or
  streaming); replace or remove the model if it does not.
- "Jeep" and "Compass" are trademarks of their owner; the in-game model is
  unbranded apart from the modelled badges in the source geometry.

## M416 / HK416 rifle (`assets/models/weapons/m416.glb`)

Converted by `tools/export_m416.py` from "M416 / HK416" by natholas,
[Blend Swap #17759](http://www.blendswap.com/blends/view/17759), released under
**CC0 (public domain)**; no attribution required. Scaled to 0.85 m, decimated to
14k triangles, cartridges removed, flat PBR colours. Carried by the on-foot
character (key 1); no firing yet.

## AK-47 rifle (`assets/models/weapons/ak47.glb` and its three textures)

Converted by `tools/export_ak47.py` from the BlenderKit model "Ak47" by ReWork3D
(asset `1231f34c-13a2-43a1-b28b-f7598440436c`), downloaded through the BlenderKit
add-on on 2026-10-28 to `~/blenderkit_data/models/ak47_…/ak47_2K_….blend`. Scaled
to 0.88 m, kept within a 15k-triangle budget, origin at the pistol grip,
2K albedo / metallic-roughness / normal maps. The loose cartridge from the thumbnail
was left out. Second rifle next to the M416 (key 2), in free roam and Team
Deathmatch.

- **Licence: not confirmed.** BlenderKit free assets are normally under its
  Royalty Free licence (use in games allowed, no resale of the model itself), and
  some are CC0, but the asset page was not checked. The add-on that downloaded it
  names itself "Blendkit" and talks to blendkit.com rather than blenderkit.com, so
  confirm the source and licence on blenderkit.com before any public release;
  replace the model if either does not hold.

## Houses (`assets/models/houses/house_1..3.glb`)

Converted by `tools/export_houses.py` from `house.FBX` and its `maps/` textures in
the user's download "building House.zip" (three houses, 3ds Max/Corona 2016/2018
scenes). Rescaled from millimetres, textures resized to 1024 px, decimated to
≤9k triangles each. Used on about 680 real building footprints that match their
size (see `scripts/world/building_builder.gd`).

- **Source and licence: unknown.** No licence file or source page came with the
  download. Confirm before any public release; replace or remove if it does not
  allow redistribution in a game.

## Singing fountain jets (`assets/models/fountain/fountain_jets.glb`)

Converted by `tools/export_fountain.py` from `001_Singing_Fountains_OBJ_062817.obj`
in the user's download "singing fountains.zip" (water jets only, 1.55 M
triangles), decimated to 26k triangles with a project-made water material. The
pool around it is built in Godot. Placed in Dr. B.R. Ambedkar Park as decoration;
no data says a fountain exists there.

- **Source and licence: unknown.** No licence file or source page came with the
  download. Confirm before any public release.

## Recorded engine sounds (`assets/audio/porsche_911/`, `assets/audio/thar_recorded/`)

Cut from two recordings the project owner downloaded on 2026-10-25. The file
names are Pixabay's download naming, so they are taken to be Pixabay audio
under the [Pixabay Content License](https://pixabay.com/service/license-summary/):
free for commercial and non-commercial use, no attribution required, and not
to be redistributed as standalone sound files. Shipping them inside the game
is allowed; confirm the source pages before release.

- `porsche_911/idle_1150rpm.wav`, `rev_2600rpm.wav`, `start.wav`: from
  `freesound_community-porsche-105500.mp3` (Pixabay audio 105500, uploaded by
  "freesound_community", which re-hosts Freesound recordings).
- `thar_recorded/drive_2000rpm.wav`: from
  `u_u5w7jl2icv-thar-jeep-on-offroad-185664.mp3` (Pixabay audio 185664,
  "Thar jeep on offroad").
- Changes: cut to steady sections, resampled along the measured engine-order
  track to a constant pitch, high-passed, loudness-matched and crossfaded into
  seamless loops. Reproduce with `tools/extract_engine_loops.py`.
- `thar_recorded/drive_2000rpm.wav` is not used in the game yet. Most of its
  sound is gravel and wind (engine harmonics carry only ~17 % of its energy), so
  as an engine layer it would play as a burst of gravel noise around 2000 rpm.

## Thar diesel engine loops (`assets/audio/thar_diesel/`)

`diesel_913rpm.wav` … `diesel_3133rpm.wav` are cut from
["vw diesel engine.mp3"](https://freesound.org/s/448217/) by Evilmikie on
Freesound (VW New Beetle 1.9 TDI, a four-cylinder turbo-diesel like the
Thar's 2.2 mHawk), licensed [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
No attribution is required; it is credited here anyway.

- Changes: five held revs cut out, pitch-flattened to one firing frequency,
  trimmed to whole firing cycles, high-passed at 22 Hz, peak-normalised and
  crossfaded into seamless loops. Reproduce with `tools/make_engine_loops.py`.
- Used by the Thar (`scenes/player/player.tscn`) and the Jeep Compass through
  `thar_diesel_recording.tres`.

## Apartment blocks (`assets/models/apartments/apartment_*.glb`)

Converted by `tools/export_street_blocks.py` from `source/улица скетч.fbx` and its
photo textures in the user's download "street-city-buildings-8.zip" (a 1/10-scale
diorama of panel apartment blocks, Sketchfab-style archive). Three distinct blocks were
extracted and scaled ×10 to metres. They are drawn on the ~55 real buildings that Google
Open Buildings measures at 4+ floors, stretched to each real footprint and height.

- **Source and licence: unknown.** No licence file or source page came with the
  download. Confirm before any public release.

## Coal Gallery (`assets/models/coal_mine/`)

`coal_mine_gallery.glb` and `coal_mine_floor.json` were converted from the SketchUp
Collada scene `source/temp_export.zip` in the user's download "coal-mine-gallery.zip"
(an underground mine gallery with steel arches, rails and lamps): Godot converted the
.dae to glTF, then `tools/export_coal_mine.py` merged its 1,400 instances, decimated it
from 583k to 54k triangles and recorded the walkable floor. The rock walls, portal and
lamps around it are built in Godot. It is placed below a portal near the mapped
"OCP 5 Incline" mine as game content, not a surveyed mine working.

- **Source and licence: unknown.** No licence file or source page came with the
  download. Confirm before any public release.

## Building facade textures (`assets/textures/facade/`)

`facade_albedo.jpg`, `facade_normal.jpg` and `facade_arm.jpg` are texture-array
strips packed by `tools/make_facade_textures.py` from five
[Poly Haven](https://polyhaven.com) textures, all
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/): `painted_plaster_wall`,
`peeling_painted_wall`, `brick_wall_001`, `concrete_wall_008` and
`painted_metal_shutter` (1K Diffuse, nor_gl and arm maps). No attribution is
required; they are credited here anyway.

## Real shop and street names (`data/places/`, `assets/textures/signboards/`)

`data/places/godavarikhani_places.json` (374 named shops, banks, hospitals,
schools, temples and offices) and `godavarikhani_streets.json` (12 named streets)
are built by `tools/fetch_places.py` from:

- OpenStreetMap named POIs and road names: © OpenStreetMap contributors, ODbL 1.0.
- [Overture Maps Foundation](https://overturemaps.org) places, release 2026-10-21.0.
  Each record keeps its own licence: [CDLA-Permissive-2.0](https://cdla.dev/permissive-2-0/)
  (Meta, Microsoft), Apache-2.0 (Foursquare) or CC0. Attribution: "© OpenStreetMap
  contributors, Overture Maps Foundation". It is shown on the full-screen map.
- Names are kept exactly as published. Five street names that OSM lacks
  (Laxmi Nagar Road, Markandeya Colony Main Road, Pavani College Road,
  Godavarikhani Road, Ramagundam Road) are inferred from the street written in
  real business addresses near each road; each records how many addresses back it.
- Junction names: Ramesh Nagar Centre (OpenStreetMap), and Swatantra Chowk and
  Kalyan Nagar Chowrasta (named in 4 and 2 business names/addresses, placed at
  the real road junction they cluster around). FCI X Roads is also well attested
  but lies 3.6 km out, beyond the 3 km play area.
- Many names are registered business names and brands (banks, fuel companies,
  phone and vehicle dealers). Shown as they appear in the town, but check
  trademark use before a commercial release.

`assets/textures/signboards/signboards.png` (4 atlas pages) and `boards.json`
are baked from that list by `tools/signboards/make_signboards.gd`. The text is
set in Noto Sans Black, with Noto Sans Telugu Bold as a fallback
([SIL Open Font License 1.1](https://openfontlicense.org), see
`tools/signboards/fonts/OFL.txt`). The fonts are used only to bake the image and
are not shipped in the game (`tools/signboards/fonts/` has a `.gdignore`).

## Street life (`data/places/godavarikhani_street_life.json`)

Bus stops (5, Overture Maps, CDLA-Permissive-2.0), the Saturday market and the
colony entrance gates (Bapugi Nagar, Surya Nagar, Vidya Nagar 2) are from
OpenStreetMap (ODbL), extracted by `tools/fetch_places.py`. Roadside stalls and
street-light poles are not mapped anywhere; they are placed procedurally along
the busy main roads, and all their geometry is made in code.

## Ground cover, trees and road surfaces

- `data/landcover/godavarikhani_landcover.bin`: from **ESA WorldCover 10 m 2021
  v200** (tile N18E078), © ESA WorldCover project 2021 / Contains modified
  Copernicus Sentinel data (2021) processed by ESA WorldCover consortium,
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Resampled to the
  game grid by `tools/import_landcover.py`.
- `data/trees/godavarikhani_trees.bin`: from the **Meta and World Resources
  Institute High Resolution Canopy Height Maps** (tile 123310201), CC BY 4.0.
  Attribution: "Meta and World Resources Institute (WRI) 2024. High Resolution
  Canopy Height Maps by WRI and Meta." Trees are sampled on a 7 m grid by
  `tools/import_trees.py`.
- `assets/textures/trees/broadleaf_impostor.png`: four views of
  ["Jacaranda Tree"](https://polyhaven.com/a/jacaranda_tree) from Poly Haven
  (CC0), rendered by `tools/render_tree_impostor.py`.
- `assets/textures/ground/ground_*.jpg` and `road_*.jpg`: Poly Haven CC0
  textures `dirt_floor`, `dry_mud_field_001`, `leafy_grass`, `brown_mud_leaves_01`,
  `farm_soil`, `withered_grass`, `red_laterite_soil_stones`, `asphalt_02` and
  `asphalt_01`, packed by `tools/make_ground_textures.py`.
- Both CC BY 4.0 credits are shown on the full-screen map.

## Rejected downloads

- "McLaren F1 1993" by Alex.Ka (Sketchfab download, 2026-10-25) was **not
  imported**. Its own `info.txt` says it is based on the model from
  *NFS: Shift* with parts from *Forza Motorsport 4* and *Project CARS* and
  textures from *NFS: Shift* / *NFS: Most Wanted*. That makes it ripped game
  content, which this project does not use (see README "Legal and asset
  policy"), whatever the uploader's own terms say.
- "Chubby magic girl.blend" (download, 2026-10-25, no licence or source
  included) was **not imported**. The file itself shows it is assembled from
  other products: the hair carries Daz 3D metadata (`DazUrl #Cunningham_Hair`,
  saved from a personal Daz library), whose store licence does not allow
  redistribution in a game without a Daz interactive licence. The shape-key
  actions are named after Unreal Engine game assets
  (`SK_CH_NPC_Eugenie_Facial_02_md`, `Velma_body`, `MBoots_MI_MBoots`), which
  points to ripped game characters. Can be revisited only with a source page and
  licence that cover every part.
  At the owner's request it is used **for local testing only**: a reduced copy
  lives in `assets/test_only/magic_girl/` (made by
  `tools/export_test_character.py`), which is gitignored and excluded from every
  export preset. The game loads it only if that folder exists, so builds and
  clean checkouts keep the original block figure.

## Current street upgrade

The upgraded 10-15 street buildings use original Godot primitive meshes and
original material definitions generated by this project. No external meshes,
photographs, textures, HDRIs, or downloaded files were added. This keeps the
game fully offline and avoids unverified redistribution terms.

## Reviewed free sources

These sources were reviewed as possible future additions, but no files were
downloaded for this upgrade:

- [Kenney Building Kit](https://kenney-assets.itch.io/building-kit) — free
  asset source; verify the pack license and redistribution terms before import.
- [Poly Haven textures](https://polyhaven.com/textures) — CC0 assets.
- [ambientCG](https://ambientcg.com/) — license information is provided per
  asset and must be checked before import.

The current build has no runtime or build-time dependency on these websites.

## Overture building supplements — Vidya Nagar 2

`data/buildings/vidya_nagar_2_overture.geojson` contains 11 supplemental roof
footprints from Overture Maps buildings release 2026-10-21.0, retrieved
27 October 2026. Original geometry is retained. Only candidates with upstream
confidence >=0.85, within 450 m of the project neighborhood center, at least
1 m from existing footprints, and outside road carriageways plus 1 m were kept.

- Derived building database: ODbL 1.0. Attribution: © OpenStreetMap contributors,
  Overture Maps Foundation. See https://docs.overturemaps.org/attribution/ and
  https://opendatacommons.org/licenses/odbl/1-0/.
- All 11 selected footprints originate from Google Open Buildings, CC BY 4.0:
  https://sites.research.google/open-buildings/ and
  https://creativecommons.org/licenses/by/4.0/. Source IDs, scores and dates
  are retained per feature. These are satellite-derived roof outlines, not
  independently surveyed building positions or facades.
- Ship the readable derived GeoJSON under ODbL with its source records and
  provenance. Import/filter tools are in `tools/building_sources/`.
- The in-game full map includes the additional source attribution.

Mapillary photos were inspected as dated references only. No Mapillary photo,
texture or image-derived building model is packaged in the game.

## TopoExport supplemental roads and trees

The optional offline supplement in `data/topoexport/` was exported from
TopoExport on 27 October 2026. `roads.json` contains 273 Overture Transportation
2026 road lines and `trees.json` contains 3,786 TopoExport composite tree points.
The generated files retain their source descriptions and EPSG:32644 origin in
the import tool and are converted to the game's local coordinates for runtime.

- Overture Maps Foundation Buildings/Transportation/Base 2026: ODbL 1.0.
- Global Canopy Height Maps v2, Meta and World Resources Institute: CC BY 4.0.
- EDTM terrain attribution is retained in the downloaded TopoExport licence;
  no EDTM terrain file is currently imported.
- Original export licence: `data/topoexport/source/LICENSE.txt`.

TopoExport source data is supplemental and may overlap the existing OSM layer.
Matching roads are deduplicated; missing service roads and footways are added.

### Historical shop-name observations — 27 October 2026
`data/local/historical_shop_observations.json` transcribes visible signage from
Mapillary panoramas by geomannar, captured 11 June 2020 (image IDs and links in
that file). Reference imagery is CC BY-SA 4.0; no image pixels are bundled.
The in-game Bhaskar Bhavan reference panel is bound to OSM way 599199178.
Names are historical, not assertions of current occupancy; individual shop units
are unverified. Men's Club Fashions is an unlocated note, never a routeable pin.


## Original market activity props (2026-10-27)

`assets/models/market_street/`: tea stall, vegetable cart, wooden stool, parked scooter and modular shopfront. Original procedural Blender models authored for MANA OORU, released under CC0-1.0. No downloaded third-party textures. Blender source and generation script are retained with the market deliverables.

The market additionally reuses the existing mobile adaptation of **Panipuri Cart (indian appetizers)** by **Bongblender**, licensed **CC BY 4.0**:
https://sketchfab.com/3d-models/panipuri-cart-indian-appetizers-b037fdaefe0546f6b485c16253e9429a
Original licence: https://creativecommons.org/licenses/by/4.0/
The pre-existing `gdk_panipuri_cart_mobile.glb` adaptation is reused, not newly downloaded. This credit is also available from each market counter's Asset credits button.

The market stalls are fictional gameplay additions at collision-checked roadside locations; they do not assert that a named real business exists at those coordinates.

## Original city content additions

`city_assets.gd`, `resident_details.gd` and associated procedural geometry: original MANA OORU content, CC0-1.0. Includes police and ambulance vehicle visuals, stretcher/patient, medical bag, extinguisher, barricade and resident accessories. Existing project character and vehicle source licenses continue to apply. No new third-party downloads or purchases were made.

## Player head (FaceBuilder)

The player character's head in `assets/models/characters/player_character_rigged.glb` is the
player's own likeness. The mesh was fitted with KeenTools FaceBuilder for Blender 2026.3.1 to the
player's own photos (`tools/facebuilder_head/new_refs/`). Its texture is projected straight from
those photos by `tools/facebuilder_head/bake_photo_texture.py`, and the hair volume is generated by
`tools/build_user_character.py`. The photos are the player's own and are used with their consent.
Check the KeenTools EULA before any commercial release.

## Player character v2

`assets/models/characters/player_v2_rigged.glb` and `player_v2_animations.glb` are built by
`tools/player_character_v2/` (see its README). Body, skeleton and skin weights come from the Reallusion
CC Character Base "Neutral_M" (`~/Downloads/CC_character_base`). Its licence allows use inside games,
including commercial ones. It does not allow selling or redistributing the model on its own as an asset,
character-generator products, or AI training. The head shape is the FaceBuilder likeness above. The skin
and hair textures are projected from the player's approved face sheet
(`tools/player_character_v2/references/approved_face_sheet.png`, the player's own likeness, used with
their consent). Clothing, sneakers, hair shell geometry and the conformed rest pose are original procedural
work. `player_v2_animations.glb` re-exports the existing clip library (`tools/character_animation`) on
v2's skeleton.

## Rahul (fresh rebuild, the default player)

**Since 2026-10-29 the body is a Hyper3D Rodin scan** (`tools/rahul_character/scripts/18_rodin_body.py`): the
mesh and its colour / metal-roughness / normal textures come from a Hyper3D Rodin generation made by the player
from their own photos (download `7b2af3dc-34af-4582-8f6d-228eb5b63e88`, `base_basic_pbr.glb`). **Licence not
confirmed:** Rodin's terms depend on the account plan (free-tier generations may be public or carry attribution
terms). Check the plan's terms on hyper3d.ai and record them here before any public release. The skeleton,
weights layout and every clip are still the CC-based build described below; no CC mesh is exported any more.

`assets/models/characters/rahul/rahul.glb` is built from scratch by `tools/rahul_character/` (see its README;
`11_export.py` writes it). Body, skeleton and skin weights start from the Reallusion CC Character Base
"Neutral_M" (`~/Downloads/CC_character_base`), under the same terms as player v2 above: use inside games,
including commercial ones, is allowed; selling or redistributing the model on its own, character-generator
products and AI training are not. The face fit (KeenTools FaceBuilder, check its EULA before a commercial
release) and the skin and hair textures come from the player's own photos and approved sheets, used with
their consent. Clothing, sneakers, hair, beard, rig and every clip (hand-keyed, no motion capture) are
original work. Nothing is reused from player v2 or the older avatar.

## Haathgaadi (Handcart / Thela)

`assets/models/haathgaadi/`: User-supplied handcart model (`haathgaadi.blend` from Downloads).
- **Status:** In development / user supplied.
- **Components:** 4-wheeled Indian market cart structure with green metal chassis, spoked wheels, axles, and wooden flatbed. Textures packed into `.blend` with licensed project wood texture (`assets/models/utility_pole/gdk_utility_pole_Old_Wood_texture_2_by_Tigg_stock.jpg`). Exported via `tools/export_haathgaadi.py` to `gdk_haathgaadi.glb`.

## CZ Bren 2 rifle (`assets/models/weapons/bren2.glb`)

Converted by `tools/export_bren2.py` from the user-supplied CZ Bren 2 model (`czbren2.glb` from Downloads).
Scaled to 0.85 m, kept within the 15k-triangle budget, origin at the top of the pistol grip,
barrel forward along Godot +Z. Includes receiver, tactical foregrip, folding buttstock, bolt handle,
suppressor, and red-dot sight. Playable weapon in free roam and multiplayer (Weapons.BREN2).
- **Licence: not confirmed.** User-supplied download. Confirm original author and licence before any public release.


