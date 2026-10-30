extends Control

## A short scrolling list. Every line comes from ASSET_LICENSES.md, or is the plain fact of
## what the game is built with; assets with no known author or source are left out, and
## must only join this list once that file records one.

signal closed

const SCROLL_SPEED := 36.0
const CREDITS := [
	["Map", [
		"Map data © OpenStreetMap contributors, ODbL 1.0",
		"Overture Maps Foundation",
		"Building footprints © Microsoft, ODbL 1.0",
		"Building heights: Google Open Buildings 2.5D, CC BY 4.0",
		"Street reference: Mapillary panoramas by geomannar, CC BY-SA 4.0",
		"Canopy heights: Meta and World Resources Institute (WRI) 2024, CC BY 4.0",
	]],
	["Terrain", [
		"Copernicus DEM GLO-30",
		"© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018",
		"provided under COPERNICUS by the European Union and ESA; all rights reserved",
	]],
	["Land cover", [
		"© ESA WorldCover project 2021",
		"Contains modified Copernicus Sentinel data (2021)",
		"processed by ESA WorldCover consortium, CC BY 4.0",
	]],
	["Models", [
		"Mahindra Thar 3D Model by aakash2 (BlendSwap), CC-BY",
		"Porsche 911 Carrera 4S (992) model, Blend Swap #93636, CC BY-NC 3.0",
		"M416 / HK416 by natholas (Blend Swap), CC0",
		"Ak47 by ReWork3D (BlenderKit)",
		"Panipuri Cart (indian appetizers) by Bongblender, CC BY 4.0",
		"Reallusion CC Character Base",
	]],
	["Textures and sound", [
		"Poly Haven, CC0",
		"vw diesel engine by Evilmikie (Freesound), CC0",
		"Engine recordings from Pixabay",
	]],
	["Type and engine", [
		"Noto Sans by the Noto Project Authors, SIL Open Font License 1.1",
		"Godot Engine",
	]],
	["Trademarks", [
		"Mahindra, Thar, Porsche, 911 and Jeep belong to their owners.",
	]],
]

var _scroll: ScrollContainer
var _offset := 0.0
var _rolling := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	UiTheme.make_dim(dim)
	dim.color = Color(UiTheme.SURFACE_SOLID, 1.0)
	add_child(dim)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	_scroll.add_child(column)
	_spacer(column, get_viewport_rect().size.y * 0.6)
	_line(column, "MANA OORU", UiTheme.FONT_DISPLAY, UiTheme.TEXT)
	for section: Array in CREDITS:
		_spacer(column, UiTheme.SPACE_XL)
		_line(column, section[0], UiTheme.FONT_LABEL, UiTheme.ACCENT)
		for text: String in section[1]:
			_line(column, text, UiTheme.FONT_BODY, UiTheme.TEXT)
	_spacer(column, get_viewport_rect().size.y * 0.6)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(UiTheme.TOUCH_TARGET * 3.0, UiTheme.TOUCH_TARGET)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-UiTheme.TOUCH_TARGET * 3.0 - UiTheme.SPACE_L, UiTheme.SPACE_L)
	add_child(back)
	back.pressed.connect(close)
	back.grab_focus()

func _line(parent: Control, text: String, size_px: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _spacer(parent: Control, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	parent.add_child(space)

func _process(delta: float) -> void:
	if not _rolling:
		return
	_offset += SCROLL_SPEED * delta
	_scroll.scroll_vertical = int(_offset)
	if _scroll.scroll_vertical < int(_offset):
		_offset = 0.0

## A wheel, drag or arrow means the reader has taken over.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenDrag:
		_rolling = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	closed.emit()
	queue_free()
