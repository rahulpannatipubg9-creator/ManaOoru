extends SceneTree

func _init():
	var scene_path = "res://scenes/world/godavari_bridge_driving.tscn"
	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate() as Node3D
	root.add_child(instance)
	
	for frame in range(15):
		await process_frame
	
	var img: Image = root.get_texture().get_image()
	if img:
		img.save_png("res://bridge_viewport_capture.png")
		print("Saved bridge_viewport_capture.png size: ", img.get_size(), " format: ", img.get_format())
	else:
		print("No image from root viewport")
	
	instance.queue_free()
	quit()

