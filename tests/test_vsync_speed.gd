extends SceneTree

func _init() -> void:
	var t0 = Time.get_ticks_msec()
	for i in 10:
		await process_frame
	var t1 = Time.get_ticks_msec()
	print("10 frames took: ", t1 - t0, " ms")
	quit(0)
