# Phase 1 geographic data audit

Audit date: 27 October 2026. Scope: read-only inspection of the current local project; no new geocoding, remote lookup, field visit, dataset modification or gameplay test. This document is the only project file written by this audit.

## Finding

The project has substantial source-backed road/building/POI geography, but it is **not field-verified**. Published coordinates, confidence values and source names must not be presented as survey accuracy. Generated street labels, junction-name snaps, facade appearances, roadside objects and animated populations are separate inference layers. A useful Phase 1 registry can be built from source records while retaining those distinctions.

## Projection and origin

`/Users/rahulpannati/Downloads/AI Agents Practice/ManaOoru/scripts/map/geo_projection.gd` defines longitude **79.513352**, latitude **18.751925**, radius **3000 m**, 111000 metres per degree latitude, longitude scale multiplied by cos(origin latitude). Game +X=east and −Z=north; 1 unit=1 m. A registry should store original WGS84 lon/lat and derive game X/Z through this exact projection.

The origin agrees (to rounding) with the arithmetic mean of the **21 listed vertices including the repeated closing vertex** of OSM roundabout way **818565606**, named `CHOWRASTHA`: mean 79.51335224285714,18.751925171428574. This is a reproducible map-derived anchor, not a surveyed junction center. OSM locality node **3384152837** named `CHOWRASTHA` is at 79.513376,18.7519057, approximately 3 m away; these are compatible representations, not two contradictory junctions.

## Dataset inventory

All paths below are relative to `/Users/rahulpannati/Downloads/AI Agents Practice/ManaOoru/`.

| Path | Inventory/schema | Source/date/license recorded locally | Reuse and accuracy interpretation |
|---|---|---|---|
| `data/osm/godavarikhani_core.json` | Overpass `elements`: 42,955; 34,789 nodes + 8,166 ways. Raw 1,620 highway ways and 6,546 building-tagged ways. `node:{id,lat,lon,tags}`; `way:{id,nodes,tags}`. | OSM base timestamp **2026-10-24T23:17:19Z**; ODbL-1.0. | Preserve object type/id, original tags and geometry. Counts are raw inventory, not rendered counts; parser/building filters can reduce them. `ASSET_LICENSES.md` still says 19:23:47Z: use actual file timestamp for this snapshot. |
| `data/osm/godavarikhani_features.json` | 3,198 elements: 3,066 nodes, 130 ways, 2 relations; 25 building-tagged ways. POIs, parks, water, barriers, rail, places etc. | OSM base **2026-10-24T23:10:13Z**, ODbL. | Overlaps core; deduplicate by `(osm_type,osm_id)` before counting. Relations require assembly; do not treat members as independent duplicate areas. |
| `data/local/user_shop_overpass.json` | 216 tagged objects: 196 nodes +20 ways. All20 ways have `center:{lat,lon}`. | Overpass base **2026-10-26T09:53:50Z**, ODbL. | Raw OSM IDs/tags retained; way centers are representative points, not entrances. Two object coordinates outside3km. Filename is not proof every object is a shop; includes schools/amenities. |
| `data/local/chowrasta_exact_pins.json` | `pins[2]`: `name,category,lon,lat,source`. | OSM node/way evidence in source strings; no separate snapshot/version/date/license fields. | Source-backed curated classifications, not independently surveyed. See pin checks below. |
| `data/local/traffic_signals.json` | `traffic_signals:[]`; schema comment `lat,lon,note`. | No observations or per-record licensing fields; currently empty. | No local signal overrides exist. Comment saying signals “exist” is guidance, not populated evidence. |
| `data/buildings/godavarikhani_ms_buildings.json` | **12,319** rings, flattened `[lon,lat,...]`; metadata source,url,license,attribution,quadkey123310201. | Microsoft Global ML Building Footprints; ODbL1.0. `ASSET_LICENSES.md` states release2026-02-03; JSON itself does not record release/imagery date. | Machine-derived roof footprints, locally clipped/deduplicated/trimmed by `tools/import_ms_buildings.py`; no original feature IDs retained. Neither individual house names nor precise surveyed walls. |
| `data/buildings/vidya_nagar_2_overture.geojson` | **11** Polygon features; `properties:{id,sources,height,num_floors,names}`; heights/floors/names null in sample. Source records preserve IDs, Google confidence and update_time/version. | Overture buildings release **2026-10-21.0**; ODbL with Google Open Buildings CC BY4 attribution noted. Sample source update2023-05-01; source version2024-04-16. | Confidence≥.85,450m neighborhood, existing buildings win with1m gap, reject roads+1m/holes. Original polygons selected; capture date not facade accuracy. Metadata input hashes currently match OSM core and Microsoft file. |
| `data/buildings/godavarikhani_building_heights.json` + `.bin.gz` | 3050×3050 uint8 grid,2m cells; origin X/Z −3050; value÷4=m. | Google Open Buildings2.5D Temporal Dataset **2023-06-30**, `building_height`; CC BY4. | Resampled machine height estimate, not building floor survey. Fallback floor inference remains separate. |
| `data/terrain/godavarikhani_terrain.json` + `.bin` | 417×417 float32 grid,15m spacing; origin X/Z −3120; Chowrastha elevation156.26m; range−82 to29.02m relative. | Copernicus DEM GLO-30 tileN18E079, buildings filtered/smoothed; attribution in metadata; license described in ASSET_LICENSES.md. | 15m output sampling does not make source resolution better than30m. Not street/drain invert/kerb survey. Acquisition date absent here. |
| `data/landcover/godavarikhani_landcover.json` + `.bin` | 624×624 uint8 class grid,10m spacing; origin−3120. | ESA WorldCover **2021 v200**, tileN18E078; CC BY4. | Regional classification may be outdated; cannot infer individual vacant plots, property boundaries or current vegetation. |
| `data/trees/godavarikhani_trees.json` + `.bin` | **179,070** sampled instances, float32 X/Z/height/crown-radius; sampling cell7m,minimum height5m. | Meta/WRI High Resolution Canopy Height Maps, attribution2024; CC BY4. | Source-backed canopy distribution, but sampled tree positions and crown sizes are generated representations—not179,070 surveyed individual trunks. |
| `data/places/godavarikhani_places.json` | **374** rows; exact keys `name,category,lon,lat,source,license,confidence`. | OSM extracts +Overture places release **2026-10-21.0**.105 OSM;173 Meta;52 Microsoft;34 Foursquare;7 AllThePlaces;3 DAC. | License counts:105 ODbL,228 CDLA-Permissive2,34 Apache2,7 CC0. **50 outside3km**. No original OSM/Overture IDs, addresses, source update dates or geometry methods retained. |
| `data/places/godavarikhani_streets.json` |12 streets: `name,source,evidence,lines`;3 junctions:`name,lon,lat,source,evidence`. | OSM roads +Overture places addresses release2026-10-21.0. | Seven directly OSM-named streets, five names inferred by address votes on real OSM lines. Source road IDs/voter IDs/license fields absent. Junction inference must remain candidate-only. |
| `data/places/godavarikhani_street_life.json` |5 bus-stop rows,1 market,3 entrance rows; each `name,lon,lat,source`. | OSM+Overture release2026-10-21.0. ASSET_LICENSES describes bus stops CDLA,market/entrances ODbL. | Original IDs, per-row licenses/confidence/observation dates absent; bus-stop rows were generated from all Overture confidences. Generated props/people around pins are not mapped objects. |

A release timestamp or extraction timestamp is not the date every underlying object was surveyed. License statements above report local metadata/documentation, not a fresh legal verification of upstream terms. Retain source-specific notices; do not blanket-relicense mixed datasets.

## Named location evidence and ambiguity

| Candidate | Local evidence | Registry treatment |
|---|---|---|
| Chowrastha | OSM roundabout way818565606 and locality node3384152837; reproducible origin above. | Source-backed junction/roundabout and locality records, connected by relation in registry; not field-verified. |
| Vidya Nagar2 entrance | OSM node**3384160142**, `name=ENTRANCE OF VIDYA NAGAR 2`, lat18.7549391,lon79.5163546. Derived entrance file shortens label to VIDYA NAGAR2. | Source-backed **named entrance point**; neither a neighborhood boundary nor neighborhood centroid. No `entrance=*` or `place=*` tag in original. Preserve sparse-tag caveat. |
| Project Vidya Nagar2 center | `world_generator.gd`/`building_builder.gd` use `Vector2(315.60,-334.57)` for preload/style targeting. | Project anchor only. Near the entrance but not an independently documented center or authoritative neighborhood extent.450m preload/400m style radii are implementation settings. |
| Vidyanagar(ACPI)-3 | OSM node11963163760,18.7522535,79.5115806, `amenity=childcare`, government import source. | Childcare facility; **do not treat as Vidya Nagar2** or a locality centroid. |
| lenin nagar | OSM locality node2891164207,18.7537221,79.5163232. | Source-backed locality point; no boundary. |
| Leninagar | OSM node11971496150,18.754197,79.5163004, `amenity=childcare`. | Childcare facility, not a shop or alternative locality center. Earlier screenshot’s nearest-POI label is not evidence of a shop. |
| Kalyan Nagar Chowrasta | Derived junction lat18.749347,lon79.5128052;2 address/name mentions. | **Inferred candidate**, not directly mapped named junction or surveyed pin. |
| Swatantra Chowk | Derived junction lat18.7503787,lon79.5098051;4 address/name mentions. | **Inferred candidate**. OSM “Swathanthra Chowk Area-1” node11964605162 is childcare at18.7542184,79.5087052, not junction confirmation. |
| Ramesh nagar centre | OSM node9961291897,18.7417548,79.5118009; `tourism=information`, `information=office`. | Source-backed information-office point. Regex-derived junction category is not supported by original tags. |
| NEW ASHOK THEATRE | OSM way331357115, sparse tags area=yes/name. Local pin79.51507258,18.7542867 equals mean of5 listed vertices including closure. | Map-derived representative point; curated theatre category inferred from clear name, no amenity tag. Retain classification_basis=curated_name and geometry_method=vertex_mean_including_closure. |
| ARJUN SWEET HOUSE | OSM node3384168812 at79.5150628,18.7539006, name only. | Coordinate is direct node; local pin adds shop=sweets classification. Preserve source tags and curated classification separately. |
| TGSRTC Godavarikhani bus station | OSM node13707521637,18.7601255,79.5082894,amenity=bus_station/public_transport=station; nearby named depot polygon279050788. | Station point and depot polygon distinct; a depot is not the station building or entrance. |
| Pavani Eye Hospital | OSM node6563201450 at18.7568803,79.506108 explicitly has `fixme` asking to verify position, mapped from address. | Flag needs_position_review even though generated places confidence=1.0. |
| Area Hospital Godavarikhani | OSM nodes6542777509 (18.7463654,79.5190188) and11937607118 (18.7512548,79.5058532) are about**1,486 m apart**. | Ambiguous duplicate/name-family; do not silently choose, merge or relocate. Need external/field corroboration. |
| Vittal Nagar Bus Stop | Two Overture rows at79.5252342,18.7291679 and79.51829,18.73592,about**1,046 m apart**. | Could be distinct stops or conflicting records; preserve two source candidates, not one confident pin. |

“Exact” in a local filename means coordinates copied reproducibly; it does not establish measured ground accuracy. No survey logs, geotagged field observations, dated consent/reuse records or corroborating local verification are present in these files.

## Street-name evidence

| Street | Source of name | Aggregate evidence | Stored line pieces |
|---|---|---:|---:|
| Pavani College Road | business addresses (Overture Maps) | 6 | 1 |
| township main road | OpenStreetMap | 0 | 3 |
| Ring Road | OpenStreetMap | 0 | 1 |
| Laxmi Nagar Road | business addresses (Overture Maps) | 32 | 9 |
| radhakrishnan road | OpenStreetMap | 0 | 1 |
| Markandeya Colony Main Road | business addresses (Overture Maps) | 30 | 6 |
| Godavarikhani Road | business addresses (Overture Maps) | 9 | 3 |
| lb nagar road no 2 | OpenStreetMap | 0 | 1 |
| Ramagundam Road | business addresses (Overture Maps) | 2 | 1 |
| Ram nagar road | OpenStreetMap | 0 | 1 |
| TGSRTC Godavarikhani Bus Station Inner Road | OpenStreetMap | 0 | 1 |
| TGSRTC Godavarikhani Bus Depot Inner Road | OpenStreetMap | 0 | 1 |

`tools/fetch_places.py` assigns names to nearest real OSM road lines within60m when ≥2 address votes and ≥60% share support a name. Street names can therefore be plausible yet assigned to several physically separate lines; Laxmi Nagar Road has9 pieces. Evidence0 for directly named OSM streets means “vote count not applicable,” not “no source.”

Junction candidates are found by regex in business names/addresses, densest500m cluster, mean coordinate, then snapped to a ≥3-arm OSM junction within150m. The `evidence` count alone is not positional accuracy or independent confirmation. A road called “Flyover” is a structure label; OSM way1070120416 called “BUILDINGS” is not a reliable street name. Current generation suppresses these and CHOWRASTHA from street-sign list.

## Category pitfalls in current loader

`MapData._reference_place_kind()` falls back to `shop`. Do not use that function as a factual registry classifier. Dataset categories include hospitals, places of worship, hotels, schools, colleges, police, government offices, libraries and empty strings. OSM `tourism=information`, `tourism=artwork`, `office=*`, `healthcare=*` need the key context retained, not just the value after `=`.

Actual Overture rows currently meeting ≥.95 confidence and ≤1km promotion include two Sangeetha Gadgets rows with **empty category**, Celekt electronics, Indian Overseas BankATM, HDFCBank, Coal City Speech/Hearing Clinic, and **Bajaj Finserv Gold Loan labeled fashion_and_apparel_store**. Preserve that contradiction as a review flag, rather than silently declaring a clothing shop. Source confidence is not a category/position guarantee. Catalog assigns confidence1.0 to all OSM rows; that value is exporter policy, not measured accuracy.

Safe registry categories should be explicit: retail, food/drink, healthcare, education, worship, accommodation, finance, transport, government/civic, locality, entrance, information, artwork, other/unknown. Keep raw category and source tags; unknown/empty must remain unknown, not retail.

## Recommended registry schema and import precedence

Store `id`, `name_original`, `display_name`, `feature_class`, `raw_category`, `lon`, `lat`, derived `map_x/map_z`, `geometry`, `geometry_method`, `source_dataset`, `source_file`, `source_record_type`, `source_record_id`, `source_release`, `source_snapshot`, `source_updated_at`, `source_license`, `attribution`, `evidence_kind`, `classification_basis`, `confidence_raw`, `confidence_meaning`, `review_flags`, `field_verified=false`, `inside_playable_radius`, and `source_file_sha256`.

1. Prefer raw OSM object/type/ID and original tags from core/features/user export. Deduplicate identical object IDs, retaining file provenance; do not merge separate branches solely by business name.
2. Compute representative points for ways only with a recorded method; preserve original polygon/line and label point separately. Centroid is not entrance and can lie outside concave geometry.
3. Curated pins may supplement sparse tags but must reference exact source object and note additional classification. Neither curated label nor source confidence upgrades field verification.
4. Generated places are reusable source-attributed published-coordinate candidates, but lack source IDs/update times. Recover IDs from raw extracts where match is unambiguous; otherwise use `local-record:<file>:<index>` and flag source_id_missing. Do not invent upstream IDs.
5. Inferential street/junction labels remain a separate `candidate` collection. Allow direct OSM named road/roundabout geometry in source-backed collection with ordinary mapped-data caveats.
6. Keep out-of-radius records for audit if desired but do not move them inward or expose as reachable destinations. A source way intersecting the circle can legitimately have vertices outside; line clipping is distinct from relocating point records.
7. Keep facade colors/heights fallback, roof tanks, roadside scenery, pedestrians, vehicle spawns, inferred shop frontage, procedural gates/market stands and tree sampling outside the geographic verification registry. A real point does not prove the geometry/appearance of the rendered asset at that point.

## Outside-radius catalog rows

50 of374 published place coordinates fall outside the project's3km playable circle (project projection). Full list:

Axis Bank Branch (3951 m); Axis Bank ATM (3790 m); Select Motors, Jothynagar (3768 m); Samsung SmartPlaza - Yashaswi Enterprises (3374 m); Jockey Exclusive Store (3379 m); HDFC Life (3596 m); Hindustan Petroleum (3030 m); Hindustan Petroleum (3712 m); Taj Family restaurant (3435 m); Shriram City Union Finance Limited (3380 m); Maruti Suzuki Arena (Adarsha Automotives, Ramagundam) (3345 m); ICICI Bank (3426 m); Indane - Sri Mayi Gas Agency (3436 m); Radhika Enterprises (3566 m); Saanvi Food Lounge (3539 m); Indianoil (3836 m); Manappuram Finance (3740 m); Vishal Mega Mart (3795 m); Bajaj Finserv - Personal Loan (3663 m); IIFL Gold Loan (3667 m); Muthoot Finance Gold Loan (3669 m); Apollo Pharmacy Krishna Nagar NTPC Ramagundam (3417 m); TRENDS (3593 m); HDFC Bank ATM (3377 m); Aditya Birla Finance Limited (3238 m); RamSri Sweets and Bakery (3100 m); Hotel Srimayi Grand (3704 m); Hotel O De Alphabet Home Stays@NTPC (3426 m); Gulf Carstop - Mm Motors, Ntpc (3027 m); HDFC Bank ATM (3765 m); Bajaj Allianz Life Insurance Company Limited (3556 m); IIFL Business Loan (3667 m); Gulf Carstop - Naresh Mechanic Garage & Service (3333 m); JJ FAMILYRestaurant NTPC Godavarikhani (3993 m); Sri Balaji Ramesh Sweets and Bakery (3595 m); Sachdeva School of Excellence and Junior College (3500 m); Meenakshi Medical Stores (3547 m); పెద్దపల్లి జిల్లా గొర్రెల మరియు మేకల మార్కెట్ యార్డ్ (3704 m); AV Function Palace-NTPC (3375 m); Highway Packers and Movers (3829 m); Saint Claire High School (3093 m); Fci Shopping Complex (3180 m); Sri chakra earth movers (3213 m); Adriyala longwall project,singareni collaries company limited (3102 m); Sri Swamy Ayyappa Temple (3014 m); Sri Sapthagiri Printers (3723 m); Vishwa Shanthi High School (4084 m); Shalem Gospel Ministries, Ramagundam (3705 m); NTPC Temporary Township Quarters (3564 m); NTPC Temporary Township Quarters (3847 m)

This is consistent with a bounding-box fetch rather than circle filtering. `MapData` currently promotes only≥.95 confidence places within1km; signboard/other consumers may have different selection rules. Any new registry should explicitly filter by intended radius rather than relying on old catalog size.

## Dates, provenance and limitations

- Generated place/street/street-life top-level metadata has an Overture release string but no generation timestamp or raw input hashes. OSM rows lack individual object versions/timestamps in core/features snapshots; base timestamp only identifies replication state.
- Overture places lose original IDs, addresses (removed before serialization), complete sources, update_time and source geometry method. Do not claim “exact pin confirmed” from the resulting numeric precision.
- Overture building supplement retains IDs/source metadata and matching input hashes; it is the best structured source supplement in current local inventory, but remains machine-derived2023/2024-era roof evidence under a2026 release.
- Terrain/tree/landcover and building-height output coordinate grids use game-space origins and sampling, not independent survey control points. Do not use them to prove current street drainage or exact foundations.
- ASSET_LICENSES contains source-specific notices, including licenses for non-geographic art. This audit did not re-audit model/logo rights or publish anything. No unrelated legal terms were inferred from another Telangana portal.
- No registry entries should be marked field_verified=true on the evidence inspected here.
