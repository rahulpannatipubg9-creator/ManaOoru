extends SceneTree
const OUT='res://outputs/virat_audit/'
var view: SubViewport
var cam: Camera3D
var label: Label
var atlas: Image
var shot_index := 0
var person: CharacterBody3D
var visual: Node3D
var player: AnimationPlayer
func _init() -> void: run.call_deferred()
func run() -> void:
 root.size=Vector2i(960,720)
 var stage=Node3D.new();root.add_child(stage)
 var world=WorldEnvironment.new();var env=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color('#657580');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.7;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;world.environment=env;stage.add_child(world)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.8;stage.add_child(light)
 var floor=MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.mesh.size=Vector2(200,200);var mat=StandardMaterial3D.new();mat.albedo_color=Color('#83918e');floor.material_override=mat;stage.add_child(floor)
 person=load('res://scenes/player/person.tscn').instantiate();stage.add_child(person)
 await process_frame
 person.set_physics_process(false);person.set_process(false);person.position=Vector3.ZERO
 for node in person.find_children('*','Node3D',true,false):
  if node is not AnimationPlayer:node.set_process(false)
 visual=person.get_node('TestCharacter');visual.set_process(false);player=visual.mixamo_anim_player;player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var game_cam:Camera3D=person.get_node('CameraPivot/SpringArm3D/Camera3D');game_cam.global_position=Vector3(0,1.5,-3);game_cam.look_at(Vector3(0,1.3,0));game_cam.current=true
 view=SubViewport.new();view.size=Vector2i(400,300);view.world_3d=root.world_3d;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
 cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;view.add_child(cam);cam.current=true
 var canvas=CanvasLayer.new();view.add_child(canvas);label=Label.new();label.position=Vector2(8,7);label.add_theme_font_size_override('font_size',16);label.add_theme_color_override('font_shadow_color',Color.BLACK);label.add_theme_constant_override('shadow_offset_x',1);label.add_theme_constant_override('shadow_offset_y',1);canvas.add_child(label)
 atlas=Image.create(1200,2100,false,Image.FORMAT_RGBA8);atlas.fill(Color('#26343b'))
 player.play('Idle_Natural',0);player.seek(.1,true)
 view.size=Vector2i(900,900)
 await shot('Virat — front portrait',Vector3(0,1.50,0),.68,Vector3(0,.03,4))
 await shot('Virat — full body',Vector3(0,.88,0),2.05,Vector3(0,.2,5))
 await shot('Virat — side',Vector3(0,.88,0),2.05,Vector3(5,.2,0))
 quit()
func shot(title: String, center: Vector3, size: float, offset: Vector3) -> void:
 cam.size=size;cam.position=center+offset;cam.look_at(center);label.text=title
 await process_frame
 RenderingServer.force_draw(false)
 await process_frame
 RenderingServer.force_draw(false)
 view.get_texture().get_image().save_png(OUT+'portrait_'+str(shot_index)+'.png');shot_index+=1
