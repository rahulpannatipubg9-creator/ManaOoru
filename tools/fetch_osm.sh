#!/bin/sh
# Re-download the OpenStreetMap extracts bundled with the game (build time only).
# Data © OpenStreetMap contributors, ODbL 1.0. The game itself never goes online.
set -e
cd "$(dirname "$0")/.."
fetch() {
	curl -sS -m 180 -A "ManaOoru-offline-import/0.1" --data-urlencode "data@tools/$1.overpassql" \
		https://overpass-api.de/api/interpreter -o "data/osm/$1.json"
	echo "Saved data/osm/$1.json"
}
fetch godavarikhani_core
fetch godavarikhani_features
