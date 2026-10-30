extends RefCounted

## Player-adjustable touch control preferences, stored offline in user://.
## Values are clamped on load so a hand-edited or stale file cannot break the HUD.

const DEFAULT_PATH := "user://mobile_controls.cfg"
const SECTION := "touch"
const BUTTON_SCALE_RANGE := Vector2(0.8, 1.25)
const OPACITY_RANGE := Vector2(0.35, 1.0)
const LOOK_SENSITIVITY_RANGE := Vector2(0.3, 3.0)
const GYRO_SENSITIVITY_RANGE := Vector2(0.2, 4.0)
const JOYSTICK_DEADZONE_RANGE := Vector2(0.0, 0.4)
## Matches the camera's GyroMode: OFF, SCOPE_ON, ALWAYS_ON.
const GYRO_MODE_COUNT := 3

var button_scale := 1.0
var opacity := 0.85
var left_handed := false
var sensitivity_preset := "Medium"
var ads_sensitivity := 0.75
var ads_gyro_sensitivity := 1.4
var look_sensitivity := 1.0
var gyro_mode := 0
var gyro_sensitivity := 1.8
var gyro_invert_x := false
var gyro_invert_y := false
var joystick_deadzone := 0.12
var sprint_lock := true

func load_from(path := DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	button_scale = _number(config, "button_scale", button_scale)
	opacity = _number(config, "opacity", opacity)
	left_handed = _flag(config, "left_handed", left_handed)
	sensitivity_preset = str(config.get_value(SECTION, "sensitivity_preset", "Custom"))
	ads_sensitivity = _number(config, "ads_sensitivity", ads_sensitivity)
	ads_gyro_sensitivity = _number(config, "ads_gyro_sensitivity", ads_gyro_sensitivity)
	look_sensitivity = _number(config, "look_sensitivity", look_sensitivity)
	gyro_mode = int(_number(config, "gyro_mode", gyro_mode))
	gyro_sensitivity = _number(config, "gyro_sensitivity", gyro_sensitivity)
	gyro_invert_x = _flag(config, "gyro_invert_x", gyro_invert_x)
	gyro_invert_y = _flag(config, "gyro_invert_y", gyro_invert_y)
	joystick_deadzone = _number(config, "joystick_deadzone", joystick_deadzone)
	sprint_lock = _flag(config, "sprint_lock", sprint_lock)
	sanitize()
	return true

func save_to(path := DEFAULT_PATH) -> Error:
	sanitize()
	var config := ConfigFile.new()
	for key in ["sensitivity_preset", "ads_sensitivity", "ads_gyro_sensitivity", "button_scale", "opacity", "left_handed", "look_sensitivity", "gyro_mode",
			"gyro_sensitivity", "gyro_invert_x", "gyro_invert_y", "joystick_deadzone", "sprint_lock"]:
		config.set_value(SECTION, key, get(key))
	return config.save(path)

func sanitize() -> void:
	ads_sensitivity = clampf(ads_sensitivity, 0.1, 4.0)
	ads_gyro_sensitivity = clampf(ads_gyro_sensitivity, 0.2, 4.0)
	if sensitivity_preset not in ["Low", "Medium", "High", "Seasoned Expert", "Custom"]: sensitivity_preset = "Custom"
	button_scale = clampf(button_scale, BUTTON_SCALE_RANGE.x, BUTTON_SCALE_RANGE.y)
	opacity = clampf(opacity, OPACITY_RANGE.x, OPACITY_RANGE.y)
	look_sensitivity = clampf(look_sensitivity, LOOK_SENSITIVITY_RANGE.x, LOOK_SENSITIVITY_RANGE.y)
	gyro_mode = posmod(gyro_mode, GYRO_MODE_COUNT)
	gyro_sensitivity = clampf(gyro_sensitivity, GYRO_SENSITIVITY_RANGE.x, GYRO_SENSITIVITY_RANGE.y)
	joystick_deadzone = clampf(joystick_deadzone, JOYSTICK_DEADZONE_RANGE.x, JOYSTICK_DEADZONE_RANGE.y)

static func _number(config: ConfigFile, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(SECTION, key, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback

static func _flag(config: ConfigFile, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(SECTION, key, fallback)
	return value if value is bool else fallback

func apply_preset(preset: String) -> void:
	var presets := {
		"Low": [0.6, 0.4, 0.8, 0.65],
		"Medium": [1.0, 0.75, 1.8, 1.4],
		"High": [1.5, 1.1, 2.6, 2.2],
		"Seasoned Expert": [2.0, 1.5, 3.5, 3.0]}
	if not presets.has(preset):
		sensitivity_preset = "Custom"
		return
	var values: Array = presets[preset]
	look_sensitivity = values[0]
	ads_sensitivity = values[1]
	gyro_sensitivity = values[2]
	ads_gyro_sensitivity = values[3]
	sensitivity_preset = preset
	sanitize()

func apply_to_camera(camera: Node) -> void:
	camera.look_sensitivity = look_sensitivity
	camera.ads_sensitivity = ads_sensitivity
	camera.gyro_mode = gyro_mode
	camera.gyro_sensitivity = gyro_sensitivity
	camera.ads_gyro_sensitivity = ads_gyro_sensitivity
	camera.gyro_invert_x = gyro_invert_x
	camera.gyro_invert_y = gyro_invert_y
