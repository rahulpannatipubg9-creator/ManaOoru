extends SceneTree

## The joining player for tests/tdm_network_regression.gd. Runs as its own process, connects to the
## host over real ENet on localhost, plays one scripted match and writes what it saw to a JSON file.
## Arguments after "--": ok | reject

const Session := preload("res://scripts/tactical/tdm_session.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")
const PORT := 17877

var session: Node
var report := {"entered": false, "rejected": "", "hit_confirmed": 0, "kills_seen": 0, "ended_winner": -2,
	"chat": "", "ping": false, "red": -1, "blue": -1, "team": -1, "state_live": false}

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var mode := "ok"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = args[0]
	session = Session.new()
	root.add_child(session)
	if mode == "reject":
		session.protocol_version = 999
	session.rejected.connect(func(reason: String) -> void: report.rejected = reason)
	session.entered.connect(func(_config: Variant) -> void: report.entered = true)
	session.hit_confirmed.connect(func(_victim: int, _headshot: bool, _killed: bool) -> void: report.hit_confirmed += 1)
	session.killed.connect(func(_k: int, _v: int, _h: bool, _a: Array) -> void: report.kills_seen += 1)
	session.ended.connect(func(winner: int, _rows: Array) -> void: report.ended_winner = winner)
	session.chat_received.connect(func(_from: int, text: String) -> void: report.chat = text)
	session.ping_received.connect(func(_from: int, _team: int, _position: Vector3) -> void: report.ping = true)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", PORT) != OK:
		_finish(mode)
		return
	root.multiplayer.multiplayer_peer = peer
	if mode == "reject":
		await _wait(func() -> bool: return report.rejected != "", 8.0)
		_finish(mode)
		return
	await _wait(func() -> bool: return report.entered and session.rows.size() == 2, 10.0)
	report.team = session.local_team()
	await _wait(func() -> bool: return session.state == Match.State.LIVE, 15.0)
	report.state_live = session.state == Match.State.LIVE
	await create_timer(1.5).timeout
	# A claim from nowhere near the shooter must be refused by the host.
	session.claim_hit(1, false, Vector3(80, 1.5, 80), Vector3(0, 1.0, 0))
	await create_timer(0.6).timeout
	var after_bad := int(report.hit_confirmed)
	# Four body hits on the host (28 each, regen cannot keep up) kill it: 112 damage.
	for _i in 4:
		session.claim_hit(1, false, Vector3(0, 1.5, 5), Vector3(0, 1.0, 0))
		await create_timer(0.2).timeout
	await create_timer(0.5).timeout
	report["bad_claim_confirmed"] = after_bad
	session.send_chat(0, Vector3(3, 0, 3))
	await _wait(func() -> bool: return report.chat != "" and report.ping, 5.0)
	await _wait(func() -> bool: return report.ended_winner != -2, 20.0)
	report.red = session.red_score
	report.blue = session.blue_score
	_finish(mode)

func _wait(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame

func _finish(mode: String) -> void:
	var file := FileAccess.open("user://tdm_client_%s.json" % mode, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	quit(0)
