extends SceneTree
## Rebuild after changing the source GLB or height. Uses ungrounded runtime copies,
## never accumulates corrections already stored in the JSON.
func _init() -> void: run.call_deferred()
func run() -> void:
 var person=load('res://scenes/player/person.tscn').instantiate();root.add_child(person)
 await process_frame
 person.set_physics_process(false);person.set_process(false)
 var helper=person.get_node('TestCharacter');helper.set_process(false)
 var model=load(helper.MIXAMO_MODEL_PATH).instantiate();root.add_child(model)
 var bounds:AABB=helper._skinned_model_bounds(model)
 var factor:float=helper.DEFAULT_MIXAMO_HEIGHT/bounds.size.y
 model.scale=Vector3.ONE*factor;model.position.y=-bounds.position.y*factor
 var player:AnimationPlayer=model.find_children('*','AnimationPlayer',true,false)[0]
 var rig:Skeleton3D=model.find_children('*','Skeleton3D',true,false)[0]
 preload('res://scripts/player/mixamo_animation_library.gd').prepare(player,rig,false)
 player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var curves={}
 for name in ['Crouch_To_Prone','Death_From_The_Front','Drop_Kick','Falling_To_Roll','Flying_Knee_Punch_Combo','Moving_Backward_In_Prone_Position','Prone_Death','Prone_Forward','Prone_Right_Turn','Rifle_Prone_To_Kneel','Roll_Left','Throw_Grenade','Walk_Loop']:
  var clip=player.get_animation(name);player.play(name,0);var samples=[];var count=int(ceil(clip.length*30))
  for i in count+1:
   var time=minf(float(i)/30,clip.length-.00001);player.seek(time,true);rig.force_update_all_bone_transforms()
   var box:AABB=model.transform*helper._skinned_model_bounds(model)
   samples.append([time,maxf(0,-box.position.y+.003)])
  curves[name]=samples
 var file=FileAccess.open('res://data/characters/mixamo_grounding.json',FileAccess.WRITE)
 file.store_string(JSON.stringify(curves))
 person.queue_free();model.queue_free();await process_frame
 print('Built grounding curves for ',curves.size(),' clips')
 quit()
