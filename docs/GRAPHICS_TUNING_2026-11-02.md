# M1 graphics tuning — 2026-11-02

Measured in the rendered Godavarikhani spawn scene on Apple M1, OpenGL Compatibility.
Each configuration warmed for 3 seconds, then sampled actual frame intervals for
8 seconds at the same camera/location with live city simulation. A 60 FPS target
was used for each configuration. These short comparisons do not certify sustained
smoothness, travel, thermal behaviour or Android performance.

| Configuration | Average FPS | Median frame ms | 95th-percentile frame ms |
|---|---:|---:|---:|
| Previously active | 21.82 | 44.06 | 67.35 |
| Medium, 60 FPS target | 23.70 | 41.26 | 57.74 |
| Low, 60 FPS target | 25.82 | 38.07 | 51.90 |
| Custom 50%, 60 FPS target | 26.61 | 36.14 | 54.86 |

The lightest option improved average FPS about 22%, but did not reach 60 FPS.
Its 95th-percentile frame time was slightly worse than Low in this short sample.
Reducing resolution and disabling shadows yielded only a modest improvement;
CPU/render submission and live-city simulation need profiling rather than assuming
more resolution reduction will solve the remaining frame-time cost.

Saved custom settings through the existing Settings menu path:

- Frame-rate target: 60 FPS.
- 3D resolution scale: 50%; 2D HUD retains native resolution.
- Building/prop distance: 250 m.
- Active ambient actor setting: 6.
- Simulation distance: 80 m.
- Shadows: off.
- Weather effects: 0%.

These are the existing menu controls, not new quality presets. Other bounded
systems may have independent caps; the actor setting does not prove only six
entities total are simulated. The 60 FPS option caps frame rate; it cannot ensure
that every frame finishes within 16.67 ms.

## Persistence fix

The manual flag previously restored the chosen hardware tier but discarded its
saved custom values. `DevicePerformanceManager.setup()` now overlays saved known
performance fields on the tier defaults. Weather effects are saved too. Setup and
tier override accept an optional test settings path, preventing the override test
from writing the real player's configuration.

Passed: `device_performance_manager_regression.gd`, including save/recreate/setup
checks for custom resolution, distances, actors, shadows, FPS and effects.
Also passed: `performance_settings_regression.gd` and the required
`movement_regression.gd`. A separate fresh-process probe read the actual saved
settings and confirmed 50% resolution, 250 m distance, 6 actors, shadows/effects
off, and a 60 FPS target. That probe emitted sandbox hardware-query warnings;
the saved-profile assertions passed.

The final rendered smoke passed walking, camera view toggles, vehicle entry,
6.999 m of driving and exit after braking. Sampled Engine FPS was 32 walking
and 30 driving. This moving smoke differs from the fixed-camera comparison
above and does not establish sustained smoothness or 60 FPS.
Logs: `/tmp/mana_tuned_smoke.log`, `/tmp/mana_verify_saved_graphics.log`.

Benchmark data: `/tmp/mana_graphics_benchmark.json`.
Log: `/tmp/mana_graphics_benchmark.log`.
Scripted probe: `/tmp/mana_graphics_benchmark.gd`.
No Android device was tested. No new gameplay systems were added.
