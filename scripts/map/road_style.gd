class_name RoadStyle
extends RefCounted

## Carriageway widths in metres. OSM has no width tags in this area, so widths come
## from the OSM lane count where tagged, else typical Telangana town road widths per
## class. Dual carriageways are mapped in OSM as two one-way ways, each drawn
## separately, with the real jersey-barrier median between them.
## Keep tools/import_ms_buildings.py ROAD_WIDTHS in sync.

const LANE_WIDTH := 3.5
const TWO_WAY_WIDTHS := {
	"motorway": 10.5, "trunk": 10.5, "primary": 9.0, "secondary": 7.5, "tertiary": 6.5,
	"motorway_link": 5.0, "trunk_link": 5.0, "primary_link": 5.0, "secondary_link": 5.0, "tertiary_link": 5.0,
	"unclassified": 5.0, "residential": 4.5, "living_street": 4.0, "road": 4.5,
	"service": 3.5, "track": 3.0,
	"footway": 1.8, "path": 1.8, "pedestrian": 3.0, "steps": 1.8, "cycleway": 1.8, "bridleway": 1.8,
}
const ONE_WAY_WIDTHS := {"trunk": 7.0, "primary": 7.0, "secondary": 6.5, "tertiary": 5.5}
const MAJOR := ["motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link",
	"primary_link", "secondary_link"]
const PATHS := ["footway", "path", "pedestrian", "steps", "cycleway", "bridleway"]

static func width(road: Dictionary) -> float:
	var supplied_width := float(road.get("width", 0.0))
	if supplied_width > 0.0:
		return supplied_width
	var lanes := int(road.get("lanes", 0))
	if lanes > 0:
		return lanes * LANE_WIDTH
	if int(road.get("oneway", 0)) != 0 and ONE_WAY_WIDTHS.has(road.kind):
		return ONE_WAY_WIDTHS[road.kind]
	return TWO_WAY_WIDTHS.get(road.kind, 4.5)

static func is_major(kind: String) -> bool:
	return kind in MAJOR

static func is_path(kind: String) -> bool:
	return kind in PATHS

## Major roads draw on top of minor ones where they overlap at junctions.
static func surface_height(kind: String) -> float:
	if is_major(kind):
		return 0.06
	if is_path(kind):
		return 0.02
	return 0.04
