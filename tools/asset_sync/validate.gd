extends SceneTree
func _initialize() -> void:
 var packed = load("res://scenes/world/imported_buildings_review.tscn") as PackedScene
 if packed == null:
  quit(1)
  return
 var instance = packed.instantiate()
 root.add_child(instance)
 var count = instance.get_child_count()
 print("ASSET_SYNC_REVIEW_OK: ", count, " building assets loaded")
 quit(0 if count > 0 else 1)
