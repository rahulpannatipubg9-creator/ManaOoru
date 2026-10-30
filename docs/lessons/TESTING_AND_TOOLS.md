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
