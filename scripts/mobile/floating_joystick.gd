extends RefCounted

## Floating virtual stick that owns exactly one finger. It appears where the finger
## lands inside its zone and ignores every other touch index, so fire, look and
## stance fingers never steal or release it. Pushing far ahead latches sprint,
## as in BGMI: release while latched and the character keeps running forward.

var zone := Rect2()
var radius := 90.0
## Share of the radius ignored around the centre; the rest is rescaled to 0..1.
var deadzone := 0.12
## Dragging forward past this multiple of the radius arms the sprint latch.
var sprint_reach := 1.5
var sprint_lock_enabled := true
var finger := -1
var origin := Vector2.ZERO
var value := Vector2.ZERO
var sprint_armed := false
var sprint_latched := false
var _offset := Vector2.ZERO

func is_active() -> bool:
	return finger != -1

## Claims the finger when it lands inside the zone and the stick is free.
func press(index: int, position: Vector2) -> bool:
	if finger != -1 or not zone.has_point(position):
		return false
	finger = index
	origin = position
	_offset = Vector2.ZERO
	value = Vector2.ZERO
	sprint_armed = false
	sprint_latched = false
	return true

func drag(index: int, position: Vector2) -> bool:
	if index != finger:
		return false
	_offset = position - origin
	var reach := _offset.length() / maxf(radius, 1.0)
	sprint_armed = sprint_lock_enabled and reach >= sprint_reach and _offset.y < 0.0 \
		and absf(_offset.x) <= -_offset.y * 0.5
	value = shape(_offset / maxf(radius, 1.0), deadzone)
	return true

func release(index: int) -> bool:
	if index != finger:
		return false
	sprint_latched = sprint_armed
	finger = -1
	_offset = Vector2.ZERO
	sprint_armed = false
	value = Vector2(0.0, -1.0) if sprint_latched else Vector2.ZERO
	return true

## Lost focus, cancelled touch or a menu opening: drop everything, including the latch.
func cancel() -> void:
	finger = -1
	_offset = Vector2.ZERO
	value = Vector2.ZERO
	sprint_armed = false
	sprint_latched = false

func wants_sprint() -> bool:
	return sprint_armed or sprint_latched

## Knob offset from the base centre, clamped to the ring, for drawing.
func knob_offset() -> Vector2:
	return _offset.limit_length(radius)

## Radial deadzone with rescale: no jump from 0 to the deadzone edge, full range kept.
static func shape(raw: Vector2, dead: float) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= dead or magnitude == 0.0:
		return Vector2.ZERO
	return raw / magnitude * clampf((magnitude - dead) / maxf(1.0 - dead, 0.001), 0.0, 1.0)
