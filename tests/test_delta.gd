extends SceneTree

var frame_count := 0

func _init():
	pass

func _process(delta: float) -> bool:
	frame_count += 1
	var rendered = Engine.get_process_frames()
	print("Iteration %d: delta=%.5f, process_frames=%d, physics_frames=%d" % [frame_count, delta, rendered, Engine.get_physics_frames()])
	if frame_count >= 10:
		quit()
		return true
	return false

