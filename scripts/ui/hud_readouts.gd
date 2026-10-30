extends Control

## Everything the HUD shows that is not a touch button: vitals, ammo, speed, wanted stars,
## objective, the prompt pill and coin pop-ups. Each part appears when it matters and fades
## out again (docs/reference/UI_DESIGN.md, "HUD states"); this node owns those rules and
## hud.gd just feeds it numbers.

const Icons := preload("res://scripts/ui/hud_icons.gd")
## Vitals stay this long after a change once health is back to full.
const VITALS_HOLD := 4.0
const COIN_SECONDS := 1.6
const LOW_SHARE := 0.3
const LOW_MAGAZINE := 5
const RPM_RED_SHARE := 0.88
const FUEL_LOW := 20.0
const WANTED_MAX := 5
const BAR_HEIGHT := 6.0
const STAR_SIZE := 22.0
const OBJECTIVE_WIDTH := 280.0

var health := 100.0
var max_health := 100.0
var armour := 0.0
var mag := 0
var reserve := 0
var weapon_name := ""
var wanted := 0
var speed_kmh := 0.0
var gear_label := ""
var rpm := 0.0
## Engine speed that fills the rev bar: the vehicle's redline.
var rpm_full := 6500.0
var automatic := true
var altitude := 0.0
var fuel := 100.0

## What the player is doing now, set by hud.gd every frame.
var rifle_out := false
var driving := false
var flying := false
## The full map or a match replaces all of this.
var suppressed := false

var prompt_root: CenterContainer
var _pill: PanelContainer
var _key_box: PanelContainer
var _key_label: Label
var _prompt_label: Label
var _prompt_text := ""
var _vitals: Control
var _ammo: Control
var _drive: Control
var _wanted: Control
var _objective: PanelContainer
var _objective_title: Label
var _objective_detail: Label
var _objective_area := Rect2()
var _coins: Label
var _coin_sum := 0
var _coin_left := 0.0
var _vitals_left := 0.0
var _touch := false
var _left_aligned := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vitals = _part("Vitals", _draw_vitals)
	_ammo = _part("Ammo", _draw_ammo)
	_drive = _part("Drive", _draw_drive)
	_wanted = _part("Wanted", _draw_wanted)
	_build_objective()
	_coins = _label(UiTheme.FONT_LABEL, UiTheme.ACCENT)
	_coins.name = "Coins"
	_coins.visible = false
	add_child(_coins)

func _part(part_name: String, painter: Callable) -> Control:
	var part := Control.new()
	part.name = part_name
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	part.visible = false
	part.modulate.a = 0.0
	part.draw.connect(painter.bind(part))
	add_child(part)
	return part

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_objective() -> void:
	_objective = PanelContainer.new()
	_objective.name = "Objective"
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE))
	_objective.visible = false
	_objective.modulate.a = 0.0
	add_child(_objective)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	_objective.add_child(rows)
	_objective_title = _label(UiTheme.FONT_BODY, UiTheme.TEXT)
	_objective_detail = _label(UiTheme.FONT_SMALL, UiTheme.TEXT_MUTED)
	for row: Label in [_objective_title, _objective_detail]:
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(row)

## The pill sits directly under the HUD so other systems can find "InteractionPrompt" by name.
func build_prompt(parent: Node) -> void:
	prompt_root = CenterContainer.new()
	prompt_root.name = "InteractionPrompt"
	prompt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_root.visible = false
	prompt_root.modulate.a = 0.0
	parent.add_child(prompt_root)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, UiTheme.RADIUS_PILL))
	prompt_root.add_child(_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_S)
	_pill.add_child(row)
	_key_box = PanelContainer.new()
	var key_style := UiTheme.box(UiTheme.ACCENT, 6)
	key_style.set_content_margin_all(2)
	key_style.content_margin_left = UiTheme.SPACE_S
	key_style.content_margin_right = UiTheme.SPACE_S
	_key_box.add_theme_stylebox_override("panel", key_style)
	row.add_child(_key_box)
	_key_label = Label.new()
	_key_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_key_label.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	_key_box.add_child(_key_label)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	row.add_child(_prompt_label)

## Shows one line, or nothing at all. On touch the key hint is dropped: a button does the job.
func set_prompt(value: String) -> void:
	if value == _prompt_text:
		return
	_prompt_text = value
	if value.is_empty():
		return # The old words stay on the pill while it fades.
	var parts := split_prompt(value)
	_key_label.text = parts[0]
	_key_box.visible = not parts[0].is_empty() and not _touch
	_prompt_label.text = parts[1]

func prompt() -> String:
	return _prompt_text

## "[E]  ENTER Thar_Truck" -> ["E", "ENTER Thar Truck"]. A line without a key has an empty first part.
static func split_prompt(value: String) -> PackedStringArray:
	var text := value.strip_edges()
	var key := ""
	if text.begins_with("["):
		var end := text.find("]")
		if end > 1:
			key = text.substr(1, end - 1)
			text = text.substr(end + 1).strip_edges()
	return PackedStringArray([key, text.replace("_", " ")])

func set_vitals(value: float, maximum: float, armour_value: float) -> void:
	maximum = maxf(maximum, 1.0)
	value = clampf(value, 0.0, maximum)
	armour_value = clampf(armour_value, 0.0, 100.0)
	if is_equal_approx(value, health) and is_equal_approx(maximum, max_health) and is_equal_approx(armour_value, armour):
		return
	health = value
	max_health = maximum
	armour = armour_value
	_vitals_left = VITALS_HOLD
	_vitals.queue_redraw()

func set_ammo(magazine: int, spare: int, name_text: String) -> void:
	if magazine != mag or spare != reserve or name_text != weapon_name:
		mag = magazine
		reserve = spare
		weapon_name = name_text
		_ammo.queue_redraw()

func set_wanted(level: int) -> void:
	level = clampi(level, 0, WANTED_MAX)
	if level != wanted:
		wanted = level
		_wanted.queue_redraw()

func set_objective(title: String, detail: String) -> void:
	_objective_title.text = title
	_objective_detail.text = detail
	_objective_detail.visible = not detail.is_empty()
	_place_objective()

func clear_objective() -> void:
	_objective_title.text = ""
	_objective_detail.text = ""

func objective_title() -> String:
	return _objective_title.text

func set_speed(value: float) -> void:
	if roundi(value) != roundi(speed_kmh):
		_drive.queue_redraw()
	speed_kmh = value

func set_gear(label_text: String, engine_rpm: float, is_automatic: bool) -> void:
	if label_text != gear_label or absf(engine_rpm - rpm) > 40.0 or is_automatic != automatic:
		_drive.queue_redraw()
	gear_label = label_text
	rpm = engine_rpm
	automatic = is_automatic

func set_altitude(value: float) -> void:
	if roundi(value) != roundi(altitude):
		_drive.queue_redraw()
	altitude = value

func set_fuel(percent: float) -> void:
	if (percent < FUEL_LOW) != (fuel < FUEL_LOW) or (percent < FUEL_LOW and roundi(percent) != roundi(fuel)):
		_drive.queue_redraw()
	fuel = percent

## Small "+5" beside the map. Coins arriving together add up rather than stack.
func show_coin_delta(amount: int) -> void:
	if amount == 0:
		return
	_coin_sum = (_coin_sum if _coin_left > 0.0 else 0) + amount
	_coin_left = COIN_SECONDS
	_coins.text = "%+d" % _coin_sum
	_coins.add_theme_color_override("font_color", UiTheme.ACCENT if _coin_sum > 0 else UiTheme.DANGER)

## Places every part from the screen's layout rectangles (built in hud.gd).
func place(rects: Dictionary, touch: bool) -> void:
	_touch = touch
	_left_aligned = rects.Objective.get_center().x < size.x * 0.5
	_set_rect(_vitals, rects.Vitals)
	_set_rect(_wanted, rects.Wanted)
	_set_rect(_ammo, rects.Readout)
	_set_rect(_drive, rects.Readout)
	_objective_area = rects.Objective
	_place_objective()
	_coins.position = rects.Coins.position
	_set_rect(prompt_root, rects.Prompt)
	_key_box.visible = not _key_label.text.is_empty() and not _touch
	for part: Control in [_vitals, _ammo, _drive, _wanted]:
		part.queue_redraw()

func _set_rect(part: Control, rect: Rect2) -> void:
	part.position = rect.position
	part.size = rect.size

func _place_objective() -> void:
	var width := minf(_objective_area.size.x, OBJECTIVE_WIDTH)
	_objective.custom_minimum_size.x = width
	_objective.size = Vector2(width, 0.0)
	var x := _objective_area.position.x if _left_aligned else _objective_area.end.x - width
	_objective.position = Vector2(x, _objective_area.position.y)

## Which parts the state table wants on screen right now.
func wanted_parts() -> Dictionary:
	var hide_all := suppressed
	return {
		_vitals: not hide_all and (health < max_health or rifle_out or _vitals_left > 0.0),
		_ammo: not hide_all and rifle_out and not driving,
		_drive: not hide_all and driving,
		_wanted: not hide_all and wanted > 0,
		_objective: not hide_all and not _objective_title.text.is_empty(),
		prompt_root: not hide_all and not _prompt_text.is_empty(),
	}

## True when the named part ("Vitals", "Ammo", "Drive", "Wanted", "Objective", "InteractionPrompt") is on screen.
func is_showing(part_name: String) -> bool:
	for part: Control in wanted_parts():
		if part.name == part_name:
			return part.visible
	return false

## Advances fades and timers. Timers hold still while the game is paused.
func tick(delta: float, paused := false) -> void:
	var clock := 0.0 if paused else delta
	_vitals_left = maxf(0.0, _vitals_left - clock)
	var parts := wanted_parts()
	for part: Control in parts:
		_fade(part, parts[part], delta)
	_tick_coins(clock)

func _fade(part: Control, show_part: bool, delta: float) -> void:
	part.modulate.a = move_toward(part.modulate.a, 1.0 if show_part else 0.0, delta / UiTheme.MOTION_NORMAL)
	var seen := part.modulate.a > 0.0
	if part.visible != seen:
		part.visible = seen

func _tick_coins(delta: float) -> void:
	_coin_left = maxf(0.0, _coin_left - delta)
	var seen := _coin_left > 0.0 and not suppressed
	if _coins.visible != seen:
		_coins.visible = seen
	if seen:
		_coins.modulate.a = clampf(_coin_left / UiTheme.MOTION_NORMAL, 0.0, 1.0)

func _draw_vitals(part: Control) -> void:
	var share := health / max_health
	var y := 0.0
	_bar(part, y, share, UiTheme.DANGER if share <= LOW_SHARE else UiTheme.HEALTH, &"health")
	if armour > 0.0:
		y += _icon_size() + UiTheme.SPACE_XS
		_bar(part, y, armour / 100.0, UiTheme.ARMOUR, &"armour")

func _icon_size() -> float:
	return BAR_HEIGHT * 2.4

func _bar(part: Control, y: float, share: float, tint: Color, icon: StringName) -> void:
	var icon_size := _icon_size()
	var middle := y + icon_size * 0.5
	Icons.paint(part, icon, Vector2(icon_size * 0.5, middle), icon_size, tint)
	var left := icon_size + UiTheme.SPACE_S
	var track := Rect2(left, middle - BAR_HEIGHT * 0.5, part.size.x - left, BAR_HEIGHT)
	part.draw_style_box(_flat(UiTheme.SURFACE), track)
	if share > 0.0:
		part.draw_style_box(_flat(tint), Rect2(track.position, Vector2(maxf(track.size.x * share, BAR_HEIGHT), BAR_HEIGHT)))

func _flat(fill: Color) -> StyleBoxFlat:
	var style := UiTheme.box(fill, UiTheme.RADIUS_PILL)
	style.set_content_margin_all(0)
	return style

## A run of text and icon pieces, kept together: right-aligned on desktop, centred on touch.
## Each piece is {text or icon, size, color, gap (optional, before it)}.
func _draw_row(part: Control, pieces: Array[Dictionary], baseline: float) -> void:
	var font := UiTheme.font()
	var widths: Array[float] = []
	var total := 0.0
	for piece in pieces:
		var width: float = float(piece.size) if piece.has("icon") else font.get_string_size(piece.text, HORIZONTAL_ALIGNMENT_LEFT, -1, piece.size).x
		widths.append(width)
		total += width + float(piece.get("gap", 0.0))
	var x := (part.size.x - total) * 0.5 if _touch else part.size.x - total
	for i in pieces.size():
		var piece := pieces[i]
		x += float(piece.get("gap", 0.0))
		if piece.has("icon"):
			Icons.paint(part, piece.icon, Vector2(x + widths[i] * 0.5, baseline - float(piece.size) * 0.4), float(piece.size), piece.color)
		else:
			part.draw_string(font, Vector2(x + 1.0, baseline + 1.0), piece.text, HORIZONTAL_ALIGNMENT_LEFT, -1, piece.size, Color(0, 0, 0, 0.6))
			part.draw_string(font, Vector2(x, baseline), piece.text, HORIZONTAL_ALIGNMENT_LEFT, -1, piece.size, piece.color)
		x += widths[i]

func _draw_ammo(part: Control) -> void:
	var pieces: Array[Dictionary] = [
		{"text": weapon_name, "size": UiTheme.FONT_SMALL, "color": UiTheme.TEXT_MUTED},
		{"text": str(mag), "size": UiTheme.FONT_DISPLAY, "color": UiTheme.DANGER if mag <= LOW_MAGAZINE else UiTheme.TEXT, "gap": float(UiTheme.SPACE_S)},
		{"text": "/ %d" % reserve, "size": UiTheme.FONT_LABEL, "color": UiTheme.TEXT_MUTED, "gap": float(UiTheme.SPACE_S)},
	]
	_draw_row(part, pieces, part.size.y - UiTheme.SPACE_XS)

func _draw_drive(part: Control) -> void:
	var pieces: Array[Dictionary] = []
	if fuel < FUEL_LOW and not flying:
		pieces.append({"icon": &"fuel", "size": 16, "color": UiTheme.DANGER})
		pieces.append({"text": "%d%%" % roundi(fuel), "size": UiTheme.FONT_SMALL, "color": UiTheme.DANGER, "gap": float(UiTheme.SPACE_XS)})
	var gap := float(UiTheme.SPACE_M) if not pieces.is_empty() else 0.0
	pieces.append({"text": str(roundi(speed_kmh)), "size": UiTheme.FONT_DISPLAY, "color": UiTheme.TEXT, "gap": gap})
	pieces.append({"text": "km/h", "size": UiTheme.FONT_SMALL, "color": UiTheme.TEXT_MUTED, "gap": float(UiTheme.SPACE_XS)})
	var side_text := ("%d m" % roundi(altitude)) if flying else gear_label
	pieces.append({"text": side_text, "size": UiTheme.FONT_LABEL, "color": UiTheme.ACCENT, "gap": float(UiTheme.SPACE_M)})
	var rev_room := 0.0 if flying else BAR_HEIGHT + UiTheme.SPACE_S
	_draw_row(part, pieces, part.size.y - rev_room - UiTheme.SPACE_XS)
	if flying:
		return
	var width := minf(part.size.x, 200.0)
	var left := (part.size.x - width) * 0.5 if _touch else part.size.x - width
	var track := Rect2(left, part.size.y - BAR_HEIGHT, width, BAR_HEIGHT)
	part.draw_style_box(_flat(UiTheme.SURFACE), track)
	var share := clampf(rpm / rpm_full, 0.0, 1.0)
	if share > 0.0:
		var tint := UiTheme.DANGER if share > RPM_RED_SHARE else UiTheme.TEXT
		part.draw_style_box(_flat(tint), Rect2(track.position, Vector2(maxf(track.size.x * share, BAR_HEIGHT), BAR_HEIGHT)))

func _draw_wanted(part: Control) -> void:
	# Only the earned stars: the empty ones would be noise on a calm screen.
	var x := part.size.x - STAR_SIZE if _left_aligned else 0.0
	var step := -(STAR_SIZE + UiTheme.SPACE_XS) if _left_aligned else STAR_SIZE + UiTheme.SPACE_XS
	for _i in wanted:
		Icons.paint(part, &"star", Vector2(x + STAR_SIZE * 0.5, STAR_SIZE * 0.5), STAR_SIZE, UiTheme.ACCENT)
		x += step
