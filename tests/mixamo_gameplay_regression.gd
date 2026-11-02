extends SceneTree
var failures := 0
var checks := 0
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func run() -> void:
 var person = load('res://scenes/player/person.tscn').instantiate()
 root.add_child(person)
 await process_frame
 person.set_physics_process(false)
 person.set_process(false)
 var v = person.get_node('TestCharacter')
 v.set_process(false)
 var a: AnimationPlayer = v.mixamo_anim_player
 a.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var cases = [
  ['idle',0.0,true,false,false,false,false,0.0,'Idle_Natural'],
  ['walk',1.8,true,false,false,false,false,0.0,'Walk_Loop'],
  ['jog',4.2,true,false,false,false,false,0.0,'Jogging'],
  ['sprint',7.0,true,false,false,false,false,0.0,'Jogging'],
  ['crouch idle',0.0,true,true,false,false,false,0.0,'Idle_Crouching'],
  ['crouch moving',2.1,true,true,false,false,false,0.0,'Crouch_Walking'],
  ['prone idle',0.0,true,false,true,false,false,0.0,'Prone_Idle'],
  ['prone crawl',0.7,true,false,true,false,false,0.0,'Prone_Forward'],
  ['unarmed jump',0.0,false,false,false,false,false,0.0,'Jump'],
  ['running jump',4.2,false,false,false,false,false,0.0,'Running_Jump'],
  ['armed jump',4.2,false,false,false,true,false,0.0,'Rifle_Jump'],
  ['fall',0.0,false,false,false,false,false,0.8,'Jumping_Down'],
  ['rifle idle',0.0,true,false,false,true,false,0.0,'Rifle_Aiming_Idle'],
  ['rifle move',4.2,true,false,false,true,false,0.0,'Walk_With_Rifle'],
  ['swim idle',0.0,true,false,false,false,true,0.0,'Floating'],
  ['swim moving',2.0,true,false,false,false,true,0.0,'Swimming']]
 for c in cases:
  v._mixamo_action_lock=0.0;v._crouch=1.0 if c[3] else 0.0;v._prone=1.0 if c[4] else 0.0;v._air_time=c[7]
  person.swimming=c[6];person.set_weapon_equipped(c[5]);person.velocity=Vector3(0,0,c[1]);v._moving_backward=false
  v._process_mixamo(0.016,person,c[1],c[2])
  check(v._mixamo_current_clip==c[8],c[0]+': wrong clip '+v._mixamo_current_clip)
  print('STATE ',c[0],' -> ',v._mixamo_current_clip)
 person.swimming=false;person.set_weapon_equipped(false);v._air_time=0;v._prone=0;v._crouch=0
 for armed in [false,true]:
  person.set_weapon_equipped(armed)
  for x in [-2.0,2.0]:
   person.velocity=Vector3(x,0,0)
   v._process_mixamo(.016,person,2.0,true)
   check(v._mixamo_current_clip==(('Walk_Left_with_gun' if x>0 else 'Walk_Right_with_gun') if armed else 'Strafe'),'lateral movement chooses directional clip')
 person.velocity=Vector3(0,0,-3);v._moving_backward=true;person.set_weapon_equipped(false)
 v._process_mixamo(.016,person,3,true)
 check(v._mixamo_current_clip=='Sprint_Backward','backward movement must select backward gait before jogging')
 v._moving_backward=false;person.velocity=Vector3.ZERO;person.set_weapon_equipped(true);person.weapon_kick=.03
 v._process_mixamo(.016,person,0,true);check(v._mixamo_current_clip=='Firing_Rifle','stationary firing')
 v._process_mixamo(.016,person,2,true);check(v._mixamo_current_clip=='Firing_Rifle_while_walking','moving firing')
 v.set_meta('attack_until',Time.get_ticks_msec()+300)
 v._process_mixamo(.016,person,0,true)
 check(v._mixamo_current_clip=='Firing_Rifle','real rifle attack metadata must not trigger a melee combo')
 v.set_meta('attack_until',0)
 person.weapon_kick=0;person.weapon_reload_time=2.0
 v._process_mixamo(.016,person,0,true);check(v._mixamo_current_clip=='Reload','reload connected')
 check(absf(v._mixamo_action_lock-2)<.02,'reload timing follows gameplay reload duration')
 person.weapon_reload_time=0;v._mixamo_action_lock=0;person.set_weapon_equipped(false)
 for prone in [false,true]:
  v._prone=1.0 if prone else 0.0
  v.play_grenade()
  check(v._mixamo_current_clip==('Throw_Grenade' if prone else 'Grenade_Throw'),'grenade stance selection')
  check(absf(v._mixamo_action_lock-a.get_animation(v._mixamo_current_clip).length/1.2)<.001,'full grenade duration')
  v._mixamo_action_lock=0
 v._prone=0
 for clip in v._melee_combo:
  v._start_mixamo_action(clip,1.2)
  check(absf(v._mixamo_action_lock-a.get_animation(clip).length/1.2)<.001,clip+': action not cut short')
 for stance in ['standing','crouch','prone']:
  v._prone=1.0 if stance=='prone' else 0.0;v._crouch=1.0 if stance=='crouch' else 0.0
  v.play_death(Vector3(0,0,3));v._process_mixamo(.016,person,0,true)
  var clip: String=v._mixamo_current_clip
  a.advance(a.get_animation(clip).length+1)
  check(not a.is_playing(),'death reaches held final pose')
  v._process_mixamo(.1,person,0,true)
  check(not a.is_playing(),'death must not replay after completion')
  v.reset_death();check(v._mixamo_current_clip=='Idle_Natural' and v._mixamo_action_lock==0,'respawn clears action and death state')
 v._dead=false
 v._crouch=0.0
 for prone in [false,true]:
  v._prone=1.0 if prone else 0.0;v._crouch=0.0 if prone else 1.0
  v._start_mixamo_action('Reload',1.0)
  a.seek(1.0,true)
  var bounds: AABB=v.mixamo_model.transform*v._skinned_model_bounds(v.mixamo_model)
  check(bounds.size.y < (0.9 if prone else 1.5),'reload preserves low stance instead of standing up')
 print('Mixamo gameplay regression: ',checks,' checks, ',failures,' failed')
 person.queue_free();await process_frame
 quit(1 if failures else 0)
