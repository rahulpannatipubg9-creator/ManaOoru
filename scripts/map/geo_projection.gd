class_name GeoProjection
extends RefCounted

## Single source of truth for converting OpenStreetMap coordinates to game space.
##
## Origin: the OSM way named "CHOWRASTHA" (Godavarikhani Chowrastha junction).
## Axes: +X = east, -Z = north, +Y = up. No rotation is applied.
## Scale: 1 world unit = 1 metre (equirectangular approximation, accurate to
## well under 1% inside the 3 km playable radius).
## Map-plane coordinates used by the minimap and router are Vector2(x, z).

const ORIGIN_LON := 79.513352
const ORIGIN_LAT := 18.751925
const METERS_PER_DEGREE_LAT := 111000.0
const PLAYABLE_RADIUS_METERS := 3000.0

static func meters_per_degree_lon() -> float:
	return METERS_PER_DEGREE_LAT * cos(deg_to_rad(ORIGIN_LAT))

static func lon_lat_to_map(lon: float, lat: float) -> Vector2:
	return Vector2(
		(lon - ORIGIN_LON) * meters_per_degree_lon(),
		-(lat - ORIGIN_LAT) * METERS_PER_DEGREE_LAT
	)

## Returns [lon, lat] as 64-bit floats; a Vector2 would lose ~1 m of precision at these magnitudes.
static func map_to_lon_lat(point: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([
		ORIGIN_LON + point.x / meters_per_degree_lon(),
		ORIGIN_LAT - point.y / METERS_PER_DEGREE_LAT,
	])

static func map_to_world(point: Vector2, height := 0.0) -> Vector3:
	return Vector3(point.x, height, point.y)

static func world_to_map(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)

static func is_playable(point: Vector2) -> bool:
	return point.length() <= PLAYABLE_RADIUS_METERS
