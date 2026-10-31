extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
 var game=load('res://scenes/main.tscn').instantiate();root.add_child(game)
 for i in 80:await physics_frame
 var person:CharacterBody3D=game.person
 var visual=person.get_node('TestCharacter')
 var bounds:AABB=visual.mixamo_model.global_transform*visual._skinned_model_bounds(visual.mixamo_model)
 print('WORLD PLAYER skinned bounds ',bounds,' model scale ',visual.mixamo_model.scale)
 var view=SubViewport.new();view.size=Vector2i(1280,800);view.world_3d=root.world_3d;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
 var camera=Camera3D.new();view.add_child(camera);camera.current=true;camera.fov=45
 camera.environment=root.get_camera_3d().environment
 camera.position=person.global_position+Vector3(5,3.2,5);camera.look_at(person.global_position+Vector3(0,.85,0))
 for i in 8:await process_frame
 await RenderingServer.frame_post_draw
 view.get_texture().get_image().save_png('res://outputs/animation_audit/world_scale.png')
 print('CAPTURE world scale complete')
 quit()
