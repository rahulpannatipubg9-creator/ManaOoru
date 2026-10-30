class_name UiTheme
extends RefCounted

## The one place for the game's look: colours, spacing, type sizes and shared control styles.
## Every screen takes its values from here (docs/reference/UI_DESIGN.md), never from local literals.

const FONT_PATH := "res://assets/fonts/NotoSans-Bold.ttf"
const FONT_TELUGU_PATH := "res://assets/fonts/NotoSansTelugu-Bold.ttf"

# Surfaces: dark slate, translucent in play so the town stays visible.
const INK := Color("0d1419")
const SURFACE := Color(0.05, 0.08, 0.1, 0.72)
const SURFACE_SOLID := Color(0.05, 0.08, 0.1, 0.96)
const SURFACE_RAISED := Color(0.11, 0.15, 0.18, 0.96)
const DIM := Color(0.02, 0.03, 0.04, 0.72)
const LINE := Color(1, 1, 1, 0.14)

# Text.
const TEXT := Color("f2f5f6")
const TEXT_MUTED := Color("a9b5bb")

# Marigold is the single accent. Status colours mean exactly one thing each.
const ACCENT := Color("f5b335")
const ACCENT_DARK := Color("2a1d05")
const HEALTH := Color("4fd18b")
const ARMOUR := Color("5aa9e6")
const DANGER := Color("ef5a4c")

# Spacing scale and radii, in canvas units at 1280x720.
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
const SPACE_XL := 40
const RADIUS := 10
const RADIUS_PILL := 999

# Type scale. Nothing on screen goes below FONT_SMALL.
const FONT_SMALL := 14
const FONT_BODY := 16
const FONT_LABEL := 18
const FONT_TITLE := 24
const FONT_DISPLAY := 40
const FONT_HERO := 64

const MOTION_FAST := 0.12
const MOTION_NORMAL := 0.2

## Minimum size of anything pressed by a finger or clicked in a menu.
const TOUCH_TARGET := 48.0

static var _theme: Theme

## The shared Theme, built once. Controls inherit it through the root window.
static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

## Applies the look to every control under the window. Safe to call more than once.
static func apply(window: Window) -> void:
	window.theme = theme()

static func font() -> Font:
	return load(FONT_PATH) as Font

## A rounded surface. Used for panels, chips and buttons alike, so they all match.
static func box(fill: Color = SURFACE, radius: int = RADIUS, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(1)
	style.set_content_margin(SIDE_LEFT, SPACE_M)
	style.set_content_margin(SIDE_RIGHT, SPACE_M)
	style.set_content_margin(SIDE_TOP, SPACE_S)
	style.set_content_margin(SIDE_BOTTOM, SPACE_S)
	return style

## The marigold call to action. One per screen at most.
static func make_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(ACCENT))
	button.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.12)))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, RADIUS, TEXT))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ACCENT_DARK)

## A centred full-screen dim behind a menu.
static func make_dim(rect: ColorRect) -> void:
	rect.color = DIM
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func _build() -> Theme:
	var value := Theme.new()
	var regular := font()
	if regular != null:
		var telugu := load(FONT_TELUGU_PATH) as Font
		if telugu != null and regular is FontFile:
			regular.fallbacks = [telugu]
		value.default_font = regular
	value.default_font_size = FONT_BODY
	value.set_color("font_color", "Label", TEXT)
	_style_buttons(value)
	value.set_stylebox("panel", "PanelContainer", box(SURFACE_SOLID, RADIUS))
	value.set_stylebox("panel", "Panel", box(SURFACE_SOLID, RADIUS))
	value.set_stylebox("panel", "PopupMenu", box(SURFACE_RAISED, RADIUS))
	value.set_stylebox("normal", "LineEdit", box(SURFACE_RAISED, RADIUS, LINE))
	value.set_stylebox("focus", "LineEdit", box(SURFACE_RAISED, RADIUS, ACCENT))
	value.set_stylebox("panel", "TabContainer", box(SURFACE_SOLID, RADIUS))
	value.set_stylebox("tab_selected", "TabContainer", box(SURFACE_RAISED, RADIUS))
	value.set_stylebox("tab_unselected", "TabContainer", box(Color.TRANSPARENT, RADIUS))
	value.set_stylebox("tab_hovered", "TabContainer", box(LINE, RADIUS))
	value.set_color("font_selected_color", "TabContainer", ACCENT)
	value.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)
	value.set_color("font_hovered_color", "TabContainer", TEXT)
	value.set_stylebox("tab_focus", "TabContainer", box(Color.TRANSPARENT, RADIUS, ACCENT))
	_style_ranges(value)
	return value

## Sliders and scroll bars: a thin track, marigold fill, round grabber.
static func _style_ranges(value: Theme) -> void:
	value.set_stylebox("slider", "HSlider", _track(LINE))
	value.set_stylebox("grabber_area", "HSlider", _track(ACCENT))
	value.set_stylebox("grabber_area_highlight", "HSlider", _track(ACCENT))
	value.set_icon("grabber", "HSlider", _dot(ACCENT))
	value.set_icon("grabber_highlight", "HSlider", _dot(TEXT))
	value.set_stylebox("scroll", "VScrollBar", _track(Color.TRANSPARENT))
	value.set_stylebox("grabber", "VScrollBar", _track(LINE))
	value.set_stylebox("grabber_highlight", "VScrollBar", _track(TEXT_MUTED))
	value.set_stylebox("grabber_pressed", "VScrollBar", _track(ACCENT))

static func _track(fill: Color) -> StyleBoxFlat:
	var style := box(fill, RADIUS_PILL)
	style.set_content_margin_all(3)
	return style

static func _dot(fill: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.9, 1.0])
	gradient.colors = PackedColorArray([fill, fill, Color(fill, 0.0)])
	var dot := GradientTexture2D.new()
	dot.gradient = gradient
	dot.width = 22
	dot.height = 22
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	return dot

static func _style_buttons(value: Theme) -> void:
	for type_name: String in ["Button", "OptionButton", "CheckButton"]:
		value.set_stylebox("normal", type_name, box(SURFACE_RAISED))
		value.set_stylebox("hover", type_name, box(SURFACE_RAISED.lightened(0.08)))
		value.set_stylebox("pressed", type_name, box(ACCENT.darkened(0.55)))
		value.set_stylebox("focus", type_name, box(Color.TRANSPARENT, RADIUS, ACCENT))
		value.set_stylebox("disabled", type_name, box(Color(SURFACE_RAISED, 0.5)))
		value.set_color("font_color", type_name, TEXT)
		value.set_color("font_hover_color", type_name, TEXT)
		value.set_color("font_pressed_color", type_name, ACCENT)
		value.set_color("font_focus_color", type_name, TEXT)
		value.set_color("font_disabled_color", type_name, TEXT_MUTED)
