"""Coordinate helpers shared by the import tools. Must match scripts/map/geo_projection.gd."""

import math

ORIGIN_LON = 79.513352
ORIGIN_LAT = 18.751925
METERS_PER_DEGREE_LAT = 111000.0
METERS_PER_DEGREE_LON = METERS_PER_DEGREE_LAT * math.cos(math.radians(ORIGIN_LAT))


def map_to_lon_lat(x, z):
    """Game map-plane metres (x east, z south) to longitude/latitude."""
    return ORIGIN_LON + x / METERS_PER_DEGREE_LON, ORIGIN_LAT - z / METERS_PER_DEGREE_LAT


def utm(lat, lon, zone=44):
    """WGS84 latitude/longitude to UTM easting/northing (northern hemisphere)."""
    a = 6378137.0
    f = 1 / 298.257223563
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    k0 = 0.9996
    lon0 = math.radians((zone - 1) * 6 - 180 + 3)
    phi = math.radians(lat)
    n = a / math.sqrt(1 - e2 * math.sin(phi) ** 2)
    t = math.tan(phi) ** 2
    c = ep2 * math.cos(phi) ** 2
    big_a = math.cos(phi) * (math.radians(lon) - lon0)
    m = a * ((1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256) * phi
             - (3 * e2 / 8 + 3 * e2 ** 2 / 32 + 45 * e2 ** 3 / 1024) * math.sin(2 * phi)
             + (15 * e2 ** 2 / 256 + 45 * e2 ** 3 / 1024) * math.sin(4 * phi)
             - (35 * e2 ** 3 / 3072) * math.sin(6 * phi))
    x = k0 * n * (big_a + (1 - t + c) * big_a ** 3 / 6
                  + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * big_a ** 5 / 120) + 500000
    y = k0 * (m + n * math.tan(phi) * (big_a * big_a / 2 + (5 - t + 9 * c + 4 * c * c) * big_a ** 4 / 24
                                       + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * big_a ** 6 / 720))
    return x, y


def map_to_utm_affine():
    """Affine (E, N) = f(x, z) fitted at three points; accurate to centimetres over the 6 km play area."""
    def at(x, z):
        lon, lat = map_to_lon_lat(x, z)
        return utm(lat, lon)
    e0, n0 = at(0.0, 0.0)
    ex, nx = at(1000.0, 0.0)
    ez, nz = at(0.0, 1000.0)
    return (e0, (ex - e0) / 1000.0, (ez - e0) / 1000.0, n0, (nx - n0) / 1000.0, (nz - n0) / 1000.0)
