"""Builds data/places/godavarikhani_places.json: the real, named shops, banks, hospitals,
schools, temples and offices of Godavarikhani, whose names go on the signboards; and
data/places/godavarikhani_streets.json: real street names for the street-name plates and
real junction ("centre", "chowk", "circle", "X roads") names for the junction boards; and
data/places/godavarikhani_street_life.json: real bus stops, open-air markets and colony
entrance gates for the street-life builder.

Sources:
  * OpenStreetMap named POIs from the local extracts in data/osm/ (ODbL 1.0).
  * Overture Maps Foundation "places" theme, release RELEASE, inside the play area.
    Overture places are CDLA-Permissive-2.0 (Meta, Microsoft), Apache-2.0 (Foursquare)
    or CC0; each record keeps its own licence. Only confidence >= MIN_CONFIDENCE is kept.
Names are kept exactly as published. Duplicates (same name within DEDUP_METERS) are merged,
preferring OpenStreetMap.

Street names: OpenStreetMap road names where mapped (only ~10 in this town). Other roads are
named from the street written in real business addresses (Overture places, all confidences):
a road gets a name only when at least MIN_STREET_VOTES addresses within STREET_REACH metres
name the same street and that name wins at least STREET_SHARE of the votes on that road.
Each inferred street records how many addresses back it.

Junction names: an OpenStreetMap node or roundabout named as a junction, or a junction name
that at least MIN_JUNCTION_MENTIONS business names/addresses use. Its position is the mapped
node, else the middle of the businesses that mention it, snapped to the nearest real road
junction (three or more road arms) within JUNCTION_SNAP metres. Only the densest cluster of
mentions (within JUNCTION_SPREAD metres) counts; a name whose cluster holds under a third of
its mentions is dropped as ambiguous.

Run: python tools/fetch_places.py data/places/godavarikhani_places.json data/places/godavarikhani_streets.json \
         data/places/godavarikhani_street_life.json
Needs: duckdb (pip install duckdb); downloads only the play-area rows from Overture's S3.
"""
import json
import math
import re
import sys
from collections import Counter, defaultdict

import duckdb

RELEASE = "2026-10-21.0"
BBOX = (79.4749, 18.7219, 79.5384, 18.7816)
MIN_CONFIDENCE = 0.5
DEDUP_METERS = 40.0
## Published as "shopping" but is the Chowrastha junction itself, not a business.
EXCLUDE_NAMES = {"godavarikhani chowrasta"}
MIN_STREET_VOTES = 2
MIN_JUNCTION_MENTIONS = 2
JUNCTION_SNAP = 150.0
JUNCTION_SPREAD = 500.0
JUNCTION_PATTERN = re.compile(
    r"([A-Za-z][A-Za-z .]{2,30}?\s*(?:Centre|Center|Circle|Chowk|Chowrasta|Chowrastha|X Roads|X Road|Cross Roads|Cross Road))\b", re.I)
## Words that end business names ("Mobile Service Center") rather than junction names.
NOT_JUNCTIONS = re.compile(r"(service|music|gift|matching|food|tiffin|health|development|repair|fitness|coaching|"
                           r"tution|tuition|computer|xerox|diagnostic|medical|beauty|training|study|sub ?cent)", re.I)
STREET_REACH = 60.0
STREET_SHARE = 0.6
STREET_PATTERN = re.compile(r"([A-Za-z][A-Za-z .]{2,40}?\b(?:Main Road|Road|Rd|X Roads|X Road|Cross Road|Cross Rd|Lane|Street|Marg))\b", re.I)
## OSM road names that are not street names on the ground: a junction (it has its own
## landmark board), the flyover structure, and a mis-tagged "BUILDINGS".
STREET_SKIP = {"chowrastha", "flyover", "buildings"}
ROAD_KINDS = {"trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "service", "living_street",
              "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
OSM_FILES = ["data/osm/godavarikhani_core.json", "data/osm/godavarikhani_features.json"]
OSM_KEYS = ["shop", "amenity", "office", "craft", "healthcare", "tourism", "leisure"]
SKIP_AMENITIES = {"parking", "toilets", "bench", "waste_basket", "drinking_water", "bus_station", "shelter"}
## Not signboard material: open spaces, transit and the area-named anganwadi (childcare) centres.
SKIP_CATEGORIES = {"amenity=childcare", "leisure=park", "leisure=garden", "leisure=playground", "leisure=pitch",
                   "leisure=stadium", "park", "stadium_arena", "public_transit_facility_or_service", "historic_site"}


def osm_places() -> list[dict]:
    found = {}
    for path in OSM_FILES:
        nodes = {}
        for element in json.load(open(path))["elements"]:
            if element["type"] == "node":
                nodes[element["id"]] = (element["lon"], element["lat"])
        for element in json.load(open(path))["elements"]:
            tags = element.get("tags", {})
            name = tags.get("name", "").strip()
            kind = next((f"{key}={tags[key]}" for key in OSM_KEYS if key in tags), "")
            if not name or not kind or tags.get("amenity") in SKIP_AMENITIES:
                continue
            if element["type"] == "node":
                lon, lat = element["lon"], element["lat"]
            else:
                points = [nodes[node] for node in element.get("nodes", []) if node in nodes]
                if not points:
                    continue
                lon = sum(p[0] for p in points) / len(points)
                lat = sum(p[1] for p in points) / len(points)
            found[(element["type"], element["id"])] = {
                "name": name, "category": kind, "lon": lon, "lat": lat,
                "source": "OpenStreetMap", "license": "ODbL-1.0", "confidence": 1.0,
            }
    return list(found.values())


def overture_places() -> list[dict]:
    """Every named Overture place in the play area, with its address, at any confidence."""
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2';")
    rows = con.execute(f"""
        SELECT names.primary, basic_category, confidence, ST_X(geometry), ST_Y(geometry),
               sources[1].dataset, sources[1].license, addresses[1].freeform
        FROM read_parquet('s3://overturemaps-us-west-2/release/{RELEASE}/theme=places/type=place/*', hive_partitioning=1)
        WHERE bbox.xmin BETWEEN {BBOX[0]} AND {BBOX[2]} AND bbox.ymin BETWEEN {BBOX[1]} AND {BBOX[3]}
          AND names.primary IS NOT NULL
    """).fetchall()
    return [{"name": name.strip(), "category": category or "", "confidence": round(confidence, 3), "lon": lon, "lat": lat,
             "source": f"Overture Maps ({dataset})", "license": license_name, "address": address or ""}
            for name, category, confidence, lon, lat, dataset, license_name, address in rows]


def street_key(name: str) -> str:
    """Spelling-insensitive key: "Laxmi Nagar Main Rd" and "Laxminagar Road" match."""
    key = name.lower().replace("cross", "x").replace("roads", "road").replace(" rd", " road").replace("main ", "")
    return re.sub(r"[^a-z]", "", key)


def osm_roads() -> list[dict]:
    data = json.load(open(OSM_FILES[0]))["elements"]
    nodes = {e["id"]: (e["lon"], e["lat"]) for e in data if e["type"] == "node"}
    roads = []
    for element in data:
        tags = element.get("tags", {})
        if element["type"] == "way" and tags.get("highway") in ROAD_KINDS:
            line = [nodes[n] for n in element.get("nodes", []) if n in nodes]
            if len(line) >= 2:
                roads.append({"id": element["id"], "name": tags.get("name", "").strip(), "line": line})
    return roads


def to_metres(lon: float, lat: float) -> tuple[float, float]:
    return ((lon - BBOX[0]) * 111000.0 * math.cos(math.radians(18.75)), (lat - BBOX[1]) * 111000.0)


def segment_distance(p: tuple, a: tuple, b: tuple) -> float:
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def streets(places: list[dict]) -> list[dict]:
    roads = osm_roads()
    lines = [[to_metres(*point) for point in road["line"]] for road in roads]
    votes: dict[int, Counter] = defaultdict(Counter)
    spellings: dict[str, Counter] = defaultdict(Counter)
    for place in places:
        for match in STREET_PATTERN.findall(place.get("address", "")):
            spelled = re.sub(r"\s+", " ", match.strip())
            spelled = re.sub(r"\bRd\b", "Road", spelled, flags=re.I)
            key = street_key(spelled)
            if len(key) < 6 or key in {"road", "unnamedroad", "serviceroad"}:
                continue
            spellings[key][spelled.title()] += 1
            point = to_metres(place["lon"], place["lat"])
            best, best_distance = -1, STREET_REACH
            for index, line in enumerate(lines):
                for a, b in zip(line, line[1:]):
                    distance = segment_distance(point, a, b)
                    if distance < best_distance:
                        best, best_distance = index, distance
            if best != -1:
                votes[best][key] += 1
    named: dict[str, dict] = {}
    for index, road in enumerate(roads):
        if road["name"].casefold() in STREET_SKIP:
            continue
        if road["name"]:
            entry = named.setdefault(road["name"].casefold(), {"name": road["name"], "source": "OpenStreetMap", "evidence": 0, "lines": []})
            entry["lines"].append(road["line"])
            continue
        if not votes[index]:
            continue
        key, count = votes[index].most_common(1)[0]
        if count >= MIN_STREET_VOTES and count / sum(votes[index].values()) >= STREET_SHARE:
            name = spellings[key].most_common(1)[0][0]
            entry = named.setdefault(key, {"name": name, "source": "business addresses (Overture Maps)", "evidence": 0, "lines": []})
            entry["evidence"] += count
            entry["lines"].append(road["line"])
    return list(named.values())


def meters(a: dict, b: dict) -> float:
    dx = (a["lon"] - b["lon"]) * 111000.0 * math.cos(math.radians(a["lat"]))
    dy = (a["lat"] - b["lat"]) * 111000.0
    return math.hypot(dx, dy)


def junction_key(name: str) -> str:
    key = name.lower()
    for old, new in (("center", "centre"), ("chowrastha", "chowrasta"), ("cross roads", "x road"), ("cross road", "x road"),
                     ("x roads", "x road"), ("swathantra", "swatantra"), ("near ", "")):
        key = key.replace(old, new)
    return re.sub(r"[^a-z]", "", key)


def road_junctions() -> list[tuple]:
    """Road nodes where three or more road arms meet, in metres."""
    data = json.load(open(OSM_FILES[0]))["elements"]
    nodes = {e["id"]: (e["lon"], e["lat"]) for e in data if e["type"] == "node"}
    arms: Counter = Counter()
    for element in data:
        if element["type"] == "way" and element.get("tags", {}).get("highway") in ROAD_KINDS:
            ids = element.get("nodes", [])
            for position, node in enumerate(ids):
                arms[node] += 1 if position in (0, len(ids) - 1) else 2
    return [(nodes[node], to_metres(*nodes[node])) for node, count in arms.items() if count >= 3 and node in nodes]


def junctions(places: list[dict]) -> list[dict]:
    found: dict[str, dict] = {}
    for path in OSM_FILES:
        for element in json.load(open(path))["elements"]:
            tags = element.get("tags", {})
            name = tags.get("name", "")
            if element["type"] == "node" and name and JUNCTION_PATTERN.fullmatch(name.strip()) and not NOT_JUNCTIONS.search(name):
                found[junction_key(name)] = {"name": name.strip(), "lon": element["lon"], "lat": element["lat"],
                                             "source": "OpenStreetMap", "evidence": 0}
    mentions: dict[str, list] = defaultdict(list)
    spellings: dict[str, Counter] = defaultdict(Counter)
    for place in places:
        for text in (place["name"], place.get("address", "")):
            for match in JUNCTION_PATTERN.findall(text):
                spelled = re.sub(r"\s+", " ", match.strip())
                spelled = re.sub(r"^(near|opp|opposite|beside|behind)\s+", "", spelled, flags=re.I)
                if NOT_JUNCTIONS.search(spelled) or len(spelled.split()) < 2:
                    continue
                key = junction_key(spelled)
                mentions[key].append(to_metres(place["lon"], place["lat"]))
                spellings[key][spelled.title()] += 1
    crossings = road_junctions()
    for key, points in mentions.items():
        if key in found or len(points) < MIN_JUNCTION_MENTIONS:
            if key in found:
                found[key]["evidence"] = len(points)
            continue
        # Roads named after a junction ("FCI Road") scatter mentions along their length; take
        # the densest cluster and require it to hold at least a third of them.
        cluster = max(([p for p in points if math.hypot(p[0] - c[0], p[1] - c[1]) <= JUNCTION_SPREAD] for c in points), key=len)
        if len(cluster) < MIN_JUNCTION_MENTIONS or len(cluster) * 3 < len(points):
            continue
        cx = sum(p[0] for p in cluster) / len(cluster)
        cy = sum(p[1] for p in cluster) / len(cluster)
        nearest = min(crossings, key=lambda c: math.hypot(c[1][0] - cx, c[1][1] - cy))
        if math.hypot(nearest[1][0] - cx, nearest[1][1] - cy) > JUNCTION_SNAP:
            continue
        name = spellings[key].most_common(1)[0][0]
        name = re.sub(r"\bX Road\b", "X Roads", re.sub(r"\b(Fci|Ci|Ntpc|Gdk)\b", lambda m: m.group(1).upper(), name))
        found[key] = {"name": name, "lon": nearest[0][0], "lat": nearest[0][1],
                      "source": "business names and addresses (Overture Maps)", "evidence": len(points)}
    return list(found.values())


def street_life(places: list[dict]) -> dict:
    """Bus stops (Overture), open-air markets and colony entrance gates (OpenStreetMap)."""
    stops = [{"name": p["name"], "lon": p["lon"], "lat": p["lat"], "source": p["source"]} for p in places
             if p["category"] == "public_transit_facility_or_service" or "bus stop" in p["name"].casefold()]
    markets, entrances = [], []
    for path in OSM_FILES:
        for element in json.load(open(path))["elements"]:
            tags = element.get("tags", {})
            name = tags.get("name", "").strip()
            if element["type"] != "node" or not name:
                continue
            point = {"name": name, "lon": element["lon"], "lat": element["lat"], "source": "OpenStreetMap"}
            if tags.get("amenity") == "marketplace" or (tags.get("shop") == "greengrocer" and "market" in name.casefold()):
                markets.append(point)
            elif name.casefold().startswith("entrance of "):
                point["name"] = name[len("entrance of "):].strip()
                entrances.append(point)
    unique = lambda items: list({(i["name"].casefold(), round(i["lon"], 4)): i for i in items}.values())
    return {"bus_stops": unique(stops), "markets": unique(markets), "entrances": unique(entrances)}


def main() -> None:
    kept: list[dict] = []
    overture = overture_places()
    confident = [p for p in overture if p["confidence"] >= MIN_CONFIDENCE]
    for place in osm_places() + sorted(confident, key=lambda p: -p["confidence"]):
        place = {key: value for key, value in place.items() if key != "address"}
        if place["category"] in SKIP_CATEGORIES or place["name"].casefold() in EXCLUDE_NAMES:
            continue
        key = place["name"].casefold()
        if any(other["name"].casefold() == key and meters(other, place) < DEDUP_METERS for other in kept):
            continue
        kept.append(place)
    json.dump({"generated_from": f"OpenStreetMap extracts + Overture Maps places {RELEASE}", "places": kept},
              open(sys.argv[1], "w"), ensure_ascii=False, indent=1)
    print(f"{len(kept)} named places ({sum(p['source'] == 'OpenStreetMap' for p in kept)} from OpenStreetMap)")
    named_streets = streets(overture)
    named_junctions = junctions(overture)
    for junction in named_junctions:
        print(f"  junction: {junction['name']} ({junction['source']}, {junction['evidence']} mentions)")
    json.dump({"generated_from": f"OpenStreetMap road names + Overture Maps place addresses {RELEASE}", "streets": named_streets,
               "junctions": named_junctions},
              open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
    life = street_life(overture)
    json.dump({"generated_from": f"OpenStreetMap + Overture Maps places {RELEASE}", **life},
              open(sys.argv[3], "w"), ensure_ascii=False, indent=1)
    print(f"  street life: {len(life['bus_stops'])} bus stops, {len(life['markets'])} markets, {len(life['entrances'])} colony gates")
    for street in sorted(named_streets, key=lambda s: s["source"]):
        print(f"  street: {street['name']} ({street['source']}, {len(street['lines'])} road pieces, {street['evidence']} addresses)")


main()
