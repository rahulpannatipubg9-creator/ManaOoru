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

### Camera look-behind and input processing blocked during active camera transitions (2026-10-31)
- **Symptom:** `camera_regression` failed with `C must look behind the person`. In first-person or third-person on-foot mode, pressing C or look inputs failed to respond immediately upon entering the scene or changing perspectives.
- **Cause:** `camera_controller.gd` `_process()` aborted early when `not _camera.current`. During `main.gd`'s smooth perspective transitions (0.4s duration), `_transition_camera.current` was true, causing the active player's camera controller to ignore `Input.is_action_pressed("camera_look_behind")`.
- **Rule:** In `camera_controller.gd`, treat the camera as active if `_camera.current` is true OR if its parent node possesses `input_authority == true`.
- **Check:** `tests/camera_regression.gd`.

### Character physics slope duration calibrated for realistic walk speed (2026-10-31)
- **Symptom:** `character_physics_regression` failed with `Character must walk up a 15% ramp (reached 1.9 m)`.
- **Cause:** When `walk_speed` was calibrated down from 4.2 m/s to 2.4 m/s for authentic Mixamo walking animation timing, the slope traversal test was still running for only 420 frames (7.0s = 16.8m travel), leaving the player short of the 24m mark needed to reach 3.0m elevation.
- **Rule:** Synchronize test frame counts with calibrated gait speeds. At 2.4 m/s, climbing 24m up the 15% ramp requires 650 frames (~10.8s).
- **Check:** `tests/character_physics_regression.gd`.

### Default walk speed must stay below the jog threshold to trigger Walk_Loop on W (2026-10-31)
- **Symptom:** Pressing W alone immediately played the Jogging animation rather than the walking loop, making normal on-foot traversal appear hurried.
- **Cause:** `person_controller.gd` exported `walk_speed: float = 4.2`, which exceeded `test_character.gd`'s standing jog threshold of $2.8$ m/s (`if speed > 2.8: Jogging else: Walk_Loop`).
- **Rule:** Keep `walk_speed` at $2.4$ m/s ($8.6$ km/h brisk walk) and `run_speed` at $6.8$ m/s ($24.5$ km/h sprint/jog). Walking on `W` cleanly stays below $2.8$ m/s to play `Walk_Loop`, while `Shift + W` accelerates to $6.8$ m/s to trigger `Jogging`.
- **Check:** `tests/movement_regression.gd`, `tests/character_stance_reactions_regression.gd`.

### Mixamo weapon holding without finger curl left open-palm grip (2026-10-31)
- **Symptom:** When holding rifles on Mixamo rigs, character hands reached the grip targets but fingers stayed extended, looking unattached to the trigger and handguard.
- **Cause:** `_orient_mixamo_hand()` oriented the wrist bone but had no procedural finger pose logic for `mixamorig_*HandIndex/Middle/Ring/Pinky/Thumb` joints.
- **Rule:** When equipping firearms on Mixamo rigs, apply local rotation curls to finger joints (trigger finger index slightly relaxed at 0.45, grip fingers at 0.75-0.95, and thumb wrapped).
- **Check:** `tests/mixamo_contacts_regression.gd`, `tests/test_godavarikhani_living_district.gd`.

### Mixamo action-blending non-hip bone translation tracks explode skeleton bounds (2026-10-31)
- **Symptom:** `mixamo_gameplay_regression` failed with `reload preserves low stance instead of standing up (bounds.size.y = 1.541m >= 1.5m)`. Character meshes exploded into dozens of meters when playing action clips (e.g. Reload, Melee) during crouch or prone stances.
- **Cause:** Mixamo FBX animations store non-zero translation tracks on non-hip bones in source centimeters (~48 cm). When `set_bone_pose_position` was applied to limb and spine bones during action blending in `test_character.gd`, the centimeter translation offsets were written into meter-scaled bones, throwing vertices outward.
- **Rule:** In Mixamo skeletons, translation tracks must be applied strictly and exclusively to `mixamorig_Hips`. All other bones (`Spine`, `Spine1`, `Spine2`, `UpLeg`, `Leg`, `Foot`, `Arm`, `Hand`) must only receive rotation tracks.
- **Check:** `tests/mixamo_gameplay_regression.gd`, `tests/mixamo_contacts_regression.gd`.

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

### Animation LOD and Mobile Bone Limits (2026-10-30)
- **Symptom:** High bone counts and full 60 FPS blend tree updates on multiple pedestrians, dummies and puppets caused vertex skinning bottlenecks on mobile GPUs (Vulkan/OpenGL ES 3.0).
- **Rule:** Keep mobile character rigs under 45–50 bones for seamless compatibility with mobile OpenGL/Vulkan skinning limits (preventing uniform buffer overflow). Update character skeletons at full 60 FPS up close (0–15m), but throttle distant pedestrians, bots and puppets to 15–30 FPS animation ticks (30 FPS at 15–35m, 15 FPS beyond 35m).
- **Check:** `movement_regression.gd`, verify animation fidelity up close and tick throttling in distant views.

### Default Mixamo height must be measured after axis correction (2026-10-31)
- **Symptom:** The new default looked too tall beside vehicles and the world.
- **Cause:** The Mixamo visual used a hard-coded 100x import multiplier instead of a measured game height.
- **Rule:** Fit the rotated upright bounds to DEFAULT_MIXAMO_HEIGHT (1.73m), retain a ground offset through reset, and match standing collision height. Preserve the other selectable models and animation clips.
- **Check:** character_scale_regression verifies measured height, soles at the player origin, and matching standing collision height.

### Mixamo skin bounds caused a giant sideways avatar (2026-10-31)
- **Cause:** Static mesh AABBs inherited the armature's 0.01 scale but omitted skin bind matrices that restore metre-sized vertices. Fitting those bounds multiplied the character by about 100; an extra axis correction also tipped it sideways.
- **Rule:** Keep the imported Y-up root rotation at zero. Fit skinned vertices using bone poses and inverse binds, once at startup. Never infer skin size from static mesh AABBs alone.
- **Check:** character_scale_regression measures actual skinned geometry at 1.73m and samples idle, walking, jogging and seated animation frames for size explosions.

### Audit the active Mixamo library, not the hidden legacy skeleton (2026-10-31)
- **Symptoms:** walk-start and cover-entry transitions looped; large source root travel escaped the collider; the standing grenade selected a prone throw; long actions were cut at 1.2s; deaths restarted; reload/fire had no selection. Seated poses lost wheel/peg contacts, and rifle sights sat above the eyes.
- **Fix:** build private runtime clip copies in `mixamo_animation_library.gd`, keep physics responsible for horizontal travel, close genuine loop seams, derive steady idle/walk/driver clips, preserve low stances during actions, time actions from clip/gameplay duration, and solve the active Mixamo rig after `mixer_applied`. Use its own shoulder height and prone reach in local and remote rifle presentation; test crawling and directional weapon clips as well as rifle idle. Source FBXs and GLB remain unchanged.
- **Rule:** check every source clip, every state selection and crossfade, then inspect rendered poses with props. Static bounds and hidden-rig tests cannot validate the visible skinned player. Grounding corrections belong to the source model/height and must be rebuilt when those change.
- **Check:** `mixamo_animation_audit`, `mixamo_gameplay_regression`, `mixamo_contacts_regression`, `character_scale_regression`, and the corrected visible-rig vehicle/character tests. Render all clips with `capture_mixamo_animations` and prop poses with `capture_mixamo_gameplay`. Full findings: `docs/MIXAMO_ANIMATION_AUDIT.md`.

### Virat uses the gameplay skeleton (2026-11-01)
- **Symptom:** Downloaded Virat uses unprefixed bone names and UUID animation names, incompatible with named gameplay clips.
- **Cause:** Imported skin and animation naming differ from the established Mixamo rig.
- **Rule:** Fit the skin through weighted bind-space transforms to the gameplay rig and preserve its named animation library; never substitute a GLB path without checking crouch, prone, weapon and vehicle poses. See characters/VIRAT.md.
- **Check:** Character regressions and Virat gameplay captures.

### Virat vertex colours require the albedo switch (2026-11-01)
- **Symptom:** The coloured GLB had a valid COLOR_0 stream but rendered white in Godot.
- **Cause:** Imported StandardMaterial3D.vertex_color_use_as_albedo was false.
- **Rule:** Duplicate Virat's material and explicitly enable vertex colours; verify the rendered face and clothing, not just the GLB attribute list.
- **Check:** tests/capture_virat_portraits.gd and test_character_regression.gd.
