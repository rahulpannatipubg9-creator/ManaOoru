# MANA OORU reference files

Findings from a full repository scan on 2026-10-30, at commit `635ae9a`. Start here before changing the game.

| File | What it holds |
|---|---|
| [CODEBASE_MAP.md](CODEBASE_MAP.md) | How the game is put together: start-up order, modules, data, conventions |
| [BUGS.md](BUGS.md) | Ranked defects with file, line, symptom and fix |
| [IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) | What to build next, in order, and why |
| [ASSETS_AND_LICENSES.md](ASSETS_AND_LICENSES.md) | Missing files, Blender import blocker, licence and release risks, repo clean-up |
| [WINDOWS_SETUP.md](WINDOWS_SETUP.md) | How to import and run the project on Windows |

These files sit beside the project's own docs. `docs/lessons/` is still the rule book: read the matching lesson
before touching characters, vehicles, weapons, buildings, props, imported models or multiplayer.

## How the scan was done

- **Read line by line (about 11,000 of the 26,800 non-test lines):** `main.gd`, `world_generator.gd`,
  `city_gameplay.gd`, `city_life.gd`, `person_controller.gd`, `rigid_vehicle.gd`, `arcade_vehicle.gd`,
  `traffic_vehicle.gd`, `pedestrian.gd`, `performance_controller.gd`, `network_manager.gd`, `lan_discovery.gd`,
  `loot_crate.gd`, `squad_lobby.gd`, `tdm_session.gd`, `tdm_match.gd`, `tdm_local.gd`, `tdm_roster.gd`,
  `road_network.gd`, `gps_navigator.gd`, `weapon_catalog.gd`, `weapon_pickup.gd`, `water_system.gd`, `pursuer.gd`,
  `mission_actor.gd`, `vehicle_effects.gd`, and parts of `network_player.gd`, `camera_controller.gd` and
  `settings_menu.gd`.
- **Covered by automated scans only:** every other `.gd` and `.tscn` file (unused functions, unreferenced scripts,
  unused input actions, hard-coded keys, function length, RPC declarations, hard-coded paths, secrets, runtime
  loads, per-frame lookups). This includes `hud.gd`, `test_character.gd`, `chowrasta_city.gd`, `building_builder.gd`,
  `map_data.gd`, `helicopter.gd`, `vehicle_entry.gd`, the world builders, the shaders and `tools/`. Those files can
  still hold bugs that this scan did not find.
- **Not done:** the game has not been played by hand. No bug here has been reproduced in a running game, and nothing
  about frame rate, memory or feel has been measured. Each bug in `BUGS.md` says how sure the finding is.

## Current state (commit `075b90a`)

- The repo has 7 commits by the original author, all from 2026-10-30. Commits after `635ae9a` only add models.
- All 48 committed `.glb` models import on Windows once the four `.blend` files are set aside
  (see `WINDOWS_SETUP.md`).
- All game scripts now compile, and the world builds in headless mode: 1,616 of 1,620 source roads and 18,857
  buildings. Only `assets/models/characters/rahul/rahul.glb` is still missing.
- The Android keystore password is in `export_presets.cfg` in a public repo. See `ASSETS_AND_LICENSES.md`.
