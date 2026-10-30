extends Node

## Menus built from Godot's stock controls (tabs, dropdowns, sliders, scroll lists)
## only listen to the mouse, and touch-to-mouse emulation is off so the in-game claw
## keeps true multi-touch. While a menu is open over a paused game, this switches
## Godot's emulation on (the first finger becomes the mouse, including inside the
## separate window a dropdown opens) and swallows the raw touches, so buttons that
## understand touch are not pressed twice. The game is paused while these menus are
## up, so that pointer can never fire the rifle or turn the camera.

## Returns true while a menu that needs the bridge is on screen.
var is_menu_open: Callable
## Returns true while a menu is up over a running game (a live Team Deathmatch never
## pauses). The menu fills the screen, so the pointer lands on it and not on the rifle.
var live_menu: Callable
## Returns true when menus run over a live game that cannot pause, as in a match, where firing is
## blocked by other means.
var runs_unpaused: Callable
## Fingers that landed while a menu was open. They stay the menu's until they lift,
## so the lift after "Save & Return" cannot fall through onto the minimap below it.
var _menu_fingers := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	var wanted := menu_active() or not _menu_fingers.is_empty()
	if Input.emulate_mouse_from_touch != wanted:
		Input.emulate_mouse_from_touch = wanted

func menu_active() -> bool:
	if not is_inside_tree():
		return false
	if live_menu.is_valid() and live_menu.call():
		return true
	if not is_menu_open.is_valid():
		return false
	return (get_tree().paused or (runs_unpaused.is_valid() and runs_unpaused.call())) and is_menu_open.call()

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var index: int = event.index
	var owned := _menu_fingers.has(index)
	if event is InputEventScreenTouch and event.pressed and menu_active():
		_menu_fingers[index] = true
		owned = true
	if not owned:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch and (not event.pressed or event.canceled):
		_menu_fingers.erase(index)

func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = false
