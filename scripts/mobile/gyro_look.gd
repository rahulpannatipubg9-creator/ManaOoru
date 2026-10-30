extends RefCounted

## Turns gyroscope rates into camera look deltas, "phone as a window": turning the
## device right looks right and tilting its top edge towards you looks up (as the
## rear camera would). Input.get_gyroscope() is rad/s about the display axes
## (x right, y up, z out of the screen). Output uses the mouse-relative convention
## the camera's _look() expects (+x looks right, +y looks down), in radians.
##
## The sensor only reports data when input_devices/sensors/enable_gyroscope is on.

var sensitivity := 1.8
var invert_x := false
var invert_y := false
## Rates below this (rad/s) are hand tremor, not intent.
var deadzone := 0.015
var smoothing := 12.0
var _filtered := Vector3.ZERO

func step(sample: Vector3, delta: float) -> Vector2:
	if not sample.is_finite() or delta <= 0.0:
		return Vector2.ZERO
	var target := Vector3.ZERO if sample.length() < deadzone else sample
	_filtered = _filtered.lerp(target, 1.0 - exp(-smoothing * delta))
	var look := Vector2(-_filtered.y, -_filtered.x) * sensitivity * minf(delta, 0.1)
	if invert_x:
		look.x = -look.x
	if invert_y:
		look.y = -look.y
	return look

func reset() -> void:
	_filtered = Vector3.ZERO

static func sensor_enabled() -> bool:
	return bool(ProjectSettings.get_setting("input_devices/sensors/enable_gyroscope", false))
