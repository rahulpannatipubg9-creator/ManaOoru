extends SceneTree

## Walks the real front door in a window: title, press New Game, loading, game. Saves PNGs and
## logs the time to each milestone. Run windowed, with saves off, so no real save is touched:
##   run_godot.sh 500 --path . --windowed --resolution 1280x720 --script tests/capture_front_door.gd -- --city-life-no-save --out=<dir>

var out := "user://"
var _shots := {}
var _log_next := 0.0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_run.call_deferred()

func _shot(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_text])

func _find(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var hit := _find(child, text)
		if hit:
			return hit
	return null

func _run() -> void:
	change_scene_to_file("res://scenes/boot.tscn")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	print("FRONT DOOR title first frame at %d ms" % Time.get_ticks_msec())
	for _frame in 30:
		await process_frame
	await _shot("title")
	if "--screens" in OS.get_cmdline_user_args():
		await _screens()
		quit()
		return
	var start := Time.get_ticks_msec()
	var button := _find(current_scene, "New Game")
	assert(button != null, "New Game must exist with no save")
	button.pressed.emit()
	var loading: Node = null
	while loading == null:
		await process_frame
		for child in root.get_children():
			if child is CanvasLayer and child.get("then") != null:
				loading = child
	var next_shot := 8.0
	var index := 0
	while is_instance_valid(loading):
		await process_frame
		var seconds := (Time.get_ticks_msec() - start) * 0.001
		var target: float = loading.get("_target") if is_instance_valid(loading) else 1.0
		if seconds > _log_next:
			_log_next = seconds + 2.0
			print("FRONT DOOR %.1f s bar %.2f %s" % [seconds, target, loading.get("_world_label")])
		if seconds > next_shot and paused:
			next_shot = seconds + 30.0
			index += 1
			await _shot("loading_%d" % index)
	print("FRONT DOOR game showing %.1f s after New Game; scene %s" % [(Time.get_ticks_msec() - start) * 0.001, current_scene.name])
	for _frame in 60:
		await process_frame
	await _shot("game")
	quit()

func _screens() -> void:
	_find(current_scene, "Settings").pressed.emit()
	await process_frame
	await _shot("settings")
	_find(current_scene, "Done").pressed.emit()
	await process_frame
	_find(current_scene, "Credits").pressed.emit()
	for _frame in 20:
		await process_frame
	await _shot("credits_top")
	for _frame in 400:
		await process_frame
	await _shot("credits_mid")
