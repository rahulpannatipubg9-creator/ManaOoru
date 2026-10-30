extends SceneTree
class GameStub extends Node3D:
	enum ControlState { ON_FOOT, ENTERING, DRIVING, EXITING }
	var control_state := ControlState.ON_FOOT
	var person: CharacterBody3D
	var active_vehicle: Node3D
	func is_map_open() -> bool: return false
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var game := GameStub.new()
	root.add_child(game)
	game.person = load("res://scenes/player/person.tscn").instantiate()
	game.add_child(game.person)
	game.person.set_physics_process(false)
	game.person.global_position = Vector3(0,100,0)
	game.person.set_weapon_equipped(true)
	game.person.combat_mode = true
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.global_position = Vector3(0,101,0)
	camera.current = true
	var gameplay = load("res://scripts/gameplay/city_gameplay.gd").new()
	game.add_child(gameplay)
	gameplay.set_process(false)
	gameplay.game = game
	gameplay.action_mode = true
	for sound in ["shot", "punch"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/gameplay/%s.wav" % sound)
		gameplay.add_child(audio)
		gameplay._audio[sound] = audio
	var target = load("res://scripts/gameplay/mission_actor.gd").new()
	target.game = game
	game.add_child(target)
	target.set_physics_process(false)
	target.global_position = Vector3(0,100,-8)
	GameplayControls.owner_id = game.person.get_instance_id()
	GameplayControls.blocked = false
	await physics_frame
	await physics_frame
	check(gameplay.attack() and target.health == 72.0, "Camera-aligned shot damages a visible target")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5,5,0.5)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	wall.global_position = Vector3(0,101,-4)
	await physics_frame
	await physics_frame
	gameplay._shot_cooldown = 0.0
	var ammo: int = gameplay.ammo
	check(gameplay.attack() and target.health == 72.0 and gameplay.ammo == ammo-1, "Wall blocks bullet damage while ammunition is consumed")
	await create_timer(0.15).timeout
	game.queue_free()
	await process_frame
	print("PASS combat occlusion" if failures == 0 else "FAIL combat occlusion")
	quit(0 if failures == 0 else 1)
