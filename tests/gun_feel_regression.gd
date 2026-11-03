extends SceneTree

## Gun presentation: every sound exists, a long spray allocates no new nodes, recoil climbs then levels off,
## near misses are told apart from wide shots, and hit feedback plays only on a confirmed hit.
## Run: godot --headless --path . --script tests/gun_feel_regression.gd

const GunFeel := preload("res://scripts/gameplay/gun_feel.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

class FakeGame extends Node:
	var person: Node3D
	var tdm_session: Node

class Target extends StaticBody3D:
	func tdm_claim_hit() -> void:
		pass

var failures := 0
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	# Recoil: the first round is the base kick, the climb stops, and the AK stays above the M416.
	var base := Vector2(0.02, 0.01)
	check(GunFeel.recoil_step(base, 0) == base, "the first round kicks by the catalog value")
	check(GunFeel.recoil_step(base, 5).x > GunFeel.recoil_step(base, 2).x, "recoil climbs through a burst")
	check(GunFeel.recoil_step(base, 40) == GunFeel.recoil_step(base, GunFeel.CLIMB_SHOTS), "recoil levels off")
	var m416: Vector2 = Weapons.stats(Weapons.M416).recoil
	var ak47: Vector2 = Weapons.stats(Weapons.AK47).recoil
	check(GunFeel.recoil_step(ak47, 6).x > GunFeel.recoil_step(m416, 6).x, "the AK climbs harder than the M416")

	# Near misses.
	var from := Vector3.ZERO
	var forward := Vector3.FORWARD
	check(GunFeel.near_miss(from, forward, Vector3(1.0, 0.0, -30.0)), "a round passing 1 m away cracks")
	check(not GunFeel.near_miss(from, forward, Vector3(6.0, 0.0, -30.0)), "a round passing 6 m away does not")
	check(not GunFeel.near_miss(from, forward, Vector3(0.0, 0.0, 30.0)), "a round fired away from the listener does not")
	check(not GunFeel.near_miss(from, forward, Vector3(0.0, 0.0, -3.0)), "point blank has no passing crack")

	# Surfaces.
	var wall := StaticBody3D.new()
	var car := CharacterBody3D.new()
	check(GunFeel.surface_of(wall) == GunFeel.Surface.DUST, "walls give dust")
	check(GunFeel.surface_of(car) == GunFeel.Surface.SPARK, "vehicles give sparks")
	wall.free()
	car.free()

	# The pool: a stand-in game is enough, since nothing here reads more than the person's camera pivot.
	var game := FakeGame.new()
	game.person = Node3D.new()
	game.add_child(game.person)
	root.add_child(game)
	var feel: Node = GunFeel.new()
	game.add_child(feel)
	feel.setup(game)
	for rifle: int in Weapons.IDS:
		check(feel._shot_streams[feel._sound_name(rifle)].size() == GunFeel.SHOT_VARIATIONS, "rifle %d has all its takes" % rifle)
		for stream: AudioStream in feel._shot_streams[feel._sound_name(rifle)]:
			check(stream != null, "rifle %d: a shot failed to load" % rifle)
			if stream != null:
				check(stream.get_length() < 0.6, "shot tails fit the voice pool")
	for sound: String in feel._feedback:
		check(feel._feedback[sound] != null, "%s loads" % sound)
	check(feel._feedback.size() == 8, "all feedback sounds are listed")

	var hit := {"collider": null, "normal": Vector3.UP}
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var last_variation := -1
	var repeats := 0
	for round_index in 300:
		feel.on_shot(Weapons.M416, Vector3.ZERO, Vector3(0, 0, -20), hit, false)
		if feel._last_variation == last_variation:
			repeats += 1
		last_variation = feel._last_variation
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes_before, "300 shots add no nodes")
	check(repeats == 0, "a take never plays twice running (%d repeats)" % repeats)
	check(feel._voice_index < GunFeel.SHOT_VOICES, "voices stay in the pool")

	# Reload sounds run in order, then stop.
	feel.play_reload(1.0)
	check(feel._reload_steps.size() == 3, "a reload has three sounds")
	feel._tick_reload(0.1)
	check(feel._reload_steps.size() == 2, "the magazine comes out first")
	feel._tick_reload(1.0)
	feel._tick_reload(1.0)
	check(feel._reload_steps.is_empty(), "the reload sounds finish")
	feel.play_reload(1.0)
	feel.cancel_reload()
	check(feel._reload_steps.is_empty(), "swapping rifles silences a reload")

	# Team Deathmatch blood waits for the host.
	var target := Target.new()
	game.add_child(target)
	feel.on_shot(Weapons.M416, Vector3.ZERO, Vector3(0, 0, -20), {"collider": target, "normal": Vector3.UP}, false)
	check(feel._pending_flesh == Vector3(0, 0, -20), "a player hit waits for the host's confirmation")
	feel.on_hit_confirmed(2, true, true)
	check(feel._pending_flesh == Vector3.INF, "the host's confirmation spends the pending hit")

	game.queue_free()
	print("gun feel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
