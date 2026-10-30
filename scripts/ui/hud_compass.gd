extends Control

## Thin compass tape: the direction the camera faces stays centred and the cardinal
## points slide past. It draws only when the heading moves by a visible amount.

const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## Degrees of heading shown across the full width of the tape.
const SPAN := 150.0

var heading := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

## Heading in degrees, 0 = north, clockwise.
func set_heading(degrees: float) -> void:
	var wrapped := fposmod(degrees, 360.0)
	if absf(angle_difference(deg_to_rad(wrapped), deg_to_rad(heading))) > deg_to_rad(0.4):
		heading = wrapped
		queue_redraw()

## Where a compass bearing lands on the tape, or NAN when it is out of view.
func bearing_x(bearing: float) -> float:
	var offset := wrapf(bearing - heading, -180.0, 180.0)
	if absf(offset) > SPAN * 0.5:
		return NAN
	return size.x * 0.5 + offset / SPAN * size.x

func _draw() -> void:
	draw_style_box(UiTheme.box(UiTheme.SURFACE, UiTheme.RADIUS_PILL), Rect2(Vector2.ZERO, size))
	var font := UiTheme.font()
	for step in 24:
		var bearing := step * 15.0
		var x := bearing_x(bearing)
		if is_nan(x):
			continue
		var fade := _edge_fade(x)
		if step % 3 == 0:
			var text: String = POINTS[step / 3]
			var cardinal := step % 6 == 0
			var font_size: int = UiTheme.FONT_SMALL
			var tint: Color = UiTheme.ACCENT if text == "N" else (UiTheme.TEXT if cardinal else UiTheme.TEXT_MUTED)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(tint, tint.a * fade))
		else:
			var tick := Color(UiTheme.TEXT_MUTED, 0.6 * fade)
			draw_line(Vector2(x, size.y * 0.5 - 3.0), Vector2(x, size.y * 0.5 + 3.0), tick, 1.0, true)
	var middle := size.x * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(middle - 5.0, 0.0), Vector2(middle + 5.0, 0.0), Vector2(middle, 6.0)]), UiTheme.ACCENT)

## Marks soften towards both ends so they do not pop in at the rounded edge.
func _edge_fade(x: float) -> float:
	return clampf(minf(x, size.x - x) / (size.x * 0.12), 0.0, 1.0)
