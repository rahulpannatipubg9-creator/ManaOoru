extends RefCounted

## Vector icons for the HUD and the action wheel, drawn from shapes so no emoji or image
## is needed. Each is laid out in a -1..1 box and scaled to `size` around `center`.

const STROKE := 0.13

## Draws icon `id` on `item`. Call from inside that item's draw step.
static func paint(item: CanvasItem, id: StringName, center: Vector2, size: float, color: Color) -> void:
	var pen := _Pen.new(item, center, size * 0.5, color)
	match id:
		&"fire": _bullet(pen)
		&"aim": _aim(pen)
		&"reload": _reload(pen)
		&"crouch": _crouch(pen)
		&"prone": _prone(pen)
		&"jump": _jump(pen)
		&"run": _run(pen)
		&"swap": _swap(pen)
		&"medkit": _medkit(pen)
		&"grenade": _grenade(pen)
		&"surrender": _surrender(pen)
		&"talk": _talk(pen)
		&"avatar": _avatar(pen)
		&"help": _help(pen)
		&"peek_left": _peek(pen, -1.0)
		&"peek_right": _peek(pen, 1.0)
		&"fire_auto": _fire_mode(pen, 3)
		&"fire_single": _fire_mode(pen, 1)
		&"rifle": _rifle(pen)
		&"view": _view(pen)
		&"look": _look(pen)
		&"unstuck": _unstuck(pen)
		&"radio": _radio(pen)
		&"menu": _menu(pen)
		&"wheel": _wheel(pen)
		&"interact": _interact(pen)
		&"exit": _exit(pen)
		&"handbrake": _handbrake(pen)
		&"camera": _camera(pen)
		&"up": _arrow(pen, -1.0)
		&"down": _arrow(pen, 1.0)
		&"plus": _plus(pen)
		&"minus": _minus(pen)
		&"gearbox": _gearbox(pen)
		&"health": _cross(pen, 0.72)
		&"armour": _shield(pen)
		&"fuel": _fuel(pen)
		&"star": _star(pen)

## Scales unit-box coordinates and keeps stroke widths in proportion to the icon.
class _Pen:
	var item: CanvasItem
	var center: Vector2
	var scale: float
	var color: Color

	func _init(canvas: CanvasItem, at: Vector2, radius: float, tint: Color) -> void:
		item = canvas
		center = at
		scale = radius
		color = tint

	func p(point: Vector2) -> Vector2:
		return center + point * scale

	func line(points: Array[Vector2], width := STROKE) -> void:
		var mapped := PackedVector2Array()
		for point in points:
			mapped.append(p(point))
		item.draw_polyline(mapped, color, maxf(width * scale, 1.5), true)

	func fill(points: Array[Vector2]) -> void:
		var mapped := PackedVector2Array()
		for point in points:
			mapped.append(p(point))
		item.draw_colored_polygon(mapped, color)
		mapped.append(mapped[0])
		item.draw_polyline(mapped, color, 1.0, true)

	func dot(at: Vector2, radius: float) -> void:
		item.draw_circle(p(at), radius * scale, color, true, -1.0, true)

	func ring(at: Vector2, radius: float, width := STROKE) -> void:
		arc(at, radius, 0.0, TAU, width)

	func arc(at: Vector2, radius: float, from: float, to: float, width := STROKE) -> void:
		item.draw_arc(p(at), radius * scale, from, to, 48, color, maxf(width * scale, 1.5), true)

static func _bullet(pen: _Pen) -> void:
	pen.fill([Vector2(0.0, -0.92), Vector2(0.16, -0.72), Vector2(0.3, -0.34), Vector2(0.3, 0.42), Vector2(-0.3, 0.42),
		Vector2(-0.3, -0.34), Vector2(-0.16, -0.72)])
	pen.fill([Vector2(-0.3, 0.56), Vector2(0.3, 0.56), Vector2(0.3, 0.86), Vector2(-0.3, 0.86)])

static func _aim(pen: _Pen) -> void:
	pen.ring(Vector2.ZERO, 0.62)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		pen.line([direction * 0.36, direction * 0.94])
	pen.dot(Vector2.ZERO, 0.1)

static func _reload(pen: _Pen) -> void:
	pen.arc(Vector2.ZERO, 0.68, -PI * 0.3, PI * 1.45)
	pen.fill([Vector2(0.86, -0.72), Vector2(0.72, -0.08), Vector2(0.14, -0.42)])

static func _crouch(pen: _Pen) -> void:
	pen.dot(Vector2(0.14, -0.62), 0.22)
	pen.line([Vector2(0.06, -0.3), Vector2(-0.34, 0.08), Vector2(0.26, 0.26), Vector2(0.06, 0.8)], 0.17)

static func _prone(pen: _Pen) -> void:
	pen.dot(Vector2(0.7, -0.26), 0.2)
	pen.line([Vector2(0.42, -0.06), Vector2(-0.82, 0.14)], 0.2)
	pen.line([Vector2(-0.94, 0.5), Vector2(0.94, 0.5)])

static func _jump(pen: _Pen) -> void:
	pen.line([Vector2(-0.62, -0.08), Vector2(0.0, -0.7), Vector2(0.62, -0.08)], 0.17)
	pen.line([Vector2(-0.62, 0.4), Vector2(0.0, -0.22), Vector2(0.62, 0.4)], 0.17)
	pen.line([Vector2(-0.7, 0.8), Vector2(0.7, 0.8)])

static func _run(pen: _Pen) -> void:
	pen.line([Vector2(-0.68, -0.62), Vector2(-0.06, 0.0), Vector2(-0.68, 0.62)], 0.19)
	pen.line([Vector2(0.06, -0.62), Vector2(0.68, 0.0), Vector2(0.06, 0.62)], 0.19)

static func _swap(pen: _Pen) -> void:
	pen.line([Vector2(-0.82, -0.34), Vector2(0.62, -0.34)])
	pen.line([Vector2(0.3, -0.72), Vector2(0.72, -0.34), Vector2(0.3, 0.04)])
	pen.line([Vector2(0.82, 0.34), Vector2(-0.62, 0.34)])
	pen.line([Vector2(-0.3, -0.04), Vector2(-0.72, 0.34), Vector2(-0.3, 0.72)])

static func _cross(pen: _Pen, reach: float) -> void:
	var arm := reach * 0.36
	pen.fill([Vector2(-arm, -reach), Vector2(arm, -reach), Vector2(arm, -arm), Vector2(reach, -arm), Vector2(reach, arm),
		Vector2(arm, arm), Vector2(arm, reach), Vector2(-arm, reach), Vector2(-arm, arm), Vector2(-reach, arm),
		Vector2(-reach, -arm), Vector2(-arm, -arm)])

static func _medkit(pen: _Pen) -> void:
	pen.line([Vector2(-0.84, -0.46), Vector2(0.84, -0.46), Vector2(0.84, 0.72), Vector2(-0.84, 0.72), Vector2(-0.84, -0.46)])
	pen.line([Vector2(-0.3, -0.46), Vector2(-0.3, -0.76), Vector2(0.3, -0.76), Vector2(0.3, -0.46)])
	var offset := Vector2(0.0, 0.13)
	var pieces: Array[Vector2] = [Vector2(-0.1, -0.36), Vector2(0.1, -0.36), Vector2(0.1, -0.1), Vector2(0.36, -0.1), Vector2(0.36, 0.1),
		Vector2(0.1, 0.1), Vector2(0.1, 0.36), Vector2(-0.1, 0.36), Vector2(-0.1, 0.1), Vector2(-0.36, 0.1),
		Vector2(-0.36, -0.1), Vector2(-0.1, -0.1)]
	for i in pieces.size():
		pieces[i] += offset
	pen.fill(pieces)

static func _grenade(pen: _Pen) -> void:
	pen.dot(Vector2(-0.04, 0.26), 0.6)
	pen.fill([Vector2(-0.28, -0.46), Vector2(0.2, -0.46), Vector2(0.2, -0.26), Vector2(-0.28, -0.26)])
	pen.line([Vector2(-0.3, -0.62), Vector2(0.2, -0.62), Vector2(0.72, -0.2)])

static func _surrender(pen: _Pen) -> void:
	pen.line([Vector2(-0.62, -0.9), Vector2(-0.62, 0.92)], 0.16)
	pen.fill([Vector2(-0.56, -0.84), Vector2(0.82, -0.62), Vector2(0.5, -0.32), Vector2(0.82, -0.02), Vector2(-0.56, 0.12)])

static func _talk(pen: _Pen) -> void:
	pen.line([Vector2(-0.84, -0.64), Vector2(0.84, -0.64), Vector2(0.84, 0.36), Vector2(-0.12, 0.36), Vector2(-0.5, 0.78),
		Vector2(-0.5, 0.36), Vector2(-0.84, 0.36), Vector2(-0.84, -0.64)])
	for x: float in [-0.4, 0.0, 0.4]:
		pen.dot(Vector2(x, -0.14), 0.09)

static func _avatar(pen: _Pen) -> void:
	pen.dot(Vector2(0.0, -0.4), 0.36)
	var shoulders: Array[Vector2] = [Vector2(-0.76, 0.84)]
	for step in 13:
		var angle := PI + PI * step / 12.0
		shoulders.append(Vector2(cos(angle) * 0.76, 0.84 + sin(angle) * 0.62))
	shoulders.append(Vector2(0.76, 0.84))
	pen.fill(shoulders)

static func _help(pen: _Pen) -> void:
	var heart: Array[Vector2] = []
	for step in 36:
		var t := TAU * step / 36.0
		heart.append(Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * 0.052)
	pen.fill(heart)

static func _peek(pen: _Pen, side: float) -> void:
	pen.line([Vector2(-side * 0.72, -0.9), Vector2(-side * 0.72, 0.9)], 0.2)
	pen.line([Vector2(-side * 0.22, -0.56), Vector2(side * 0.46, 0.0), Vector2(-side * 0.22, 0.56)], 0.18)

static func _fire_mode(pen: _Pen, count: int) -> void:
	for i in count:
		var x := (i - (count - 1) * 0.5) * 0.56
		pen.fill([Vector2(x, -0.72), Vector2(x + 0.17, -0.42), Vector2(x + 0.17, 0.64), Vector2(x - 0.17, 0.64),
			Vector2(x - 0.17, -0.42)])

## Side view, muzzle to the right: stock, receiver, magazine, grip and barrel.
static func _rifle(pen: _Pen) -> void:
	pen.fill([Vector2(-0.98, -0.2), Vector2(-0.62, -0.26), Vector2(-0.54, -0.2), Vector2(0.42, -0.2), Vector2(0.42, -0.08),
		Vector2(0.98, -0.08), Vector2(0.98, 0.02), Vector2(0.42, 0.02), Vector2(0.42, 0.12), Vector2(0.06, 0.12),
		Vector2(0.14, 0.56), Vector2(-0.12, 0.6), Vector2(-0.2, 0.12), Vector2(-0.36, 0.12), Vector2(-0.46, 0.44),
		Vector2(-0.64, 0.4), Vector2(-0.58, 0.06), Vector2(-0.98, 0.14)])

static func _view(pen: _Pen) -> void:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var tip := corner * 0.78
		pen.line([tip - Vector2(corner.x * 0.36, 0.0), tip, tip - Vector2(0.0, corner.y * 0.36)])
	pen.dot(Vector2(0.0, -0.18), 0.2)
	pen.fill([Vector2(-0.36, 0.42), Vector2(-0.2, 0.08), Vector2(0.2, 0.08), Vector2(0.36, 0.42)])

static func _look(pen: _Pen) -> void:
	var outline: Array[Vector2] = []
	for step in 25:
		var t := PI + PI * step / 24.0
		outline.append(Vector2(cos(t) * 0.9, sin(t) * 0.56))
	for step in range(1, 25):
		var t := PI * step / 24.0
		outline.append(Vector2(cos(t) * 0.9, sin(t) * 0.56))
	pen.line(outline)
	pen.dot(Vector2.ZERO, 0.26)

static func _unstuck(pen: _Pen) -> void:
	pen.line([Vector2(0.0, 0.42), Vector2(0.0, -0.8)], 0.17)
	pen.line([Vector2(-0.46, -0.34), Vector2(0.0, -0.8), Vector2(0.46, -0.34)], 0.17)
	pen.line([Vector2(-0.8, 0.8), Vector2(0.8, 0.8)])

static func _radio(pen: _Pen) -> void:
	pen.line([Vector2(-0.84, -0.28), Vector2(0.84, -0.28), Vector2(0.84, 0.76), Vector2(-0.84, 0.76), Vector2(-0.84, -0.28)])
	pen.line([Vector2(-0.56, -0.3), Vector2(0.6, -0.92)])
	pen.dot(Vector2(0.38, 0.24), 0.2)
	pen.line([Vector2(-0.6, 0.06), Vector2(-0.08, 0.06)])
	pen.line([Vector2(-0.6, 0.42), Vector2(-0.08, 0.42)])

static func _menu(pen: _Pen) -> void:
	for y: float in [-0.56, 0.0, 0.56]:
		pen.line([Vector2(-0.78, y), Vector2(0.78, y)], 0.16)

static func _wheel(pen: _Pen) -> void:
	for i in 6:
		var from := TAU * i / 6.0 - PI * 0.5 + 0.17
		pen.arc(Vector2.ZERO, 0.76, from, from + TAU / 6.0 - 0.34, 0.2)
	pen.dot(Vector2.ZERO, 0.17)

static func _interact(pen: _Pen) -> void:
	pen.ring(Vector2.ZERO, 0.72, 0.14)
	pen.dot(Vector2.ZERO, 0.34)

static func _exit(pen: _Pen) -> void:
	pen.line([Vector2(-0.1, -0.86), Vector2(-0.8, -0.86), Vector2(-0.8, 0.86), Vector2(-0.1, 0.86)])
	pen.line([Vector2(-0.3, 0.0), Vector2(0.8, 0.0)], 0.17)
	pen.line([Vector2(0.36, -0.44), Vector2(0.82, 0.0), Vector2(0.36, 0.44)], 0.17)

static func _handbrake(pen: _Pen) -> void:
	pen.ring(Vector2.ZERO, 0.62, 0.14)
	pen.arc(Vector2.ZERO, 0.9, PI * 0.72, PI * 1.28, 0.12)
	pen.arc(Vector2.ZERO, 0.9, -PI * 0.28, PI * 0.28, 0.12)
	pen.line([Vector2(-0.18, 0.34), Vector2(-0.18, -0.34), Vector2(0.1, -0.34), Vector2(0.24, -0.18), Vector2(0.24, -0.1),
		Vector2(0.1, 0.04), Vector2(-0.18, 0.04)])

static func _camera(pen: _Pen) -> void:
	pen.line([Vector2(-0.88, -0.42), Vector2(-0.34, -0.42), Vector2(-0.2, -0.68), Vector2(0.2, -0.68), Vector2(0.34, -0.42),
		Vector2(0.88, -0.42), Vector2(0.88, 0.64), Vector2(-0.88, 0.64), Vector2(-0.88, -0.42)])
	pen.ring(Vector2(0.0, 0.1), 0.3)

static func _arrow(pen: _Pen, direction: float) -> void:
	pen.fill([Vector2(0.0, direction * 0.78), Vector2(0.74, direction * -0.1), Vector2(0.28, direction * -0.1),
		Vector2(0.28, direction * -0.78), Vector2(-0.28, direction * -0.78), Vector2(-0.28, direction * -0.1),
		Vector2(-0.74, direction * -0.1)])

static func _plus(pen: _Pen) -> void:
	pen.line([Vector2(-0.66, 0.0), Vector2(0.66, 0.0)], 0.2)
	pen.line([Vector2(0.0, -0.66), Vector2(0.0, 0.66)], 0.2)

static func _minus(pen: _Pen) -> void:
	pen.line([Vector2(-0.66, 0.0), Vector2(0.66, 0.0)], 0.2)

static func _gearbox(pen: _Pen) -> void:
	for x: float in [-0.66, 0.0, 0.66]:
		pen.line([Vector2(x, -0.66), Vector2(x, 0.66)])
		pen.dot(Vector2(x, -0.66), 0.14)
		pen.dot(Vector2(x, 0.66), 0.14)
	pen.line([Vector2(-0.66, 0.0), Vector2(0.66, 0.0)])

static func _shield(pen: _Pen) -> void:
	pen.fill([Vector2(0.0, -0.9), Vector2(0.74, -0.62), Vector2(0.74, 0.02), Vector2(0.5, 0.5), Vector2(0.0, 0.92),
		Vector2(-0.5, 0.5), Vector2(-0.74, 0.02), Vector2(-0.74, -0.62)])

static func _fuel(pen: _Pen) -> void:
	pen.fill([Vector2(-0.7, -0.84), Vector2(0.2, -0.84), Vector2(0.2, 0.86), Vector2(-0.7, 0.86)])
	pen.line([Vector2(0.2, 0.2), Vector2(0.52, 0.2), Vector2(0.52, 0.6), Vector2(0.78, 0.6), Vector2(0.78, -0.3), Vector2(0.46, -0.62)])

static func _star(pen: _Pen) -> void:
	var outer: Array[Vector2] = []
	for i in 10:
		var angle := -PI * 0.5 + TAU * i / 10.0
		var radius := 0.96 if i % 2 == 0 else 0.42
		outer.append(Vector2(cos(angle), sin(angle)) * radius)
	# Fan from the centre: a star is concave, and the polygon fill wants simple shapes.
	for i in 10:
		pen.fill([Vector2.ZERO, outer[i], outer[(i + 1) % 10]])
