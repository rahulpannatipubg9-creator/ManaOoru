extends SceneTree

## Covers BUGS.md 11, 17, 18, 19, 22 and 25: the F7 route, saving on Android close, backups of saves,
## armour feedback, hold-to-crouch and the tracer pool.

const PATH := "user://save_and_feedback_regression.json"

var failures := 0
var game: Node
var life: Node
var gameplay: Node

func _init() -> void:
	call_deferred("run_checks")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run_checks() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	life = game.city_life
	gameplay = game.gameplay
	life.save_path = PATH
	life.save_enabled = true
	_clean_saves()
	_check_backups()
	_check_android_close()
	_clean_saves()
	life.save_enabled = false
	_check_f7()
	await _check_armour()
	await _check_shot_pool()
	_check_ctrl_crouch()
	_check_audit_fixes()
	game.queue_free()
	await process_frame
	print("save_and_feedback_regression: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func _clean_saves() -> void:
	for suffix: String in ["", ".bak", ".rejected", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _check_backups() -> void:
	game.hud.set_coins(41)
	check(life.save_progress() and not FileAccess.file_exists(PATH + ".bak"), "The first save has nothing to back up")
	check(life.save_progress() and FileAccess.file_exists(PATH + ".bak"), "Each later save must keep the previous one")
	_write(PATH, "{ not json")
	game.hud.set_coins(0)
	check(life.load_progress() and game.hud.coins_available() == 41, "A corrupt save must fall back to the backup")
	check(FileAccess.get_file_as_string(PATH + ".rejected") == "{ not json", "The corrupt file must be kept")
	check(JSON.parse_string(FileAccess.get_file_as_string(PATH)) is Dictionary, "The restored save must be back in place for city_gameplay")
	_clean_saves()
	_write(PATH, '{"version":99,"coins":500}')
	check(not life.load_progress(), "A save from a newer build must not load")
	check(FileAccess.get_file_as_string(PATH + ".rejected").contains("500"), "A save from a newer build must survive the next autosave")
	check(not FileAccess.file_exists(PATH), "The rejected save must be out of the autosave's way")
	check(life.save_progress(), "A new game must still be able to save")
	check(FileAccess.get_file_as_string(PATH + ".rejected").contains("500"), "Saving must not touch the rejected file")
	_clean_saves()

func _check_android_close() -> void:
	for what: int in [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_WM_GO_BACK_REQUEST, Node.NOTIFICATION_WM_CLOSE_REQUEST]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		game._notification(what)
		check(FileAccess.file_exists(PATH), "Notification %d must save progress" % what)

func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _check_f7() -> void:
	var press := _key(KEY_F7, true)
	game._input(press)
	check(not root.get_viewport().is_input_handled(), "F7 must reach the Activities board, not a map change")
	gameplay._unhandled_input(press)
	check(life.has_modal(), "F7 must open Activities")
	life.close_modal()

func _check_armour() -> void:
	var person: Node = game.person
	person.combat_mode = true
	person.heal_full()
	await process_frame
	gameplay.armour = 50.0
	var seen: Array[float] = []
	var record := func(value: float, _maximum: float) -> void: seen.append(value)
	person.health_changed.connect(record)
	person.take_damage(40.0)
	check(is_equal_approx(person.health, 84.0), "Armour must absorb 60%% of the hit, health is %f" % person.health)
	await process_frame
	await process_frame
	check(seen.size() == 2 and is_equal_approx(seen[-1], person.health), "The last health signal must carry the health after armour: %s" % str(seen))
	person.health_changed.disconnect(record)
	check(is_equal_approx(gameplay.armour, 26.0), "Armour must only be spent once, it is %f" % gameplay.armour)
	person.heal_full()

func _check_shot_pool() -> void:
	var before: int = gameplay.get_child_count()
	for shot in 40:
		gameplay._tracer(Vector3(0, 2, 0), Vector3(0, 2, 10 + shot))
		gameplay._shot_flash(Vector3(0, 2, 0))
	check(gameplay.get_child_count() - before <= gameplay.SHOT_POOL_SIZE * 2, "Sustained fire must not add nodes")
	var line: MeshInstance3D = gameplay._tracers[-1]
	check(line.mesh == gameplay._tracers[0].mesh, "Tracers must share one mesh")
	check(is_equal_approx(line.global_basis.y.length(), 49.0), "A tracer must span its shot, it spans %f" % line.global_basis.y.length())
	check(line.global_position.is_equal_approx(Vector3(0, 2, 24.5)), "A tracer must sit between muzzle and hit")
	check(line.global_basis.y.normalized().is_equal_approx(Vector3.BACK), "A tracer must point along its shot")
	await create_timer(0.2).timeout
	check(not line.visible and not gameplay._flashes[-1].visible, "Tracers and flashes must hide after their moment")

func _step(ctrl: bool) -> void:
	Input.parse_input_event(_key(KEY_CTRL, ctrl))
	Input.flush_buffered_events()
	game.person._physics_process(0.016)

func _check_ctrl_crouch() -> void:
	var person: Node = game.person
	GameplayControls.blocked = false
	person.set_movement_enabled(true)
	_step(true)
	check(person.crouching, "Holding Ctrl must crouch")
	_step(true)
	check(person.crouching, "Crouch must last while Ctrl is held")
	_step(false)
	check(not person.crouching, "Releasing Ctrl must stand up")
	# C toggles: a Ctrl tap on top of it must not undo the toggle.
	person._update_stance(true, false)
	_step(true)
	_step(false)
	check(person.crouching, "Ctrl must not cancel a crouch toggled with C")
	person._update_stance(false, false)
	# Going prone from a held crouch must not snap the player up when Ctrl is let go.
	_step(true)
	person._update_stance(false, true)
	_step(false)
	check(person.prone, "Releasing Ctrl must not cancel prone")
	person._update_stance(false, false)

## Fixes from reading helicopter.gd, city_environment.gd and test_character.gd.
func _check_audit_fixes() -> void:
	var environment: Node = life.environment
	environment.set_weather_mode("Rain")
	environment.set_weather_mode("Automatic")
	check(environment.rain_target == 0.0, "Automatic must drop a forced rain, not hold it for the next cycle")
	environment.set_hour(12)
	for lamp: SpotLight3D in environment._lamps:
		check(not lamp.visible, "Street lamps must stay off by day")
	for vehicle: Node in game.vehicles:
		if vehicle is GdkHelicopter:
			vehicle.condition = 0.0
			vehicle.driving_enabled = true
			vehicle._grounded = not vehicle.can_exit_safely()
			vehicle._physics_process(0.016)
			check(vehicle._grounded == vehicle.can_exit_safely(), "A wreck must keep the exit prompt up to date")
			vehicle.driving_enabled = false
			vehicle.condition = 100.0
	var character: Node = game.person.get_node("TestCharacter")
	game.person.peek_input = 1.0
	character.scripted_speed = 1.8
	for frame in 40:
		character._process(0.05)
	check(absf(character._peek) < 0.01, "A lean must let go during a scripted move")
	game.person.peek_input = 0.0
	character.scripted_speed = -1.0
	character.male_model.rotation.z = 0.3
	character.seated = true
	character._process(0.016)
	check(character.male_model.rotation.is_zero_approx(), "A seated driver must sit upright")
	character.seated = false
