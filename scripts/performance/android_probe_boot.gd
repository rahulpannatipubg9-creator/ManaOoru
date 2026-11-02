extends Node

## Only the isolated Android Performance export uses this entry scene.
func _ready() -> void:
	print("PAD7_BOOT ", OS.get_user_data_dir())
	if FileAccess.file_exists("user://pad7_patch.pck"):
		assert(ProjectSettings.load_resource_pack("user://pad7_patch.pck", true))
		print("PAD7_BOOT_PATCH_LOADED")
	if FileAccess.file_exists("user://stress_test.gd"):
		add_child(load("user://stress_test.gd").new())
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
