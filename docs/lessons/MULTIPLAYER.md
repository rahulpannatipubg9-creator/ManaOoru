# Multiplayer: lessons

Code: `scripts/network/` (squad, sync), `scripts/tactical/` (Team Deathmatch). Design: `docs/TDM_DESIGN.md`.

## Entries

### A notification sent every frame (2026-10-30)
- **Symptom:** holding revive spammed the toast with a new "Reviving X: 41%" line each frame, too fast to read.
- **Cause:** `network_manager.gd` emitted `notification_posted` from the per-frame revive loop, and the changing
  percentage beat any repeat check.
- **Rule:** emit a notification once, when the state changes. Progress belongs in a bar, never in a message.
- **Check:** `tests/on_screen_text_regression.gd` covers the queue and its limit; the emit itself is not exercised there.
### The floating stick ate taps on match panels (2026-10-30)
- **Symptom:** on touch, lobby and menu buttons on the left of the screen did nothing.
- **Cause:** `hud.gd` `_handle_screen_touch()` claims any touch in the stick zone in `_input`, before panels see it. It
  only knows free-roam modals, not `tdm_hud.gd` panels.
- **Rule:** `tdm_local.gd` `_show_touch_controls()` hides the claw whenever `needs_cursor()` is true.
- **Check:** `tdm_hud_regression` ("a finger on JOIN changes team").

### Settings ignored fingers in a match (2026-10-30)
- **Cause:** `menu_touch_bridge.gd` only turned on while the tree was paused, and a match never pauses.
- **Rule:** the match sets the bridge's `runs_unpaused`. `can_fire()` stops the rifle behind the menu instead of a pause.
- **Check:** `tdm_hud_regression`.

### Free-roam widgets leaked onto the match screen (2026-10-30)
- **Symptom:** the desktop SETTINGS button sat on the score bar and "Action mode enabled" floated over the lobby.
- **Cause:** `settings_menu.gd` builds its entry button locally, and `city_life.gd` shows its toast every frame.
- **Rule:** `tdm_local.gd` `_hide_free_roam_ui()` and `_keep_free_roam_ui_hidden()` own this list. Check a render of
  every match state after adding any always-on widget.
- **Check:** `tdm_hud_regression`.

### Team changes go through one host rule (2026-10-30)
- **Rule:** every player-asked move goes through `tdm_match.gd` `change_team()`, which returns the words to show when
  it refuses. The host's own lobby move skips the balance rule on purpose. A live move costs a normal respawn and
  keeps K/D, with a cooldown so nobody hops sides to dodge a fight.
- **Check:** `tdm_match_regression`, `tdm_hud_regression`.

### Friendly checks live on both sides (2026-10-30)
- **Rule:** the client drops a shot on a teammate in `network_player.gd` `tdm_claim_hit()`, because a sent claim uses
  up the shooter's fire-rate slot on the host. The host still refuses friendly fire for a modified client. Names and
  markers are for teammates only; enemies must show nothing through walls.
- **Check:** `tdm_hud_regression`.

### Stale position reports stranded respawned players (2026-10-30)
- **Symptom:** after a respawn a player's hits were refused for seconds ("hit_far_from_target").
- **Cause:** `tdm_session.gd` `_on_rules_spawned()` cleared `_position_times`, so the speed check skipped the next
  report. A packet sent before the teleport won, and every real report then failed the check against that old spot.
- **Rule:** a teleport stamps the time; it never clears it.
- **Check:** `tdm_hud_regression`.

### Match rules said "go", the HUD hid it (2026-10-30)
- **Symptom:** GO! never appeared, and the last "respawning in 5" stayed behind the end screen.
- **Cause:** `refresh()` set the banner from the state straight after `show_banner()`; the ENDED branch of
  `_on_state_changed()` left the death label up.
- **Rule:** timed messages own their own expiry. Every state change clears the messages of the state it leaves.
- **Check:** `tdm_hud_regression`.

### Damage arcs mirrored left and right (2026-10-30)
- **Cause:** `_draw_arcs()` flipped the sign of `Vector2.angle_to()`, which is already signed.
- **Rule:** keep screen-angle maths in a static function that a test can call (`arc_angle()`).
- **Check:** `tdm_hud_regression`.

### Panels with no way to reach them (2026-10-30)
- **Symptom:** on desktop the lobby and end-screen buttons could not be clicked, practice had no exit, and ammo was
  not shown anywhere in a match.
- **Cause:** the HUD was built for touch. The mouse stays captured, and free-roam status text is hidden in a match.
- **Rule:** every panel is checked on desktop and touch. Any state with buttons returns true from
  `tdm_local.needs_cursor()`. Every mode has a route out through the match menu.
- **Check:** `tdm_hud_regression`.

### Anchored buttons ended up off screen (2026-10-30)
- **Symptom:** SCORE and CHAT were cut off at the right edge, and the feed and chat could cover the minimap.
- **Rule:** `tdm_hud.gd` `_layout()` places them from the real screen and minimap rectangles. Do not add new
  corner widgets with anchor presets and hand-set positions.
- **Check:** `tdm_hud_regression`, then a render on both layouts.
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
  `tdm_session.gd` (now 3). A joiner on another version is refused with "Different game version", so the tablet
  and the phone always need the same build.

### Squeezing new state into the sync (2026-10-29)
- **Rule:** extend the stance code bits rather than the RPC signature when the value is small (bit 4 aim,
  bits 8+ rifle id), and make "no bits" mean the old behaviour so an older build still reads it.

### Never trust a client's numbers
- The host decides damage from the rifle id, limits the fire rate per rifle, and checks positions, range and
  walls (`_claim_problem()`). New claims must go through the same checks.
