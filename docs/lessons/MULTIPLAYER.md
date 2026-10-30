# Multiplayer: lessons

Code: `scripts/network/` (squad, sync), `scripts/tactical/` (Team Deathmatch). Design: `docs/TDM_DESIGN.md`.

## Entries

### Trusting a client's word in free-roam squad (2026-10-30)
- **Symptom:** any client could hurt anyone, rewrite the room or spawn crates. Crates shared one name per player,
  so looting could remove the wrong one. Nothing refused another build.
- **Cause:** every RPC in `network_manager.gd` was `any_peer` with no sender check, and peers shared crate names.
- **Rule:** the host announces with `authority` RPCs. Clients ask through `rpc_request_*`, which use the real
  sender and never an id from the message. Crates use host-issued ids. Changing these messages bumps
  `NetworkManager.PROTOCOL_VERSION`; it is separate from the one in `tdm_session.gd`.
- **Check:** `tests/test_multiplayer_loopback.gd` sends forged RPCs and impossible requests, then checks nothing changed.

### Knock-down, elimination and name tags in squad (2026-10-30)
- **Symptom:** a knocked-down player was also sent home and charged the fee. An eliminated player vanished for good.
  Name tags said "Player 12345". Crates promised coins they never paid and put ammo in the magazine.
- **Cause:** `city_gameplay.gd` `_respawn` ignored the squad session. `rpc_notify_eliminated` removed the puppet and
  `rpc_sync_transform` ignores unknown senders. `_spawn_puppet` returned early when the puppet already existed.
  `loot_crate.gd` `collect` only returned the numbers.
- **Rule:** in a session, zero health means `knock_down_local()`, never a trip home. Keep a puppet until its peer
  disconnects: `set_eliminated()`, then `try_return()` shows it again. Puppets are spawned from the host's roster,
  so they have real names from the start.
- **Check:** the same test, with the real `city_gameplay.gd` wired to one client.

### Scene changes with a live connection (2026-10-30)
- **Symptom:** after a map switch the peer stayed on the tree with no nodes left to receive its RPCs.
- **Cause:** `change_scene_to_file` frees `NetworkManager` without closing the connection.
- **Rule:** `NetworkManager._exit_tree` closes the peer, so this is safe by default. Menus should call
  `leave_and_change_scene(path)` so that everyone is told first.
- **Check:** the end of `tests/test_multiplayer_loopback.gd` removes a manager from the tree and watches the host.

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
