# Multiplayer: lessons

Code: `scripts/network/` (squad, sync), `scripts/tactical/` (Team Deathmatch). Design: `docs/TDM_DESIGN.md`.

## Entries

### TDM network test suites require explicit armor reduction calibration (2026-10-31)
- **Symptom:** `tdm_network_regression` failed with `the client's validated hits killed the host` and 6 related checks.
- **Cause:** When BGMI Level 2 Armor reduction (`tdm_armor_reduction = 0.40`) was added to `tdm_config.gd` to raise TTK to 5-6 shots in live gameplay, the test's 4-shot body kill scenario (4 * 28 = 112 raw damage) only dealt 67.2 damage, leaving the host alive.
- **Rule:** Network regression suites verifying raw damage application and kill state transitions must explicitly set `config.tdm_armor_reduction = 0.0` (matching `tests/weapon_switch_regression.gd`).
- **Check:** `tests/tdm_network_regression.gd`.

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

### Shared character animations must tolerate remote controller fields (2026-10-31)
- The local player exposes `weapon_kick` and reload timing; `NetworkPlayer` does not. Shared animation selection must read optional state through `get()` guards. Keep local and remote shoulder anchors consistent when a different visible skeleton is selected. Validated with `weapon_switch_regression`; no RPC format changed.
