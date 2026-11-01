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
 var doc=GLTFDocument.new();var state=GLTFState.new();doc.append_from_file('/Users/rahulpannati/Downloads/Virat.glb',state)
 var original=doc.generate_scene(state);stage.add_child(original)
 for ap in original.find_children('*','AnimationPlayer',true,false):ap.stop()
 await process_frame
 view=SubViewport.new();view.size=Vector2i(400,300);view.world_3d=root.world_3d;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
 cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;view.add_child(cam);cam.current=true
 var canvas=CanvasLayer.new();view.add_child(canvas);label=Label.new();label.position=Vector2(8,7);label.add_theme_font_size_override('font_size',16);label.add_theme_color_override('font_shadow_color',Color.BLACK);label.add_theme_constant_override('shadow_offset_x',1);label.add_theme_constant_override('shadow_offset_y',1);canvas.add_child(label)
 atlas=Image.create(1200,2100,false,Image.FORMAT_RGBA8);atlas.fill(Color('#26343b'))
 view.size=Vector2i(900,900)
 await shot('Original download — front',Vector3(0,1.65,0),.7,Vector3(0,.03,4))
 quit()
func shot(title: String, center: Vector3, size: float, offset: Vector3) -> void:
 cam.size=size;cam.position=center+offset;cam.look_at(center);label.text=title
 await process_frame
 RenderingServer.force_draw(false)
 await process_frame
 RenderingServer.force_draw(false)
 view.get_texture().get_image().save_png(OUT+'source_portrait_'+str(shot_index)+'.png');shot_index+=1
