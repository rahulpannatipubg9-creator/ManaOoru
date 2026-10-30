extends Node3D
## SYNTHETIC engineering demonstration. No geographic coordinates or source GIS.
const Channel = preload("res://scripts/world/drainage_channel.gd")
var camera: Camera3D
var yaw := 0.0
var pitch := -0.65
var distance := 55.0

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b9d3df")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	# Separate ground strips leave the main channel exposed below grade.
	_slab(Vector3(-16, -0.15, 0), Vector3(28, 0.3, 60), Color("85866e"))
	_slab(Vector3(16, -0.15, 0), Vector3(28, 0.3, 60), Color("85866e"))
	_channel(PackedVector3Array([Vector3(0, 0, -30), Vector3(0, 0, -3)]), 3.4, 1.5)
	_channel(PackedVector3Array([Vector3(0, 0, -3), Vector3(0, 0, 3)]), 3.4, 1.5, true)
	_channel(PackedVector3Array([Vector3(0, 0, 3), Vector3(0, 0, 30)]), 3.4, 1.5)
	_slab(Vector3(0, 0.22, 0), Vector3(60, 0.3, 5), Color("494e51"))
	# Raised cutaway trays make the small examples visible without terrain excavation.
	_channel(PackedVector3Array([Vector3(9, 1.0, 7), Vector3(9, 1.0, 24)]), 0.8, 0.7)
	_channel(PackedVector3Array([Vector3(-9, 1.0, 7), Vector3(-9, 1.0, 24)]), 0.8, 0.7, true)
	_label("OPEN CHANNEL\nillustrative 3.4 m × 1.5 m", Vector3(0, 2, -19))
	_label("COVERED CROSSING\nillustrative box culvert", Vector3(0, 3, 0))
	_label("OPEN DRAIN\nraised cutaway", Vector3(10, 3, 16))
	_label("COVERED DRAIN\nraised cutaway", Vector3(-10, 3, 16))
	camera = Camera3D.new()
	camera.current = true
	camera.far = 250.0
	add_child(camera)
	_update_camera()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var notice := Label.new()
	notice.text = "SYNTHETIC DRAINAGE DEMO — NOT GODAVARIKHANI DATA\nDrag left mouse to orbit · Wheel to zoom · Esc to release mouse\nDimensions are examples. No real routes, flow direction or hydraulic simulation."
	notice.position = Vector2(18, 18)
	notice.add_theme_color_override("font_color", Color.WHITE)
	notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice.add_theme_constant_override("shadow_offset_x", 2)
	notice.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(notice)

func _channel(points: PackedVector3Array, width: float, depth: float, covered := false) -> void:
	var channel := Channel.new()
	add_child(channel)
	channel.build(points, width, depth, covered)

func _slab(at: Vector3, size: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var helper := Channel.new()
	add_child(helper)
	helper._box(helper, at, size, material)

func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 40
	label.pixel_size = 0.035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch - event.relative.y * 0.008, -1.45, -0.15)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(12.0, distance - 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(100.0, distance + 3.0)
		_update_camera()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(Vector3.ZERO)
