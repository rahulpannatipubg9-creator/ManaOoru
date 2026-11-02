# Mixamo animation audit — 2026-10-31

All 73 unique source clips from 78 FBX files are present. The original FBX files and GLB were preserved. The tested runtime library adds three derived clips: Idle_Natural, Walk_Loop and Drive_Seated.

Playback integrity passed for all 76 runtime clips. This is not a claim that all optional interactions exist in the game. The table below identifies every active clip, source-only clip and library-only alternative.

## Evidence and results

| Check | Result |
|---|---|
| Library playback | 76 clips; 5,625 bone-pose frames sampled at 30 Hz; 988 skinned geometry samples; 0 failures |
| Adjacent clip transitions | 75 transitions, 300 blend samples; no nonfinite geometry or size explosions |
| Gameplay selection/timing | 50 checks, 0 failed: locomotion, strafing, backward travel, stances, jump/fall, swimming, firing, reload, grenades, melee timing, death hold and respawn |
| Visible-rig contacts | 552 checks, 0 failed: Porsche, Compass, Thar, Bullet; M416, AK47 and Bren 2 across 13 rifle/locomotion poses in ready/aim, including crouch, crawl, directional walk, firing and jump |
| Character scale | Upright reference fitted to 1.730m; animated idle is approximately 1.735m, with soles about 3mm above origin |
| Required regressions | movement, vehicle entry, visible vehicle entry, test character, stance/reactions, arm hang, weapon switch and character scale passed |
| Visual inspection | 228 clip frames across seven sheets, plus 21 gameplay/prop pose images reviewed in Godot Compatibility renderer on Apple M1 |

## Fixes made

- Replaced repeated walk-start with a derived walking loop and arm-stretching idle with a relaxed breathing idle. Used a steady seated pose for driving instead of the fidget/lean sequence.
- Copied clips privately at runtime; removed horizontal root travel from the collider-driven character and bounded residual sway. Closed the tails of true loops and left transitions/actions as one-shots.
- Added source-derived gait playback rates and jump timing based on the controller’s flight time. Backward motion takes priority over forward jog.
- Connected firing, moving fire and reload; prevented rifle attack metadata from selecting melee clips; selected standing versus prone grenade clips correctly. Long actions now last for their actual clip duration. Completed deaths hold instead of restarting.
- Preserved low-body stance during crouched/prone actions instead of standing the visual up inside a short collider.
- Added post-animation IK for the visible Mixamo rig: seated pelvis, pedals/pegs, feet orientation, wheel/handlebar contacts and rifle wrist/palm fitting. Corrected local/remote rifle shoulder height and prone reach for this skeleton.
- Added offline grounding curves for 13 clips. Worst sampled penetration reduced from approximately 15cm to 1.4cm (within the 2.5cm audit tolerance).
- Updated legacy regression checks to measure the visible character. Guarded optional local-only firing state on network characters. Included grounding JSON in export filters.

## Limits and remaining work

- Library-only clips passed isolated playback and rendered pose review, but their required gameplay interactions were not implemented or tested as complete features. Ladder/ledge climbing, cover, briefcase handling, kneeling, dodge/roll travel and special turns require their own interaction/collision systems.
- No authored car-entry, bike-mount or seated-driving clip exists in this folder. Entry/exit continues to use the existing procedural door/bend/leg-over sequence; driving uses a derived seated pose with fitted contacts.
- No dedicated forward sprint was supplied; sprint uses Jogging retimed to movement speed. This is not a newly authored sprint animation.
- No dedicated prone reload was supplied. The current fix preserves prone hips/legs while playing the reload upper body; exact magazine removal/insertion and prop synchronization are not validated.
- Grounding is measured on a flat test floor. Uneven terrain foot placement, every imported car interior, exhaustive pairwise transitions, sustained multiplayer sessions, Android export and device performance were not tested in this audit.
- Full-world headless tests print renderer/ObjectDB resource-leak messages at teardown even after functional passes. Those cleanup diagnostics remain unresolved; they are not presented as a clean engine-log pass.

## Reproduce

Run Godot with `--headless --path . --script tests/mixamo_animation_audit.gd`, then `tests/mixamo_gameplay_regression.gd` and `tests/mixamo_contacts_regression.gd`. Run the two `capture_mixamo_*.gd` scripts windowed under `caffeinate -d -i` for actual rendered evidence. Rebuild grounding with `tools/mixamo_animation_audit/build_grounding.gd` after replacing the GLB or changing height, then rerun the audit. Generate this report using `python3 tools/mixamo_animation_audit/report.py`.

## Every clip

Gameplay: 40 original + 3 derived. Derived source clips: 2. Library-only clips: 31.

| Clip | Duration | Mode | Playback / visual | Connection | Notes |
|---|---:|---|---|---|---|
| Air_Squat_Bent_Arms | 1.90s | Loop | Pass / reviewed | Library only | Optional exercise/emote; no automatic gameplay trigger. |
| Arm_Stretching | 8.90s | Loop | Pass / reviewed | Library only | Optional exercise/emote; no automatic gameplay trigger. |
| Big_Side_Hit | 1.50s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Boxing | 1.77s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Climbing | 3.87s | One-shot | Pass / reviewed | Library only | Needs a ladder/ledge interaction, contact targets and collision traversal; isolated playback tested only. |
| Cover_To_Stand | 1.53s | One-shot | Pass / reviewed | Library only | Needs cover detection and cover state transitions; kept as one-shots. |
| Crouch_Death | 2.40s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Crouch_To_Prone | 1.83s | One-shot | Pass / reviewed | Library only | Alternative authored transition; gameplay currently blends stance clips instead. |
| Crouch_Walking | 1.20s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Death_From_The_Front | 3.47s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Dodging | 1.67s | Loop | Pass / reviewed | Library only | Needs a dodge/roll action with collision-aware body travel; isolated playback tested. |
| Drive_Seated | 2.50s | Loop | Pass / reviewed | Gameplay (derived) | Derived runtime pose/loop; original source clip preserved. |
| Drop_Kick | 2.93s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Falling_To_Roll | 2.17s | One-shot | Pass / reviewed | Library only | Needs a dodge/roll action with collision-aware body travel; isolated playback tested. |
| Firing_Rifle | 1.20s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Firing_Rifle_while_walking | 1.40s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Fist_Fight_B | 4.70s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Floating | 3.63s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Flying_Kick | 1.53s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Flying_Knee_Punch_Combo | 2.27s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Freehang_Climb | 3.90s | One-shot | Pass / reviewed | Library only | Needs a ladder/ledge interaction, contact targets and collision traversal; isolated playback tested only. |
| Grab_Rifle_From_The_Side | 2.50s | One-shot | Pass / reviewed | Library only | Needs timed draw/holster prop handling; current weapon presentation uses its existing draw transition. |
| Grenade_Throw | 2.80s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Headbutt | 2.13s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Hit_Reaction | 0.63s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Hook | 2.30s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Idle_Crouching | 2.13s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Idle_Natural | 2.50s | Loop | Pass / reviewed | Gameplay (derived) | Derived runtime pose/loop; original source clip preserved. |
| Illegal_Elbow_Punch | 2.30s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Jog_In_Circle | 5.97s | One-shot | Pass / reviewed | Library only | Curved locomotion with authored turning; not substituted for straight player movement. |
| Jogging | 2.60s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Jump | 2.20s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Jumping_Down | 2.53s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Kidney_Hit | 1.17s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Left_Turn_W_Briefcase | 2.17s | One-shot | Pass / reviewed | Library only | Requires a briefcase prop and matching interaction. |
| Look_Over_Shoulder | 3.80s | One-shot | Pass / reviewed | Library only | Optional exercise/emote; no automatic gameplay trigger. |
| Medium_Hit_To_Head | 0.97s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Mma_Kick | 1.63s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Moving_Backward_In_Prone_Position | 1.93s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Opening_Door_Inwards | 6.40s | One-shot | Pass / reviewed | Library only | Long inward-door interaction; vehicle entry continues to use its fitted procedural doorway bend and door timing. |
| Pistol_Kneeling_Idle | 3.83s | Loop | Pass / reviewed | Library only | Pistol/kneeling alternative; current equipped weapons are rifles. |
| Prone_Death | 1.90s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Prone_Firing_Rifle | 0.87s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Prone_Forward | 2.37s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Prone_Idle | 4.97s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Prone_Right_Turn | 1.33s | One-shot | Pass / reviewed | Library only | Authored turn requires controller yaw synchronization; camera-relative controller still owns yaw. |
| Prone_To_Crouch_Transition | 1.83s | One-shot | Pass / reviewed | Library only | Alternative authored transition; gameplay currently blends stance clips instead. |
| Reload | 3.70s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Rifle_Aiming_Idle | 3.13s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Rifle_Crouch_Walk_To_Kneel | 2.77s | One-shot | Pass / reviewed | Library only | Needs a dedicated kneeling stance/collider transition. |
| Rifle_Jump | 0.63s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Rifle_Prone_To_Kneel | 2.00s | One-shot | Pass / reviewed | Library only | Needs a dedicated kneeling stance/collider transition. |
| Rifle_Turn_And_Kick | 2.80s | One-shot | Pass / reviewed | Library only | Alternative combat move; not in the normal melee combo. |
| Right_Turn_W_Briefcase | 2.17s | One-shot | Pass / reviewed | Library only | Requires a briefcase prop and matching interaction. |
| Roll_Left | 2.53s | One-shot | Pass / reviewed | Library only | Needs a dodge/roll action with collision-aware body travel; isolated playback tested. |
| Running_Jump | 0.93s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Shooting_Gun | 5.33s | One-shot | Pass / reviewed | Library only | Different source gun gesture; kept as a preview alternative, not used instead of the rifle firing clips. |
| Sitting | 5.97s | Loop | Pass / reviewed | Derived source | Source for Drive_Seated; full fidget animation retained separately. |
| Sprint_Backward | 0.53s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Stand_To_Cover | 1.17s | One-shot | Pass / reviewed | Library only | Needs cover detection and cover state transitions; kept as one-shots. |
| Standing_Cover_Turn | 1.03s | One-shot | Pass / reviewed | Library only | Needs cover detection and cover state transitions; kept as one-shots. |
| Start_Walking | 2.97s | One-shot | Pass / reviewed | Derived source | Source for Walk_Loop / Idle_Natural. |
| Stop_Walking_With_Rifle | 2.30s | One-shot | Pass / reviewed | Library only | Alternative deceleration transition; current controller blends directly to rifle idle. |
| Strafe | 1.20s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Strafing | 1.80s | One-shot | Pass / reviewed | Library only | Alternative locomotion/interaction clip; current controller uses its selected gait variants. |
| Swimming | 4.57s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Throw_Grenade | 3.53s | One-shot | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Turn_90_Left | 1.03s | One-shot | Pass / reviewed | Library only | Authored turn requires controller yaw synchronization; camera-relative controller still owns yaw. |
| Turn_Left | 1.53s | One-shot | Pass / reviewed | Library only | Authored turn requires controller yaw synchronization; camera-relative controller still owns yaw. |
| Turn_right | 1.53s | One-shot | Pass / reviewed | Library only | Authored turn requires controller yaw synchronization; camera-relative controller still owns yaw. |
| Walk_Crouching_Right | 1.03s | Loop | Pass / reviewed | Library only | Alternative locomotion/interaction clip; current controller uses its selected gait variants. |
| Walk_Left_with_gun | 1.03s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Walk_Loop | 1.20s | Loop | Pass / reviewed | Gameplay (derived) | Derived runtime pose/loop; original source clip preserved. |
| Walk_Right_with_gun | 1.03s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Walk_With_Rifle | 1.47s | Loop | Pass / reviewed | Gameplay | Selected by the current gameplay animation controller. |
| Wheelbarrow_Walk | 1.00s | Loop | Pass / reviewed | Library only | Alternative locomotion/interaction clip; current controller uses its selected gait variants. |
