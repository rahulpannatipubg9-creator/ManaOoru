extends SceneTree

## Screenshots of the HUD in its main states, for looking at the design. Needs a real window:
##   run_godot.sh 120 --path . --script tests/capture_hud.gd                 (stub game, quick)
##   run_godot.sh 400 --path . --script tests/capture_hud.gd -- --real-game  (whole town, slow)
## PNGs land in user://hud_captures (the path is printed).

const OUT := "user://hud_captures"
const Readouts := preload("res://scripts/ui/hud_readouts.gd")
const PLAYER := """extends CharacterBody3D
var is_running := false
var movement_enabled := true
var respawn_position := Vector3.ZERO
var touch_peek_input := 0.0
var camera_pivot: Node3D
var health := 100.0
var max_health := 100.0
var weapon_id := 0
var crouching := false
var prone := false
var equipped := false
func set_touch_move_input(_v: Vector2) -> void: pass
func set_touch_run_pressed(_v: bool) -> void: pass
func is_weapon_equipped() -> bool: return equipped
"""
const PIVOT := """extends Node3D
var touch_aim := false
var is_aiming := false
var gyro_mode := 0
var touch_free_look := false
var look_sensitivity := 1.0
var ads_sensitivity := 1.0
var gyro_sensitivity := 1.0
var ads_gyro_sensitivity := 1.0
var gyro_invert_x := false
var gyro_invert_y := false
func clear_touch_look() -> void: touch_aim = false
"""
const GAMEPLAY := """extends Node
var action_mode := false
var has_rifle := true
var ammo := 24
var reserve := 120
var medkits := 2
var grenades := 3
var fire_mode := 0
var armour := 0.0
var wanted_level := 0
var mission: Dictionary = {}
var touch_fire_pressed := false
func rifles() -> Array[int]: return [0, 1]
"""
const GAME := """extends Node
enum ControlState { ON_FOOT, DRIVING }
var control_state := ControlState.ON_FOOT
var gameplay: Node
var city_life: Node
var first_person_view := false
"""

var _hud: CanvasLayer
var _game: Node
var _play: Node
var _person: Node
var _background: ColorRect

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await process_frame
	root.size = Vector2i(1280, 720)
	if OS.get_cmdline_user_args().has("--real-game"):
		await _boot_real_game()
	else:
		await _boot_stub()
	await _shoot_all()
	print("Captures in ", ProjectSettings.globalize_path(OUT))
	quit()

func _boot_stub() -> void:
	var gradient := GradientTexture2D.new()
	gradient.fill_to = Vector2(0.0, 1.0)
	gradient.gradient = Gradient.new()
	gradient.gradient.set_color(0, Color("9cc4d8"))
	gradient.gradient.set_color(1, Color("6f6a58"))
	var picture := TextureRect.new()
	picture.texture = gradient
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size = Vector2(1280, 720)
	root.add_child(picture)
	_background = ColorRect.new() # Stands in for the minimap, which needs a whole town.
	_background.color = Color("3a4a44")
	root.add_child(_background)
	_game = Node.new()
	_game.set_script(_script(GAME))
	root.add_child(_game)
	_play = Node.new()
	_play.set_script(_script(GAMEPLAY))
	_game.add_child(_play)
	_game.gameplay = _play
	_person = CharacterBody3D.new()
	_person.set_script(_script(PLAYER))
	_person.name = "Player"
	_game.add_child(_person)
	var pivot := Node3D.new()
	pivot.set_script(_script(PIVOT))
	_person.add_child(pivot)
	_person.camera_pivot = pivot
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_game.add_child(_hud)
	await process_frame
	_hud._game = _game
	UiTheme.apply(root)

func _boot_real_game() -> void:
	_game = load("res://scenes/main.tscn").instantiate()
	root.add_child(_game)
	for _i in 30:
		await process_frame
	_hud = _game.hud
	_play = _game.gameplay
	_person = _game.person
	_play.has_rifle = true
	_play.owned_rifles.assign([0, 1])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _touch(value: bool) -> void:
	_hud._touch_overlay_enabled = value
	_hud.get_node("TouchControls").visible = value
	_hud._layout_for_viewport()
	if _background != null:
		var rects: Dictionary = _hud._layout_context(_hud._current_profile()).rects if value else _hud._desktop_rects(Vector2(1280, 720))
		_background.position = rects[&"Minimap"].position
		_background.size = rects[&"Minimap"].size

func _calm() -> void:
	_play.action_mode = false
	_person.set("equipped", false)
	if _person.has_method("set_weapon_equipped"):
		_person.set_weapon_equipped(false)
	_play.wanted_level = 0
	_play.mission = {}
	_person.health = _person.max_health
	_play.armour = 0.0
	_hud.set_interaction_prompt("")
	_hud.set_enter_available(false)
	_hud.action_wheel.close()
	_hud.readouts._vitals_left = 0.0

func _rifle() -> void:
	_play.action_mode = true
	_person.set("equipped", true)
	if _person.has_method("set_weapon_equipped"):
		_person.set_weapon_equipped(true)

func _driving(flying := false) -> void:
	_calm()
	_game.control_state = _game.ControlState.DRIVING
	_hud.set_speed(72.0)
	_hud.set_gear("D3", 3400.0, true)
	_hud.readouts.flying = flying

func _shoot_all() -> void:
	for touch: bool in [false, true]:
		var tag := "touch" if touch else "desktop"
		_touch(touch)
		_calm()
		await _shoot(tag + "_calm")
		_hud.set_interaction_prompt("[E]  ENTER Thar_Truck")
		_hud.set_enter_available(true)
		await _shoot(tag + "_prompt")
		_calm()
		_rifle()
		_person.health = 62.0
		_play.armour = 40.0
		_play.wanted_level = 2
		_play.mission = {"title": "Market delivery", "stage": "Pickup", "time": 252.0}
		_hud.show_coin_delta(5)
		await _shoot(tag + "_rifle_wanted_job")
		_hud.action_wheel.open_sticky()
		_hud.action_wheel.selected = 3
		_hud.action_wheel.queue_redraw()
		await _shoot(tag + "_wheel")
		_hud.action_wheel.close()
		_driving()
		await _shoot(tag + "_driving")
		if touch:
			_hud.set_gear("3", 5900.0, false)
			await _shoot(tag + "_driving_manual")
			_hud.set_gear("D3", 3400.0, true)
		_game.control_state = _game.ControlState.ON_FOOT

func _shoot(shot: String) -> void:
	# Long enough for the fades to finish: UiTheme.MOTION_NORMAL is 0.2 s.
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [OUT, shot]
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script
