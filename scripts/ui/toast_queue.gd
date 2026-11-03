extends PanelContainer
## The one notification surface in play: a single pill under the compass (docs/reference/UI_DESIGN.md).
## Messages wait their turn, each shows for DURATION, and a repeat of one already showing or waiting is dropped.

const DURATION := 3.0
## Waiting messages beyond this drop the oldest, so a burst cannot back up for half a minute.
const MAX_WAITING := 4
## Clears the compass strip at the top of the screen.
const TOP_OFFSET := 56

## While held (the full map is open) the current message keeps its remaining time.
var held := false
var _label: Label
var _waiting: PackedStringArray = PackedStringArray()
var _current := ""
var _elapsed := 0.0

func _init() -> void:
	name = "ToastQueue"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above an open shop modal, which is where a purchase result is reported.
	z_index = 10
	anchor_left = 0.5
	anchor_right = 0.5
	offset_top = TOP_OFFSET
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	theme = UiTheme.theme()
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SURFACE, UiTheme.RADIUS))
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	add_child(_label)
	visible = false

## Queues `text`. Empty text and repeats are ignored.
func push(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty() or message == _current or _waiting.has(message):
		return
	_waiting.append(message)
	if _waiting.size() > MAX_WAITING:
		_waiting.remove_at(0)
	if _current.is_empty():
		_next()

func current() -> String:
	return _current

func waiting() -> PackedStringArray:
	return _waiting

func _process(delta: float) -> void:
	if held or _current.is_empty():
		return
	_elapsed += delta
	if _elapsed >= DURATION:
		_next()
		return
	modulate.a = minf(minf(_elapsed, DURATION - _elapsed) / UiTheme.MOTION_NORMAL, 1.0)

func _next() -> void:
	_elapsed = 0.0
	_current = ""
	if not _waiting.is_empty():
		_current = _waiting[0]
		_waiting.remove_at(0)
	_label.text = _current
	visible = not _current.is_empty()
	modulate.a = 0.0
	# Equal offsets let the pill take its text's width, centred, in both directions.
	offset_left = 0.0
	offset_right = 0.0
