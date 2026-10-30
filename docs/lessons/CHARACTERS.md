# Characters: lessons

Applies to every rigged character: the player, remote players, pedestrians and test models. Per-character
notes are in [characters/](characters/). Code: `scripts/player/test_character.gd` (all posing),
`scripts/player/person_controller.gd` (the body that moves).

## Before you change a character or swap in a new model

1. Read the character's own file in `characters/`.
2. Check every pose, not just walking: idle, walk/jog/sprint, crouch, prone, **seated in each car type**,
   **armed (both rifles)**, hit and death. A model swap breaks the poses you did not look at.
3. Run `vehicle_entry_regression`, `movement_regression`, `test_character_regression`,
   `character_stance_reactions_regression`, `character_arm_hang_regression`, `weapon_switch_regression`.
4. Render it in the game (see [TESTING_AND_TOOLS.md](TESTING_AND_TOOLS.md)) and look at the pictures.

## Entries

### Lean and open hands carried into the driver's seat (2026-10-30)
- **Symptom:** a lean held while the player boarded stayed on the driver for the whole drive, and Rahul's fingers
  stayed open on handlebars.
- **Cause:** `person_controller.gd` stops updating `peek_input` during a scripted move, and `_pose_static_male`
  returns early when seated, so `male_model.rotation` kept its last value. `_pose_male_driving` only curled the
  fingers on the fallback wheel, not on vehicle grips.
- **Rule:** anything a pose function sets every frame must be reset on the path that returns early.
- **Check:** `save_and_feedback_regression` covers the lean. The fingers have no test, so look at a render.

### Crouch refused under a low ceiling: the headroom query hit the floor (2026-10-29)
- **Symptom:** `character_physics_regression` failed "Crouch must shrink the collider". A player squeezed
  under a low roof could not crouch out of it.
- **Cause:** `person_controller.gd` `_update_stance()` asked `_has_headroom(crouch_height)` before every
  crouch. A standing capsule under a 1.4 m ceiling is pushed about 15 cm into the floor, so the query, which
  starts 2 cm above the body origin, hit the ground.
- **Rule:** check headroom only when the capsule grows (stand up, prone → crouch). Shrinking is always allowed.
- **Check:** `character_physics_regression` (crouch headroom), `character_stance_reactions_regression`.

### Peek leaned the wrong way: Q tipped the body right (2026-10-29)
- **Symptom:** Q / "< PEEK" (peek -1) slid the third-person camera 0.45 m to the screen's right and tipped the
  body to the character's right, while the camera roll went left. BGMI leans left on Q.
- **Cause:** sign errors where peek becomes motion: `camera_controller.gd` (`peek_lateral`), the whole-model
  roll in `test_character.gd`, the block figure in `person_controller.gd`, the capsules in `network_player.gd`.
  Nothing measured the direction, only that a lean happened.
- **Rule:** peek -1 is left. A roll of `peek * 0.28` about +z (forward) tips toward +x, the character's left;
  the camera slides by `-peek * 0.45` along its x. Test a direction by measuring it (head and camera along the
  camera's screen-right axis), never only that something moved.
- **Check:** `rahul_rifle_stance_regression` (Q: head, camera slide and roll all to the left).

### Seated driver: arms out of the windows, feet through the floor (2026-10-29)
- **Symptom:** in the Porsche the player sat with an arm hanging out of the window and the body half outside;
  in every car the legs dangled instead of reaching the pedals.
- **Cause:** `_pose_male_driving()` swung the arms about the character's x axis. The CC rig rests in a
  **T-pose**, so the arm already lies along x and that rotation only twisted it: the arms stayed straight out
  sideways (hands 1.3 m apart). The legs used fixed angles (thigh -1.05, calf 1.25), which left the feet
  0.3–0.5 m short of the pedals and, in the low Porsche (seat 0.46 m), under the car's floor.
- **Rule:** never pose a limb with fixed angles about a world/character axis. Solve it to a target: legs to
  `foot_target` (the pedals from `vehicle_entry.gd`), hands to the wheel (`_solve_male_limb()` and
  `_pose_vehicle_grips()`). For a T-pose rig, an arm swing must aim the bone, not rotate about x.
- **Check:** probe hands and feet in the car's space after getting in (hands within the cabin, feet at the
  pedal ± 2 cm); render the driver from the side and front in the Thar and the Porsche;
  `vehicle_entry_regression`.

### The same T-pose trap on foot (before 2026-10-29)
- **Symptom:** arms stayed horizontal while walking.
- **Cause:** swinging T-pose arms about their rest axis.
- **Rule:** aim the arms down from the shoulder first, then swing (see the comment in `_pose_static_male()`).

### Prone never lay down (2026-10-29)
- **Symptom:** the realistic character only leaned a little when prone.
- **Cause:** the prone tilt was blended a little each frame from an upright reset, so it never accumulated.
- **Rule:** blend toward a target from the current value kept between frames (`_prone`), never from a value
  reset every frame.
- **Check:** `character_stance_reactions_regression`.

### Walk and run looked like a half squat (2026-10-29)
- **Symptom:** bent legs and sliding feet at walking and running speed.
- **Cause:** the walk clip was authored for about 1.2 m/s and the run for 3.3 m/s, but the game moves at
  4.2 and 7.0 m/s. A planted foot must move back at the body's speed.
- **Rule:** author gait clips for the speeds the game uses (stride × 30 / frames = speed;
  `tools/character_animation/locomotion.py`) and blend by speed. Changing `walk_speed`/`run_speed` means new clips.

### Model tipped head-down after import (before 2026-10-29)
- **Cause:** the glTF importer already converts to Y-up; the code rotated it again.
- **Rule:** keep an imported model's rotation at zero. Never "fix" axes twice.

### Feet below or above the ground (before 2026-10-29)
- **Cause:** a hard-coded ground offset (the old model's origin was 18 cm below its soles).
- **Rule:** compute the offset from the model's bounds (`-bounds.position.y`), and keep the soles at y = 0 in
  the export. Do not fit height to the bounds when the bounds include hair.

### Left hand could not reach the rifle's handguard (2026-10-29)
- **Cause:** the arms alone are about 9 cm too short at the ready position.
- **Rule:** turn the chest so the left shoulder comes forward (`_pose_armed()`), then solve the arm.
