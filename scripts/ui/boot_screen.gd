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

## Quits from anywhere. In the game, main.gd saves when it hears the close request.
static func quit_game(tree: SceneTree) -> void:
	tree.root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	tree.quit()
