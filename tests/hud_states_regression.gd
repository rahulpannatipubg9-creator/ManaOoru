extends SceneTree

## The HUD state table and touch table from docs/reference/UI_DESIGN.md, on the real HUD scene
## with a stub game: what shows in each moment, what fades, and the public API.

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
func clear_touch_look() -> void: touch_aim = false
"""
const GAMEPLAY := """extends Node
var action_mode := false
var has_rifle := true
var ammo := 24
var reserve := 120
var medkits := 1
var grenades := 3
var fire_mode := 0
var armour := 0.0
var wanted_level := 0
var mission: Dictionary = {}
var touch_fire_pressed := false
var owned: Array[int] = [0]
func rifles() -> Array[int]: return owned
"""
const GAME := """extends Node
enum ControlState { ON_FOOT, DRIVING }
var control_state := ControlState.ON_FOOT
var gameplay: Node
var city_life: Node
var first_person_view := false
"""

var _failures := 0
var _hud: CanvasLayer
var _read: Control
var _game: Node
var _play: Node
var _person: Node

func _init() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	_game = Node.new()
	_game.set_script(_script(GAME))
	viewport.add_child(_game)
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
	_read = _hud.readouts
	_test_removed_ui()
	await _test_calm()
	await _test_prompt()
	await _test_vitals_fade()
	await _test_rifle()
	await _test_wanted_and_objective()
	await _test_driving()
	_test_coins()
	await _test_touch_table()
	_test_prompt_parsing()
	if _failures > 0:
		print("FAIL hud states regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS hud states regression: removed debug UI, calm screen, prompt pill, vitals fade, rifle/driving/wanted/job states, coin pop-up, touch table")
	quit()

func _test_removed_ui() -> void:
	for gone: String in ["Panel", "Offline", "VehicleControlsHint", "TouchControls/LookHint", "TouchControls/Reset"]:
		_check(_hud.get_node_or_null(gone) == null, "%s is gone from the HUD" % gone)
	for button in _hud.get_node("TouchControls").find_children("*", "Button", true, false):
		var words := ""
		for character in button.text:
			if character.unicode_at(0) > 0x2000:
				words = button.text
		_check(words.is_empty(), "%s shows no emoji" % button.name)
	_check(_hud.get_node_or_null("InteractionPrompt") != null, "The pill keeps the name Team Deathmatch hides it by")

## Runs frames, then enough fade time for anything on its way in or out to finish.
func _settle() -> void:
	await process_frame
	_read.tick(1.0)

func _test_calm() -> void:
	await _settle()
	for part: String in ["Vitals", "Ammo", "Drive", "Wanted", "Objective", "InteractionPrompt"]:
		_check(not _read.is_showing(part), "Calm on foot hides %s" % part)
	_check(_hud.compass_bar.visible, "Calm on foot keeps the compass")

func _test_prompt() -> void:
	_hud.set_interaction_prompt("[E]  ENTER Thar_Truck")
	await _settle()
	_check(_read.is_showing("InteractionPrompt"), "A prompt shows the pill")
	_hud.set_interaction_prompt("")
	await _settle()
	_check(not _read.is_showing("InteractionPrompt"), "An empty prompt hides the pill")

func _test_vitals_fade() -> void:
	_person.health = 70.0
	await _settle()
	_check(_read.is_showing("Vitals"), "Getting hurt shows vitals")
	for _i in 10:
		_read.tick(1.0)
	_check(_read.is_showing("Vitals"), "Vitals stay while health is below full")
	_person.health = 100.0
	await process_frame
	_read.tick(0.01)
	_read.tick(3.0)
	_check(_read.is_showing("Vitals"), "Vitals stay for a while after healing")
	_read.tick(1.5)
	_read.tick(0.5)
	_check(not _read.is_showing("Vitals"), "Vitals fade about 4 s after reaching full health")
	_play.armour = 50.0
	await _settle()
	_check(is_equal_approx(_read.armour, 50.0), "Armour is read from the game")
	_play.armour = 0.0
	await process_frame
	_read.tick(5.0)

func _test_rifle() -> void:
	_person.equipped = true
	await _settle()
	_check(_read.is_showing("Ammo") and _read.is_showing("Vitals"), "Rifle out shows ammo and vitals")
	_check(_read.mag == 24 and _read.reserve == 120, "Ammo is read from the game")
	_check(not _read.weapon_name.is_empty(), "The rifle is named")
	_person.equipped = false
	await process_frame
	_read.tick(5.0)
	_check(not _read.is_showing("Ammo") and not _read.is_showing("Vitals"), "Putting it away hides both again")

func _test_wanted_and_objective() -> void:
	_play.wanted_level = 3
	_play.mission = {"title": "Delivery", "stage": "Pickup", "time": 125.0}
	await _settle()
	_check(_read.is_showing("Wanted") and _read.wanted == 3, "Wanted shows stars")
	_check(_read.is_showing("Objective") and _read.objective_title() == "Delivery", "A job shows the objective")
	_check(_read._objective_detail.text.contains("2:05"), "The objective carries the timer (%s)" % _read._objective_detail.text)
	_play.wanted_level = 0
	_play.mission = {}
	await _settle()
	_check(not _read.is_showing("Wanted") and not _read.is_showing("Objective"), "Both leave when over")
	_hud.set_objective("Find Rahul", "Near the bridge")
	await _settle()
	await _settle()
	_check(_read.is_showing("Objective") and _read.objective_title() == "Find Rahul", "A caller's objective is not wiped by the game's empty one")
	_hud.clear_objective()
	await _settle()
	_check(not _read.is_showing("Objective"), "clear_objective clears it")

func _test_driving() -> void:
	_game.control_state = _game.ControlState.DRIVING
	_hud.set_speed(72.4)
	_hud.set_gear("D3", 3200.0, true)
	await _settle()
	_check(_read.is_showing("Drive") and not _read.is_showing("Ammo"), "Driving shows speed")
	_check(roundi(_read.speed_kmh) == 72 and _read.gear_label == "D3", "Speed and gear reach the readout")
	_hud.set_flight_altitude(120.0)
	_check(is_equal_approx(_read.altitude, 120.0), "Altitude reaches the readout")
	_game.control_state = _game.ControlState.ON_FOOT
	await _settle()
	_check(not _read.is_showing("Drive"), "Getting out hides speed")

func _test_coins() -> void:
	_read.tick(10.0)
	_hud.set_coins(10)
	_check(not _read._coins.visible, "Loading a wallet makes no pop-up")
	_hud.add_coins(5)
	_read.tick(0.01)
	_check(_read._coins.visible and _read._coins.text == "+5", "Earning shows +5")
	_hud.add_coins(3)
	_read.tick(0.01)
	_check(_read._coins.text == "+8", "Coins arriving together add up (%s)" % _read._coins.text)
	_read.tick(3.0)
	_check(not _read._coins.visible, "The pop-up fades")
	_check(_hud.spend_coins(4), "Spending works")
	_read.tick(0.01)
	_check(_read._coins.text == "-4", "Spending shows -4 (%s)" % _read._coins.text)
	_check(_hud.coins_available() == 14, "The wallet stays right")
	_read.tick(3.0)

func _visible_buttons() -> Array[String]:
	var names: Array[String] = []
	for child in _hud.get_node("TouchControls").get_children():
		if child is Button and child.visible:
			names.append(child.name)
	names.sort()
	return names

func _expect_buttons(state: String, expected: Array[String]) -> void:
	await process_frame
	await process_frame
	expected.sort()
	var seen := _visible_buttons()
	_check(seen == expected, "%s shows %s, got %s" % [state, expected, seen])

func _test_touch_table() -> void:
	_hud._touch_overlay_enabled = true
	_hud.get_node("TouchControls").visible = true
	_hud._layout_for_viewport()
	await _expect_buttons("Calm on foot", ["Jump", "Run", "BtnWheel", "BtnMenu"])
	_hud.set_enter_available(true)
	await _expect_buttons("Near a vehicle", ["Jump", "Run", "Enter", "BtnWheel", "BtnMenu"])
	_hud.set_enter_available(false)
	_hud.set_interaction_prompt("[E] SHOP")
	await _expect_buttons("Near a shop", ["Jump", "Run", "Enter", "BtnWheel", "BtnMenu"])
	_hud.set_interaction_prompt("")
	_play.action_mode = true
	_person.equipped = true
	await _expect_buttons("Rifle out", ["Jump", "Run", "BtnWheel", "BtnMenu", "BtnFireRight", "BtnScope", "BtnReload", "BtnCrouch"])
	_play.owned = [0, 1]
	await _expect_buttons("Two rifles", ["Jump", "Run", "BtnWheel", "BtnMenu", "BtnFireRight", "BtnScope", "BtnReload", "BtnCrouch", "BtnSwap"])
	_play.owned = [0]
	_play.action_mode = false
	_person.equipped = false
	_game.control_state = _game.ControlState.DRIVING
	await _expect_buttons("Driving automatic", ["Handbrake", "Exit", "Camera", "BtnWheel", "BtnMenu"])
	_hud.set_gear("3", 3000.0, false)
	await _expect_buttons("Driving manual", ["Handbrake", "Exit", "Camera", "GearUp", "GearDown", "BtnWheel", "BtnMenu"])
	_hud.set_gear("D3", 3000.0, true)
	_game.control_state = _game.ControlState.ON_FOOT
	await process_frame

func _test_prompt_parsing() -> void:
	var split: PackedStringArray = _read.split_prompt("[E]  ENTER Thar_Truck")
	_check(split[0] == "E" and split[1] == "ENTER Thar Truck", "A prompt splits into key and words (%s)" % [split])
	split = _read.split_prompt("Vehicle recovered")
	_check(split[0].is_empty() and split[1] == "Vehicle recovered", "A prompt without a key has no key cap")

func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
