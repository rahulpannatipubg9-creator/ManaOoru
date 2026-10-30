# MANA OORU — Team Deathmatch (TDM) design

Status: **implemented (2026-10-29), not yet tested on devices.** See section 13 for what is built, what differs from this design and what is untested.
A BGMI-TDM-inspired mode on our own map: a 125 m-radius arena around the Chowrastha junction.
Every rule below was confirmed by the owner over eight question rounds (2026-10-28 and 29).
Reference renders of the arena: `outputs/tdm_reference/` (`00_contact_sheet.png`).

## 1. Pitch

A separate, selectable game mode: two teams fight in a small arena cut out of the real Godavarikhani map,
centred on the Chowrastha junction (world origin, `scripts/map/geo_projection.gd`). Friends host and join
over the existing SQUAD flow on the same Wi-Fi. Free-roam stays as it is; TDM is a different ruleset on the
same world, not a fork of the game.

## 2. Match rules

| Item | Decision |
|---|---|
| Teams | Red and Blue. Default 4v4, host can pick 2v2 to 8v8 (`MAX_CLIENTS` is 16) |
| Win | First team to the kill limit (default **40**) or most kills at the time limit (default **10:00**) |
| Tie at the timer | Sudden death: next kill wins; draw if nobody scores within 60 s |
| Death | Instant. **No downed state, no revive** (BGMI's DBNO is a battle-royale mechanic) |
| Health | 100 HP. Slow regen starting 5 s after the last damage taken (start value about 10 HP/s, tune in playtests). Host-owned |
| Respawn | 5 s, then at a safe spawn zone of the player's own team; 3 s spawn protection that ends the instant they fire |
| Weapon | Everyone carries the **M416** and the **AK-47** and switches freely (key 2 / ⇄): 30-round magazines (one per rifle), unlimited reserve, about 2 s reload, no pickups, no grenades. M416 28 body / 70 head every 0.11 s; AK-47 34 / 85 every 0.13 s with more recoil (added 2026-10-29) |
| Friendly fire | Off |
| Movement | Run, jump, crouch, prone, peek-lean. **Vault off** (can get stuck on props) |
| Camera | Player's choice of first or third person (V key) |
| Vehicles | None in v1. Parked vehicles become static cover |
| City systems | Off: missions, wanted/police, pedestrians, traffic, shops, weather changes, free-roam saving |
| Assists | 30 or more damage to the victim within 8 s before the kill |
| Suicides | Fall, out of bounds or below the world: a death with no kill credit. If an enemy hit them in the last 5 s, that enemy gets the kill |
| Late join | Joins the smaller team as a normal respawn: full health, 3 s protection, score continues |
| Host leaves | Match ends for everyone (no host migration in v1) |

**Lobby options the host can set:** team size (2v2 to 8v8), kill limit (20 / 40 / 60), time limit (5 / 10 / 15 min),
time of day (morning / afternoon / night, fixed for the whole match). Arena size and protection time are fixed in v1.

**Teams:** players auto-balance into the smaller team. A swap button works only if it keeps teams within
one player of each other; the host can move anyone. A rematch swaps sides. Team score is its own counter,
so it does not drop when a player leaves.

**Characters:** each player picks Lady or Male before the match and the choice is synced. Both models need
the same head/body hit zones for host validation. The Male is the realistic likeness model; its head size and
hair were still being tuned (see the avatar notes), so check it before relying on it.

## 3. The arena

- **Centre:** Chowrastha junction (0, 0). **Boundary:** circle of radius `ARENA_RADIUS = 125 m`: 250 m across,
  about 4.9 ha, about 36 s to run across at 7 m/s, about 6,100 m² per player in 4v4. A config value, tuned
  after playtests (drop to 100 m if it feels empty, raise for 8v8).
- **What is there:** flat, low-rise streets. A dual carriageway runs NW–SE through the junction; a single road
  crosses it from the NE and a tertiary road leaves to the S. HDFC Bank sits at the junction and is the
  contested centre. See section 12 for the data scan.
- **Spawns:** Red on the NW arm, Blue on the SE arm, about **75–85 m from the junction** (about 160 m apart,
  23 s to run). The renders show the highway is a straight, open sight line, so spawn zones go on the **side
  lanes beside the highway**, not on it, and cover goes on the road itself (market-street stalls, carts, walls,
  static parked vehicles, assets in `assets/models/market_street` and the panipuri/bhelpuri carts).
- **Spawn choice:** each team has 3 or 4 zones. The picker prefers the zone farthest from enemies and **rejects any
  zone with a clear line of sight to an enemy**. If a point is occupied, fall back to the next so nobody is telefragged.
- **Boundary:** a red edge vignette and "Return to the combat area" with a 5 s countdown from the 125 m ring.
  Staying out is a death with no kill credit. The countdown does not run during the pre-match countdown or while protected.
  Anything below the ground is also a death.
- **Culling (the biggest mobile-FPS lever):** the world has 18,862 buildings. In TDM only build and keep what is
  within about `ARENA_RADIUS + 50 m`.
- **Map and minimap:** reuse `minimap.gd` / `full_map.gd`, clamped to the arena with the boundary ring drawn.
  Teammates are always shown; enemies appear briefly after they fire. Sector names (NW lane, Bank crossing,
  Municipal Complex side, Hospital side) are used for callouts because only 14 named places exist within 300 m.

## 4. Netcode

Existing (`scripts/network/`): ENet host/join, LAN discovery, squad lobby, 20 Hz position sync, puppets,
DBNO/revive, loot crates. It is peer-trusting: `rpc_apply_damage` is `any_peer` and health lives on each client,
so a scoreboard has no single source of truth.

**TDM model: host-authoritative match, client-authoritative movement.**

| Owned by | What |
|---|---|
| Host | Match state and timer, teams, health and regen, hit validation, kills/deaths/assists, respawn and spawn choice, win/tie rules, pings and chat rate limits |
| Each client | Its own movement (stance and peek included), camera and aim, magazine and reload state, firing requests |

**One shot:** client fires → `rpc_id(1, request_fire, origin, dir, weapon_tick)` → the host ray-casts in its copy of
the world and rejects shots that start far from the shooter's last known position, fire faster than the weapon
allows, hit dead or protected players, or hit teammates → host updates health → host broadcasts
`damage_applied`, `player_killed`, `score_changed`. Clients show only what the host confirms; the shooter's hit
marker comes from the host's reply. Movement is clamped to about 1.5 times run speed.

**Hit accuracy:** v1 has no rewind. Positions arrive at 20 Hz today (0.35 m of running per tick), so TDM
uses **30 Hz** and generous tolerance, to be confirmed on devices. Add a short position history only if
close-range misses show up in testing. The network puppets need real head/body hit zones.

**New RPCs** (any-peer ones check `get_remote_sender_id()`): `request_fire`, `request_team_swap`,
`request_ready`, `request_ping`, `request_chat`; host to clients: `match_state`, `roster`, `damage_applied`,
`player_killed`, `player_respawn`, `score_changed`, `match_ended`.

**Connection handling**
- The join handshake carries a build/rules version. A mismatch is **rejected** with an "update the game"
  message before any match state is sent.
- A dropped player's slot is held **60 s**. They keep team and score, rejoin with the token the host issued, and are an
  invulnerable, untargetable ghost until then. After 60 s the slot is freed; their kills stay in the team total.
- Duplicate names are auto-suffixed. A team with nobody left forfeits after 30 s. A lone host cannot start a match but gets practice mode.

## 5. Interface and feedback

- **Pre-match:** 5 s countdown, players frozen at spawn but free to look around, weapons disabled, big "3, 2, 1, GO".
  The host starts the clock for everyone at the same server time.
- **HUD:** team totals and timer always on screen; kill feed at the top (last 4 kills, 5 s each: killer, weapon icon,
  victim, headshot mark, names in team colours); a small button shows the full scoreboard (both teams, kills /
  deaths / assists) for 3 s. On desktop `Tab` is already "quick information", so use another key.
- **Hits:** hit marker and click on every hit; red and sharper for a headshot; no damage numbers.
- **Damage direction:** a red arc around the crosshair pointing at the shooter.
- **Death:** a 3 s killcam on the killer, then the 5 s respawn countdown. If the killer is gone, a plain countdown.
- **Sound:** footsteps carry about 25 m and gunshots about 120 m, attenuated locally from synced positions.
- **Aim assist:** light touch slowdown near targets (start value about 25 % sensitivity reduction, tune in playtests).
- **Team identity:** a red or blue armband on every player and a floating nameplate on **teammates only**. Enemies
  show no name or outline.
- **Spawn protection cue:** a soft glow visible to everyone plus a shield icon on the player's own HUD. No transparency (slow on mobile).
- **Quick chat wheel (team-only, no voice in v1):** Enemy here, Need backup, On my way, Good shot, Thanks, Hold position.
  The first three also drop a map ping. One active ping per player, 6 s, visible to teammates only. The host rate-limits both.
- **Match end:** winner banner, then the scoreboard with the top player highlighted, then the host chooses REMATCH or LOBBY.
- **Practice mode (lone host):** standing dummies with head and body zones that respawn; a counter of hits, headshots,
  shots fired and accuracy; no timer or score; runs on the host with no AI.

## 6. Flow

1. Host: tap the 🌐 SQUAD button on the HUD → GAME MODE = Team Deathmatch → set options → HOST GAME. (SQUAD is a HUD button; it is not in the Settings menu.)
2. Others: FIND GAMES → tap the room (shows "TDM 4v4 · night") → auto-placed on the smaller team.
3. Lobby: Red and Blue columns, READY toggles, host taps START → countdown with everyone at spawns.
4. Match, end screen, rematch or lobby.

## 7. Code layout

Use the empty `scripts/tactical/` folder so the mode is isolated from free-roam:

```text
scripts/tactical/
  tdm_config.gd        # radius, kill/time limit, team size, time of day (Resource)
  tdm_match.gd         # host-only state machine: LOBBY → COUNTDOWN → LIVE → ENDED
  tdm_roster.gd        # peer → team, kills, deaths, assists, balance rules, reconnect tokens
  tdm_spawns.gd        # spawn zones and the safest-spawn picker
  tdm_arena.gd         # boundary, out-of-bounds timer, culls the world to the arena
  tdm_hud.gd           # score bar, timer, kill feed, scoreboard, respawn and killcam
scenes/tactical/tdm_arena.tscn
```

Integration points (kept small):
- `scripts/main.gd` already creates `network_manager`; add a `game_mode` (FREE_ROAM / TDM) that decides which
  systems start. City gameplay, pedestrians and vehicles are not enabled in TDM, and TDM never touches the free-roam save.
- `network_manager.gd` stays the transport. Its trusting damage path is bypassed in TDM and DBNO is disabled by the mode.
- `squad_lobby.gd` gets the host-only mode selector and options; add `mode` and the version to the LAN discovery room dictionary.
- Local pause (Esc) must not freeze a player in a live match: use a menu overlay while the player stays in the world. Check how pause works today.

## 8. Risks

- **Determinism.** Building styling is seeded from position (`building_builder.gd:616`), so buildings match across devices. Other
  generators (roadside props, drainage) are not yet checked. All TDM cover props must be static and identically placed.
- **Scale.** 125 m radius is still a little larger than BGMI's TDM maps (about 100–200 m across, from memory, not measured).
- **Mobile FPS.** The 30 FPS target is unmeasured. Culling to the arena is mandatory.
- **Phone interruptions.** Calls and locked screens stop the game; covered by the 60 s ghost slot. A host on a phone ending the match is a real risk.
- **Hit accuracy** at 20/30 Hz without rewind (see section 4).
- **Internet play.** Same Wi-Fi or IP only; different networks need a relay. A later decision (and it conflicts with the README's "no network dependency").
- **Cheating.** Host-validated hits stop casual cheating; a malicious host can still cheat, which is out of scope for friends.

## 9. Milestones

| # | Deliverable | Done when |
|---|---|---|
| 0 | Data scan and reference renders (done at 300 m / 125 m view); pick exact spawn points and cover in the engine; measure FPS on desktop and one Android device with culling | Spawn positions and FPS numbers written down |
| 1 | Host-authoritative match core (`tdm_match`, `tdm_roster`, `tdm_spawns`), no UI; head/body hit zones on puppets | Headless test: two peers, host-counted kills, respawn, win and tie rules |
| 2 | Arena: culling, boundary, spawns and cover in-world | Walk the whole boundary; no stuck spawn |
| 3 | HUD, lobby/settings mode selector, discovery `mode` and version | Two devices complete a match through the UI |
| 4 | Feedback polish: kill feed, hit markers, damage arc, killcam, protection glow, scoreboard, chat and pings, rematch | |
| 5 | Android device testing and profiling | Reported honestly; anything unmeasured is marked "not tested" |

Tests to add under `tests/` (per AGENTS.md, report only what is actually run): `tdm_scoring_regression`,
`tdm_spawn_selection_regression`, `tdm_boundary_regression`, `tdm_team_balance_regression`,
`tdm_hit_validation_regression`, a two-process LAN connect test, and the existing `movement_regression` after any gameplay change.

## 10. Decisions for milestone 2 (2026-10-29)

- **Edge look:** beyond the 125 m ring the world fades into fog with no buildings (cheapest on phones, hides the
  culling), a soft haze dome marks the edge, and the red out-of-bounds warning applies.
- **Cover assets:** existing project assets (market-street stalls, carts, vehicles) plus plain blockout shapes for
  barriers and walls. No new models, so no new entries in `ASSET_LICENSES.md`.
- **Test devices:** the Xiaomi Pad 7 and one phone on the same Wi-Fi. Frame rate and the two-device match are
  measured on those; phone-side behaviour can't be observed from this Mac, so it is marked "not tested" until the
  owner reports it.
- **Way of working:** one step at a time, no parallel agents.

## 11. Still open (defaults apply)

- 30 Hz sync in TDM: confirm on devices.
- Regen rate and aim-assist strength: tune in playtests.
- Arena radius 125 m and spawns at 75–85 m: revisit after the first playtest.
- Internet play: not in v1.

## 12. Appendix: data scan of the area (from the 300 m scan)

Computed from `data/osm/godavarikhani_core.json`, the Microsoft footprints, `data/places` and the Copernicus
terrain grid. The 125 m arena is the inner part of the scanned 300 m circle. The two building sources were
counted separately and not de-duplicated, so totals overlap. The scan was not re-run at 125 m.

| Item | Result inside 300 m |
|---|---|
| Buildings | 546 OSM + 228 Microsoft footprints, about 48,000 + 21,000 m², at most about 25 % of the circle |
| Roads | 78 highway ways: 6 secondary, 4 tertiary, 3 unclassified, 62 residential, 3 links |
| Main roads | Dual carriageway NW–SE (exits near 313° and 133°); single secondary road from the NE (44°); tertiary road to the S (about 190°) |
| Terrain | Almost flat: -3 m to +7 m |
| Named places | 14 in total. HDFC Bank 6 m from the junction, Municipal Complex 154 m at 233°, Madeena General Stores 219 m at 49°, Asha General Hospital 276 m at 239° |

## 13. Implementation status (2026-10-29)

**Built** (all under `scripts/tactical/` unless noted):
`tdm_config`, `tdm_roster`, `tdm_spawns`, `tdm_match` (host rules); `tdm_session` (networking, host validation, chat/pings,
version handshake, reconnect); `tdm_arena` (spawn zones, cover, boundary shell, fog and far-plane culling);
`tdm_local` (turns session events into gameplay, practice mode, aim assist, radar data); `tdm_hud` (lobby, score bar,
kill feed, hit marker, damage arcs, boundary warning, scoreboard, chat wheel, radar, end screen); `tdm_dummy`.
Hooks in existing files: `main.gd` (session, view, pause guard, no vehicles), `squad_lobby.gd` (mode picker and options),
`lan_discovery.gd` (mode and detail in the room list), `network_manager.gd` (30 Hz in TDM, trusting damage and DBNO off),
`network_player.gd` (team armband, teammate nameplate, head zone, 3D sounds), `city_gameplay.gd` (30-round magazine, 2 s
reload, no crime, no grenades, vault, medkits, missions or extra vehicles), `settings_menu.gd` (no tree pause in a match).

**Differences from the design above**
- Rifles (2026-10-29): hit claims name the rifle; the host takes its damage and its own minimum fire interval
  (M416 0.075 s, AK-47 0.09 s) from `scripts/gameplay/weapon_catalog.gd` and refuses unknown ids. Protocol version 2,
  so a version-1 game is turned away. Remote players show the held rifle from bits 8 and up of the synced stance code.
- Hit flow: the shooter's client reports `(victim, headshot, origin, hit position)`; the host checks it (positions known,
  shooter near the origin, target near the hit point, range, no wall in between, fire rate, protection, friendly fire)
  rather than re-casting the ray itself. This avoids the 20/30 Hz stale-puppet problem. No rewind.
- Spawn zones: up to six candidates per team are found; those with a straight line to an enemy zone are pruned, keeping at least two.
- Minimap: the free-roam minimap is hidden in a match. A small north-up radar replaces it (teammates, enemies for 3 s
  after they fire, pings). Pings are not drawn on the original minimap.
- Killcam: a text message ("Killed by X, respawning in N") instead of a camera on the killer.
- Falls: only dropping below the arena floor counts as a fall death; ordinary fall damage is ignored.
- Fog density is a fixed 0.0065, a trade between hiding the far plane and seeing across the arena.

**Tests added** (`tests/`): `tdm_match_regression` (94 checks, rules), `tdm_network_regression` (21 checks, two real
processes over ENet on localhost: handshake, version refusal, host-validated hits and kill, chat and ping relay, end of
match), `tdm_integration_regression` (42 checks, inside the real game scene: arena, culling, no open sight line between
spawn zones, practice mode, live match, firing, clean return to free roam). All pass on the Mac.

**Not tested** (no device access from this Mac): any Android device, frame rate with culling, two real devices on Wi-Fi,
touch controls and aim assist, audible 3D footsteps and gunshots, auto-rejoin after a dropped connection, two game
instances shooting each other through the real puppets (the network test sends claims directly), cover balance and
spawn placement by playtest, the 30 Hz sync rate on Wi-Fi.
