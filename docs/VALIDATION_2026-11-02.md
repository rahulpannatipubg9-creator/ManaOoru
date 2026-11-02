# Mana Ooru validation — 2026-11-02

Branch: `feature/traffic-v1`. `git pull origin main` reported already up to date.
This review includes the existing uncommitted feature batch; it does not certify every test or asset in the repository.

## Parked-vehicle regression

The final change corrects `tests/movement_regression.gd`; vehicle physics is unchanged.
The previous fixture retained its isolated flat ground underneath the real city,
measured before streamed collision settled, and mixed player-input isolation with
live pedestrian/traffic impacts. It also left touch input active during its keyboard-W check.

The corrected fixture frees the pad before loading the city, waits a bounded time
for settlement, stops ambient callbacks without removing world collision or disabling
enterable vehicles, and sweeps for a clear walking path. It retains the original
1 cm parked-vehicle tolerance, checks parked physics stays enabled, and clears
touch input before keyboard W. The required command passes:

`godot --headless --path . --script tests/movement_regression.gd`

An experimental runtime sleep guard and suspension-ray change were removed after
character collision validation regressed. They are not part of the final change.

## Feature checks

Passed:

- Movement: axes, diagonal normalization, idle stability, translation, ownership, entry/exit and recovery.
- Traffic following/lane stability, traffic signals, manager spawn/cap/despawn, scooter obstacles.
- Camera views, chase camera, vehicle entry, scene collision configuration, character physics (including parked-car blocking and impacts).
- Streaming cleanup and high-speed lookahead/cache checks.
- Device performance classification/settings persistence and sensitivity settings.
- Weapon switching; imported vehicles (31 vehicles); Bullet motorcycle.
- TDM network regression: 21 checks, 0 failed.

Failed:

- `tdm_match_regression.gd`: 94 checks, 27 failed. Failures include health/damage,
  kills/assists, respawn/regen and match completion/rematch. There is also an empty-array
  error in the kill-event fixture. Cause has not been diagnosed; this is a blocker.

Headless output/logs: `/tmp/mana_validation_20261102/`.
The first sandboxed settings checks could not write user settings; the permitted rerun passed.
A zero process exit alone is not sufficient: TDM network reports its success as
`21 checks, 0 failed`, and assertion errors can leave other Godot fixtures running.

## M1 playtest

Rendered scripted smoke testing used the Apple M1 OpenGL Compatibility renderer.
The probe exercises actual game APIs and physics; it is not a manual keyboard/touch playtest.
The first exit request was issued before cached speed updated. The corrected probe
brakes normally and waits for a low speed before exit.

Final-runtime run passed walking, camera view toggles, entry, driving and exit.
Walking translated 1.040 m; driving translated 6.999 m. Exit was requested after
braking to -0.173 m/s and completed successfully. No other validation process
was running during this final rendered run. Sampled Engine FPS was 22 walking
and 23 driving, below the desktop 60 FPS target. These are short samples, not
a sustained frame-time/memory profile. Performance needs attention before expansion.
Final log: `/tmp/mana_m1_retained_runtime.log`; scripted probe: `/tmp/mana_m1_smoke.gd`.
Screenshots: `/tmp/mana_m1_walking.png`, `/tmp/mana_m1_driving.png`.

## Android and remaining limits

`adb devices -l` returned an empty device list on both permitted checks.
No Android installation, touch playtest or mobile profiling was performed.
Connect and authorize a USB-debugging device before that part can be completed.

Full-city camera clipping, extended soak, all mission playthroughs, physical LAN
matches, every facade/survey test, and Windows/iOS were not tested in this review.
No APK was rebuilt, no feature systems were added, and nothing was committed or pushed.
Across the selected regressions, 18 passed and 1 failed (TDM match); the rendered
M1 smoke is additional. Keep feature expansion on hold pending TDM repair,
M1 performance investigation and Android testing.
