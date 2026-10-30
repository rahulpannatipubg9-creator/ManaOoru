# Assets, licences and repo health

Commit `635ae9a`, 2026-10-30.

## Missing files

Referenced by scripts or scenes but not in the repo.

Updated for commit `075b90a`. Only one file is still missing:

- `assets/models/characters/rahul/rahul.glb` (the default player). The code does not preload it, so the game still
  compiles.

Only the paths written as plain strings could be checked. Files built by string formatting may not all be covered.

## Blender files block import

Four tracked `.blend` files stop all model import on any machine without Blender configured. Details are in
`WINDOWS_SETUP.md`. They also bloat the repo. Move Blender sources outside the Godot project, for example to a
separate `art-source` repo or a folder with a `.gdignore`, and keep only the exported `.glb`.

## Security: do this before anything else

`export_presets.cfg` line 28 holds the Android release keystore password in plain text, in a public repo, since
commit `50b9aa5`. The keystore itself is not in the repo.

1. Create a new keystore and password. Assume the old password is public.
2. Move credentials to Godot's `.godot/export_credentials.cfg`, which is ignored, or use environment variables.
3. Removing the line in a new commit does not clear history. Rotating the key is what counts.

The package name `com.manaooru.prototype` and the keystore path also point at one person's Mac, so each developer
needs their own debug signing.

## Licence risks

From `ASSET_LICENSES.md`. A public APK counts as distribution.

| Asset | Status | Risk |
|---|---|---|
| Porsche 911 | CC BY-NC 3.0, author name unknown | Must go before any commercial release; trademark and design rights too |
| Jeep Compass | Source and licence unknown | Do not distribute until confirmed |
| Mahindra Thar | CC BY, credit required | Trademark and design rights need permission or de-badging |
| AK-47 | Licence not confirmed; the add-on used looks unofficial | Confirm or replace |
| CZ Bren 2 | Licence not confirmed; brand name in game | Confirm or replace; consider a fictional name |
| Houses, apartments, coal mine, fountain | Source and licence unknown | Do not distribute until confirmed |
| Haathgaadi | User supplied, licence not stated | Confirm |
| Real shop names and signs | Noted in `ASSET_LICENSES.md` | Check trademark use before commercial release |

Safest path: unbranded fictional vehicles and rifles with original or CC0 models. That removes most of this table.

## Map data and street imagery

- **Credits are required but not shown properly.** OSM and Microsoft footprints (ODbL), Google Open Buildings,
  Copernicus DEM and ESA WorldCover all need attribution. `map_data.gd` loads an attribution string, but the scan
  found no credits screen. `market_street.gd:149` has an "Asset credits" button, but it sits inside a market shop
  and is about market props. Add a Credits page under Settings before any public build.
- **ODbL share-alike** may apply to data derived from OSM. Keep attribution, and publish the derived data if needed.
- **Google Street View:** several facades and data files are built from "user supplied Google Street View
  screenshots" (`data/local/bhaskar_neighbour_reference.json`, `vidyanagar2_photo_sequence.json`,
  `ashok_theatre_facade.gd`, `cinema_poster_wall.gd`, `vidya_nagar_one_entrance.gd`). Google's terms restrict
  deriving content from its imagery. Use your own photos as reference before a public release.
- **Mapillary** imagery is CC BY-SA 4.0, so credit it.
- **Cinema posters:** `assets/textures/cinema/weathered_movie_posters.png` may show real film posters. Check it.

## Repo clean-up

| Item | Action |
|---|---|
| `tools/__pycache__/*.pyc` (5 files) | Delete, ignore `__pycache__/` |
| `bridge_viewport_capture.png` in the root | Delete or move to docs |
| `tests/tmp_nav_debug.gd`, stray `tests/tmp_helicopter_debug.gd.uid` | Delete |
| `opencode.jsonc` | Delete if nobody uses it |
| `/Users/rahulpannati/...` paths in tools and 3 tests | Use arguments or relative paths |
| No `.gitattributes` | Add `* text=auto eol=lf`, so Windows and Mac stop fighting over line endings |
| Git size is already 170 MB | Use Git LFS for `.glb`, large textures and audio now, before history grows |
| `.gitignore` covers `*.zip` and `*.exe` | Fine, keep it |

## Tests

- 96 test scripts with no runner and no CI. Each must be started by hand.
- 23 of them are captures, inspections and debug scripts, mixed in with real tests. Move them to `tools/`.
- Failed loads can leave a test hanging instead of failing, so a runner needs a timeout.
- `docs/TEST_RESULTS.md` records passes on an M1 only.
