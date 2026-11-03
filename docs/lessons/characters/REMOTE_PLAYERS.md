# Remote players (squad and Team Deathmatch)

Other people's characters on this device. Code: `scripts/network/network_player.gd`, driven by the same
`test_character.gd` as the local player.

| | |
|---|---|
| Body | the player model ([PLAYER_RAHUL.md](PLAYER_RAHUL.md)), `male_only`; capsules if the model file is missing |
| What they must offer | `velocity`, `crouching`, `prone`, `peek_input`, `is_weapon_equipped()`, `weapon`, `puppet_on_floor()` |
| Synced pose | stance code: bits 1–2 stance (0 stand, 1 crouch, 2 prone, 3 downed), bit 4 aiming, bits 8+ rifle id |
| Phone cost | animate only within 70 m of the camera (`ANIMATION_RANGE`) |

## Entries

### Remote bodies stuttered: smoothing toward the newest packet (2026-10-30)
- **Symptom:** other players moved in small surges and their feet did not match their speed.
- **Cause:** `network_player.gd` eased toward the latest 30 Hz state and took the feet's speed from that easing.
- **Rule:** draw remote bodies `interpolation_delay` (0.1 s) in the past from `_snapshots`, and take leg speed from
  the sampled motion. Extrapolate at most `extrapolation_cap`, then stop the legs too. Steps come from the character's
  `foot_planted`, not a timer.
- **Check:** `feel_regression` `test_remote_buffer`.

### Everyone looked like they held an M416 (2026-10-29)
- **Cause:** the rifle model was hard-coded in `network_player.gd`.
- **Rule:** anything a player can change that others should see must be synced. The held rifle travels in
  bits 8+ of the stance code; a value from an older build (no bits) means the M416.
- **Check:** `weapon_switch_regression` (remote player part).

### Capsules instead of a character (2026-10-29)
- **Cause:** remote players had their own stand-in visuals and were never driven by the character script.
- **Rule:** remote players use the same character and posing code as the local player; give them the same
  queries rather than writing a second animation path.
- **Check:** `tdm_remote_character_regression`.
