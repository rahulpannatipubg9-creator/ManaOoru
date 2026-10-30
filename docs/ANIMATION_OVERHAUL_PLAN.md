# MANA OORU — Character animation overhaul (plan)

Status: **plan only, nothing built.** Written 2026-10-29 after the first Team Deathmatch playtest feedback:
the gun hold, the walk and run, the aiming pose and the movement controls all feel bad, on every character.
Owner choices so far: full overhaul; motion generated in Blender (extending `tools/character_animation/`);
the full plan is reviewed before any building starts.

## 1. What exists today (checked in the code)

| Piece | State |
|---|---|
| Walk, run, idle, transitions for Rahul (CC_Base rig) | Authored in `tools/character_animation/` with foot IK and heel/ball/toe roll, exported to `assets/models/characters/player_character_animations.glb` and played by `scripts/player/test_character.gd`. Unarmed only |
| Gun hold | None authored. `person_controller.gd` puts the rifle at a fixed offset (`weapon_hold_offset`) and `test_character.gd` points both hands at two grip targets with arm IK. No hold pose, no aim pose, no recoil, no reload motion |
| Crouch, prone, peek, jump | Procedural bone offsets in `test_character.gd`, not authored clips |
| Remote players in a match | `network_player.gd` draws a **capsule-and-sphere stand-in with a box rifle**, not a character. They do not walk or aim with a rig at all |
| Lady model | Desktop test model under `assets/test_only/`, **excluded from the APK** by `export_presets.cfg`. Different rig (DEF bones). Not on the tablet or phone |
| Legacy avatar | Block figure, no skeleton: cannot be bone-animated |
| Movement | `person_controller.gd`: walk 4.2, run 7.0 m/s, acceleration 18, stopping 28, crouch x0.5, prone x0.32. Same speed in every direction; the body faces the camera when armed |

So on the devices the real animated character is **Rahul only**; other players are capsules. Both
facts matter for the plan.

## 2. Targets

1. The rifle is held properly: two-handed at the chest while moving, raised to the shoulder when aiming,
   with recoil on each shot and a reload that matches the 2 s reload.
2. Walk and run look right in all four directions, with no foot sliding.
3. Crouch and prone move and aim convincingly.
4. Aiming up and down turns the upper body and the rifle, not just the camera.
5. Other players in a match are real characters with the same animation, not capsules.
6. Movement feels like a shooter: speed by direction, acceleration, turning, stopping.
7. Runs on the tablet and phone without a frame-rate loss we can measure.

## 3. Animation set to author (30 fps, all in `tools/character_animation/`)

Naming follows the existing master: `STATE_Action`, one NLA track each, previews rendered as MP4.

| Group | Clips | Notes |
|---|---|---|
| Rifle ready (hip) | `RIFLE_Idle`, `RIFLE_Walk_F/B/L/R`, `RIFLE_Run_F` | Rifle held two-handed at the chest. Diagonals blended in Godot from the four directions. Run is forward only, rifle lowered slightly |
| Rifle aim (shouldered) | `AIM_Idle`, `AIM_Walk_F/B/L/R` | Stock at the shoulder, head down the sight. Slower movement |
| Crouch | `CROUCH_Idle`, `CROUCH_Walk_F/B/L/R` | Rifle ready and aim share the legs |
| Prone | `PRONE_Idle`, `PRONE_Crawl_F/B/L/R` | Elbow crawl |
| Air | `JUMP_Start`, `JUMP_Air`, `JUMP_Land` | Rifle kept on the chest |
| Actions (upper body) | `FIRE_Kick`, `RELOAD` (2.0 s), `EQUIP` (0.35 s), `HIT_F/B/L/R`, `PEEK_L`, `PEEK_R` | Layered over the legs so they play while moving |
| Death | `DEATH_Forward`, `DEATH_Back` | One per direction the shot came from |

About 38 clips. Left and right sets are mirrors of one authored pair, which keeps the count and the work down.

**How it is authored:** the existing generator builds gait from curves and solves legs with IK. It is extended with:
- a rifle control bone (`CTRL_Rifle`) with a hip pose and a shoulder pose, blended by an `aim` property;
- arm IK from each hand to the rifle's foregrip and pistol grip, finger curls for the grip, and a small sway from breathing;
- a movement direction on the gait generator, so the same cycle can step forward, back and sideways with the hips and spine turned correctly;
- extra posture curves for crouch and prone.

`validation_report.json` already measures foot drift, ground penetration, knee flex and loop seams. It is extended
with hand-to-grip distance, rifle penetration into the body and loop checks for the new cycles.

## 4. How it plays in the game (Godot)

- A new `AnimationTree` on Rahul's skeleton: a state machine for stand, crouch, prone and air, with a 2D blend by
  local movement direction and speed, and a hip-to-aim blend. Playback speed follows ground speed so the feet match the floor.
- The action clips (fire, reload, equip, hit, peek) run on an upper-body filter, so a reload plays while walking.
- Aim pitch: spine and head bones are rotated by the camera pitch at runtime, so the rifle follows where you look.
- The old procedural posing stays as the fallback for the Lady and anything without the new clips.
- Remote players: `network_player.gd` swaps the capsules for the same rigged character with the same tree, fed by the
  state already sent over the network (position, yaw, aim pitch, stance, peek, armed, firing). Each player's team armband stays.
- Everything stays inside `scripts/player/` (animation driver) with no change to hit validation or the match rules.

## 5. Movement feel (done together with the animation)

- Speed by direction: backward and sideways slower than forward; crouch and prone speeds kept, sprint forward only.
- Acceleration and stopping tuned so animation and body stop together; no sliding when stopping.
- Body turns toward the aim direction with a short smoothed lag instead of snapping.
- Landing and jump timing matched to the new jump clips.
- Values stay in `person_controller.gd` as exported numbers so they can be tuned on the devices.
- Starting values are a guess, not a copy of any other game. Final numbers come from playtesting on the tablet and phone.

## 6. Characters

| Character | Plan |
|---|---|
| Rahul (CC_Base rig) | Primary. Everything above |
| Remote players | Use Rahul's model with team armbands (needs a decision: everyone looks the same) |
| Lady (desktop test only) | Optional last stage. Needs the same clip set rebuilt on the DEF rig; not on devices today |
| Legacy block avatar | Cannot be bone-animated. Leave as is, or hide it in matches (needs a decision) |

## 7. Stages (each ends with renders for review before the next starts)

| # | Deliverable | Done when |
|---|---|---|
| 1 | Rifle rig and ready-hold clips (`RIFLE_*`, `AIM_*`, `FIRE_Kick`, `RELOAD`, `EQUIP`) | Previews show a correct two-handed hold in idle, walk and aim; hands stay on the grips; no rifle clipping |
| 2 | Directional locomotion and the game-side `AnimationTree` for standing | In-game captures show forward, back and strafe walking and running without foot sliding; aim pitch follows the camera |
| 3 | Crouch, prone, jump | Same checks for each stance; stance changes blend cleanly |
| 4 | Hit, death, peek, transitions | Each plays from any state and returns to the correct one |
| 5 | Remote players use the character and animations | Two game windows: each shows the other as an animated rifleman |
| 6 | Movement feel tuning | Tested on the tablet and phone, numbers adjusted from your feedback |
| 7 | Lady on the DEF rig (optional) | Only if you still want it |

## 8. How it is checked

- Blender: the extended `validation_report.json`, plus side, front and three-quarter preview videos per clip (you
  check these in the live Blender viewport, as before).
- Godot: a headless test that loads the clips and the tree, checks clip names, lengths and loops and that every state
  can be reached; in-game captures of each state for the character; the existing movement, camera, weapon-presentation
  and TDM tests rerun after each stage.
- Device: frame rate and feel on the tablet and phone. These are only "tested" once measured there.

## 9. Risks

- **Hoodie and arms:** sleeves or the jacket may clip into the rifle in the shouldered pose; weights may need small fixes.
- **Foot sliding in blends:** diagonal blends of four directional cycles can slide; the speed-matching and a short blend time reduce it, but it needs checking per direction.
- **Mobile cost:** a blend tree on a high-poly rig costs CPU; it must be measured, and a lower-detail model or fewer bones may be needed on the phone.
- **Size:** the animation file grows from about 5 MB; a limit should be agreed.
- **Subjective result:** "looks good" is the owner's call; every stage is therefore reviewed before moving on.
- **Everyone looks the same in a match** (all use Rahul's model) until team outfits or more models exist.

## 10. Decisions (2026-10-29)

- **Other players:** everyone uses Rahul's model with a red or blue armband. (Owner confirmed.)
- **Phone model:** the phone may use a lower-detail model. (Owner confirmed.) Stage 5 and the device tests decide where the cut is.
- **Block avatar:** not answered; default is to hide it in matches.
- **Lady:** not answered; default is to skip it (stage 7 stays optional and unstarted).
- **Size limit:** not answered; no limit for now, size reported after each stage.

## 11. Original open questions

1. What other players look like in a match (Rahul's model with team armbands, or something else).
2. What happens to the legacy block avatar in a match.
3. Whether the Lady is worth rebuilding (desktop only).
4. A size limit for the animation file and whether the phone may use a lower-detail model.

## 12. Stage 1 progress (2026-10-29)

Built, and checked with close-up renders from the side, front, top and underneath
(`outputs/character_review/`, before: `00_before.png`, after: `00_c7_hands.png` and `00_c7_move.png`):

- **Loose parts hidden.** The M416 model has three loose accessory pieces (`M416_part_2` to `_4`) that floated
  below the rifle. Found by measuring each part. They are now hidden (`LOOSE_WEAPON_PARTS` in `person_controller.gd`).
- **Carry position.** In third person the rifle is carried against the body (chest ready, shouldered when aiming,
  lowered across the body while sprinting), with a recoil pitch and a reload tilt, instead of hanging off the camera.
- **Hands.** The right hand takes the pistol grip and the left cups the handguard. The hands are turned to wrap the grips
  and the fingers close around them (`_pose_armed` in `test_character.gd`).
- **Stance.** The chest turns toward the rifle side (about 29 degrees) with the head turned back to face forward. The arms
  alone are about 9 cm too short for the left hand to reach the handguard, so the shoulder has to come forward.
- **Approach change.** Stage 1 is done at runtime in Godot (rifle transform plus arm IK) rather than as baked Blender
  clips. It is faster to iterate with on-screen checks, costs less on the phone, and keeps the rifle following the camera.
  Blender-authored clips remain the plan for locomotion, stances and actions (stages 2 to 4).

**Found while checking, not yet fixed (stage 2):** in the side renders the legs of the walk and run look like a half
squat. Hip height drops only about 6 cm, so the cause is the stride and the leg pose, not a sunken body: the walk clip is
authored for about 1.2 m/s, but the player walks at 4.2 m/s and runs at 7 m/s, so the cadence and stride do not match the
speed. This needs gait clips authored for the speeds the game actually uses.

**Not done in stage 1:** the first-person view is unchanged; the aim pose seen by other players needs stage 5; the right
hand's fingers look open from some angles; walking and running with the new hold has not been looked at beyond four
still frames; nothing has been tested on a device.

## 13. Stage 2 progress (2026-10-29)

Done (walk and run matched to the game's speeds):
- **Cause confirmed.** The old walk clip was built for about 1.2 m/s and the run for 3.3 m/s, but the game moves at 4.2 and
  7.0 m/s (crouch 2.1). A planted foot has to move back under the body at the body's speed, so the feet slid and the
  legs were forced into a half-squat.
- **New gaits** in `tools/character_animation/locomotion.py`, each built so that stride x 30 / cycle frames equals its speed:
  `WALK_Brisk` 2.0 m/s (24 frames, 1.6 m stride), `JOG_Realistic` 4.2 m/s (20 frames, 2.8 m), `SPRINT_Realistic` 7.0 m/s
  (16 frames, 3.73 m). The Blender validation report shows foot drift under 0.1 mm, ground penetration about 1 mm, no
  knee crossing. Knee flexion peaks at 81, 129 and 152 degrees.
- **Game side** (`test_character.gd`): the four clips (`WALK_Realistic` 1.17, brisk 2.0, jog 4.2, sprint 7.0 m/s) are blended by
  speed, and the stride phase advances by speed divided by the blended stride, so feet stay planted. Moving backwards
  plays the cycle in reverse. The older walk/run pair stays as the fallback if a clip is missing.
- **Checked** with frame sequences in the game (`outputs/character_review/00_strip_game.png`) and Blender frame strips
  (`00_blender_jog.png`); a headless probe of one jog stance shows the planted ankle moving about 1 cm over 0.17 s while the
  body moves 0.7 m. A tidy ground-contact slide metric was not achieved (the first attempts were flawed and are not quoted).

Not done in stage 2:
- **Side-stepping.** Moving sideways still plays the forward gait. It needs cycles authored with a lateral step direction
  (a change to the gait generator's foot placement). Backward is only the forward cycle reversed.
- **Crouch and prone** still use the procedural pose (stage 3), so crouch-walking at 2.1 m/s is not using the brisk clip.
- Nothing has been tested on a device, and the installed APK still has the old animation.

## 14. Stage 5 progress (2026-10-29): remote players are the real character

- `network_player.gd` now builds the realistic character (same rig, gait clips, rifle hold and hand posing as the local
  player) instead of capsules. It offers the same queries the local person does (`velocity` from the synced movement,
  `crouching`, `prone`, `peek_input`, `is_weapon_equipped()`, `weapon`), so `test_character.gd` drives it unchanged. The
  desktop-only test model is skipped (`male_only`). The capsules remain as the fallback if the model file is missing.
- **Rifle:** the M416 with its loose parts hidden, carried at the chest from the synced facing and aim pitch, lowered while
  sprinting; the muzzle flash sits on its barrel.
- **Armband:** a cylinder on the left upper arm in the team colour, attached to the arm bone. **Spawn protection:** a soft
  cyan overlay on the character meshes. Both replace the capsule versions.
- **Phone cost:** a remote character only animates within 70 m of the camera. Whether a full match of seven rigs holds
  the frame rate on the phone has not been measured; a lower-detail model for remote players is the next lever if not.
- Checked in the game with four remote players (`outputs/character_review/remote_players_front.png`, `_side.png`) and by
  `tests/tdm_remote_character_regression.gd` (17 checks).

Not done: the aim pose (shouldered) for remote players, the muzzle-flash and recoil animation beyond the flash, hit and death
reactions (stage 4), crouch and prone clips (stage 3). Remote players do not yet turn their chest toward the aim like the local
one's shooter stance only partly; verified only by stills.

## 15. Remaining items fixed together (2026-10-29)

- **Crouch:** authored `CROUCH_Idle` and `CROUCH_Walk` (2.1 m/s, 1.4 m per cycle, hips 30 cm lower) in
  `locomotion.py` (`CROUCH`, `CROUCH_IDLE`, `use_idle`), blended in by how crouched the body is. Validation: foot drift
  0.04 mm, knee flex 118 deg, ground penetration 4 mm on the walk.
- **Prone:** the body now actually lies on its chest (80 deg). It used to be blended a little each frame from an upright
  reset, so the realistic character never lay down. Head lifted to look ahead, legs straight, one knee drawn up at a time
  while moving (a low crawl, procedural). The rifle is carried from the chest bone in every stance.
- **Hit and death:** a hit jolts the chest and head away from the shot for 0.3 s; a death drops the body over in the shot's
  direction (0.7 s). Remote players' bodies stay down for 2.5 s, cannot be hit, then disappear. Procedural, not authored clips.
- **Aim pose for remote players:** the aim state travels in bit 4 of the synced stance code; an aiming remote player
  shoulders the rifle.
- **Movement feel:** with a rifle out, sideways is 0.9 and backwards 0.75 of forward speed; acceleration 16 (was 18),
  stopping 24 (was 28); the body follows the aim at 14/s (was 18). All exported values in `person_controller.gd`.
- **Killcam:** 3 s over the killer's shoulder, looking where they look, then back to the player's camera.
- **Pings on the minimap:** the game's minimap stays up in a match and draws team-mates, enemies for 3 s after they fire,
  and team pings. The separate radar is no longer shown.
- **Tests:** `tests/character_stance_reactions_regression.gd` (15 checks); the integration and remote-character tests gained
  minimap, killcam and body-timing checks (47 and 18 checks).

Known: when the local player goes prone the camera's existing behaviour hides their own body (it was not changed);
other players see the prone pose. None of this is tested on a device.
