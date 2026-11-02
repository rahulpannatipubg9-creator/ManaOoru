extends SceneTree
const OUT='res://outputs/animation_audit/'
func _init(): call_deferred('run')
func run():
 root.size=Vector2i(960,720)
 var view=SubViewport.new();view.size=Vector2i(320,240);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
 var stage=Node3D.new();view.add_child(stage)
 var world=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#657580');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.7;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;world.environment=env;stage.add_child(world)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.8;stage.add_child(light)
 var floor=MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(200,200);var mat=StandardMaterial3D.new();mat.albedo_color=Color('#83918e');floor.material_override=mat;stage.add_child(floor)
 var person=load('res://scenes/player/person.tscn').instantiate();stage.add_child(person)
 await process_frame
 person.set_physics_process(false);person.position=Vector3.ZERO
 var v=person.get_node('TestCharacter');v.set_process(false)
 var a=v.mixamo_anim_player;a.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var sk=v.mixamo_model.find_children('*','Skeleton3D',true,false)[0]
 var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;view.add_child(cam);cam.current=true
 var canvas=CanvasLayer.new();view.add_child(canvas);var label=Label.new();label.position=Vector2(6,5);label.add_theme_font_size_override('font_size',13);label.add_theme_color_override('font_shadow_color',Color.BLACK);label.add_theme_constant_override('shadow_offset_x',1);label.add_theme_constant_override('shadow_offset_y',1);canvas.add_child(label)
 DirAccess.make_dir_recursive_absolute(OUT+'previews')
 var names=a.get_animation_list();var page:Image;var pages=0
 for i in names.size():
  if i%12==0:page=Image.create(960,2880,false,Image.FORMAT_RGBA8);page.fill(Color('#26343b'))
  var clip=names[i];var anim=a.get_animation(clip);a.play(clip,0)
  for j in 3:
   var t=anim.length*[.1,.5,.9][j];a.seek(t,true);sk.force_update_all_bone_transforms()
   var b=v.mixamo_model.transform*v._skinned_model_bounds(v.mixamo_model)
   cam.size=maxf(2.35,maxf(b.size.y,b.size.x)*1.45);cam.position=b.get_center()+Vector3(3,1.1,5);cam.look_at(b.get_center())
   label.text=clip+'\n%.2fs / %.2fs' %[t,anim.length]
   await process_frame
   await RenderingServer.frame_post_draw
   var img=view.get_texture().get_image();page.blit_rect(img,Rect2i(0,0,320,240),Vector2i(j*320,(i%12)*240))
  page.get_region(Rect2i(0,(i%12)*240,960,240)).save_png(OUT+'previews/'+clip+'.png')
  if i%12==11 or i==names.size()-1:
   pages+=1;page.save_png(OUT+'corrected_%02d.png'%pages);print('SAVED page ',pages)
 print('RENDERED ',names.size(),' clips at three times')
 quit()
