extends SceneTree

func _init() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var controls: CanvasLayer = game.environment_controls
	var environment: CityEnvironment = controls.environment
	for mode: String in ["Morning", "Afternoon", "Night"]:
		environment.set_time_mode(mode)
		var selected_hour := environment.hour
		environment._process(1.0)
		assert(environment.hour == selected_hour, "Selected time must stay fixed")
		assert((environment.night > 0.95) == (mode == "Night"), "Preset lighting must match selection")
	assert(not environment._lamp_positions.is_empty(), "Road lamps must exist")
	var lamp_at := environment._lamp_positions[0]
	game.person.global_position = lamp_at - Vector3.UP * 5.0
	environment.apply_state()
	assert(environment._lamps.size() <= 12, "Keep the light pool bounded")
	var lit := false
	for lamp in environment._lamps:
		if lamp.visible:
			lit = true
			assert(lamp.light_energy > 0.0 and lamp.spot_range >= 20.0, "Night lamps must illuminate road level")
			assert((-lamp.global_basis.z).dot(Vector3.DOWN) > 0.99, "Streetlights must point down")
	assert(lit, "Nearby streetlight must activate at night")
	environment.set_weather_mode("Rain")
	environment._process(5.0)
	assert(environment.rain > 0.5 and environment.wetness > 0.0, "Rain selection must produce rain and wetness")
	environment.set_weather_mode("Clear")
	environment._process(8.0)
	assert(environment.rain == 0.0, "Clear selection must stop rain")
	controls.open_menu()
	assert(paused and controls._panel.visible, "Menu must pause gameplay")
	controls.close_menu()
	assert(not paused and not controls._panel.visible, "Closing menu must resume gameplay")
	environment.set_weather_mode("Automatic")
	environment.set_time_mode("Automatic")
	var before := environment.hour
	environment._process(1.0)
	assert(environment.auto_weather and environment.hour != before, "Automatic modes must resume")
	if "--capture" in OS.get_cmdline_user_args():
		environment.set_time_mode("Night")
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.global_position = lamp_at + Vector3(14, 10, 18)
		camera.look_at(lamp_at - Vector3.UP * 5.0)
		camera.current = true
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mana_ooru_night_mode.png")
		controls.open_menu()
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/mana_ooru_weather_menu.png")
		controls.close_menu()
	print("PASS environment modes: fixed presets, automatic cycle, rain/clear, downward road lights, bounded pool, menu pause/resume")
	game.queue_free()
	await process_frame
	quit()
