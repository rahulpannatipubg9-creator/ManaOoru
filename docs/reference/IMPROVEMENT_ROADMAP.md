# Improvement roadmap

Order matters: get it running, stop the bleeding, then make it fun. Sizes are rough: S under a day, M a few days,
L a week or more. Recommendations come from reading the code. Feel and frame rate are unmeasured, so review this list
after the first play session.

## Phase 0: make it run (now)

| Task | Size |
|---|---|
| Get `rahul.glb`, the last missing model | S, needs the repo owner |
| Rotate the keystore password | S, needs the repo owner |
| Move `.blend` sources out of the project | S |
| First Windows play-through, recording every problem | S |
| Run all 73 regression tests on Windows and record results | S |
| Baseline numbers: load time, FPS, memory, draw calls at Chowrastha | S |

## Phase 1: fix what players will hit (week 1)

- Fix `BUGS.md` items 1 to 4: R teleport, match keys, save corruption, arena pickups.
- Rebuild input around one table: every key is an action in `project.godot`, grouped by on-foot, driving, flying and
  menu, with no raw `KEY_*` for gameplay. Add a rebinding screen and a controls help page. This removes a whole class
  of bugs.
- Put debug teleports behind a developer flag.
- Fix squad bugs 5 to 7 and bump the protocol (9).
- Add a script that runs every test with a timeout and prints one summary, plus GitHub Actions on each push.

## Phase 2: a game you can start and finish (weeks 2 to 4)

The game has no front door.

- **Loading screen:** everything builds on the main thread with a blank window. Show progress, and move data parsing
  to worker threads. The code has no threads today.
- **Title screen:** Continue, New Game, Multiplayer, Settings, Credits. Credits are also a legal need.
- **Real pause menu:** resume, map, settings, save and quit.
- **Save system:** save position, vehicles, time and weather, mission state. Add backups and version migration.
- **Clean the HUD:** the status line is a block of text with key hints. Use icons, a health bar, and a compact ammo
  counter. Show hints only when relevant.
- **Update the README and design document** to match the game that exists.

## Phase 3: make the city feel alive (month 2)

This is the biggest win for a game about a real town.

- **Traffic that reacts.** Ambient vehicles have no collision, so you drive through them, and they do not stop for
  you. They also turn around on the spot at the end of a route. Add simple collision, braking for obstacles, and
  routes through the road network with proper junction choices.
- **Pedestrians that react.** They have no physics either, so cars pass through them. Add avoidance and being hit.
- **Replace blockouts.** Motorcycle, scooter, police car, ambulance, boat and plane are boxes labelled "blockout".
  In India the motorcycle and scooter matter most, so do these first, with a proper lean and physics model.
- **Local identity:** Telugu signs and voice lines, autos and RTC buses, Singareni mine shift changes, festivals,
  morning tea and evening market rhythms.
- **Vehicle lights and indicators:** the input actions exist but nothing uses them.

## Phase 4: give players a reason to stay (months 2 to 3)

Today all 8 job types share one skeleton: go to a point, sometimes hold a key, receive 20 to 30 coins. The story is
three short delivery chapters.

- **Story:** a real arc rooted in the town, with named characters, cutscenes and choices. Start with 6 to 8 missions.
- **Mission variety:** chases, stealth, timed rescues, escorts, each scripted through one mission framework instead
  of more `if kind ==` branches in `city_gameplay.gd`.
- **Economy:** energy and fuel drain but have no effect, and rewards are flat. Make them matter or remove them. Add
  things worth saving for: garages, vehicles, clothes, businesses that visibly change.
- **Police:** pursuers are road-following boxes that damage on contact. Add real driving, officers on foot, and
  escape tactics.
- **Combat:** add cover, enemies who flank, hit reactions and better feedback.
- **Progression:** a phone menu in the game for missions, map, contacts and bank.

## Phase 5: multiplayer that holds up (month 3)

- Move free-roam damage to the host, as Team Deathmatch does (bug 8).
- Sync vehicles in squad mode. Today only people sync.
- Add editable nicknames and a host version check for free roam.
- Add client-side prediction and interpolation tests with real Wi-Fi lag.
- Try internet play through a relay later. ENet here has no encryption and needs port forwarding, so keep it LAN
  until that is designed.

## Phase 6: performance and release (month 3 onward)

- Profile before optimising. Budgets in `docs/PERFORMANCE_BUDGETS.md` have never been measured.
- Test the likely hot spots: 18,862 buildings, terrain mesh collision, shadows on budget phones, 45 scripts with
  per-frame processing, one material per actor, A* on the main thread (police re-plan every 2.5 s).
- Add LOD and impostors for buildings, instancing for props, and object pools for tracers and flashes.
- Add automatic quality scaling from measured frame time, not just device memory.
- Test `get_viewport().scaling_3d_scale` under the Compatibility renderer, in case it has no effect there.
- Compare Jolt physics for cars and terrain.
- Add controller support, accessibility options, and language support for Telugu, Hindi and English.
- Test on real Android devices, and resolve every licence item before any public build.

## Code structure, as you go

Refactor only while working in an area:

- Split `main.gd` into input routing, possession and camera transitions.
- Split `city_gameplay.gd` into combat, police, missions and shop or economy.
- Rename `test_character.gd` to `player_character.gd`.
- Replace `has_method` checks with a vehicle base interface. The car, helicopter and arcade vehicles share one.
- Replace private calls across modules with public methods.
- Retire the old `player_controller.gd` car. `scenes/player/player.tscn` still uses it, so check that scene first.
- Remove the dead code listed in `CODEBASE_MAP.md`.

## First five tasks

1. Get `rahul.glb` and play the game on Windows.
2. Fix R reload, then B and F7.
3. Stop free-roam systems acting during Team Deathmatch.
4. Add the test runner and CI.
5. Build the loading screen and title screen.
