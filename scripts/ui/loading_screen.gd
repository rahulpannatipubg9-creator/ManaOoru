extends CanvasLayer

## Sits on the root above every scene and takes the game from the title to play.
## The bar shows real work: the threaded scene load, then the world's build stages, then
## main.gd's own set-up. This layer draws in the frames the staged build leaves free.

const MAIN_SCENE := "res://scenes/main.tscn"
const BOOT_SCENE := "res://scenes/boot.tscn"
const THEN_SQUAD := "squad"
const THEN_SETTINGS := "settings"
const SKY_SHADER := preload("res://shaders/title_sky.gdshader")
## Share of the bar for each phase: files read by then, world built by then.
const FILES_END := 0.15
const WORLD_END := 0.95
const TIP_SECONDS := 5.0
## Six words at most, one at a time.
const TIPS := [
	"Every road here is real.",
	"Traffic keeps left in India.",
	"Watch your fuel on long drives.",
	"Coins wait along the roadside.",
	"Explore the coal gallery underground.",
	"The bus station shows every route.",
	"The Godavari bridge is worth finding.",
	"Shops sell tea and snacks.",
]

## What to open once the game is up: THEN_SQUAD, THEN_SETTINGS or nothing.
var then := ""
## Seconds from start to the game showing, for measuring.
var elapsed_msec := 0
var _started_msec := 0
var _target := 0.0
var _shown := 0.0
var _world_label := ""
var _bar: ColorRect
var _track: ColorRect
var _tip: Label
var _tip_index := 0
var _tip_left := TIP_SECONDS
var _game: Node
var _root: Control

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_msec = Time.get_ticks_msec()
	_build()
	_tip_index = randi() % TIPS.size()
	_tip.text = TIPS[_tip_index]
	_root.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_root, "modulate:a", 1.0, UiTheme.MOTION_NORMAL)
	await fade.finished
	await _load_game()

func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 0.5)
	_bar.size.x = _track.size.x * _shown
	_tip_left -= delta
	if _tip_left <= 0.0:
		_tip_left = TIP_SECONDS
		_next_tip()

func _next_tip() -> void:
	var fade := create_tween()
	fade.tween_property(_tip, "modulate:a", 0.0, UiTheme.MOTION_NORMAL)
	fade.tween_callback(func() -> void:
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip.text = TIPS[_tip_index])
	fade.tween_property(_tip, "modulate:a", 1.0, UiTheme.MOTION_NORMAL)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var sky := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter("ink", UiTheme.INK)
	material.set_shader_parameter("marigold", UiTheme.ACCENT)
	var view := _root.get_viewport_rect().size
	material.set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))
	sky.material = material
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(sky)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL * 2)
	margin.add_theme_constant_override("margin_bottom", UiTheme.SPACE_XL)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", UiTheme.SPACE_S)
	margin.add_child(column)
	_tip = Label.new()
	_tip.add_theme_font_size_override("font_size", UiTheme.FONT_LABEL)
	column.add_child(_tip)
	_track = ColorRect.new()
	_track.color = UiTheme.LINE
	_track.custom_minimum_size.y = UiTheme.SPACE_XS
	column.add_child(_track)
	_bar = ColorRect.new()
	_bar.color = UiTheme.ACCENT
	_bar.custom_minimum_size.y = UiTheme.SPACE_XS
	_bar.size.x = 0.0
	_track.add_child(_bar)

func _load_game() -> void:
	ResourceLoader.load_threaded_request(MAIN_SCENE, "", true)
	var parts := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, parts)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_fail()
			return
		_target = maxf(_target, float(parts[0]) * FILES_END)
		await get_tree().process_frame
	_target = FILES_END
	# Let the bar reach the end of this phase before the long instantiate holds the thread.
	await get_tree().process_frame
	await _enter_game(ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene)

func _fail() -> void:
	push_error("Could not load %s" % MAIN_SCENE)
	get_tree().change_scene_to_file(BOOT_SCENE)
	queue_free()

func _enter_game(scene: PackedScene) -> void:
	_game = scene.instantiate()
	var world: Node = _game.get_node("World")
	# Named through the instance: the class name here would load the world with the title.
	var world_script: GDScript = world.get_script()
	world_script.set("async_build", true)
	world.progress.connect(_on_world_progress)
	# Deferred so main.gd, which awaits the same signal, finishes its set-up first.
	world.built.connect(_on_world_built, CONNECT_DEFERRED)
	var boot := get_tree().current_scene
	get_tree().root.add_child(_game)
	world_script.set("async_build", false)
	get_tree().current_scene = _game
	if boot:
		boot.queue_free()

func _on_world_progress(fraction: float, label: String) -> void:
	_target = maxf(_target, lerpf(FILES_END, WORLD_END, fraction))
	if label != "":
		_world_label = label

func _on_world_built() -> void:
	_target = 1.0
	_open_requested()
	# The first frames of the town are the slowest; cover them, then lift.
	for _frame in 3:
		await get_tree().process_frame
	elapsed_msec = Time.get_ticks_msec() - _started_msec
	print("Loading screen: %.1f s to game" % (elapsed_msec / 1000.0))
	var fade := create_tween()
	fade.tween_property(_root, "modulate:a", 0.0, UiTheme.MOTION_NORMAL)
	await fade.finished
	queue_free()

func _open_requested() -> void:
	var hud: Node = _game.get("hud")
	if then == THEN_SQUAD:
		hud.toggle_multiplayer_panel()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif then == THEN_SETTINGS:
		hud.settings_menu.open_menu()
