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

`tools/run_tests.sh [timeout] [filter]` runs every `tests/*_regression.gd` and prints a table. Set `GODOT` to the
binary, or `GODOT_RUNNER` to a wrapper such as `run_godot.sh`. Scripts that only take pictures or inspect a model live
in `tools/captures/`.

## Entries

### Line endings: `.gitattributes` added, repo not renormalised (2026-10-30)
- **Symptom:** a Windows checkout with `core.autocrlf=true` turns about 890 text files to CRLF; Mac and Windows fight.
- **Cause:** nothing in the repo set a line-ending rule.
- **Rule:** `* text=auto eol=lf`, plus `binary` for images, audio, models and fonts. Every new checkout gets LF. Do not
  mix `git add --renormalize .` into a feature branch.
- **To do:** after the UI branches merge, run `git add --renormalize .` alone in one commit. Only
  `assets/models/indian_water_tank/source/tank.mtl` and `tank.obj` should change: they are the only text files stored
  with CRLF. Existing clones convert a file when it is next touched; a fresh clone is cleanest.
- **Check:** `git ls-files --eol | grep i/crlf` prints nothing.

### Every shot allocated a mesh and a material (2026-10-30)
- **Symptom:** sustained fire built new resources for each tracer and flash (BUGS 25).
- **Cause:** a tracer's length was baked into its `CylinderMesh`.
- **Rule:** `_tracer` shares a 1 m mesh and scales `axes.y`, the column of the basis. `Basis.scaled()` would scale
  along the world axis instead, so an angled shot would shear.
- **Check:** `save_and_feedback_regression` measures the length, centre and direction of a pooled tracer.

### A nested signal reaches later listeners out of order (2026-10-30)
- **Symptom:** after armour absorbed a hit, a listener connected after `city_gameplay` would see the true health and
  then the lower value (BUGS 18).
- **Cause:** emitting `health_changed` inside its own handler delivers the new value first; the outer emit then goes
  on to the remaining listeners with the old one.
- **Rule:** when a handler corrects a signal's value, re-emit with `call_deferred`.
- **Check:** `save_and_feedback_regression`, which listens after `city_gameplay` does.

### Saves: keep what you cannot read (2026-10-30)
- **Symptom:** a corrupt save, or one from a newer build, started a new game and the next autosave destroyed it
  (BUGS 19). Android lost up to 30 s because it rarely sends a close request (BUGS 17).
- **Cause:** `load_progress` treated "unreadable" as "no save". `main._notification` only knew the desktop close.
- **Rule:** `save_progress` copies the old save to `.bak`. An unreadable save moves to `.rejected`, and the `.bak` is
  restored to `save_path`, because `city_gameplay` reads that file itself. When `SAVE_VERSION` rises, add the
  migration to `_read_save` and make `city_gameplay` read through it too.
- **Check:** `save_and_feedback_regression`.
### Feel checks that counted frames failed on a busy machine (2026-10-30)
- **Symptom:** `feel_regression` passed or failed on ADS, landing and reload depending on what else was running.
- **Cause:** waiting a number of `process_frame`s assumed 60 fps. Headless draws faster when idle and slower under load.
- **Rule:** wait `physics_frame`s for a fixed time, or measure real seconds and metres per second.
- **Check:** `feel_regression` while another worker runs Godot.
### A test printed PASS over a script error (2026-10-30)
- **Symptom:** `pause_menu_regression` and `environment_modes_regression` printed PASS and exited 0, and the same
  output held `Invalid access to property or key 'city_life'`.
- **Cause:** `main._handle_menu_input` calls `pause_menu.owns_keys()` before the menu's first `_process` had set
  `_game` (`scripts/ui/pause_menu.gd`). The menu's touch-bridge wiring also waited for the first `open_menu()`, so
  Settings opened directly over a live match got no touch.
- **Rule:** anything another node may call checks its own setup first, and setup must not wait for one particular
  screen to open. Read test output for `SCRIPT ERROR`: an exit code or a PASS line does not rule it out.
- **Check:** `tests/pause_menu_regression.gd` asserts the bridge is wired before the first open; its output must hold
  no `SCRIPT ERROR`.

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
