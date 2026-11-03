# Bugs found in the 2026-10-30 scan

Commit `635ae9a`. The game could not be run, so these come from reading the code.

- **Certain:** the code path is plain and nothing guards it.
- **Likely:** the reading is sound but depends on engine or runtime behaviour, so confirm it in a running game.

Fix the High items first, and add a `docs/lessons/` entry with each fix, as `AGENTS.md` requires.

## High

### 1. Reloading with R teleports the player backwards (Certain)
- **Where:** `scripts/main.gd:214-220`, `scripts/gameplay/city_gameplay.gd:158`
- **Symptom:** on foot, R reloads and also runs `person.recover_person()`. The player snaps to the safe spot saved up
  to 2 s ago (up to about 14 m at a run) or to the respawn point, and sees "Returned to safe ground". This happens in
  Team Deathmatch too.
- **Fix:** give on-foot recovery its own key or a menu button. Keep R for reload on foot and recover in vehicles.

### 2. Team Deathmatch does not block free-roam keys (Certain)
- **Where:** `scripts/main.gd:265-280` (F5, F6, F7, B), `scripts/world/city_life.gd:400`
- **Symptom:** in a live match:
  - B teleports the player 3 km to the bridge.
  - F7 replaces the whole scene, so a host's match dies without telling anyone.
  - F5 opens a journal that sets `paused = true` directly, bypassing `main.pause_tree`, so that player freezes in
    the fight.
  - E near a shop does the same through `open_shop`.
- **Fix:** return early from these handlers when `tdm_local.in_match`, and route all pausing through `pause_tree`.

### 3. Team Deathmatch can write match gear into the free-roam save (Certain)
- **Where:** `scripts/world/city_life.gd:94-97` and `:517`, `scripts/main.gd:370`, `scripts/gameplay/weapon_pickup.gd:88`
- **Symptom:** `tdm_local.gd` promises that a match never changes free-roam progress, but autosave keeps running and
  `save_progress` has no match check. Quitting during a match saves `has_rifle`, all rifles and 9999 reserve
  (restored as 999).
- **Fix:** skip saves while `tdm_active`, or save the snapshot in `tdm_local._saved`.

### 4. Street rifles stay live inside the Team Deathmatch arena (Certain)
- **Where:** `scripts/gameplay/weapon_pickup.gd:65-91`, `scripts/tactical/tdm_local.gd:182-194`
- **Symptom:** pickups sit within about 15 m of Chowrastha, inside the 125 m arena, and `_hide_city` does not hide
  them. Walking over one sets a 30-round magazine to 24, adds reserve and triggers a save.
- **Fix:** disable the `weapon_pickups` group during a match. Also read magazine size from `gameplay.mag_size`.

### 5. Being knocked down in squad mode also respawns you at home (Likely)
- **Where:** `scripts/network/network_manager.gd:349-353`, `scripts/gameplay/city_gameplay.gd:778-797`
- **Symptom:** health reaching 0 emits `health_changed`, which defers `_respawn`. The same frame sets `downed = true`.
  `_respawn` then teleports home, heals fully and charges the fee, but never clears `downed`. The player crawls at
  15% speed with full health until the bleed-out timer eliminates them. `test_multiplayer_loopback.gd` tests the
  network layer, so it may not catch this if the gameplay layer is absent.
- **Fix:** in `_health_changed`, skip `_respawn` when a squad session is active or `person.downed` is set.

### 6. Eliminated squad players vanish for good (Certain)
- **Where:** `scripts/network/network_manager.gd:492-493`, `:323`
- **Symptom:** other peers remove the puppet on elimination. The player respawns locally, but `rpc_sync_transform`
  ignores unknown senders, so nobody sees them again until they reconnect.
- **Fix:** hide the puppet and show it on respawn, or call `_spawn_puppet` from the sync handler when it is missing.

### 7. Squad name tags show "Player 12345" (Certain)
- **Where:** `scripts/network/network_manager.gd:168`, `:203-205`, `:289`, `:315`
- **Symptom:** the puppet is created on `peer_connected` with a placeholder. When the real name arrives,
  `_spawn_puppet` returns early, so `puppet.nickname` is never updated. `_update_overhead_display` shows the old name.
- **Fix:** set the nickname and refresh the label when the puppet already exists.

### 8. Squad RPCs let any peer do anything (Certain)
- **Where:** `scripts/network/network_manager.gd:280-501`
- **Symptom:** `rpc_apply_damage`, `rpc_notify_eliminated`, `rpc_notify_revived`, `rpc_receive_room_state` and
  `rpc_peer_joined` are `any_peer` and check nothing about the sender. A modified client can kill anyone, overwrite
  the player list or spawn crates. Team Deathmatch is protected, free roam is not.
- **Fix:** make host-to-client messages `authority`. Route damage through the host as Team Deathmatch does. This
  matters less on a private LAN, so it can follow the bugs players will see.

### 9. New rifle added without a protocol bump (Certain)
- **Where:** `scripts/tactical/tdm_session.gd:14-16`, `scripts/gameplay/weapon_catalog.gd:57-75`
- **Symptom:** the CZ Bren 2 is now a valid id and Team Deathmatch hands out `Weapons.IDS`, but `PROTOCOL_VERSION` is
  still 2. An older build can join a newer host, which breaks the project's own rule in `docs/lessons/MULTIPLAYER.md`.
- **Fix:** bump to 3 and update the comment.

## Medium

### 10. B key does three things (Certain)
- **Where:** `scripts/main.gd:277-280`, `scripts/gameplay/city_gameplay.gd:160`, `project.godot:98-101`
- **Symptom:** B teleports to the bridge and marks the event handled, so fire mode never toggles even though the
  status line advertises "B Auto/Single". B is also `camera_look_behind`. The README says look-behind is C, which is
  actually crouch.
- **Fix:** move the teleport behind a debug flag, keep B for one job, and correct the README.

### 11. F7 no longer opens Activities (Certain)
- **Where:** `scripts/main.gd:273-276`, `scripts/gameplay/city_gameplay.gd:153-154`, `:240`
- **Symptom:** `main._input` handles F7 first and loads Chowrasta City, so `open_board` never runs from the key. The
  status line and `docs/GAMEPLAY_EXPANSION.md` still say "F7 Activities". The board is only reachable through
  Settings → Activities.
- **Fix:** give the map switch its own route and restore F7, or update the text.

### 12. E leans right as well as interacting (Certain)
- **Where:** `project.godot:30`, `:86-89`, `:138-141`, `scripts/player/person_controller.gd:253`, `scripts/main.gd:208`
- **Symptom:** on foot E is `lean_right`, `vehicle_enter` and `interact`, so peeking right tries to enter vehicles and
  shops. Other shared keys are safe because they split by on-foot and driving (Z, Q, H, L).
- **Fix:** move lean right to a free key.

### 13. Pausing during Team Deathmatch only shows text (Certain)
- **Where:** `scripts/main.gd:354-366`
- **Symptom:** `_set_menu_paused(true)` sets `_paused` and shows "PAUSED", but the tree is not paused in a match, and
  mouse mode depends on `tree.paused`. The player keeps moving, with no cursor to use.
- **Fix:** in a match, open a non-pausing menu with a visible cursor.

### 14. Loot crates give the wrong rewards (Certain)
- **Where:** `scripts/network/loot_crate.gd:91-105`, `scripts/gameplay/city_gameplay.gd:630`
- **Symptom:** the toast says "+15 Coins" but no coins are added. Ammo goes into the magazine, which can pass
  `mag_size`, instead of `reserve`.
- **Fix:** call `hud.add_coins`, and add ammo to `reserve` with its cap.

### 15. Repeat deaths give crates clashing names (Likely)
- **Where:** `scripts/network/network_manager.gd:475`, `:504`
- **Symptom:** crates are named `LootCrate_<peer>`. A second crate from the same player while the first exists gets
  an auto-generated name, so looting by name can remove the wrong one or none.
- **Fix:** use a unique crate id from the host.

### 16. Android APK will probably have no trees (Likely)
- **Where:** `export_presets.cfg:8`, `scripts/world/tree_builder.gd:13`, `:79`
- **Symptom:** non-resource files must be listed in `include_filter`, and `data/trees/*.bin` is not.
  `data/buildings/vidya_nagar_2_overture.geojson` is also unlisted. Confirm by exporting.
- **Fix:** add `data/trees/*.bin` and `data/**/*.geojson`, then check the APK contents.

### 17. Android may lose progress when the app is closed (Likely)
- **Where:** `scripts/main.gd:369-371`
- **Symptom:** the save on exit only runs for `NOTIFICATION_WM_CLOSE_REQUEST`. Android apps usually get
  `NOTIFICATION_APPLICATION_PAUSED` or a go-back request, so up to 30 s can be lost.
- **Fix:** also save on those notifications.

### 18. Armour absorption leaves the HUD behind (Certain)
- **Where:** `scripts/gameplay/city_gameplay.gd:773-777`
- **Symptom:** health is raised after the signal without a new emit, so the health display shows too little.
- **Fix:** emit again after absorbing, guarding against recursion.

### 19. Silent progress loss on a future save version (Certain)
- **Where:** `scripts/world/city_life.gd:531-536`
- **Symptom:** a corrupt file or a version other than 1 starts a new game, and the next autosave overwrites the old
  file. There is no backup or migration.
- **Fix:** keep a `.bak`, and add version migrations before changing the format.

### 20. Nothing stops a map change during multiplayer (Certain)
- **Where:** `scripts/ui/settings_menu.gd:116-121`, `scripts/main.gd:273-276`
- **Symptom:** scene changes do not disconnect. The multiplayer peer stays on the tree while the networking nodes are
  gone, so incoming RPCs fail.
- **Fix:** disconnect first, or disable these buttons while connected.

## Low

| # | Where | Issue |
|---|---|---|
| 21 | `main.gd:221-222`, `:290` | Tab shows an info hint and switches character at once; README only describes the hint |
| 22 | `person_controller.gd:247` | Holding Ctrl crouches, but releasing does not stand up; the README calls it hold-style |
| 23 | `squad_lobby.gd:39` | Nickname comes from the device model and cannot be edited |
| 24 | `tdm_session.gd:198-208` | Fast falls (over 12 m/s) count as teleports, so the host's position lags during a drop |
| 25 | `gameplay/city_gameplay.gd:604-620`, `:1180-1192` | Each shot allocates a new mesh and material; pool them |
| 26 | `traffic_vehicle.gd:171-192` | Each scooter scans all World grandchildren and builds a physics query every frame; traffic is capped at 10, so the cost is bounded |
| 27 | `pedestrian.gd:150-156` | Ground sampling loops over every storefront 12.5 times a second per pedestrian |
| 28 | `project.godot:6`, `:22` | `config/features` still says 4.3 and `renderer/rendering_method.driver` is not a real setting |

## Checked and cleared

- Fuel, energy and `main.gd:601` `velocity`: `RigidVehicle` has a `velocity` alias, so exit does not crash.
- Hidden ambient actors do come back: `pedestrian.gd:88` and `traffic_vehicle.gd:47` restore visibility.
- `chowrasta_city.gd:1065` has a way back to the main scene.
- `_job_points` mixing world and map coordinates is safe, because the map plane is `Vector2(x, z)`.

## Fixed on `ui/fixes`

11, 16, 17, 18, 19, 21, 22, 25, 28, 29. For 16 the filter is tested, but no APK has been built and opened.

## Found reading the vehicle, helicopter, character and environment code (2026-10-30)

These come from reading the code, not from a running game. Already fixed on `ui/fixes`:

- A wrecked helicopter never updated its exit prompt and skipped the fall-out-of-world recovery (`helicopter.gd`).
- Weather set back to Automatic held forced rain for up to 180 s (`city_environment.gd`).
- Street lamps were sorted four times a second by day, when none can show (`city_environment.gd`).
- A helicopter parked in mid-air stayed there out of reach (`helicopter.gd`, was 29).
- A held lean stayed on the driver for the whole drive, and Rahul's fingers stayed open on handlebars
  (`test_character.gd`).

Still open:

| # | Rating | Where | Issue |
|---|---|---|---|
| 30 | Medium, Likely | `player/test_character.gd:379`, `:1225` | `_pose_male_face` runs after the clips and sets `CC_Base_Head` from rest, which wipes the head from the gait and `Rifle_ADS_Idle` clips and the `HEADING_HEAD` twist. Running it first looks right, but the rifle head turn was tuned on top of the wiped pose, so check it in a render |
| 31 | Low, Certain | `world/city_environment.gd:91`, `gameplay/city_gameplay.gd:998` | Headlights are only built at setup, so bought vehicles never get any |
| 32 | Low, Certain | `player/test_character.gd:286` | `hip_height()` reads `_hip`, which only the test lady sets. Rahul sits at the 0.95 fallback in a shipped build, but at her hip height on a desktop that has her model |
| 33 | Low, Likely | `world/city_environment.gd:178-179` | Lightning holds the sun at full energy until the next `apply_state`, and at night it lights the town from below the ground |
| 34 | Low, Certain | `vehicle/vehicle_entry.gd:154` | Boarding from the far side walks the player straight through the vehicle, because the walk is a position change with no collision |
| 35 | Low, Certain | `vehicle/helicopter.gd:47`, `:181`, `:249` | `_collective` is never read, the quiet-engine branch cannot run, and the comment on `entry_door_position` is wrong: `vehicle_entry.gd` does not call it |
