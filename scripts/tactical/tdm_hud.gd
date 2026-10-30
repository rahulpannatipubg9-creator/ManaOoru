extends CanvasLayer

## Everything the player sees in Team Deathmatch: lobby, score bar, kill feed, hit marker, damage arcs,
## boundary warning, death message, scoreboard, quick chat, match menu and the end screen
## (docs/TDM_DESIGN.md, section 5). Pure presentation: it reports button presses through signals and
## reads state from the session; tdm_local.gd does the gameplay.

const Match := preload("res://scripts/tactical/tdm_match.gd")
const Session := preload("res://scripts/tactical/tdm_session.gd")
const Claw := preload("res://scripts/mobile/claw_layout.gd")
const Discovery := preload("res://scripts/network/lan_discovery.gd")

# Look of the match screens, all in one place.
const TEXT := Color("f2f5f6")
const TEXT_MUTED := Color("a9b5bb")
const ACCENT := Color("f5b335")
const HEALTH := Color("4fd18b")
const DANGER := Color("ef5a4c")
const SURFACE := Color(0.05, 0.08, 0.1, 0.72)
const SURFACE_SOLID := Color(0.05, 0.08, 0.1, 0.96)
const LINE := Color(1.0, 1.0, 1.0, 0.14)
const FONT_SMALL := 14
const FONT_BODY := 16
const FONT_LABEL := 18
const FONT_TITLE := 24
const FONT_HERO := 40
const FONT_BANNER := 64
const SPACE_TINY := 4
const SPACE_SMALL := 8
const SPACE_MEDIUM := 16
const SPACE_LARGE := 24
const SPACE_HUGE := 40
const RADIUS := 10
const RED_COLOR := Color(0.95, 0.25, 0.25)
const BLUE_COLOR := Color(0.3, 0.5, 1.0)
const BUTTON_HEIGHT := 56.0
const ROW_HEIGHT := 40.0
const TOUCH_BUTTON_SIZE := Vector2(84.0, 60.0)
## Finger-sized panel buttons on touch, within the game's 7.5 mm rule for phones and tablets alike.
const TOUCH_TARGET_MIN := 60.0
const TOUCH_TARGET_MAX := 79.0
## A full 8v8 lobby must still fit a 720-high landscape screen.
const LOBBY_MAX_ROWS := 8
const LOBBY_CHROME_HEIGHT := 330.0
const LOBBY_ROW_MIN := 48.0
const SCORE_ROW_HEIGHT := 52.0
const FEED_WIDTH := 300.0
const STATUS_WIDTH := 240.0
const WOUND_RISE_PER_SECOND := 2.0
const WOUND_FADE_PER_SECOND := 0.6
const WOUND_MAX := 0.8
const HEARTBEAT_HEALTH := 30.0
const TAG_SECONDS := 0.4
const WOUND_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength = 0.0;
uniform float desaturate = 0.0;
void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	scene = mix(scene, vec3(dot(scene, vec3(0.3, 0.59, 0.11))), desaturate);
	float edge = smoothstep(0.3, 0.75, distance(UV, vec2(0.5)));
	COLOR = vec4(mix(scene, vec3(0.6, 0.02, 0.02), edge * strength), 1.0);
}
"""
## Phones get the red edge without reading the screen back, which costs a full-screen copy every frame.
const WOUND_SHADER_MOBILE := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform float desaturate = 0.0;
void fragment() {
	float edge = smoothstep(0.3, 0.75, distance(UV, vec2(0.5)));
	COLOR = vec4(vec3(0.6, 0.02, 0.02) * (1.0 - desaturate * 0.5), edge * strength);
}
"""
const FEED_LINES := 3
const FEED_SECONDS := 5.0
const SCOREBOARD_SECONDS := 3.0
const CHAT_LINES := 3
const CHAT_SECONDS := 6.0
const HIT_MARKER_SECONDS := 0.18
const ARC_SECONDS := 1.2

signal start_pressed
signal team_requested(team: int)
signal move_requested(peer_id: int)
signal switch_team_pressed
signal practice_pressed
signal leave_pressed
signal rematch_pressed
signal chat_selected(index: int)
signal settings_pressed
signal back_to_lobby_pressed

var session: Node
## func() -> Camera3D used to aim the damage arcs.
var camera_provider: Callable
## func(peer_id) -> Vector3 or Vector3.INF: where an attacker is standing.
var position_provider: Callable
## func() -> Rect2: where the game's minimap sits, so the feed and chat stay clear of it.
var minimap_provider: Callable
## func() -> float: the y the player status must stay above (the touch item bar sits below it).
var status_floor_provider: Callable
## True on phones and tablets: small on-screen buttons replace the Tab, T and Esc keys.
var touch_mode := false:
	set(value):
		if value != touch_mode:
			touch_mode = value
			_apply_touch_sizes()

var _root: Control
var _score_box: PanelContainer
var _red_name: Label
var _blue_name: Label
var _red_score: Label
var _blue_score: Label
var _timer_label: Label
var _goal_label: Label
var _banner: Label
var _banner_until := 0.0
var _notice: Label
var _message: Label
var _message_until := 0.0
var _teammate_tag: Label
var _tag_until := 0.0
var _wound: ColorRect
var _wound_strength := 0.0
var _heartbeat: AudioStreamPlayer
var _feed: VBoxContainer
var _feed_times: Array[float] = []
var _status_box: VBoxContainer
var _health_bar: ProgressBar
var _health_label: Label
var _ammo_label: Label
var _protected_label: Label
var _death_label: Label
var _boundary_label: Label
var _vignette: ColorRect
var _hit_marker: Control
var _arc_layer: Control
var _menu_button: Button
var _scoreboard_button: Button
var _scoreboard_panel: PanelContainer
var _scoreboard_grid: GridContainer
var _scoreboard_until := 0.0
var _chat_button: Button
var _chat_wheel: PanelContainer
var _chat_log: VBoxContainer
var _chat_times: Array[float] = []
var _practice_label: Label
var _lobby_panel: PanelContainer
var _lobby_title: Label
## One entry per team: {header: Label, join: Button, rows: VBoxContainer}.
var _team_columns: Array[Dictionary] = []
var _lobby_buttons: Dictionary = {}
var _menu_panel: PanelContainer
var _menu_back: Button
var _menu_switch: Button
var _end_panel: PanelContainer
var _end_title: Label
var _end_board: GridContainer
var _end_rematch: Button
var _end_shown := false
var _hit_until := 0.0
var _hit_color := Color.WHITE
var _arcs: Array[Dictionary] = []
var _practice := false

func _ready() -> void:
	layer = 20
	name = "TdmHud"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_wound()
	_build_vignette()
	_build_arcs_and_marker()
	_build_score_bar()
	_build_feed()
	_build_status()
	_build_scoreboard()
	_build_chat()
	_build_lobby()
	_build_end_screen()
	_build_menu()
	_root.resized.connect(_layout)
	hide_all()

func setup(p_session: Node) -> void:
	session = p_session
	session.lobby_changed.connect(refresh)
	session.state_changed.connect(func(_s: int) -> void: refresh())

func hide_all() -> void:
	for node: CanvasItem in [_lobby_panel, _end_panel, _menu_panel, _banner, _notice, _message, _teammate_tag, _death_label, _boundary_label,
			_vignette, _wound, _scoreboard_panel, _chat_wheel, _protected_label, _practice_label]:
		node.visible = false
	_banner_until = 0.0
	_message_until = 0.0
	_wound_strength = 0.0
	_heartbeat.stop()
	_end_shown = false
	_root.visible = false

# --- Showing the right thing for the match state ---------------------------------

func refresh() -> void:
	if session == null or not (session.active or _practice):
		hide_all()
		return
	_root.visible = true
	var state: int = session.state
	var playing: bool = _practice or state == Match.State.COUNTDOWN or state == Match.State.LIVE
	var menu := _menu_panel.visible
	_lobby_panel.visible = not _practice and state == Match.State.LOBBY and not menu
	_end_panel.visible = not _practice and state == Match.State.ENDED and not menu
	_score_box.visible = not _practice and state != Match.State.LOBBY
	_status_box.visible = playing
	_ammo_label.visible = not touch_mode
	_menu_button.visible = touch_mode and playing
	var live: bool = not _practice and state == Match.State.LIVE
	_scoreboard_button.visible = touch_mode and live
	_chat_button.visible = touch_mode and live
	if not live:
		_chat_wheel.visible = false
	_practice_label.visible = _practice
	if state == Match.State.LOBBY:
		_end_shown = false
	elif state == Match.State.ENDED and not _end_shown:
		_end_title.text = "MATCH OVER"
		_end_title.add_theme_color_override("font_color", Color.WHITE)
		_end_rematch.visible = session.is_host
		_fill_board(_end_board, session.rows)
	_update_lobby()
	_update_score()
	_layout()

func set_practice(value: bool) -> void:
	_practice = value
	if value:
		_chat_wheel.visible = false
	else:
		_menu_panel.visible = false
	refresh()

func _update_lobby() -> void:
	var red_ready := 0
	var blue_ready := 0
	for row: Dictionary in session.rows:
		if not row.get("connected", true):
			continue
		if int(row.team) == 0:
			red_ready += 1
		else:
			blue_ready += 1
	_fill_team(0)
	_fill_team(1)
	_lobby_title.text = "TEAM DEATHMATCH  •  first to %d  •  %d min" % [session.config.kill_limit(), int(session.config.time_limit_seconds() / 60.0)] \
		if session.config != null else "TEAM DEATHMATCH"
	var can_start := red_ready > 0 and blue_ready > 0
	_lobby_buttons.start.visible = session.is_host
	_lobby_buttons.start.disabled = not can_start
	_lobby_buttons.practice.visible = session.is_host and session.rows.size() <= 1
	var hint: Label = _lobby_buttons.hint
	hint.text = ("Tap a player to move them" if can_start else "Waiting for a player on each team") if session.is_host else "Waiting for the host to start…"
	hint.visible = not hint.text.is_empty()
	var address: Label = _lobby_buttons.address
	var numbers: Array[String] = Discovery.local_ipv4s() if session.is_host else ([] as Array[String])
	address.text = "Room number: %s" % numbers[0] if not numbers.is_empty() else ""
	address.visible = not address.text.is_empty()

## A column of tappable rows: the host taps one to move that player, everyone else just reads them.
func _fill_team(team: int) -> void:
	var column: Dictionary = _team_columns[team]
	var rows: Array = session.rows.filter(func(row: Dictionary) -> bool: return int(row.team) == team)
	var mine: int = session.local_team()
	column.header.text = "%s (%d)" % ["RED" if team == 0 else "BLUE", rows.size()]
	column.join.visible = mine != team
	var box: VBoxContainer = column.rows
	var signature := "%s %s %s" % [rows, session.is_host, lobby_row_height()]
	if box.get_meta("signature", "") == signature:
		return
	box.set_meta("signature", signature)
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		var peer_id := int(row.peer_id)
		var you: bool = peer_id == session.local_id()
		var text := "%s%s%s%s" % [row.nickname, "  (you)" if you else "", "  (host)" if peer_id == Session.HOST_ID else "",
			"" if row.get("connected", true) else "  (dropped)"]
		var entry := _button(text, func() -> void: move_requested.emit(peer_id))
		entry.custom_minimum_size = Vector2(240.0, lobby_row_height())
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.clip_text = true
		entry.add_theme_font_size_override("font_size", FONT_BODY)
		entry.add_theme_color_override("font_disabled_color", TEXT)
		entry.disabled = not session.is_host or you
		box.add_child(entry)

## The finger target for this device, in the canvas units the HUD is laid out in.
func touch_target() -> float:
	var viewport := get_viewport()
	var units := Claw.units_per_mm(viewport.get_visible_rect().size, Vector2(DisplayServer.window_get_size()), float(DisplayServer.screen_get_dpi()))
	return clampf(Claw.min_target(Claw.canvas_safe_rect(viewport), units), TOUCH_TARGET_MIN, TOUCH_TARGET_MAX)

## Rows shrink only as far as a full lobby needs to fit the screen.
func lobby_row_height() -> float:
	if not touch_mode:
		return ROW_HEIGHT
	return clampf((_root.size.y - LOBBY_CHROME_HEIGHT) / LOBBY_MAX_ROWS, LOBBY_ROW_MIN, touch_target())

func _apply_touch_sizes() -> void:
	if not is_node_ready():
		return
	var height := touch_target() if touch_mode else BUTTON_HEIGHT
	for panel: Control in [_lobby_panel, _menu_panel, _end_panel, _chat_wheel]:
		for button: Node in panel.find_children("*", "Button", true, false):
			button.custom_minimum_size.y = height

func team_color(team: int) -> Color:
	return RED_COLOR if team == 0 else BLUE_COLOR

func _update_score() -> void:
	var mine: int = session.local_team()
	_red_name.text = "YOU  RED" if mine == 0 else "RED"
	_blue_name.text = "BLUE  YOU" if mine == 1 else "BLUE"
	_red_score.text = str(session.red_score)
	_blue_score.text = str(session.blue_score)
	_goal_label.visible = session.sudden_death

func _process(delta: float) -> void:
	if not _root.visible:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if session != null and session.active:
		_timer_label.text = _clock(session.time_left) if session.state != Match.State.COUNTDOWN else "--:--"
		_update_score()
		var counting: bool = session.state == Match.State.COUNTDOWN
		if counting:
			_banner.text = str(maxi(1, ceili(session.countdown_left)))
		_banner.visible = counting or now < _banner_until
		var mine: Dictionary = session.vitals.get(session.local_id(), {})
		_protected_label.visible = bool(mine.get("protected", false)) and bool(mine.get("alive", false))
		var health := float(mine.get("hp", _health_bar.value))
		_set_health(health)
		_update_wounds(health, bool(mine.get("alive", false)), delta)
	_message.visible = now < _message_until
	_teammate_tag.visible = now < _tag_until
	_fade_lines(_feed, _feed_times, now, FEED_SECONDS)
	_fade_lines(_chat_log, _chat_times, now, CHAT_SECONDS)
	var board_held: bool = Input.is_key_pressed(KEY_TAB) and _score_box.visible and not _menu_panel.visible
	_scoreboard_panel.visible = board_held or (now < _scoreboard_until and not _menu_panel.visible)
	if _scoreboard_panel.visible and session != null:
		_fill_board(_scoreboard_grid, session.rows)
	_hit_marker.visible = now < _hit_until
	_hit_marker.queue_redraw()
	_arcs = _arcs.filter(func(arc: Dictionary) -> bool: return now - float(arc.at) < ARC_SECONDS)
	_arc_layer.visible = not _arcs.is_empty()
	_arc_layer.queue_redraw()
	_layout()

func _input(event: InputEvent) -> void:
	if not _root.visible or touch_mode or session == null or _practice or _menu_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T and session.state == Match.State.LIVE:
		toggle_chat()
		get_viewport().set_input_as_handled()

static func _clock(seconds: float) -> String:
	var whole := maxi(0, ceili(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]

func _set_health(value: float) -> void:
	_health_bar.value = value
	_health_label.text = str(ceili(value))

## The screen is the main health signal: the edges redden with missing health and clear as it comes back;
## near death the colour drains and a heartbeat starts. The host owns the number; this only shows it.
func _update_wounds(health: float, alive: bool, delta: float) -> void:
	var live: bool = alive and session.state == Match.State.LIVE
	var target := (1.0 - health / _health_bar.max_value) * WOUND_MAX if live else 0.0
	_wound_strength = move_toward(_wound_strength, target, delta * (WOUND_RISE_PER_SECOND if target > _wound_strength else WOUND_FADE_PER_SECOND))
	_wound.visible = _wound_strength > 0.01
	var critical: bool = live and health < HEARTBEAT_HEALTH
	if _wound.visible:
		var material := _wound.material as ShaderMaterial
		material.set_shader_parameter("strength", _wound_strength)
		material.set_shader_parameter("desaturate", 0.7 * clampf(1.0 - health / HEARTBEAT_HEALTH, 0.0, 1.0) if critical else 0.0)
	if critical != _heartbeat.playing:
		if critical:
			_heartbeat.play()
		else:
			_heartbeat.stop()

func _fade_lines(box: Control, times: Array[float], now: float, lifetime: float) -> void:
	while not times.is_empty() and now - times[0] > lifetime:
		times.pop_front()
		box.get_child(0).queue_free()
		box.remove_child(box.get_child(0))

# --- Placing everything for the current screen ------------------------------------

## Positions are worked out here rather than with anchors, so nothing can land off screen and the
## kill feed and chat move out of the way of the minimap, which changes corner between desktop and touch.
func _layout() -> void:
	var view := _root.size
	var safe := Rect2(Vector2.ZERO, view)
	if touch_mode:
		safe = Claw.canvas_safe_rect(get_viewport()).intersection(safe)
	var minimap: Rect2 = minimap_provider.call() if minimap_provider.is_valid() else Rect2()
	var map_on_top := minimap.has_area() and minimap.position.y < view.y * 0.5
	var map_on_right := minimap.has_area() and minimap.get_center().x > view.x * 0.5

	_score_box.reset_size()
	_score_box.position = Vector2((view.x - _score_box.size.x) * 0.5, safe.position.y + SPACE_SMALL)
	_center_line(_goal_label, _score_box.position.y + _score_box.size.y + 2.0)
	var below_score := _score_box.position.y + SCORE_ROW_HEIGHT + 22.0

	var x := safe.position.x + SPACE_SMALL
	for button: Button in [_menu_button, _scoreboard_button, _chat_button]:
		button.size = TOUCH_BUTTON_SIZE
		button.position = Vector2(x, safe.position.y + SPACE_SMALL)
		x += TOUCH_BUTTON_SIZE.x + 8.0

	var feed_right := safe.end.x - SPACE_SMALL
	if map_on_top and map_on_right:
		feed_right = minimap.position.x - SPACE_SMALL
	_feed.position = Vector2(feed_right - FEED_WIDTH, below_score)

	_chat_log.reset_size()
	if minimap.has_area() and not map_on_top:
		_chat_log.position = Vector2(minimap.position.x, minimap.position.y - 8.0 - _chat_log.size.y)
	else:
		_chat_log.position = Vector2(safe.position.x + SPACE_SMALL, safe.position.y + SPACE_SMALL + TOUCH_BUTTON_SIZE.y + 8.0)

	var status_floor: float = status_floor_provider.call() if status_floor_provider.is_valid() else -1.0
	if status_floor < 0.0:
		status_floor = safe.end.y - SPACE_SMALL
	_status_box.reset_size()
	_status_box.position = Vector2((view.x - STATUS_WIDTH) * 0.5, status_floor - _status_box.size.y)
	_center_line(_practice_label, _score_box.position.y + 4.0)
	_center_line(_notice, view.y * 0.28)
	_center_line(_message, view.y * 0.2)
	_center_line(_teammate_tag, view.y * 0.5 + SPACE_LARGE)
	_center_line(_boundary_label, below_score)
	_center_line(_death_label, view.y * 0.62)

func _center_line(label: Label, y: float) -> void:
	label.position = Vector2(0.0, y)
	label.size.x = _root.size.x

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
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(FEED_WIDTH, 26.0)
	line.add_theme_font_size_override("normal_font_size", FONT_BODY)
	var color := "#dddddd" if killer_team < 0 else ("#ff5555" if killer_team == 0 else "#5588ff")
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
	line.add_theme_font_size_override("font_size", FONT_BODY)
	line.add_theme_color_override("font_color", team_color(team))
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	line.add_theme_constant_override("outline_size", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log.add_child(line)
	_chat_times.append(Time.get_ticks_msec() / 1000.0)
	while _chat_log.get_child_count() > CHAT_LINES:
		_chat_log.get_child(0).queue_free()
		_chat_log.remove_child(_chat_log.get_child(0))
		_chat_times.pop_front()

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
	_banner_until = Time.get_ticks_msec() / 1000.0 + seconds

func show_switching(seconds: float) -> void:
	_death_label.text = "Switching team  •  respawning in %d" % ceili(seconds)
	_death_label.visible = true

## A short message that clears itself, such as a refused team move.
func show_message(text: String, seconds: float, color := TEXT) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = true
	_message_until = Time.get_ticks_msec() / 1000.0 + seconds

## Held on for a moment, so sweeping past a teammate does not flicker.
func set_teammate_tag(on: bool) -> void:
	if on:
		_tag_until = Time.get_ticks_msec() / 1000.0 + TAG_SECONDS

## A message that stays up until it is cleared with "", such as a lost connection.
func set_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = not text.is_empty()

func set_practice_stats(hits: int, headshots: int, shots: int) -> void:
	var accuracy := 0 if shots == 0 else roundi(100.0 * hits / shots)
	_practice_label.text = "PRACTICE  •  hits %d  •  headshots %d  •  accuracy %d%%" % [hits, headshots, accuracy]

func set_ammo(rifle: String, ammo: int, magazine: int, reloading: bool) -> void:
	_ammo_label.text = "%s   RELOADING" % rifle if reloading else "%s   %d / %d" % [rifle, ammo, magazine]
	_ammo_label.add_theme_color_override("font_color", DANGER if ammo <= 5 and not reloading else TEXT)

func show_end(winner: int, rows: Array) -> void:
	var result := "DRAW" if winner < 0 else ("RED WINS" if winner == 0 else "BLUE WINS")
	_end_shown = true
	_end_title.text = result
	_end_title.add_theme_color_override("font_color", Color.WHITE if winner < 0 else (RED_COLOR if winner == 0 else BLUE_COLOR))
	_fill_board(_end_board, rows)
	_end_rematch.visible = session != null and session.is_host
	_menu_panel.visible = false
	_end_panel.visible = true

func toggle_chat() -> void:
	_chat_wheel.visible = not _chat_wheel.visible

## The Esc menu. An open chat wheel closes first, as players expect from Esc.
func toggle_menu() -> void:
	if _chat_wheel.visible:
		_chat_wheel.visible = false
	elif _menu_panel.visible:
		close_menu()
	else:
		_menu_back.visible = _practice
		_menu_switch.visible = not _practice and session != null and session.state == Match.State.LIVE
		_menu_panel.visible = true
		refresh()

func close_menu() -> void:
	_menu_panel.visible = false
	refresh()

func menu_open() -> bool:
	return _menu_panel.visible

## True while a panel over the live game needs the cursor.
func overlay_open() -> bool:
	return _menu_panel.visible or _chat_wheel.visible

# --- Building the controls ---------------------------------------------------------

func _build_wound() -> void:
	_wound = ColorRect.new()
	_wound.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wound.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = WOUND_SHADER_MOBILE if OS.has_feature("mobile") else WOUND_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_wound.material = material
	_root.add_child(_wound)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = _heartbeat_sound()
	_heartbeat.volume_db = -6.0
	add_child(_heartbeat)

## Lub-dub, once a second: two low decaying thumps, generated so no asset is needed.
static func _heartbeat_sound() -> AudioStreamWAV:
	const RATE := 22050
	var samples := PackedByteArray()
	samples.resize(RATE * 2)
	for index in RATE:
		var time := float(index) / RATE
		var value := sin(TAU * 55.0 * time) * exp(-time * 16.0)
		if time >= 0.3:
			value += 0.7 * sin(TAU * 48.0 * (time - 0.3)) * exp(-(time - 0.3) * 16.0)
		samples.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = RATE
	return stream

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

## Screen angle (0 = right, clockwise) of the arc for an attacker at `offset` from the camera, on the
## ground plane, with `forward` the camera's ground direction. Straight ahead is the top of the ring.
static func arc_angle(forward: Vector2, offset: Vector2) -> float:
	return forward.angle_to(offset.normalized()) - PI * 0.5

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
		var fade := 1.0 - (now - float(arc.at)) / ARC_SECONDS
		var start := arc_angle(forward, offset) - 0.35
		_arc_layer.draw_arc(center, radius, start, start + 0.7, 16, Color(1.0, 0.1, 0.1, clampf(fade, 0.0, 1.0)), 8.0)

## One line: RED 0  9:59  0 BLUE.
func _build_score_bar() -> void:
	_score_box = PanelContainer.new()
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.set_corner_radius_all(RADIUS)
	style.content_margin_left = SPACE_MEDIUM
	style.content_margin_right = SPACE_MEDIUM
	style.content_margin_top = SPACE_TINY
	style.content_margin_bottom = SPACE_TINY
	_score_box.add_theme_stylebox_override("panel", style)
	_root.add_child(_score_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_MEDIUM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_box.add_child(row)
	_red_name = _label("RED", FONT_LABEL, RED_COLOR)
	row.add_child(_red_name)
	_red_score = _label("0", FONT_TITLE, TEXT)
	row.add_child(_red_score)
	_timer_label = _label("10:00", FONT_TITLE, ACCENT)
	_timer_label.custom_minimum_size.x = 64.0
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_timer_label)
	_blue_score = _label("0", FONT_TITLE, TEXT)
	row.add_child(_blue_score)
	_blue_name = _label("BLUE", FONT_LABEL, BLUE_COLOR)
	row.add_child(_blue_name)
	_goal_label = _label("SUDDEN DEATH", FONT_SMALL, DANGER)
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_goal_label)

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)
	_chat_log = VBoxContainer.new()
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chat_log)

func _build_status() -> void:
	_status_box = VBoxContainer.new()
	_status_box.custom_minimum_size.x = STATUS_WIDTH
	_status_box.add_theme_constant_override("separation", SPACE_TINY)
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status_box)
	_protected_label = _label("🛡 PROTECTED", FONT_BODY, Color(0.5, 0.95, 1.0))
	_protected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_box.add_child(_protected_label)
	_ammo_label = _label("", FONT_LABEL, TEXT)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_box.add_child(_ammo_label)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", SPACE_SMALL)
	health_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_child(health_row)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(0.0, SPACE_SMALL)
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = SURFACE
	track.set_corner_radius_all(SPACE_TINY)
	_health_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HEALTH
	fill.set_corner_radius_all(SPACE_TINY)
	_health_bar.add_theme_stylebox_override("fill", fill)
	health_row.add_child(_health_bar)
	_health_label = _label("100", FONT_SMALL, TEXT)
	_health_label.custom_minimum_size.x = 30.0
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_row.add_child(_health_label)
	_banner = _label("3", FONT_BANNER, TEXT)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_root.add_child(_banner)
	_notice = _centered_label(FONT_TITLE, ACCENT)
	_message = _centered_label(FONT_TITLE, TEXT)
	_teammate_tag = _centered_label(FONT_SMALL, HEALTH)
	_teammate_tag.text = "Teammate"
	_death_label = _centered_label(FONT_TITLE, TEXT)
	_boundary_label = _centered_label(FONT_TITLE, DANGER)
	_practice_label = _centered_label(FONT_LABEL, ACCENT)

func _centered_label(size: int, color: Color) -> Label:
	var label := _label("", size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	return label

func _small_button(text: String, action: Callable) -> Button:
	var button := _button(text, action)
	button.custom_minimum_size = TOUCH_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", FONT_SMALL)
	_root.add_child(button)
	return button

func _build_scoreboard() -> void:
	_menu_button = _small_button("MENU", toggle_menu)
	_scoreboard_button = _small_button("SCORE", func() -> void: _scoreboard_until = Time.get_ticks_msec() / 1000.0 + SCOREBOARD_SECONDS)
	_scoreboard_panel = _panel()
	_scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_grid = _board_grid()
	_scoreboard_panel.add_child(_scoreboard_grid)
	_root.add_child(_scoreboard_panel)

func _build_chat() -> void:
	_chat_button = _small_button("CHAT", toggle_chat)
	_chat_wheel = _panel()
	_chat_wheel.set_anchors_preset(Control.PRESET_CENTER)
	_chat_wheel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chat_wheel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", SPACE_SMALL)
	grid.add_theme_constant_override("v_separation", SPACE_SMALL)
	_chat_wheel.add_child(grid)
	for index in Session.CHAT_LINES.size():
		var entry := _button(Session.CHAT_LINES[index], func() -> void:
			_chat_wheel.visible = false
			chat_selected.emit(index))
		entry.custom_minimum_size = Vector2(170.0, 48.0)
		grid.add_child(entry)
	_root.add_child(_chat_wheel)

func _build_lobby() -> void:
	_lobby_panel = _panel()
	_lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lobby_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", SPACE_SMALL)
	_lobby_panel.add_child(column)
	_lobby_title = _label("TEAM DEATHMATCH", FONT_TITLE, ACCENT)
	column.add_child(_lobby_title)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", SPACE_LARGE)
	column.add_child(teams)
	for team in 2:
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", SPACE_SMALL)
		teams.add_child(side)
		var header := _label("", FONT_LABEL, team_color(team))
		side.add_child(header)
		var rows := VBoxContainer.new()
		rows.custom_minimum_size = Vector2(240.0, ROW_HEIGHT * 2.0)
		rows.add_theme_constant_override("separation", SPACE_TINY)
		side.add_child(rows)
		var join := _button("JOIN %s" % ("RED" if team == 0 else "BLUE"), func() -> void: team_requested.emit(team))
		join.custom_minimum_size.y = ROW_HEIGHT + SPACE_SMALL
		side.add_child(join)
		_team_columns.append({"header": header, "join": join, "rows": rows})
	_lobby_buttons["hint"] = _label("", FONT_SMALL, TEXT_MUTED)
	column.add_child(_lobby_buttons.hint)
	_lobby_buttons["address"] = _label("", FONT_SMALL, TEXT_MUTED)
	column.add_child(_lobby_buttons.address)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", SPACE_SMALL)
	column.add_child(buttons)
	_lobby_buttons["start"] = _button("START", func() -> void: start_pressed.emit())
	buttons.add_child(_lobby_buttons.start)
	_lobby_buttons["practice"] = _button("PRACTICE", func() -> void: practice_pressed.emit())
	buttons.add_child(_lobby_buttons.practice)
	buttons.add_child(_button("LEAVE", func() -> void: leave_pressed.emit()))
	_root.add_child(_lobby_panel)

func _build_end_screen() -> void:
	_end_panel = _panel()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", SPACE_SMALL)
	_end_panel.add_child(column)
	_end_title = _label("MATCH OVER", FONT_HERO, TEXT)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_title)
	_end_board = _board_grid()
	column.add_child(_end_board)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", SPACE_SMALL)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	_end_rematch = _button("REMATCH", func() -> void: rematch_pressed.emit())
	buttons.add_child(_end_rematch)
	buttons.add_child(_button("LEAVE", func() -> void: leave_pressed.emit()))
	_root.add_child(_end_panel)

func _build_menu() -> void:
	_menu_panel = _panel()
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 260.0
	column.add_theme_constant_override("separation", SPACE_SMALL)
	_menu_panel.add_child(column)
	column.add_child(_button("RESUME", close_menu))
	column.add_child(_button("SETTINGS", func() -> void:
		close_menu()
		settings_pressed.emit()))
	_menu_back = _button("BACK TO LOBBY", func() -> void:
		close_menu()
		back_to_lobby_pressed.emit())
	column.add_child(_menu_back)
	_menu_switch = _button("SWITCH TEAM", func() -> void:
		close_menu()
		switch_team_pressed.emit())
	column.add_child(_menu_switch)
	column.add_child(_button("LEAVE MATCH", func() -> void: leave_pressed.emit()))
	_root.add_child(_menu_panel)

func _board_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", SPACE_LARGE)
	grid.add_theme_constant_override("v_separation", SPACE_TINY)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grid

## Red first then Blue, best players on top of each team.
static func board_order(source: Array) -> Array:
	var sorted := source.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.team) != int(b.team):
			return int(a.team) < int(b.team)
		return int(a.kills) > int(b.kills))
	return sorted

## One real column per value: a proportional font cannot line up text padded with spaces.
func _fill_board(grid: GridContainer, source: Array) -> void:
	var signature := str(source)
	if grid.get_meta("signature", "") == signature:
		return
	grid.set_meta("signature", signature)
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for title in ["PLAYER", "K", "D", "A"]:
		grid.add_child(_label(title, FONT_SMALL, TEXT_MUTED))
	for row: Dictionary in board_order(source):
		var mine: bool = session != null and int(row.peer_id) == session.local_id()
		var color := RED_COLOR if int(row.team) == 0 else BLUE_COLOR
		var player := "%s%s" % [String(row.nickname).left(20), "  (you)" if mine else ""]
		var name_label := _label(player, FONT_LABEL, color)
		name_label.custom_minimum_size.x = 240.0
		grid.add_child(name_label)
		for value in [row.kills, row.deaths, row.assists]:
			grid.add_child(_label(str(value), FONT_LABEL, TEXT))

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
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", FONT_LABEL)
	button.add_theme_color_override("font_color", TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal": SURFACE_SOLID.lightened(0.08), "hover": SURFACE_SOLID.lightened(0.18),
			"pressed": SURFACE_SOLID, "disabled": SURFACE}[state]
		style.border_color = LINE
		style.set_border_width_all(1)
		style.set_corner_radius_all(RADIUS)
		style.set_content_margin_all(SPACE_SMALL)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE_SOLID
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS)
	style.set_content_margin_all(SPACE_LARGE)
	panel.add_theme_stylebox_override("panel", style)
	return panel
