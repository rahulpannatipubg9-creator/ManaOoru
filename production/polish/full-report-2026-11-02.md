# Mana Ooru performance report — 2026-11-02

## Outcome

M1 optimization and selected regressions completed. Latest-build tablet testing is
blocked by installation approval. No changes have been committed or pushed.

Inputs found: runtime source, tree/map data, documented budgets, M1 rendered frame
intervals, callback timing, rendering counters, tablet identity and original settings.
Absent: successful latest-build tablet run, usable M1 GPU timestamps, extended thermal
or memory measurements. No project YAML budget configuration/helper exists here.
Enforcement is informational/warn. Desktop goal: 60 FPS / 16.67 ms. Documented budget
Android target is 30 FPS / 33.3 ms; the user's requested mobile goal is now 60 FPS.

## M1 measured results

Apple M1, OpenGL Compatibility. Same saved custom quality: 50% 3D scale, 250 m view,
6 ambient actor setting, 80 m simulation, shadows/effects off, 60 FPS cap.

| Short sample | FPS | Median ms | p95 ms | p99 ms | Max ms | Frames over 33.34 ms |
|---|---:|---:|---:|---:|---:|---:|
| Before: idle, 10 s | 26.20 | 36.09 | 60.31 | 71.48 | 85.92 | 166 / 262 |
| After: idle, 12 s | 58.20 | 16.75 | 18.79 | 21.85 | 154.93 | 2 / 699 |
| After: walking, 10 s | 60.02 | 16.66 | 17.26 | 18.24 | 19.29 | 0 / 601 |
| After: driving, 10 s | 60.17 | 16.64 | 17.56 | 19.00 | 20.14 | 0 / 602 |

Walking covered 21.90 m. Driving covered 8.20 m before obstruction: this is a short
city sample, not sustained high-speed travel. Idle still had a 154.93 ms outlier.
Before/after are different scene moments rather than deterministic replay.

Initial draw calls averaged ~2,148 (median 2,170); walking/driving after was ~1,581.
This still exceeds the custom settings' 180 draw-call soft target. Initial measured
render CPU was around 20 ms, after about 7.2 ms, but those counters may be cached:
actual frame intervals above are the primary pacing evidence. GPU timers returned
zero/unsupported: NOT ASSESSED. Initial physics averaged ~2.8 ms.

## Confirmed hotspot and retained fix

Temporary callback timers found `TreeBuilder._process()` consuming ~553 ms per second,
with a 48.9 ms callback. Traffic was next at ~25 ms/second. All temporary timing
wrappers were restored before final changes.

The old tree queue contained every map cell and kept generating distant foliage and
trunk bodies during play. A whole chunk could exceed its outer frame budget, and
remote chunks were never retired. The retained code now:

- Queues cells near streaming focus and obeys configured view distance.
- Resumes generation between source trees under a 1.2 ms processing budget.
- Frees distant chunk meshes and PhysicsServer trunk ownership.
- Recreates identical seeded placements on return.
- Applies distance changes to existing and future foliage.

Native chunk commit/allocation can still exceed the small loop budget in a dense
area; longer travel tests are needed. The ownership regression now stops ambient
callbacks before waiting for parked sleep, preserving world collision, enterable
vehicle physics and its 1 cm tolerance.

## Checks actually performed

Passed after the retained change:

- Required `movement_regression.gd`: input axes, diagonal normalization, idle,
  ownership, entry/exit and recovery.
- `tree_streaming_regression.gd`: local queue, real trunk ray collision, unload,
  deterministic return and resumable work.
- `performance_settings_regression.gd`, `performance_integration_regression.gd`.
- `camera_regression.gd`, `traffic_regression.gd`, `traffic_manager_regression.gd`.

Evidence: `/tmp/mana_tree_checks/`, `/tmp/mana_movement_after_tree.log`,
`/tmp/mana_tree_test.log`, `/tmp/mana_cost_profile.json`,
`/tmp/mana_script_costs.json`, `/tmp/mana_m1_after_tree.json`.
Reusable rendered probe: `scripts/performance/frame_profile.gd`.

## Tablet findings and blocker

Connected model: **2410CRP4CI**, device `uke`, SoC **SM7675**, reported GPU
**Adreno 732**, physical display **2136 × 3200**. Original saved game settings had
**30 FPS cap**, 65% scale, 320 m view, 120 m simulation, 12 actors and shadows off.
A 60 FPS target must be selected to test 60 FPS; that setting cannot guarantee it.
Observed battery temperature during preparation: 31–32 °C, not a thermal soak.

Original package `com.manaooru.prototype` was last updated 2026-10-30. Android
rejected replacement APKs with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Its signing
key did not match the available local keys. Original app/data were not removed.

A separate latest-source performance copy was built:

- `builds/ManaOoru-performance-latest.apk`, approximately 1.2 GB.
- Package `com.manaooru.perfcheck`, launcher label **MANA PERF**.
- APK signature and 16 KB ZIP alignment verified.
- Existing exported asset baseline plus listed current performance source/remaps;
  `tools/performance/package_probe.py` records script hashes inside the APK.
- First launch profiles; later launches run the normal main scene.

The tablet rejected this installation with:
**INSTALL_FAILED_USER_RESTRICTED: Install canceled by user**.
No successful latest-build tablet run occurred. APK staging to
`/data/local/tmp/manaooru-performance.apk` completed (1,315,204,798 bytes); retrying
does not require another transfer.
The user has been asked to approve installation on the tablet.

Tablet frame percentiles, CPU/GPU costs, memory/PSS, touch behaviour and thermal
throttling: **NOT ASSESSED — latest installation not approved**.

## Remaining work

1. Approve the MANA PERF installation, run its probe and pull the tablet report.
2. Investigate the idle outlier and dense-area native chunk commits.
3. Test longer driving, district crossings and a 30-minute memory/thermal soak.
4. Measure repeated street furniture/imported rendering before changing models.

Memory/loading headroom: NOT ASSESSED — no complete measurements or numeric budgets.
A short near-60 FPS result does not certify sustained smoothness on every device.
