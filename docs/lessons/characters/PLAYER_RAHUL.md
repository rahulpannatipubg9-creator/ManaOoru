# Player character: Rahul

The player's own likeness, used for the local player and every remote player.

| | |
|---|---|
| Model | `assets/models/characters/rahul/rahul.glb` (`MALE_MODEL_PATH` in `test_character.gd`), every clip inside it; body = Hyper3D Rodin scan since 2026-10-29 (`18_rodin_body.py`) |
| Source and pipeline | `tools/rahul_character/` (README): from scratch, `15_rifle.py` AK-47 set, `17_game_clips.py` game clips, `11_export.py` |
| Height | 1.77 m to the top of the hair, true scale (no fitting); soles at y = 0 |
| Rig | CC deformation skeleton (`CC_Base_*` bones) + `Weapon_R` socket, **rest pose A-pose** |
| Forward | +z in the character's space; +x is the character's left |
| Clips the game samples | `IDLE_Natural`, `WALK_Realistic` 1.17, `WALK_Brisk` 2.0, `JOG_Realistic` 4.2, `SPRINT_Realistic` 7.0, `CROUCH_Idle`, `CROUCH_Walk` 2.1 m/s; rifle `Rifle_Idle`, `Rifle_Jog_InPlace`, `Rifle_Sprint_InPlace`, `Rifle_ADS_Idle`, `Rifle_Peek_Left/Right`, `Rifle_Jump` |

Useful bones: `CC_Base_Hip` (pelvis), `CC_Base_Head`, `CC_Base_{L,R}_{Thigh,Calf,Foot}`,
`CC_Base_{L,R}_{Upperarm,Forearm,Hand}`, `CC_Base_Waist`, `CC_Base_Spine01/02`, `CC_Base_NeckTwist01/02`,
fingers `CC_Base_{L,R}_{Index,Mid,Ring,Pinky,Thumb}{1,2,3}`.

Rahul replaced player v2 as the default (local and remote players) on 2026-10-29. v2's files stay on disk
(`player_v2_rigged.glb`, `player_v2_animations.glb`) but nothing loads them. Clips stepped by stride are
exported one frame past the cycle (the game reads the last frame as a repeat of the first). With a rifle out the
Rifle_* clips set the body and the game still solves the arms onto its own rifle (`_pose_armed`); the
`Weapon_R` socket is not used by the game (its rifle is placed by `person_controller.gd`). Check:
`rahul_rifle_stance_regression`, `character_clip_library_regression`, `tools/captures/capture_rahul_ingame.gd`.

## Entries

### Scan hair showed specks of what was behind the head (2026-10-29)
- **Symptom:** light specks across the curly hair, and dark dots on the nose and ears, in the in-game
  captures.
- **Cause:** the glTF stores a separate vertex on each side of every UV seam, so the scan arrived as islands
  (163,576 open edges). Decimating each island on its own pulled the seams apart into cracks.
  - The first two attempts treated symptoms: a roughness floor and a double-sided material.
  - An enlarged crop showed the wall behind the head in the specks.
- **Rule:** weld a glTF scan (`remove_doubles` 1e-5; UVs stay per corner) before decimating it
  (`18_rodin_body.py` `weld()`). To diagnose specks, enlarge the capture and check their colour: the
  background colour means a hole. The roughness floor and double-sided material are kept.
  (corrected 2026-10-29)
- **Check:** the `WELD open edges … -> 0` line from the build; `unarmed_standing.png` enlarged around the head.

### Swapping in a scanned body: keep the skeleton, move the mesh to it (2026-10-29)
- **Context:** the Hyper3D Rodin scan came with its own rig: Mixamo bone names, arms hanging about 70°,
  shoulders about 10 cm lower than CC.
- **Trap:** two easy routes both break the game.
  - Exporting the scan with its own rig breaks every `CC_Base_*` lookup in `test_character.gd` and
    `network_player.gd`.
  - Keeping the CC skeleton without re-posing the mesh breaks the clips. They store local rotations
    against the CC rest, so every arm pose would be off by about 40°.
- **Rule:** bring the mesh to the skeleton (`18_rodin_body.py`):
  - Pose the scan's rig onto the CC rest directions and bake that pose into the mesh.
  - Rename the weights to CC bones.
  - Move the CC joints to the scan's joints with their orientations unchanged.
  - Re-export from Blender so the clips' position tracks follow the new joint offsets. Godot clips carry a
    position track for every bone, so moving bones in Godot alone would snap back.
- **Check:** `character_clip_library_regression`, `rahul_rifle_stance_regression`,
  `character_arm_hang_regression`, `vehicle_entry_regression`, `tdm_remote_character_regression`;
  renders of idle, sprint, crouch walk, deep squat, arms up, ADS and rifle sprint.

### Rifle stance turned 52 degrees off the aim: two blades stacked (2026-10-29)
- **Symptom:** in the first in-game captures the chest and head faced well to the right of the rifle.
- **Cause:** the Rifle_* clips blade the chest (about 20 degrees) and `_pose_armed()` then added its full
  procedural blade (`BLADE_*`, about 29 degrees) on top.
- **Rule:** when a clip already does part of a procedural correction, keep only the share still needed and
  measure it: here the left hand's reach. `RIFLE_CLIP_BLADE` 0.35 keeps the left hand within 2.5 cm in the
  sprint carry with the chest at about 33 degrees; outside combat mode (body not facing the aim) the full turn.
- **Check:** `rahul_rifle_stance_regression` (grip gaps standing, peeking, jogging, sprinting, exploration,
  remote aiming).

### Clip pelvis motion wiped by the heading twist reset (2026-10-29)
- **Cause:** `_apply_heading()` put `CC_Base_Hip` back to rest after the clips, written when no clip turned
  the hip. Rahul's clips do (pelvis yaw and the rifle stance's turn).
- **Rule:** reset a bone that procedural code builds on before the clips are applied, not after
  (`_pose_static_male()` now resets the hip first).

### Rebuild: unarmed clips exported with the arms locked onto an invisible rifle (2026-10-29)
- **Symptom:** after the rifle set was added, Idle / Walk / Run / DeformTest held both hands up at chest height.
- **Cause:** `15_rifle.py` set the Rigify `IK_FK` switch to IK on the rig itself; a rig property is not part of any
  clip unless keyed, so every clip baked with the arms in IK on the rifle.
- **Rule:** key the IK/FK switches (and any other mode property) inside every action (`key_arm_mode`), never only
  on the rig.
- **Check:** `12_validate.py` `hand_above_hip_m_frame0` (about 0 for Idle / DeformTest); renders of Idle and Walk.

### Rebuild: rifle socket in the wrong axes, and ADS aimed 20 degrees off (2026-10-29)
- **Symptom:** (found by review) `ak47.glb` parented to `Weapon_R` would have pointed along the wrong axis; ADS and
  peek clips aimed 10-20 degrees right of where the body faced; the stock sat in the neck.
- **Cause:** the socket copied the `gun` control (bone Y = barrel) while the model's barrel is glTF +Z; the rifle
  inherited the chest's bladed yaw; the ADS stance was 6 cm off centre instead of in the shoulder pocket.
- **Rule:** build a socket in the attached model's own axes (here bone Y = up, Z = barrel); take only the chest's
  position, pitch and roll for a held rifle, not its yaw; measure the stock end against the shoulder pocket.
- **Check:** `12_validate.py` `aim_yaw_max_deg` (<= 2.5 for ADS / peek); `renders/godot_ak_socket.png` (Godot,
  identity-parented AK in both hands).

### Rebuild: dark flecks on the face from the beard shell (2026-10-29)
- **Symptom:** small black triangles on the cheeks, nose sides and neck in close-ups (not in the photo-camera renders).
- **Cause:** `tools/rahul_character/scripts/05_build.py` cut the beard shell's alpha from raw photo darkness, so
  pores and crease shadows became isolated opaque faces 2-5 mm proud of the skin.
- **Rule:** build a beard (or any alpha shell) from a heavily smoothed, continuous coverage zone; drop faces
  outside it and islands under 25 faces; put fine detail in the alpha pattern, not in the face set.
- **Check:** render the face close up from an oblique angle with the shell on and off (`_speck_*` renders).

### Rebuild: hair cap read as a black slab (2026-10-29)
- **Symptom:** a flat black block on top of the head behind the quiff.
- **Cause:** a plain near-black opaque cap standing 50-80 % of the hair depth, with cards that did not cover it.
- **Rule:** texture the cap with the hair projected from the references (it keeps the head UVs) and lay cards on
  its surface; check front, three-quarter and profile against the sheet.
- **Check:** `renders/compare_sheet_*.png` overlays.

### Rebuild: clips imported non-looping in Godot (2026-10-29)
- **Cause:** plain clip names; Godot only loops glTF animations named `*_Cycle` (it strips the suffix).
- **Rule:** export looping clips as `<Name>_Cycle` (`11_export.py` `LOOPING`), or set loop in the importer.
- **Check:** `export/godot_engine_report.json` shows `loop` true for Idle / Walk_InPlace / Run_InPlace.

### Driving pose broken after the switch to v2 (2026-10-29)
- **Symptom:** arm out of the car window, legs through the floor (see [../CHARACTERS.md](../CHARACTERS.md)).
- **Cause:** fixed-angle driving pose on a T-pose rig; it was never checked seated when the model changed.
- **Rule:** after any change to this model or its rig, render it seated in the Thar and the Porsche and armed
  with both rifles, not only walking.
- **Check:** hands at the wheel (about 0.4 m above and ahead of the hips), feet at the pedals.

### Swapped in while another session was working on the game (2026-10-29)
- The v2 swap landed in `test_character.gd` while the AK-47 work was editing the same file. Edits were merged by
  hand. Rule: check a file's state just before writing to it; see [../TESTING_AND_TOOLS.md](../TESTING_AND_TOOLS.md).
