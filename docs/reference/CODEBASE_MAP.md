# Codebase map

Godot 4.7.2, GDScript, Compatibility (OpenGL) renderer. No autoloads, no plugins, no addons. Android arm64 is the
main target; macOS on an M1 is the only tested platform.

| Area | Size |
|---|---|
| Game and tool scripts (`.gd`, excluding tests) | 26,800 lines |
| Tests | 96 scripts, 7,900 lines, 73 named `*_regression.gd` |
| Shaders | 10 files, 765 lines |
| Scenes | 16 `.tscn` |
| Models | 48 `.glb` committed, 1 referenced file still missing |

## Start-up order

`scenes/main.tscn` is the main scene. There is no title screen or loading screen. Everything builds in `_ready` on
the main thread:

1. `World` (`scripts/world/world_generator.gd`) builds first as a child: map data, terrain, roads, nearby buildings,
   signs, landmarks, spawns, street life, trees, birds, pedestrians, traffic, coins.
2. `scripts/main.gd` `_ready`: environment, sun, HUD, vehicle placement, `RoadNetwork`, `GpsNavigator`,
   `VehicleEntry`.
3. Then in this order, and later steps depend on earlier ones: `CityLife` → `CityGameplay` → `EnvironmentControls` →
   performance controller → `NetworkManager` → `TdmSession` → `TdmLocal`.

## Modules

| Folder | Role | Key files |
|---|---|---|
| `scripts/main.gd` | Game state, possession, input routing, cameras, teleports | 735 lines; everything depends on it |
| `scripts/player/` | On-foot movement, the character rig, old car, engine sound, gearbox | `person_controller.gd`, `test_character.gd` (the real player rig despite the name), `gearbox.gd` |
| `scripts/vehicle/` | Rigid-body cars, helicopter, entry and exit | `rigid_vehicle.gd`, `helicopter.gd`, `vehicle_entry.gd` |
| `scripts/camera/` | Orbit, first person, chase, aim, recoil, gyro | `camera_controller.gd` |
| `scripts/gameplay/` | Single-player activities, combat, police, economy, market | `city_gameplay.gd` (1,192 lines) |
| `scripts/world/` | World building, city life, save file, weather | `world_generator.gd`, `building_builder.gd`, `city_life.gd`, `chowrasta_city.gd` |
| `scripts/map/` | Map data, routing, GPS, minimap drawing | `map_data.gd`, `road_network.gd`, `gps_navigator.gd` |
| `scripts/network/` | ENet free-roam squad, LAN discovery, lobby | `network_manager.gd`, `network_player.gd`, `squad_lobby.gd` |
| `scripts/tactical/` | Team Deathmatch, host authoritative | `tdm_match.gd` (rules), `tdm_session.gd` (network), `tdm_local.gd` (device side) |
| `scripts/ui/` | HUD, map, menus | `hud.gd` (1,075 lines), `settings_menu.gd` |
| `scripts/mobile/` | Touch layouts and settings | `claw_layout.gd`, `hud_layout_profiles.gd` |
| `scripts/performance/` | Graphics presets, ambient actor limits | `graphics_settings.gd`, `performance_controller.gd` |
| `data/` | Offline map data: OSM, terrain, buildings, trees, land cover, places | Read with `FileAccess` at runtime |
| `tools/` | Python and Blender pipelines | Many have hard-coded Mac paths |

## Game modes

- **Free roam:** the default. Exploration, shops, jobs, wanted level, rifles from street pickups.
- **Squad (LAN):** ENet on port 7777 with UDP discovery on 7778 and 7779. Peers trust each other.
- **Team Deathmatch (LAN):** the host owns the match and checks hit claims. Weapons are limited to the rifles. The
  city is trimmed to a 125 m arena around Chowrastha.
- **Other scenes:** `chowrasta_city.tscn` (sketch-based map), `godavari_bridge_driving.tscn`.

The README and the Game Design Document still describe a single-player game with no combat. The code has moved
well past them.

## Conventions worth keeping

- Coordinates: 1 unit is 1 m, +X east, -Z north. Map plane is `Vector2(x, z)`, and `GeoProjection` converts.
- Input goes through `GameplayControls`, with one owner at a time.
- Bump `PROTOCOL_VERSION` in `tdm_session.gd` when rules or messages change.
- Record every external asset in `ASSET_LICENSES.md`. A fix needs an entry in `docs/lessons/`.
- Typing is excellent: 5,093 of 5,102 `var` declarations are typed or inferred.

## Where the quality sits

Self-contained modules are the strongest code. `tdm_match.gd`, `tdm_roster.gd`, `road_network.gd`,
`gps_navigator.gd`, `lan_discovery.gd` and the physics in `rigid_vehicle.gd` read as careful, and the reading
turned up no defects in them.

Bugs cluster where systems meet: `main.gd` input routing, `network_manager.gd` free-roam code, and the join between
Team Deathmatch and free-roam systems.

## Coupling hot spots

- `main.gd` is reached from everywhere as `game`. Modules call its private methods (`_finish_exit_vehicle`,
  `_clear_control_inputs`, `_sync_input_context`, `_window_unfocused`).
- `hud._game` appears 15 times, `signage._nearest_road` 12 times, `life._button` 6 times.
- `has_method` and dynamic calls are heavy in `hud.gd` and `main.gd` (16 each) and `city_gameplay.gd` (10).
- Keys are read in three different ways: input actions, `Input.is_key_pressed`, and raw `KEY_*` in event handlers.
  This is the direct cause of the key conflicts in `BUGS.md`.

## Dead code

Never referenced anywhere: `city_gameplay._build_touch_controls`, `main._interact`, `main._toggle_camera_shoulder`,
`road_network.node_count`, `gyro_look.sensor_enabled`, `network_manager.get_local_peer_id`,
`test_character._scale_character_model`, `tdm_roster.remove_member`, `tdm_session.host_move_player`,
`tdm_spawns.zone_count`, `hud._press_action`, `hud._release_action`, `vehicle_entry.is_busy`,
`vehicle_entry.is_seated`, `building_builder._distance_to_footprint`, `city_environment.cycle_weather`,
`godavari_bridge_builder._valley_ground_material`, `signage_builder.dustbin_count`.

Also: `main.gd` has unused `_interact_was_pressed` and `_character_was_pressed`. `city_gameplay._build_ui` creates
an Activities button and frees it straight away. `scripts/world/shop_marker_loader.gd` is unreferenced.

Unused input actions: `vehicle_brake`, `vehicle_steer_left`, `vehicle_steer_right`, `vehicle_lights`,
`vehicle_indicator_left`, `vehicle_indicator_right`, `interact`.

`host_move_player` and `vehicle_lights` look like features that were started and never connected, so check before
deleting them.
