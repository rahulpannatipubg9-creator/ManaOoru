# Tests, captures and tools: lessons

## Running tests

- `godot --headless --path . --script tests/<name>.gd`. A test whose assertion fails inside `_init` does **not
  quit**: it hangs until killed. Run tests with a time limit (macOS has no `timeout`; use
  `perl -e 'alarm 600; exec @ARGV' godot …`).
- Run the tests for the area **before** changing it too, so an old failure isn't blamed on new work.
- Report only tests actually run (AGENTS.md).

## Seeing the game

- Headless runs render nothing. For pictures, run windowed under `caffeinate -d -i` (Godot windows stall from
  macOS App Nap; `defaults write org.godotengine.godot NSAppSleepDisabled -bool YES` is set).
- Film close-ups through a `SubViewport` sharing the world (`world_3d = root.get_viewport().world_3d`) with its
  own camera, so the game camera stays current (the rifle and HUD follow the game camera).
- The game blocks input while unfocused; captures set `GameplayControls.blocked = false` when they need input.

## Entries

### Incremental Android installs can disappear after reporting success (2026-11-02)
- **Symptom:** A successful incremental installation disappeared before launch. PackageManager subsequently removed its incremental storage mount. A separate session was also installing diagnostics under the original shared package ID.
- **Cause:** Incremental installation reported success before the APK was fully delivered. That result did not establish a durable installation. The earlier source-patched APK separately failed script/remap parsing before reaching gameplay.
- **Rule:** Use `adb install --no-incremental`, a unique benchmark package (`com.manaooru.pad7bench`) and a complete Godot export. Verify package presence after installation, clean script loading and actual gameplay before collecting FPS. Keep the device foreground stable and record interrupted runs as incomplete.
- **Check:** `Android Performance` exports the complete current project; `tools/performance/run_pad7_probe.py` preserves raw device logs, frame distributions, memory and temperature samples. A parse or install failure is not an FPS result.

### A signed and zip-aligned APK can still fail Android installation (2026-11-02)
- **Symptom:** Pad 7 rejected the performance copy with error -124: Android R+ requires an uncompressed, 4-byte-aligned `resources.arsc`.
- **Cause:** `tools/performance/package_probe.py` compressed every replacement, including the resource table. Signature verification and zipalign alone did not detect that requirement.
- **Rule:** Store `resources.arsc` uncompressed, align the completed APK, verify its signature, and require successful installation before reporting gameplay results. Preserve the original game's package/data.
- **Check:** Inspect the resource table's ZIP compression method as well as running zipalign and apksigner; the actual Pad 7 installation is the final packaging check.

### Android profiling builds need signature and space checks (2026-11-02)
- **Symptom:** Latest APK signing exhausted host disk space; installing a manually signed APK failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
- **Cause:** Export and signing held large APK copies alongside editor memory/swap. The installed tablet build's signature did not match either local debug key or the repository release key.
- **Rule:** Verify signing identity before a large transfer, sign after the exporter exits when space is tight, and never uninstall a user's game to bypass the mismatch. Use an explicitly labelled, separate debug test package when the original signing key is unavailable. Verify ZIP alignment and the APK signature after any debug-source packaging.
- **Check:** `package_probe.py` creates package `com.manaooru.perfcheck` labelled `MANA PERF`, preserving the original app. Its first launch profiles; subsequent launches run the normal scene. Read installation success and device logs before claiming tablet validation.

### Custom rendering was replaced by tier defaults on restart (2026-11-02)
- **Symptom:** Manually lowering rendering settings did not reliably survive the next launch.
- **Cause:** `DevicePerformanceManager.setup()` saw the manual flag but regenerated the selected tier without restoring the saved performance fields. `save_settings()` also omitted weather effects. The tier-override test wrote its default path and could replace real user preferences.
- **Rule:** Restore saved known performance fields over tier defaults for manual profiles; persist effects too. Allow setup and tier overrides to use an isolated settings path in tests. Do not equate a 60 FPS cap with measured 60 FPS rendering.
- **Check:** `device_performance_manager_regression.gd` now saves custom scale, distances, actors, shadows, FPS and effects, creates a fresh manager, runs setup from the test file and checks all values survived.

### Keep collision present when isolating ambient simulation (2026-11-02)
- **Symptom:** Pausing the world fixture made parked cars fall; a rendered exit probe was refused immediately after zeroing velocity.
- **Cause:** `PROCESS_MODE_DISABLED` can remove CollisionObject3D bodies through their disable mode. Separately, `main.gd.exit_vehicle()` checks controller `current_speed`, which was still the previous physics tick's driving speed.
- **Rule:** For an input-ownership fixture, stop world process/physics callbacks while preserving collision and every enterable vehicle subtree. For rendered exit checks, brake normally and allow physics to update speed before requesting exit. Keep live-city smoke checks separate from isolated ownership checks.
- **Check:** Required movement regression passes with parked physics enabled; the M1 smoke probe logs speed at the exit request.

### Camera fixture quit with engine audio still playing (2026-11-01)
- **Symptom:** Chase-camera assertions passed but the test leaked Ogg and generator playback resources at shutdown.
- **Cause:** The standalone driving fixture was still running its engine when the test called `quit()`; queued audio teardown had not retired playback.
- **Rule:** Park/mute the fixture, allow playback retirement, free owned fixture nodes and drain deferred frees before quitting. Keep the camera assertions intact. Accelerated fixed-FPS runs are not evidence of real-time audio teardown timing.
- **Check:** `godot --headless --path . --verbose --script tests/chase_camera_regression.gd` passes without resource-leak warnings after fixture cleanup.


### Cloud CI/CD and Codespaces Godot Android export keystores and editor settings (2026-10-30)
- **Symptom:** Cloud headless exports in GitHub Actions / Codespaces failed with errors regarding missing Android keystores or unconfigured Android SDK paths; local exports failed on non-developer machines due to hardcoded absolute Mac paths in `export_presets.cfg`.
- **Cause:**
  1. `export_presets.cfg` referenced an absolute macOS filesystem path (`/Users/rahulpannati/Downloads/.../builds/manaooru-release.keystore`), which broke on Linux runners (GitHub Actions Ubuntu / Codespaces).
  2. Godot headless exporter requires `export/android/sdk_path` and `export/android/java_sdk_path` in `~/.config/godot/editor_settings-4.tres` before it will compile APKs from the command line.
  3. `builds/` is git-ignored, so fresh cloud runner checkouts lack keystores unless generated during pre-export setup.
- **Rule:**
  1. Always use relative Godot paths (`res://builds/manaooru-release.keystore`) inside `export_presets.cfg`.
  2. Dev container and CI/CD workflow scripts must create `builds/` and auto-generate fallback debug and release keystores if not present.
  3. Dev container setup and CI/CD jobs must write `~/.config/godot/editor_settings-4.tres` mapping `export/android/sdk_path` to `${ANDROID_HOME}` and `export/android/java_sdk_path` to `${JAVA_HOME}`.
- **Check:** `godot --headless --export-debug "Android" builds/ManaOoru.apk` runs cleanly without path errors; GitHub Actions `.github/workflows/build_android_apk.yml` and `.devcontainer/setup.sh` pass quality gates.

### Touch screen camera drag lag and physics interpolation queue delay (2026-10-30)
- **Symptom:** "evern after fix i feel laggy" on mobile and tablets (Xiaomi Pad 7); camera rotation felt sluggish, heavy, and unresponsive to thumb swipes and gyroscope movements despite steady 50-60 FPS rendering.
- **Cause:** Three separate latency traps in `camera_controller.gd`:
  1. `_unhandled_input` required `event.relative.length_squared() > 16.0` (over 4 physical pixels in a single drag event) before assigning `_look_touch_index`. On 120Hz/240Hz touch polling digitizers, subtle, small, or precise finger swipes produce 1-2 pixel deltas per event, meaning every drag was discarded (`if event.index != _look_touch_index: return`), creating a deadzone where gentle swipes did nothing until the player violently flicked.
  2. Camera rotation was only applied in `_physics_process()` (60 Hz tick). Touch drag, mouse motion, gyroscope, and chase camera calculations updated `_yaw` and `_pitch` in input handlers and `_process(delta)`, but render frames drew with stale orientations until the next physics step.
  3. With `common/physics_interpolation=true`, `CameraPivot` inherited physics interpolation from the player/vehicle body, which delayed camera orientation changes by 1-2 full physics ticks (16-33 ms) and smoothed them out.
- **Rule:**
  1. Touch look zone touches must immediately claim `_look_touch_index` on press and accept all drag events without artificial single-frame distance thresholds.
  2. `CameraPivot` must disable physics interpolation (`physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF`) so view rotation updates instantly on the render frame while still inheriting the parent body's interpolated spatial position.
  3. Call `_apply_orbit_rotation()` immediately upon mouse/touch look events and at the end of `_process(delta)` so render frames reflect real-time input without waiting for physics ticks.
- **Check:** `tests/movement_regression.gd`, `tests/camera_regression.gd`, `tests/chase_camera_regression.gd`.

### High-resolution mobile tablets (Xiaomi Pad 7 / 3.2K display) suffered severe lag under Tier 4 desktop settings (2026-10-30)
- **Symptom:** "game is fulll lag" on Xiaomi Pad 7; measured frame rates dropped to 30-35 FPS with heavy frame drops and thermal throttling.
- **Cause:** `DevicePerformanceManager.classify_device` assigned any high-resolution or 6GB+ tablet to Tier 4 (`TIER_4_PRO_TABLET_DESKTOP`). The Tier 4 profile unlocked 120 FPS, 4 shadow splits (`SHADOW_PARALLEL_4_SPLITS`), 100m shadow distance, 900m view distance, 400m simulation distance, 55 actors, and 0.75 resolution scale. On a 3200x2136 screen, 0.75 scale is 2400x1602 (3.84 million pixels per frame). Compounded by 4 cascaded shadow passes across 250+ building chunks in Godot Compatibility (GLES3) forward rendering, the mobile CPU and Adreno 732 GPU were completely choked.
- **Rule:** Mobile tablets (`not is_desktop`) must never be assigned desktop PC settings. For mobile tablets in Tier 4: cap target FPS at 60 to prevent thermal throttling, use 0.55x 3D scale on 3K+ displays (~1760x1175 ~ 1080p equivalent) while keeping the 2D HUD at native resolution, use 1-cascade orthogonal shadow (`SHADOW_ORTHOGONAL`) with 35m range, 550m view distance, 220m simulation distance, and 28 actors. Frame time drops from 57ms down to 6ms-8ms (locked 60 FPS).
- **Check:** `tests/device_performance_manager_regression.gd`, `tests/movement_regression.gd`, and live `dumpsys gfxinfo com.manaooru.prototype` on Xiaomi Pad 7 showing 6ms 50th percentile / 8ms 90th percentile.

### Godot iOS export preset and iPhone multi-orientation support (2026-10-30)
- **Symptom:** Mana Ooru lacked an iOS export pipeline; attempting to build for iPhone failed with missing export preset and Xcode configuration errors, while mouse capture on mobile disrupted touchscreen input.
- **Cause:** `export_presets.cfg` only defined `preset.0` (Android). In addition, `main.gd` exclusively checked `OS.has_feature("android")` for bypassing mouse capture, leaving iOS falling through to desktop captured mouse mode. Furthermore, `window/handheld/orientation` was fixed at 0 (Landscape Left only), which prevented 180° rotation on iPhones with charging cables plugged in.
- **Rule:** When configuring iOS export in Godot:
  1. Add an iOS export preset with `application/targeted_device_family=2` (iPhone & iPad universal, mapping to `TARGETED_DEVICE_FAMILY = "1,2"` in Xcode).
  2. Set `application/export_project_only=true` so the headless export writes a complete Xcode project (`ManaOoru.xcodeproj`) and data pack (`ManaOoru.pck`) that can be opened or built via Xcode or CI/CD without hardcoded developer team credentials.
  3. Ensure `window/handheld/orientation=4` (Sensor Landscape) in `project.godot` so `UISupportedInterfaceOrientations` includes both `UIInterfaceOrientationLandscapeLeft` and `UIInterfaceOrientationLandscapeRight`.
  4. Always check `OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")` when configuring mouse mode, HUD touch overlays, and platform performance tiers.
- **Check:** `tools/build_ios.sh` and headless export `godot --headless --export-debug "iOS" builds/ios/ManaOoru.ipa` followed by `grep TARGETED_DEVICE_FAMILY builds/ios/ManaOoru.xcodeproj/project.pbxproj`.

### Hardware-aware device tier classification & settings persistence (2026-10-30)
- **Symptom:** Different mobile devices and tablets either stuttered or overheated when running uniform graphics presets without hardware inspection.
- **Cause:** GPU, CPU cores, RAM, and screen refresh rate were not inspected at boot to choose appropriate viewport scaling, shadow cascades, and frame rates.
- **Rule:** Use `DevicePerformanceManager` at boot to classify into Tier 1 (Budget Mobile 30 FPS, 0.65x scale, no shadows), Tier 2 (Mid-Range 60 FPS, 0.80x scale, 1-cascade 35m shadow), Tier 3 (Flagship Killer 90 FPS, 0.85x scale), and Tier 4 (Pro Tablet/Desktop, 0.75x scale on 3K+ tablets to prevent throttling, 1.0x native on PC/Mac, with tablet ergonomics insetting HUD on 4:3 and 16:10 screens). Persist device profiles to `user://settings.cfg`.
- **Check:** `tests/device_performance_manager_regression.gd`, `tests/scene_regression.gd`, and `tests/performance_integration_regression.gd`.

### Tuk-tuk driver test checks a hidden rig (2026-10-29, open)
- **Symptom:** `tuk_tuk_driver_pose_regression` fails ("Driver wrist must contact its handlebar grip").
- **Cause:** written on 2026-10-27 for the old `DEF-` rig (`character.skeleton`). Since Rahul became the default,
  that rig is hidden and the visible one is `male_skeleton`. On the visible rig the hands sit 2.8 cm from the
  grips at rest, but one hand trails by 7 cm on full steering lock.
- **Rule:** a character test must measure the rig that is actually visible
  (`male_skeleton` when `male_model.visible`). When the default character changes, update its tests too.
- **To do:** move the test to the visible rig and fix the 7 cm lag on full lock.

### White renders were a real bug, not the capture (2026-10-29)
- Over-exposed test renders were dismissed as a capture problem; it was the bridge's Blender lamps lighting the
  whole world. **Rule:** when a render looks wrong, find out why before moving on.

### Another session edited the same files (2026-10-29)
- Two Claude sessions worked in ManaOoru at once (player v2 swap and the AK-47).
- **Rule:** back up or diff the files you will change, and check they are unchanged just before writing; merge by
  hand if not. Never overwrite someone else's change with an older copy.

### Settings navigation and live-match input (2026-10-31)
- A settings close may fail to save: callbacks must check panel.visible before opening missions or changing maps.
- Live multiplayer deliberately does not pause SceneTree. Include visible settings in the shared input gate so movement, gyro and firing stop locally while the match continues.
- Numeric slider labels need explicit refresh when a restored value equals the initial minimum; value_changed otherwise does not fire.
- Capture helpers should call settings navigation instead of traversing fixed parent chains.
