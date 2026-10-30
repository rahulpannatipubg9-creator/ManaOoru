extends SceneTree

## The on-screen word budget (docs/reference/UI_DESIGN.md): one toast at a time, first-use hints that
## persist, at most 8 words in a toast and 4 in a prompt, and no floating labels on things that explain themselves.

const ToastQueue := preload("res://scripts/ui/toast_queue.gd")
const FirstUseHints := preload("res://scripts/ui/first_use_hints.gd")
const HINTS_PATH := "user://hints_regression_only.cfg"
const REMOVED_LABELS: Array[String] = ["\"PATIENT", "\"HOLD O", "PARCEL PICKUP", "POLICE • STOP", "GANG MEMBER", "\"SUSPECT\"", "\"POLICE\"",
	"FUEL\\n[E]", "[E] Browse •"]
const STALE_KEYS: Array[String] = ["B Auto/Single", "P Fire mode", "BRIDGE [B]", "Press [B]", "P toggles fire mode", "Hotkey: B"]

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_queue()
	_test_hints()
	_test_no_hud_push()
	_test_control_hints()
	_test_sources()
	print("%s on-screen text: toast queue, first-use hints, HUD pull, control hints, word limits, removed labels" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)

func _test_queue() -> void:
	var queue: Control = ToastQueue.new()
	root.add_child(queue)
	queue.push("First")
	_check(queue.current() == "First" and queue.visible, "A toast shows at once when nothing else is up")
	queue.push("First")
	queue.push("Second")
	queue.push("Second")
	_check(queue.waiting().size() == 1, "Repeats of the current or a waiting toast are dropped")
	queue._process(ToastQueue.DURATION - 0.1)
	_check(queue.current() == "First", "A toast stays up for its full time")
	queue.held = true
	queue._process(10.0)
	_check(queue.current() == "First", "A held toast keeps its remaining time")
	queue.held = false
	queue._process(0.2)
	_check(queue.current() == "Second", "The next toast follows only when the first ends")
	queue._process(ToastQueue.DURATION)
	_check(queue.current().is_empty() and not queue.visible, "The pill hides when the queue is empty")
	queue.push("")
	_check(queue.current().is_empty(), "Empty text never shows")
	for i in ToastQueue.MAX_WAITING + 3:
		queue.push("Message %d" % i)
	_check(queue.waiting().size() == ToastQueue.MAX_WAITING, "A burst cannot grow the queue without limit")
	queue.free()

func _test_hints() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINTS_PATH))
	var hints: RefCounted = FirstUseHints.new(HINTS_PATH)
	_check(hints.claim("rifle"), "A hint shows the first time")
	_check(not hints.claim("rifle"), "A hint shows only once")
	var reopened: RefCounted = FirstUseHints.new(HINTS_PATH)
	_check(reopened.is_seen("rifle") and not reopened.is_seen("plane"), "Seen hints persist across sessions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HINTS_PATH))
	var memory: RefCounted = FirstUseHints.new("")
	_check(memory.claim("rifle") and not FileAccess.file_exists(HINTS_PATH), "An empty path never touches the disk")

## The HUD reads vitals, ammo, wanted, objective and fuel itself; a second push once sent it wrong types.
func _test_no_hud_push() -> void:
	for path: String in ["res://scripts/gameplay/city_gameplay.gd", "res://scripts/world/city_life.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for pushed: String in ["hud.set_fuel", "_send_hud", "\"set_ammo\"", "\"set_objective\"", "\"set_vitals\""]:
			_check(not pushed in text, "%s pushes HUD readouts again: %s" % [path, pushed])

## An empty hint used to blank the prompt pill for two seconds; hints now go to the toast queue only.
func _test_control_hints() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(not "_show_control_hint(\"\")" in text, "main.gd sends an empty control hint")
	_check(not "_hint_until_msec" in text, "A control hint must not hold back the prompt pill")

func _test_sources() -> void:
	var toast := RegEx.create_from_string("(?:\\.|^|\\s)toast\\(\"([^\"]*)\"(?:\\s+if\\s.*?\\selse\\s+\"([^\"]*)\")?")
	var hint := RegEx.create_from_string("hint\\(\"[^\"]+\", \"([^\"]*)\"\\)")
	var prompt := RegEx.create_from_string("(?:_set_prompt|set_interaction_prompt)\\(\"([^\"]*)\"")
	var checked := 0
	for path: String in _scripts("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for stale: String in STALE_KEYS:
			_check(not stale in text, "%s still mentions %s" % [path, stale])
		for found: RegExMatch in toast.search_all(text) + hint.search_all(text):
			for group in range(1, found.get_group_count() + 1):
				var message := found.get_string(group)
				checked += 1
				_check(message.split(" ", false).size() <= 8, "%s: toast too long: %s" % [path, message])
				_check(not "•" in message, "%s: bullet chain in toast: %s" % [path, message])
		for found: RegExMatch in prompt.search_all(text):
			_check(found.get_string(1).split(" ", false).size() <= 4, "%s: prompt too long: %s" % [path, found.get_string(1)])
		if path.contains("/gameplay/") or path.ends_with("/city_life.gd"):
			for removed: String in REMOVED_LABELS:
				_check(not removed in text, "%s keeps %s" % [path, removed])
	_check(checked > 40, "The source scan must find the toast strings")

func _scripts(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(_scripts(folder.path_join(sub)))
	return found
