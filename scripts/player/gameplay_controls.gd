class_name GameplayControls
extends RefCounted
## Shared authority gate. Standalone physics labs have no owner; main.gd sets
## the only permitted controller and explicit contextual mode in the real game.
enum Mode { ON_FOOT, DRIVING_CAR, RIDING_MOTORCYCLE, FLYING_HELICOPTER, TRANSITION, PAUSED, UI_FOCUSED }
static var mode := Mode.ON_FOOT
static var owner_id := 0
static var blocked := false

static func allows(body: Node) -> bool:
	return not blocked and not (body.is_inside_tree() and text_focused(body.get_viewport())) and (owner_id == 0 or owner_id == body.get_instance_id())

static func movement() -> Vector2:
	var axes := Input.get_vector("left", "right", "forward", "backward")
	if axes.is_zero_approx():
		axes = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	return axes.limit_length()

static func clear_held() -> void:
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_F, KEY_R, KEY_C, KEY_V, KEY_SPACE, KEY_SHIFT, KEY_CTRL]:
		var release := InputEventKey.new()
		release.keycode = key
		release.physical_keycode = key
		release.pressed = false
		Input.parse_input_event(release)
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)

static func text_focused(viewport: Viewport) -> bool:
	if not is_instance_valid(viewport):
		return false
	var focused := viewport.gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
