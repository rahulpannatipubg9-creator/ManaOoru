extends RefCounted

## Start-up timing, off unless the game runs with the user argument --profile-startup:
## Godot --path . -- --profile-startup
## mark() closes the step that ended now and prints a table on report().

static var enabled: bool = "--profile-startup" in OS.get_cmdline_user_args()
static var _last_usec: int = 0
static var _rows: Array[Array] = []

## Time since the previous mark, charged to this step.
static func mark(step: String) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	_rows.append([step, (now - _last_usec) / 1000.0])
	_last_usec = now

## Forget the time since the last mark (for example, a gap between stages).
static func restart() -> void:
	_last_usec = Time.get_ticks_usec()

static func report(title: String) -> void:
	if not enabled:
		return
	print("--- startup profile: %s (process age %d ms) ---" % [title, Time.get_ticks_msec()])
	var total := 0.0
	for row: Array in _rows:
		print("%9.1f ms  %s" % [row[1], row[0]])
		total += row[1]
	print("%9.1f ms  total" % total)
	_rows.clear()
