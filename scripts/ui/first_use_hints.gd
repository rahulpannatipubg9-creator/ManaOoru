extends RefCounted
## Remembers which one-time hints the player has seen (docs/reference/UI_DESIGN.md: teach by doing).

const PATH := "user://hints.cfg"
const SECTION := "seen"

var _path := ""
var _seen := ConfigFile.new()

## An empty `path` keeps hints in memory only, for tests and no-save runs.
func _init(path := PATH) -> void:
	_path = path
	if not _path.is_empty() and FileAccess.file_exists(_path):
		_seen.load(_path)

func is_seen(id: String) -> bool:
	return _seen.has_section_key(SECTION, id)

## True the first time `id` is claimed, ever; the claim is saved at once.
func claim(id: String) -> bool:
	if is_seen(id):
		return false
	_seen.set_value(SECTION, id, true)
	if not _path.is_empty():
		_seen.save(_path)
	return true
