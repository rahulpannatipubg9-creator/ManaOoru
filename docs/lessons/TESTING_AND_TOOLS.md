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

### A test can print PASS after a script error (2026-10-30)
- **Symptom:** `hud_states_regression` and `hud_layout_profiles_regression` printed PASS and exited 0 while most of a
  test function never ran.
- **Cause:** a SCRIPT ERROR aborts only the current GDScript function; the caller carries on to its PASS line. Here it
  was assigning an untyped array to an `Array[int]` stub (`_play.owned = [0, 1]`) and a removed `PeekLeft` slot.
- **Rule:** read test output for SCRIPT ERROR, never only the last line. Fill typed arrays with `.assign()`.
- **Check:** `grep -E "SCRIPT ERROR|^FAIL|^PASS"` on the output of each run.

### Compass letters drawn as blocks (2026-10-30)
- **Symptom:** in `capture_hud` the desktop compass showed pale blocks instead of NW and NE.
- **Likely cause:** `hud_compass.gd` `_draw` only ran when the heading moved, and recorded `draw_string` glyphs seem to
  go stale when the font atlas grows. Not proven by isolating the atlas; the capture is the evidence.
- **Rule:** custom `_draw` text must redraw from time to time; prefer a Label where one will do.
- **Check:** `hud_states_regression` (periodic redraw) and `tests/capture_hud.gd`, desktop shots.

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
