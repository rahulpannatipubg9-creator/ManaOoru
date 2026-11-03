extends CanvasLayer
## Holds the shared weather controller. Its menu is the Time & Weather tab in Settings.

const TAB := "Time & Weather"

var environment: CityEnvironment
var _game: Node

func setup(game: Node) -> void:
	_game = game
	process_mode = Node.PROCESS_MODE_ALWAYS
	environment = game.city_life.environment
	game.hud.settings_menu.apply_audio()

func open_menu() -> void:
	_game.hud.settings_menu.open_tab(TAB)

func close_menu() -> void:
	_game.hud.settings_menu.close_menu()

func is_open() -> bool:
	return _game.hud.settings_menu.panel.visible
