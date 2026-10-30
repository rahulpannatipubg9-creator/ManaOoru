# Multiplayer: lessons

Code: `scripts/network/` (squad, sync), `scripts/tactical/` (Team Deathmatch). Design: `docs/TDM_DESIGN.md`.

## Entries

### A notification sent every frame (2026-10-30)
- **Symptom:** holding revive spammed the toast with a new "Reviving X: 41%" line each frame, too fast to read.
- **Cause:** `network_manager.gd` emitted `notification_posted` from the per-frame revive loop, and the changing
  percentage beat any repeat check.
- **Rule:** emit a notification once, when the state changes. Progress belongs in a bar, never in a message.
- **Check:** `tests/on_screen_text_regression.gd` covers the queue and its limit; the emit itself is not exercised there.

### Changing rules or messages without a version bump (2026-10-29)
- **Rule:** any change to hit claims, damage, fire rate or RPC arguments bumps `PROTOCOL_VERSION` in
  `tdm_session.gd` (now 2). A joiner on another version is refused with "Different game version", so the tablet
  and the phone always need the same build.

### Squeezing new state into the sync (2026-10-29)
- **Rule:** extend the stance code bits rather than the RPC signature when the value is small (bit 4 aim,
  bits 8+ rifle id), and make "no bits" mean the old behaviour so an older build still reads it.

### Never trust a client's numbers
- The host decides damage from the rifle id, limits the fire rate per rifle, and checks positions, range and
  walls (`_claim_problem()`). New claims must go through the same checks.
