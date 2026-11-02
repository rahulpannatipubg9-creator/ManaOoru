extends SceneTree
func _init()->void:
 var document:=GLTFDocument.new()
 var state:=GLTFState.new()
 var result:=document.append_from_file("res://assets/models/vehicles/royal_enfield_bullet/bullet_rig.glb",state)
 if result!=OK:quit(1);return
 var model:=document.generate_scene(state)
 var scene:=PackedScene.new()
 scene.pack(model)
 var saved:=ResourceSaver.save(scene,"res://assets/models/vehicles/royal_enfield_bullet/bullet_motorcycle.scn")
 print("PACK_BULLET ",saved)
 model.free()
 quit(saved)
