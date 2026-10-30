# MANA OORU — gameplay expansion

Implemented directly in the existing Godot project. Run `project.godot` and play the main scene. This source update does not replace the previously exported Android APK.

## Play

- **F7 / Activities:** timed delivery and taxi jobs, checkpoint races, three short neighbourhood delivery chapters, medical response, fire response, vigilante and gang encounters, supplies, vehicle repair, business ownership, and extra vehicles.
- **F5 / Journal:** discoveries, shops, time changes, ambience volume.
- **F6 / Time & weather:** automatic time/weather, fixed times, clear, rain, and storm.
- Start in **peaceful exploration**. Switch to **Action** in Activities for weapons, damage to the player, and wanted/police consequences.
- Follow the GPS and gold checkpoint. Taxi/race checkpoints require a vehicle. Taxi and delivery pickups/drop-offs require stopping. Medical/fire response requires exiting and holding **O** at the scene. Combat jobs require stopping the marked hostile actors.

## Controls

| Key | Action |
| --- | --- |
| WASD / Shift / Space / C | Move, run, jump, crouch |
| E / F | Enter / exit vehicle |
| V / B | Camera view / look behind |
| 1 | Equip or hide weapon |
| Left click / right click | Fire or punch / aim |
| Y / G | Reload / throw grenade |
| K / P | Use medkit / surrender while on foot |
| J / U | Talk to nearby resident / vault low obstacle |
| Hold O | First aid or extinguishing at a service checkpoint |
| F8 | Radio off / original electronic loop / original mellow loop |
| F7 | Activities, inventory counts, shops, repair, businesses, extra vehicles |
| Plane: W, I/K, Q/E | Throttle, pitch, bank; build speed before taking off |
| Swimming: WASD / Space | Swim / rise toward surface |

Basic touch buttons are provided on mobile. Android device behavior has not been verified.

## Added systems

- Re-enabled the dormant city-life controller in the main scene: shops/interiors, fuel, energy, discoveries, coin rewards, journal, and saved progression.
- Shared one environment controller between city life and the weather menu.
- Mission state, GPS targets, timeouts, cancellation and single-payment rewards. Three finite story chapters; other jobs are repeatable.
- Player ammunition, reload timing, camera-ray aiming, punch/gun damage, grenade explosions, armour, medical recovery, supplies and pickups. World geometry blocks bullets and blast damage.
- Five wanted levels, up to three physical police pursuers following the road network, sirens, high-level roadblocks, escape timers and surrender fines. Hostiles can return fire when they have line of sight.
- Vehicle impact condition, reduced engine power, disabling at zero condition, smoke, explosions and paid repair. Helicopter damage/repair are included.
- Wet-road tyre grip and braking limits, generated sky/clouds/stars, storm lighting and original thunder audio.
- Motorcycle, boat and fixed-wing aircraft controllers with original blockout models; reuse existing entry/camera/HUD contracts. Extra vehicle creation is bounded to one per type. Boats require a mapped water polygon of sufficient size.
- Swimming tied to mapped water polygons, collision-checked vaulting, basic combat/swimming poses, male eye/head/jaw motion, resident danger reactions and text conversations.
- Business ownership and bounded income during active play, persistent inventory and activity progress, generated radio/music loops, footsteps and combat effects. Optional spoken dialogue uses an installed system voice; text remains available without a voice.
- Scratch files excluded from Android exports.

## Prototype limits

This is a broad playable prototype, not finished GTA-level content. New vehicles, police, hostiles, fire/patient markers, service interactions and story briefings use simple assets and behavior. Taxi passengers and medical transport are represented by job state rather than animated boarding. Patrols can become stuck in dense streets. The flight controllers are arcade models and need tuning through playtesting.

The supplied character rigs have eye/head/jaw bones but no usable eyelid or lip-expression morphs. Natural blinking, emotional facial deformation and phoneme lip-sync remain unimplemented; those require character asset work. There are no cinematic cutscenes. Dialogue is simple scripted text, with optional system speech. Full multiplayer, production storytelling, recorded voice acting, advanced traffic theft/occupant simulation and production artwork are not included.

Desktop rendering was checked on Apple M1. Android touch controls and installed system voices were not device-tested. Existing regression scripts may report resource cleanup warnings at process exit; those are documented in the test logs.

## Validation

See `TEST_RESULTS.md` beside this document for the checks actually executed. No Android APK export or installation was performed.
