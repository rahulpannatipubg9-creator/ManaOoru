extends Node

## The first scene. It stays this small on purpose: nothing here may reach the game's
## scripts, because whatever this file loads delays the first frame of the title.

const TitleScreen := preload("res://scripts/ui/title_screen.gd")

func _ready() -> void:
	UiTheme.apply(get_tree().root)
	# Stock buttons only answer the mouse, and the project turns touch emulation off for the game.
	Input.emulate_mouse_from_touch = true
	add_child(TitleScreen.new())

func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = false
