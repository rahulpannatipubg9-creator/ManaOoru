extends SceneTree
const OUT='res://outputs/animation_audit/'
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
 for item in [['Idle_Natural','Idle',0.6],['Jogging','Jog',0.6],['Idle_Crouching','Crouch',0.6],['Prone_Idle','Prone',0.6],['Jump','Jump pose',1.1],['Grenade_Throw','Standing grenade',1.3],['Throw_Grenade','Prone grenade',1.6],['Reload','Prone reload',1.3]]:
  visual._prone=1.0 if item[1]=='Prone reload' else 0.0;visual._crouch=0.0;visual._mixamo_action_lock=1.0 if item[1]=='Prone reload' else 0.0
  player.play(item[0],0);player.seek(item[2],true)
  await shot(item[1],person.global_position+Vector3(0,.85,0),2.35,Vector3(3,1,5))
 visual._prone=0;visual._mixamo_action_lock=0;person.combat_mode=true;person.set_weapon_equipped(true)
 for weapon in [0,1,2]:
  person.set_weapon_model(weapon);person.weapon_draw_time=0
  for aim in [0.0,1.0]:
   person._aim_blend=aim;player.play('Rifle_Aiming_Idle',0);player.seek(.6,true);person._update_weapon_presentation(0);player.seek(.6,true)
   await shot(['M416','AK47','Bren 2'][weapon]+(' aiming' if aim>0 else ' ready'),Vector3(0,1.0,.1),2.35,Vector3(3,1,5))
 person.prone=true
 for weapon in [0,1,2]:
  person.set_weapon_model(weapon);person.weapon_draw_time=0;person._aim_blend=1.0
  player.play('Prone_Forward',0);player.seek(.4,true);person._update_weapon_presentation(0);player.seek(.4,true)
  await shot(['M416','AK47','Bren 2'][weapon]+' prone crawl',Vector3(0,.35,.2),2.35,Vector3(3,1,5))
 person.prone=false
 person.set_weapon_equipped(false);visual.seated=true;visual._seat=1
 for path in ['res://scenes/vehicles/porsche_911.tscn','res://scenes/vehicles/jeep_compass.tscn','res://scenes/vehicles/rigid_thar.tscn','res://scenes/vehicles/royal_enfield_bullet.tscn']:
  var car=load(path).instantiate();stage.add_child(car);car.freeze=true;car.global_transform=Transform3D.IDENTITY
  var car_bounds:=AABB();var first:=true
  for mesh:MeshInstance3D in car.find_children('*','MeshInstance3D',true,false):
   if not mesh.is_visible_in_tree():continue
   var box:=mesh.global_transform*mesh.get_aabb()
   car_bounds=box if first else car_bounds.merge(box);first=false
  car.position.y=-car_bounds.position.y+.01;car.reset_physics_interpolation()
  var entry=load('res://scripts/vehicle/vehicle_entry.gd').new();stage.add_child(entry);entry.begin_enter(person,car);entry.set_process(false);entry.set_physics_process(false);visual.seated=true;visual._seat=1.0
  if entry._door_rig:entry._door_rig.set_fraction(1)
  person.global_transform=entry.seat_transform(car);entry._follow_seat()
  player.play('Drive_Seated',0);player.seek(1.0,true)
  await shot(path.get_file().get_basename()+' driver',car.global_position+Vector3(0,.85,0),3.3 if 'bullet' in path else 4.7,Vector3(-4,1.1,3))
  car.queue_free();entry.queue_free();await process_frame
 atlas.save_png(OUT+'gameplay_contacts.png');print('CAPTURE gameplay poses ',shot_index)
 quit()
func shot(title: String, center: Vector3, size: float, offset: Vector3) -> void:
 cam.size=size;cam.position=center+offset;cam.look_at(center);label.text=title
 await process_frame
 await RenderingServer.frame_post_draw
 atlas.blit_rect(view.get_texture().get_image(),Rect2i(0,0,400,300),Vector2i((shot_index%3)*400,(shot_index/3)*300));shot_index+=1
