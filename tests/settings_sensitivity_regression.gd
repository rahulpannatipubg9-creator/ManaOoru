extends SceneTree
const Settings := preload("res://scripts/mobile/mobile_controls_settings.gd")
func _init() -> void: run.call_deferred()
func run() -> void:
	var settings := Settings.new()
	var person = load("res://scenes/player/person.tscn").instantiate()
	root.add_child(person)
	person.set_physics_process(false)
	var camera = person.camera_pivot
	var previous := 0.0
	for preset: String in ["Low", "Medium", "High", "Seasoned Expert"]:
		settings.apply_preset(preset)
		assert(settings.look_sensitivity > previous, "Presets increase sensitivity")
		previous = settings.look_sensitivity
		settings.apply_to_camera(camera)
		assert(camera.ads_sensitivity == settings.ads_sensitivity)
		assert(camera.ads_gyro_sensitivity == settings.ads_gyro_sensitivity)
	settings.sensitivity_preset = "Custom"
	settings.ads_sensitivity = 0.45
	settings.ads_gyro_sensitivity = 2.35
	settings.gyro_mode = 2
	assert(settings.save_to("user://settings_regression.cfg") == OK)
	var loaded := Settings.new()
	assert(loaded.load_from("user://settings_regression.cfg"))
	assert(is_equal_approx(loaded.ads_sensitivity, 0.45) and is_equal_approx(loaded.ads_gyro_sensitivity, 2.35))
	assert(loaded.sensitivity_preset == "Custom" and loaded.gyro_mode == 2)
	loaded.apply_to_camera(camera)
	camera.gyro_smoothing = 12.0
	camera.gyro_deadzone = 0.0
	camera.gyro_mode = 0
	var before: float = camera._yaw
	camera.apply_gyro_sample(Vector3(0, 1, 0), 0.1)
	assert(camera._yaw == before, "Off ignores hardware gyro samples")
	camera.gyro_mode = 1
	camera.is_aiming = false
	camera.apply_gyro_sample(Vector3(0, 1, 0), 0.1)
	assert(camera._yaw == before, "Scope-only ignores hip-fire samples")
	camera.is_aiming = true
	camera.apply_gyro_sample(Vector3(0, 1, 0), 0.1)
	assert(camera._yaw != before, "Scope-only accepts ADS samples")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_regression.cfg"))
	person.queue_free()
	await process_frame
	print("PASS settings: presets, separate ADS/gyro wiring, custom persistence, Off/Scope gyro gating")
	quit(0)
