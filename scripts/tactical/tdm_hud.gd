extends CanvasLayer

## Everything the player sees in Team Deathmatch: lobby, score bar, kill feed, hit marker, damage arcs,
## boundary warning, death message, scoreboard, quick chat and the end screen (docs/TDM_DESIGN.md,
## section 5). Pure presentation: it reports button presses through signals and reads state from
## the session; tdm_local.gd does the gameplay.

const Match := preload("res://scripts/tactical/tdm_match.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")

const RED_COLOR := Color(0.95, 0.25, 0.25)
const BLUE_COLOR := Color(0.3, 0.5, 1.0)
const BUTTON_HEIGHT := 56.0
const FEED_LINES := 4
const FEED_SECONDS := 5.0
const SCOREBOARD_SECONDS := 3.0
const CHAT_SECONDS := 6.0
const HIT_MARKER_SECONDS := 0.18
const ARC_SECONDS := 1.2

signal start_pressed
signal swap_pressed
signal ready_toggled(value: bool)
signal practice_pressed
signal leave_pressed
signal rematch_pressed
signal chat_selected(index: int)

var session: Node
## func() -> Camera3D used to aim the damage arcs.
var camera_provider: Callable
## func(peer_id) -> Vector3 or Vector3.INF: where an attacker is standing.
var position_provider: Callable
## func() -> Dictionary {me: Vector3, allies: Array, enemies: Array, pings: Array} for the radar.
var radar_provider: Callable
const RADAR_SIZE := 170.0
const RADAR_RADIUS_METERS := 130.0

var _root: Control
var _score_label: Label
var _timer_label: Label
var _goal_label: Label
var _banner: Label
var _feed: VBoxContainer
var _feed_times: Array[float] = []
var _health_bar: ProgressBar
var _protected_label: Label
var _death_label: Label
var _boundary_label: Label
var _vignette: ColorRect
var _hit_marker: Control
var _radar: Control
var _arc_layer: Control
var _scoreboard_button: Button
var _scoreboard_panel: PanelContainer
var _scoreboard_label: Label
var _scoreboard_until := 0.0
var _chat_button: Button
var _chat_wheel: GridContainer
var _chat_log: VBoxContainer
var _chat_times: Array[float] = []
var _practice_label: Label
var _lobby_panel: PanelContainer
var _lobby_title: Label
var _red_label: Label
var _blue_label: Label
var _lobby_buttons: Dictionary = {}
var _end_panel: PanelContainer
var _end_title: Label
var _end_board: Label
var _end_rematch: Button
var _hit_until := 0.0
var _hit_color := Color.WHITE
var _arcs: Array[Dictionary] = []
var _ready_state := false
var _practice := false

func _ready() -> void:
	layer = 20
	name = "TdmHud"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vignette()
	_build_arcs_and_marker()
	_build_score_bar()
	_build_feed()
	_build_status()
	_build_radar()
	_build_scoreboard()
	_build_chat()
	_build_lobby()
	_build_end_screen()
	hide_all()

func setup(p_session: Node) -> void:
	session = p_session
	session.lobby_changed.connect(refresh)
	session.state_changed.connect(func(_s: int) -> void: refresh())

func hide_all() -> void:
	for node: CanvasItem in [_radar, _lobby_panel, _end_panel, _banner, _death_label, _boundary_label, _vignette, _scoreboard_panel,
			_chat_wheel, _protected_label, _practice_label]:
		node.visible = false
	_root.visible = false

# --- Showing the right thing for the match state ---------------------------------

func refresh() -> void:
	if session == null or not (session.active or _practice):
		hide_all()
		return
	_root.visible = true
	var state: int = session.state
	_lobby_panel.visible = not _practice and state == Match.State.LOBBY
	_end_panel.visible = not _practice and state == Match.State.ENDED
	_banner.visible = state == Match.State.COUNTDOWN
	_scoreboard_button.visible = not _practice
	_chat_button.visible = not _practice and state == Match.State.LIVE
	_practice_label.visible = _practice
	_update_lobby()
	_update_score()

func set_practice(value: bool) -> void:
	_practice = value
	refresh()

func _update_lobby() -> void:
	var red: Array[String] = []
	var blue: Array[String] = []
	for row: Dictionary in session.rows:
		var line := "%s%s%s" % [row.nickname, "  ✔" if row.get("ready", false) else "", "" if row.get("connected", true) else "  (dropped)"]
		(red if int(row.team) == 0 else blue).append(line)
	_lobby_title.text = "TEAM DEATHMATCH  •  first to %d  •  %d min" % [session.config.kill_limit(), int(session.config.time_limit_seconds() / 60.0)] \
		if session.config != null else "TEAM DEATHMATCH"
	_red_label.text = "RED (%d)\n%s" % [red.size(), "\n".join(red)]
	_blue_label.text = "BLUE (%d)\n%s" % [blue.size(), "\n".join(blue)]
	_lobby_buttons.start.visible = session.is_host
	_lobby_buttons.practice.visible = session.is_host and session.rows.size() <= 1
	_lobby_buttons.rematch_hint.visible = not session.is_host
	var red_count := red.size()
	var blue_count := blue.size()
	_lobby_buttons.start.disabled = red_count == 0 or blue_count == 0

func _update_score() -> void:
	_score_label.text = "%d   RED     BLUE   %d" % [session.red_score, session.blue_score]
	_goal_label.text = "FIRST TO %d%s" % [session.config.kill_limit() if session.config != null else 40, "  •  SUDDEN DEATH" if session.sudden_death else ""]

func _process(delta: float) -> void:
	if not _root.visible:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if session != null and session.active:
		_timer_label.text = _clock(session.time_left) if session.state != Match.State.COUNTDOWN else "--:--"
		_update_score()
		if session.state == Match.State.COUNTDOWN:
			_banner.text = str(maxi(1, ceili(session.countdown_left)))
			_banner.visible = true
		var mine: Dictionary = session.vitals.get(session.local_id(), {})
		_protected_label.visible = bool(mine.get("protected", false)) and bool(mine.get("alive", false))
		_health_bar.value = float(mine.get("hp", _health_bar.value))
	_fade_lines(_feed, _feed_times, now, FEED_SECONDS)
	_fade_lines(_chat_log, _chat_times, now, CHAT_SECONDS)
	_scoreboard_panel.visible = now < _scoreboard_until
	if _scoreboard_panel.visible:
		_scoreboard_label.text = _board_text()
	_hit_marker.visible = now < _hit_until
	_hit_marker.queue_redraw()
	# The game's minimap shows team-mates, firing enemies and pings in a match (tdm_local.gd); the radar is spare.
	_radar.visible = false
	_arcs = _arcs.filter(func(arc: Dictionary) -> bool: return now - float(arc.at) < ARC_SECONDS)
	_arc_layer.visible = not _arcs.is_empty()
	_arc_layer.queue_redraw()

static func _clock(seconds: float) -> String:
	var whole := maxi(0, ceili(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]

func _fade_lines(box: Control, times: Array[float], now: float, lifetime: float) -> void:
	while not times.is_empty() and now - times[0] > lifetime:
		times.pop_front()
		box.get_child(0).queue_free()
		box.remove_child(box.get_child(0))

# --- Events pushed in by tdm_local.gd ------------------------------------------

func flash_hit(headshot: bool) -> void:
	_hit_color = Color(1.0, 0.2, 0.2) if headshot else Color.WHITE
	_hit_until = Time.get_ticks_msec() / 1000.0 + HIT_MARKER_SECONDS

func show_damage_from(attacker_id: int) -> void:
	_arcs.append({"attacker": attacker_id, "at": Time.get_ticks_msec() / 1000.0})

func add_kill(killer: String, victim: String, killer_team: int, headshot: bool) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.custom_minimum_size = Vector2(300.0, 26.0)
	line.add_theme_font_size_override("normal_font_size", 17)
	var color := "#ff5555" if killer_team == 0 else "#5588ff"
	line.text = "[right][color=%s]%s[/color]  [color=#dddddd]⌖[/color]%s  %s[/right]" % [
		color, killer if killer != "" else "The arena", " ✦" if headshot else "", victim]
	_feed.add_child(line)
	_feed_times.append(Time.get_ticks_msec() / 1000.0)
	while _feed.get_child_count() > FEED_LINES:
		_feed.get_child(0).queue_free()
		_feed.remove_child(_feed.get_child(0))
		_feed_times.pop_front()

func add_chat(sender: String, text: String, team: int) -> void:
	var line := Label.new()
	line.text = "%s: %s" % [sender, text]
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", RED_COLOR if team == 0 else BLUE_COLOR)
	_chat_log.add_child(line)
	_chat_times.append(Time.get_ticks_msec() / 1000.0)

func show_death(killer_name: String, seconds: float) -> void:
	_death_label.text = "Killed by %s  •  respawning in %d" % [killer_name, ceili(seconds)] if killer_name != "" else "You died  •  respawning in %d" % ceili(seconds)
	_death_label.visible = true

func hide_death() -> void:
	_death_label.visible = false

func show_boundary(seconds_left: float) -> void:
	_boundary_label.text = "RETURN TO THE COMBAT AREA  %d" % maxi(0, ceili(seconds_left))
	_boundary_label.visible = true
	_vignette.visible = true

func hide_boundary() -> void:
	_boundary_label.visible = false
	_vignette.visible = false

func show_banner(text: String, seconds := 1.5) -> void:
	_banner.text = text
	_banner.visible = true
	get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if session == null or session.state != Match.State.COUNTDOWN:
			_banner.visible = false)

func set_practice_stats(hits: int, headshots: int, shots: int) -> void:
	var accuracy := 0 if shots == 0 else roundi(100.0 * hits / shots)
	_practice_label.text = "PRACTICE   hits %d   headshots %d   shots %d   accuracy %d%%" % [hits, headshots, shots, accuracy]

func show_end(winner: int, rows: Array) -> void:
	var result := "DRAW" if winner < 0 else ("RED WINS" if winner == 0 else "BLUE WINS")
	_end_title.text = result
	_end_title.add_theme_color_override("font_color", Color.WHITE if winner < 0 else (RED_COLOR if winner == 0 else BLUE_COLOR))
	_end_board.text = _board_text(rows)
	_end_rematch.visible = session != null and session.is_host
	_end_panel.visible = true

# --- Building the controls ---------------------------------------------------------

func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.8, 0.0, 0.0, 0.18)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)

func _build_arcs_and_marker() -> void:
	_arc_layer = Control.new()
	_arc_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arc_layer.draw.connect(_draw_arcs)
	_root.add_child(_arc_layer)
	_hit_marker = Control.new()
	_hit_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_marker.draw.connect(_draw_hit_marker)
	_root.add_child(_hit_marker)

func _draw_hit_marker() -> void:
	var center := _hit_marker.size * 0.5
	for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_hit_marker.draw_line(center + direction * 8.0, center + direction * 20.0, _hit_color, 3.0)

## Red arcs around the crosshair, each pointing at whoever shot you.
func _draw_arcs() -> void:
	var camera: Camera3D = camera_provider.call() if camera_provider.is_valid() else null
	if camera == null:
		return
	var center := _arc_layer.size * 0.5
	var radius := minf(_arc_layer.size.x, _arc_layer.size.y) * 0.22
	var forward := Vector2(-camera.global_basis.z.x, -camera.global_basis.z.z).normalized()
	var now := Time.get_ticks_msec() / 1000.0
	for arc in _arcs:
		var from: Vector3 = position_provider.call(int(arc.attacker)) if position_provider.is_valid() else Vector3.INF
		if from == Vector3.INF:
			continue
		var offset := Vector2(from.x - camera.global_position.x, from.z - camera.global_position.z)
		if offset.length() < 0.01:
			continue
		var angle := forward.angle_to(offset.normalized())
		if forward.cross(offset.normalized()) < 0.0:
			angle = -angle
		var fade := 1.0 - (now - float(arc.at)) / ARC_SECONDS
		var start := angle - PI * 0.5 - 0.35
		_arc_layer.draw_arc(center, radius, start, start + 0.7, 16, Color(1.0, 0.1, 0.1, clampf(fade, 0.0, 1.0)), 8.0)

func _build_score_bar() -> void:
	var bar := VBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 56.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	_score_label = _label("0   RED     BLUE   0", 26, Color.WHITE)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_score_label)
	_timer_label = _label("10:00", 22, Color(1.0, 0.9, 0.5))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_timer_label)
	_goal_label = _label("FIRST TO 40", 14, Color(0.8, 0.85, 0.9))
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_goal_label)

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-320.0, 120.0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)
	_chat_log = VBoxContainer.new()
	_chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_log.position = Vector2(16.0, -190.0)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chat_log)

func _build_status() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_health_bar.position = Vector2(16.0, -48.0)
	_health_bar.custom_minimum_size = Vector2(260.0, 22.0)
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_health_bar)
	_protected_label = _label("🛡 PROTECTED", 18, Color(0.5, 0.95, 1.0))
	_protected_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_protected_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_protected_label.position = Vector2(16.0, -78.0)
	_root.add_child(_protected_label)
	_banner = _label("3", 96, Color.WHITE)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_root.add_child(_banner)
	_death_label = _label("", 28, Color(1.0, 0.7, 0.7))
	_death_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_death_label.position.y = -160.0
	_root.add_child(_death_label)
	_boundary_label = _label("", 30, Color(1.0, 0.35, 0.3))
	_boundary_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boundary_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boundary_label.position.y = 150.0
	_root.add_child(_boundary_label)
	_practice_label = _label("PRACTICE", 20, Color(1.0, 0.9, 0.5))
	_practice_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_practice_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_practice_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_practice_label.position.y = -20.0
	_root.add_child(_practice_label)

## North-up radar of the arena: teammates always, enemies only while they are firing, pings for a few seconds.
func _build_radar() -> void:
	_radar = Control.new()
	_radar.custom_minimum_size = Vector2(RADAR_SIZE, RADAR_SIZE)
	_radar.size = Vector2(RADAR_SIZE, RADAR_SIZE)
	_radar.position = Vector2(12.0, 12.0)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.draw.connect(_draw_radar)
	_root.add_child(_radar)

func _draw_radar() -> void:
	var center := Vector2(RADAR_SIZE, RADAR_SIZE) * 0.5
	var scale := (RADAR_SIZE * 0.5 - 4.0) / RADAR_RADIUS_METERS
	_radar.draw_circle(center, RADAR_SIZE * 0.5, Color(0.04, 0.07, 0.1, 0.7))
	_radar.draw_arc(center, 125.0 * scale, 0.0, TAU, 48, Color(1.0, 0.85, 0.2, 0.9), 2.0)
	if not radar_provider.is_valid():
		return
	var data: Dictionary = radar_provider.call()
	if data.is_empty():
		return
	var me: Vector3 = data.me
	for point: Vector3 in data.get("pings", []):
		_radar.draw_circle(center + Vector2(point.x - me.x, point.z - me.z).limit_length(RADAR_SIZE * 0.5 - 6.0) * scale, 5.0, Color(1.0, 0.9, 0.3))
	for point: Vector3 in data.get("allies", []):
		_radar.draw_circle(center + Vector2(point.x - me.x, point.z - me.z).limit_length(RADAR_SIZE * 0.5 - 6.0) * scale, 4.0, Color(0.35, 1.0, 0.45))
	for point: Vector3 in data.get("enemies", []):
		_radar.draw_circle(center + Vector2(point.x - me.x, point.z - me.z).limit_length(RADAR_SIZE * 0.5 - 6.0) * scale, 5.0, Color(1.0, 0.25, 0.25))
	_radar.draw_circle(center, 5.0, Color.WHITE)
	var junction := center + Vector2(-me.x, -me.z) * scale
	if center.distance_to(junction) < RADAR_SIZE * 0.5 - 4.0:
		_radar.draw_rect(Rect2(junction - Vector2(3, 3), Vector2(6, 6)), Color(0.8, 0.8, 0.9))

func _build_scoreboard() -> void:
	_scoreboard_button = _button("SCORE", func() -> void: _scoreboard_until = Time.get_ticks_msec() / 1000.0 + SCOREBOARD_SECONDS)
	_scoreboard_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_scoreboard_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_scoreboard_button.position = Vector2(-16.0, 60.0)
	_scoreboard_button.custom_minimum_size = Vector2(110.0, 44.0)
	_root.add_child(_scoreboard_button)
	_scoreboard_panel = _panel()
	_scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard_label = _label("", 18, Color.WHITE)
	_scoreboard_panel.add_child(_scoreboard_label)
	_root.add_child(_scoreboard_panel)

func _build_chat() -> void:
	_chat_button = _button("CHAT", func() -> void: _chat_wheel.visible = not _chat_wheel.visible)
	_chat_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chat_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chat_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_button.position = Vector2(-16.0, -150.0)
	_chat_button.custom_minimum_size = Vector2(110.0, 44.0)
	_root.add_child(_chat_button)
	_chat_wheel = GridContainer.new()
	_chat_wheel.columns = 2
	_chat_wheel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chat_wheel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chat_wheel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_wheel.position = Vector2(-16.0, -204.0)
	for index in Session.CHAT_LINES.size():
		var entry := _button(Session.CHAT_LINES[index], func() -> void:
			_chat_wheel.visible = false
			chat_selected.emit(index))
		entry.custom_minimum_size = Vector2(150.0, 48.0)
		_chat_wheel.add_child(entry)
	_root.add_child(_chat_wheel)

func _build_lobby() -> void:
	_lobby_panel = _panel()
	_lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lobby_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_lobby_panel.add_child(column)
	_lobby_title = _label("TEAM DEATHMATCH", 24, Color(1.0, 0.85, 0.35))
	column.add_child(_lobby_title)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 40)
	column.add_child(teams)
	_red_label = _label("RED", 20, RED_COLOR)
	_red_label.custom_minimum_size = Vector2(240.0, 120.0)
	teams.add_child(_red_label)
	_blue_label = _label("BLUE", 20, BLUE_COLOR)
	_blue_label.custom_minimum_size = Vector2(240.0, 120.0)
	teams.add_child(_blue_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	buttons.add_child(_button("SWAP TEAM", func() -> void: swap_pressed.emit()))
	var ready_button := _button("READY", func() -> void: pass)
	ready_button.pressed.connect(func() -> void:
		_ready_state = not _ready_state
		ready_button.text = "NOT READY" if _ready_state else "READY"
		ready_toggled.emit(_ready_state))
	buttons.add_child(ready_button)
	_lobby_buttons["start"] = _button("START", func() -> void: start_pressed.emit())
	buttons.add_child(_lobby_buttons.start)
	_lobby_buttons["practice"] = _button("PRACTICE", func() -> void: practice_pressed.emit())
	buttons.add_child(_lobby_buttons.practice)
	buttons.add_child(_button("LEAVE", func() -> void: leave_pressed.emit()))
	_lobby_buttons["rematch_hint"] = _label("Waiting for the host to start…", 15, Color(0.8, 0.85, 0.9))
	column.add_child(_lobby_buttons.rematch_hint)
	_root.add_child(_lobby_panel)

func _build_end_screen() -> void:
	_end_panel = _panel()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_end_panel.add_child(column)
	_end_title = _label("RED WINS", 44, Color.WHITE)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_title)
	_end_board = _label("", 18, Color.WHITE)
	column.add_child(_end_board)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	_end_rematch = _button("REMATCH", func() -> void: rematch_pressed.emit())
	buttons.add_child(_end_rematch)
	buttons.add_child(_button("LEAVE", func() -> void: leave_pressed.emit()))
	_root.add_child(_end_panel)

func _board_text(source: Array = []) -> String:
	var board: Array = source if not source.is_empty() else (session.rows if session != null else [])
	var lines: Array[String] = ["TEAM   PLAYER                 K   D   A"]
	var sorted := board.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.kills) > int(b.kills))
	for row: Dictionary in sorted:
		lines.append("%s   %-20s %3d %3d %3d" % ["RED " if int(row.team) == 0 else "BLUE", String(row.nickname).left(20), row.kills, row.deaths, row.assists])
	return "\n".join(lines)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal": Color(0.16, 0.3, 0.45, 0.95), "hover": Color(0.22, 0.4, 0.58, 0.95),
			"pressed": Color(0.1, 0.2, 0.32, 0.95), "disabled": Color(0.15, 0.17, 0.2, 0.8)}[state]
		style.set_corner_radius_all(8)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.93)
	style.border_color = Color(0.3, 0.6, 0.85, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	return panel
