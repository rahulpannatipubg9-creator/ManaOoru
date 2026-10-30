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

### A real click reached a capture window (2026-10-30)
- **Symptom:** `credits_mid.png` from `tests/capture_front_door.gd --screens` showed the loading screen, and Godot
  segfaulted on exit.
- **Cause:** most likely a real mouse click on the window. A traced rerun logged real clicks and wheel events
  reaching `title_screen.gd`, though that rerun did not start loading. The segfault was not reproduced; it fits
  `quit()` during the threaded load.
- **Rule:** when a windowed capture shows an impossible state, log its input before blaming the UI. Don't use the
  mouse over capture windows.
- **Check:** view the PNGs; `credits_mid.png` must show credits.

### A check ran one frame after the state it guards (2026-10-30)
- **Symptom:** `front_door_regression` failed "the player must not fall" although the player had not fallen.
- **Cause:** the `while world.building` loop checks after its `await`, and by the last pass `main.gd` had rightly
  moved the player to the spawn.
- **Rule:** after an `await` in a polling loop, test the loop's condition again before asserting.
- **Check:** `tests/front_door_regression.gd`.

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
