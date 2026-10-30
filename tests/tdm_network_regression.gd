extends SceneTree

## Two real processes over ENet on localhost: this one hosts a Team Deathmatch, tests/tdm_net_client.gd joins it.
## Checks the join handshake, version refusal, host-validated hits and kills, chat relay and the end of the match.
## Run: godot --headless --path . --script tests/tdm_network_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const PORT := 17877

var session: Node
var failures := 0
var checks := 0
var damaged_events: Array = []
var killed_events: Array = []
var host_end := {"winner": -2}

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tdm_client_ok.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tdm_client_reject.json"))
	var peer := ENetMultiplayerPeer.new()
	check(peer.create_server(PORT, 4) == OK, "the test port is free")
	root.multiplayer.multiplayer_peer = peer
	session = Session.new()
	root.add_child(session)
	var config := Config.new()
	config.countdown_seconds = 1.0
	config.spawn_protection_seconds = 0.3
	config.respawn_seconds = 1.0
	var zones: Array[PackedVector3Array] = [PackedVector3Array([Vector3(-40, 0, -40)]), PackedVector3Array([Vector3(40, 0, 40)])]
	session.host_begin(config, "Host", zones)
	session.damaged.connect(func(victim: int, attacker: int, amount: float, _h: bool, health: float) -> void:
		damaged_events.append([victim, attacker, amount, health]))
	session.killed.connect(func(killer: int, victim: int, _h: bool, _a: Array) -> void: killed_events.append([killer, victim]))
	session.ended.connect(func(winner: int, _rows: Array) -> void: host_end.winner = winner)
	check(session.rows.size() == 1 and session.state == Match.State.LOBBY, "the host starts alone in the lobby")

	# A joiner on a different protocol version is turned away before it sees any match state.
	var reject_pid := _start_client("reject")
	await _wait_file("user://tdm_client_reject.json", 20.0)
	var rejected := _read("user://tdm_client_reject.json")
	check(String(rejected.get("rejected", "")).contains("version"), "a mismatched version is refused with a clear message")
	check(not rejected.get("entered", true), "the refused client never entered the match")
	check(session.rows.size() == 1, "the refused client is not on the roster")

	# A matching client joins.
	var client_pid := _start_client("ok")
	await _wait_until(func() -> bool: return session.rows.size() == 2, 20.0)
	check(session.rows.size() == 2, "the matching client joins the roster")
	check(session.team_of(1) == 0 and _client_team() == 1, "host takes Red, the joiner is balanced onto Blue")
	check(session.host_start(), "the host starts the match")
	await _wait_until(func() -> bool: return session.state == Match.State.LIVE, 10.0)
	check(session.state == Match.State.LIVE, "the countdown ends in a live match")
	var client_id := _client_id()
	# Stand both players side by side; a real report this far from the spawn would fail the speed check.
	session._position_times.clear()
	session.on_peer_position(1, Vector3(0, 0, 0))
	session.on_peer_position(client_id, Vector3(0, 0, 5))
	await _wait_until(func() -> bool: return killed_events.size() > 0, 20.0)
	check(killed_events.size() == 1 and killed_events[0] == [client_id, 1], "the client's validated hits killed the host")
	check(damaged_events.size() == 4 and damaged_events.all(func(e: Array) -> bool: return e[1] == client_id and e[2] == 28.0),
		"exactly the four valid hits were applied, none from the bad claim")
	session.rules.time_left = 0.3
	await _wait_until(func() -> bool: return host_end.winner != -2, 10.0)
	check(host_end.winner == 1, "Blue wins on time with the only kill")
	await _wait_file("user://tdm_client_ok.json", 30.0)
	var report := _read("user://tdm_client_ok.json")
	check(report.get("entered", false), "the client entered the match")
	check(int(report.get("team", -1)) == 1, "the client knows it is on Blue")
	check(report.get("state_live", false), "the client saw the match go live")
	check(int(report.get("bad_claim_confirmed", -1)) == 0, "a claim from far away was refused by the host")
	check(int(report.get("hit_confirmed", 0)) == 4, "the client got a confirmation for each valid hit")
	check(int(report.get("kills_seen", 0)) == 1, "the client saw the kill")
	check(int(report.get("ended_winner", -2)) == 1, "the client was told Blue won")
	check(int(report.get("red", -1)) == 0 and int(report.get("blue", -1)) == 1, "the client's score mirrors the host's")
	check(report.get("chat", "") == "Enemy here" and report.get("ping", false), "quick chat with a ping reaches teammates")
	print("TDM network regression: %d checks, %d failed" % [checks, failures])
	OS.kill(reject_pid)
	OS.kill(client_pid)
	quit(1 if failures > 0 else 0)

func _start_client(mode: String) -> int:
	return OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/tdm_net_client.gd", "--", mode])

func _client_id() -> int:
	for row: Dictionary in session.rows:
		if int(row.peer_id) != 1:
			return int(row.peer_id)
	return 0

func _client_team() -> int:
	return session.team_of(_client_id())

func _wait_until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame

func _wait_file(path: String, seconds: float) -> void:
	await _wait_until(func() -> bool: return FileAccess.file_exists(path), seconds)

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
