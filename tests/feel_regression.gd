extends SceneTree

## On-foot feel: acceleration and stop curves, sprint rules, step and stance smoothing, ADS travel, boom recovery,
## recoil recovery per rifle, stride-timed footsteps, upper-body aim, turn on the spot, landing, reload hand, and
## buffered remote players (docs/lessons/characters/REMOTE_PLAYERS.md).
## Run: godot --headless --path . --script tests/feel_regression.gd

const PersonScript := preload("res://scripts/player/person_controller.gd")
const NetworkPlayerScript := preload("res://scripts/network/network_player.gd")
const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")

var failures := 0
var checks := 0
var person: CharacterBody3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var character: Node3D

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = size
	shape.shape = solid
	body.add_child(shape)
	body.position = at
	root.add_child(body)
	return body

func flat_speed() -> float:
	return Vector2(person.velocity.x, person.velocity.z).length()

func run() -> void:
	box(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))
	test_velocity_curve()
	person = (load("res://scenes/player/person.tscn") as PackedScene).instantiate()
	root.add_child(person)
	await frames(10)
	pivot = person.get_node("CameraPivot")
	arm = pivot.get_node("SpringArm3D")
	camera = arm.get_node("Camera3D")
	character = person.get_node("TestCharacter")
	check(character.male_model != null and character.male_model.scene_file_path.ends_with("rahul/rahul.glb"), "the default player loads rahul.glb")
	await test_sprint_curve()
	await test_stance_camera()
	await test_step_smoothing()
	await test_footsteps_and_bob()
	await test_armed_rules()
	await test_turn_on_the_spot()
	await test_upper_body_pitch()
	await test_ads_travel()
	await test_recoil()
	await test_boom()
	await test_landing()
	await test_reload_hand()
	await test_remote_buffer()
	print("Feel regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

func test_velocity_curve() -> void:
	var step := 1.0 / 60.0
	var speed_at := func(ticks: int, ease_share: float) -> float:
		var v := Vector2.ZERO
		for _i in ticks:
			v = PersonScript.step_ground_velocity(v, Vector2(4.2, 0.0), 16.0, 24.0, 30.0, ease_share, step)
		return v.x
	check(speed_at.call(6, 0.5) > 1.2 and speed_at.call(6, 0.5) < 1.61, "the body picks up speed at once (%.2f)" % speed_at.call(6, 0.5))
	check(speed_at.call(15, 0.5) < speed_at.call(15, 0.0), "the pace eases in near the top")
	check(absf(speed_at.call(60, 0.5) - 4.2) < 0.01, "it reaches the target speed")
	var diagonal := Vector2.ZERO
	var target := Vector2(1.0, 1.0).normalized() * 4.2
	for _i in 10:
		diagonal = PersonScript.step_ground_velocity(diagonal, target, 16.0, 24.0, 30.0, 0.5, step)
	check(absf(diagonal.angle_to(target)) < 0.001, "a diagonal keeps its direction while speed builds")
	var reversing := PersonScript.step_ground_velocity(Vector2(7.0, 0.0), Vector2(-4.2, 0.0), 16.0, 24.0, 30.0, 0.5, step)
	check(absf(reversing.x - (7.0 - 0.5)) < 0.001, "a reversal uses the firm rate (%.2f)" % reversing.x)
	var stopping := PersonScript.step_ground_velocity(Vector2(7.0, 0.0), Vector2.ZERO, 16.0, 24.0, 30.0, 0.5, step)
	check(absf(stopping.x - (7.0 - 0.4)) < 0.001, "a stop uses the stopping rate (%.2f)" % stopping.x)

func test_sprint_curve() -> void:
	person.set_touch_move_input(Vector2(0.0, -1.0))
	person.set_touch_run_pressed(true)
	var ticks := 0
	while flat_speed() < person.run_speed * 0.95 and ticks < 180:
		await physics_frame
		ticks += 1
	print("MEASURED sprint to 95%%: %.2f s" % (ticks / 60.0))
	check(ticks > 18 and ticks < 90, "a sprint builds over a moment (%d ticks)" % ticks)
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)
	var start := person.global_position
	ticks = 0
	while flat_speed() > 0.05 and ticks < 120:
		await physics_frame
		ticks += 1
	print("MEASURED stop from sprint: %.2f s, %.2f m" % [ticks / 60.0, start.distance_to(person.global_position)])
	check(ticks > 8 and ticks < 40, "a stop takes a moment (%d ticks)" % ticks)
	await frames(10)

func test_stance_camera() -> void:
	var standing: float = pivot.position.y
	person._update_stance(true, false)
	await physics_frame
	await physics_frame
	var early: float = pivot.position.y
	check(early > standing - 0.2, "crouching does not cut the camera down (%.2f -> %.2f)" % [standing, early])
	await frames(60)
	check(pivot.position.y < standing - 0.4, "the view settles at crouch height (%.2f)" % pivot.position.y)
	person._update_stance(false, false)
	await frames(60)
	check(absf(pivot.position.y - standing) < 0.02, "the view returns to standing height")

func test_step_smoothing() -> void:
	person.global_position = Vector3(30.0, 0.05, 0.0)
	person.rotation.y = 0.0
	var kerb := box(Vector3(8.0, 0.3, 8.0), Vector3(30.0, 0.15, 3.0 + 4.0))
	await frames(10)
	var heading: float = pivot.movement_yaw()
	person.set_touch_move_input(Vector2(0.0, -1.0).rotated(heading - PI))
	var worst := 0.0
	var last: float = camera.global_position.y
	var worst_body := 0.0
	var last_body: float = person.global_position.y
	for _i in 120:
		await physics_frame
		worst = maxf(worst, absf(camera.global_position.y - last))
		last = camera.global_position.y
		worst_body = maxf(worst_body, absf(person.global_position.y - last_body))
		last_body = person.global_position.y
	person.set_touch_move_input(Vector2.ZERO)
	await frames(30)
	print("MEASURED kerb: capsule worst %.3f m/tick, camera worst %.3f m/tick, top %.2f" % [worst_body, worst, person.global_position.y])
	check(person.global_position.y > 0.25, "the body climbed the kerb (y %.2f)" % person.global_position.y)
	check(worst < worst_body * 0.5, "the camera takes a kerb gently (%.3f against %.3f m per tick)" % [worst, worst_body])
	kerb.queue_free()
	person.global_position = Vector3(0.0, 0.05, 0.0)
	await frames(20)
	check(absf(person.camera_height_lag) < 0.1 and absf(person.step_visual_offset) < 0.1, "the height offsets ease away")

func test_footsteps_and_bob() -> void:
	var plants: Array[int] = []
	var record := func(side: int, _speed: float) -> void: plants.append(side)
	character.foot_planted.connect(record)
	person.set_touch_move_input(Vector2(0.0, -1.0))
	await frames(40)
	plants.clear()
	await frames(120)
	person.set_touch_move_input(Vector2.ZERO)
	character.foot_planted.disconnect(record)
	var seconds := 2.0
	var stride: float = character._gait_stride(person.walk_speed)
	var expected: float = person.walk_speed * seconds / stride * 2.0
	print("MEASURED footsteps at %.1f m/s: %d in %.1f s, %.1f expected from the stride of %.2f m" % [person.walk_speed, plants.size(), seconds, expected, stride])
	check(absf(plants.size() - expected) <= 1.5, "footsteps keep time with the stride (%d, expected %.1f)" % [plants.size(), expected])
	var alternates := true
	for index in range(1, plants.size()):
		alternates = alternates and plants[index] != plants[index - 1]
	check(alternates, "footsteps alternate left and right")
	check(person.stride_phase() >= 0.0, "the stride phase is offered to the camera")
	await frames(20)

func test_armed_rules() -> void:
	person.combat_mode = true
	person.set_weapon_equipped(true)
	await frames(20)
	person.set_touch_run_pressed(true)
	person.set_touch_move_input(Vector2(1.0, 0.0))
	await frames(50)
	check(not person.is_running and flat_speed() < person.walk_speed + 0.2, "no sprinting sideways (%.2f)" % flat_speed())
	person.set_touch_move_input(Vector2(0.0, -1.0))
	await frames(70)
	check(person.is_running, "sprints forward")
	pivot.touch_aim = true
	await frames(50)
	check(not person.is_running and absf(flat_speed() - person.walk_speed * person.aim_speed_scale) < 0.3,
		"aiming stops the sprint and slows the walk (%.2f)" % flat_speed())
	pivot.touch_aim = false
	person.set_touch_run_pressed(false)
	person.set_touch_move_input(Vector2.ZERO)
	await frames(40)

func test_turn_on_the_spot() -> void:
	var rig: Skeleton3D = character.male_skeleton
	var thigh := rig.find_bone("CC_Base_L_Thigh")
	await frames(40)
	var low := INF
	var high := -INF
	for tick in 60:
		pivot._yaw += 0.05
		await physics_frame
		var turn := rig.get_bone_pose_rotation(thigh).get_euler().x
		low = minf(low, turn)
		high = maxf(high, turn)
	print("MEASURED turn on the spot: thigh range %.2f rad, clip weight %.2f, speed %.2f" % [high - low, character._clip_weight, flat_speed()])
	check(high - low > 0.08 and flat_speed() < 0.1, "the feet step round in a turn on the spot (%.2f rad)" % (high - low))
	await frames(40)

func test_upper_body_pitch() -> void:
	pivot._pitch = -0.1
	await frames(40)
	var chest := character.chest_position() as Vector3
	var forward: Vector3 = person.global_basis.z
	pivot._pitch = 0.5
	await frames(40)
	var chest_up := character.chest_position() as Vector3
	pivot._pitch = -0.6
	await frames(40)
	var chest_down := character.chest_position() as Vector3
	print("MEASURED chest forward: up %.3f, level %.3f, down %.3f m" % [(chest_up - person.global_position).dot(forward),
		(chest - person.global_position).dot(forward), (chest_down - person.global_position).dot(forward)])
	check(character._aim_pitch < -0.4, "the upper body follows the camera's pitch (%.2f)" % character._aim_pitch)
	check((chest_down - chest_up).dot(forward) > 0.01, "looking down carries the chest forward, looking up back")
	pivot._pitch = -0.1
	await frames(30)

func test_ads_travel() -> void:
	var worst := 0.0
	await frames(20)
	var last := camera.global_position
	var look := -camera.global_basis.z
	pivot.touch_aim = true
	var first_arrival := -1
	for tick in 24:
		await process_frame
		worst = maxf(worst, camera.global_position.distance_to(last))
		last = camera.global_position
		if first_arrival < 0 and pivot.is_sight_view():
			first_arrival = tick
	print("MEASURED ADS in: sight after %d frames, worst camera step %.3f m" % [first_arrival, worst])
	check(first_arrival > 2, "the view travels to the sight instead of cutting (frame %d)" % first_arrival)
	check(worst < 0.7, "no jump on the way to the sight (%.3f m)" % worst)
	check(look.angle_to(-camera.global_basis.z) < 0.05, "the aim point holds")
	pivot.touch_aim = false
	worst = 0.0
	last = camera.global_position
	for _tick in 24:
		await process_frame
		worst = maxf(worst, camera.global_position.distance_to(last))
		last = camera.global_position
	print("MEASURED ADS out: worst camera step %.3f m" % worst)
	check(worst < 0.7, "no jump back to the shoulder (%.3f m)" % worst)
	check(not pivot.is_first_person(), "the view is back at the shoulder")
	await frames(30)

func test_recoil() -> void:
	# Per rifle: the AK's climb comes back slower than the Bren's.
	check(float(Weapons.stats(Weapons.AK47).recoil_recovery) < float(Weapons.stats(Weapons.BREN2).recoil_recovery), "recovery is per rifle")
	person.set_weapon_model(Weapons.M416)
	var rest: float = pivot._pitch
	pivot.add_recoil(0.03, 0.0)
	check(pivot._pitch == rest, "a kick goes through the tick, not straight into the pose")
	await physics_frame
	await physics_frame
	var kicked: float = pivot._pitch
	check(kicked > rest + 0.008 and kicked < rest + 0.03, "a kick arrives over a few ticks (%.4f)" % (kicked - rest))
	await frames(6)
	var peak: float = pivot._pitch
	check(peak > rest + 0.02, "the kick lands in full")
	await frames(40)
	check(absf(pivot._pitch - rest) < 0.004, "the view settles back after the trigger rests (%.4f)" % (pivot._pitch - rest))
	var yaw: float = pivot._yaw
	pivot.add_recoil(0.0, 0.0, 0.01)
	await frames(30)
	check(absf(pivot._yaw - yaw - 0.01) < 0.0005, "yaw_bias reaches the view (%.4f)" % (pivot._yaw - yaw))
	pivot.add_recoil()
	await frames(30)

func test_boom() -> void:
	await frames(30)
	var free_length := arm.get_hit_length()
	var behind: Vector3 = camera.global_position - pivot.global_position
	var wall := box(Vector3(6.0, 6.0, 0.4), pivot.global_position + behind.normalized() * 1.2)
	wall.look_at_from_position(wall.position, wall.position + behind.normalized(), Vector3.UP)
	await frames(4)
	var blocked := arm.get_hit_length()
	check(blocked < free_length - 0.8, "a wall shortens the boom at once (%.2f -> %.2f)" % [free_length, blocked])
	wall.queue_free()
	await physics_frame
	await physics_frame
	await physics_frame
	var worst := 0.0
	var last := arm.get_hit_length()
	for _i in 60:
		await physics_frame
		worst = maxf(worst, absf(arm.get_hit_length() - last))
		last = arm.get_hit_length()
	print("MEASURED boom recovery: worst %.3f m/tick, end %.2f of %.2f" % [worst, last, free_length])
	check(worst < 0.12, "the boom does not pop out when the wall clears (%.3f m per tick)" % worst)
	check(last > free_length - 0.1, "the boom returns to full length")

func test_landing() -> void:
	person.global_position += Vector3.UP * 4.0
	var lowest := 0.0
	var landed := false
	var knee_peak := 0.0
	for _i in 120:
		await process_frame
		lowest = minf(lowest, camera.v_offset)
		knee_peak = maxf(knee_peak, character._land_crouch)
		landed = landed or person.is_on_floor()
	print("MEASURED landing: camera dip %.3f m, knee crouch %.2f" % [lowest, knee_peak])
	check(landed and lowest < -0.03 and lowest > -0.2, "a landing dips the view (%.3f m)" % lowest)
	check(knee_peak > 0.2, "the knees take a landing (%.2f)" % knee_peak)
	check(absf(pivot._dip) < 0.01, "the dip springs back")

func test_reload_hand() -> void:
	var weapon_low := INF
	await frames(10)
	var rest: Vector3 = character.left_grip_target
	person.weapon_reload_time = 2.0
	var farthest := 0.0
	for _i in 125:
		await process_frame
		farthest = maxf(farthest, character.left_grip_target.distance_to(rest))
		weapon_low = minf(weapon_low, person.weapon.global_position.y)
	await frames(10)
	print("MEASURED reload: left hand %.2f m from the handguard at most" % farthest)
	check(farthest > 0.25, "the left hand leaves the handguard (%.2f m)" % farthest)
	check(person.reload_progress() < 0.0, "the reload ends")
	check(character.left_grip_target.distance_to(rest) < 0.12, "the hand comes back")

## Feeds a 30 Hz walk with Wi-Fi-like arrival jitter straight into the buffer and samples every 60 Hz frame.
func test_remote_buffer() -> void:
	var puppet: CharacterBody3D = NetworkPlayerScript.new()
	root.add_child(puppet)
	await physics_frame
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	var speed := 4.2
	for packet in 60:
		var sent := packet / 30.0
		puppet.push_snapshot(10.0 + sent + noise.randf_range(0.0, 0.025), Vector3(speed * sent, 0.0, 0.0), 0.0, 0.0, 0.0)
		if puppet._snapshots.size() > 8:
			puppet._snapshots.pop_front()
		if packet == 30:
			var worst := 0.0
			var previous: float = puppet.sample_snapshots(10.0 + sent - 0.3).position.x
			for frame in 12:
				var time: float = 10.0 + sent - 0.3 + (frame + 1) / 60.0
				var now: float = puppet.sample_snapshots(time).position.x
				worst = maxf(worst, absf((now - previous) * 60.0 - speed))
				previous = now
			print("MEASURED remote: speed error %.2f m/s under 25 ms arrival jitter" % worst)
			check(worst < 1.5, "buffered motion is steady under jitter (error %.2f m/s)" % worst)
	var last: Dictionary = puppet._snapshots.back()
	var early: Dictionary = puppet.sample_snapshots(last.time + 0.05)
	var capped: Dictionary = puppet.sample_snapshots(last.time + 2.0)
	check(early.position.x > last.position.x and early.motion.length() > 1.0, "a short gap carries on along the motion")
	check(absf(capped.position.x - (last.position.x + speed * puppet.extrapolation_cap)) < 0.5, "extrapolation stops at the cap (%.2f)" % (capped.position.x - last.position.x))
	check(capped.motion == Vector3.ZERO, "past the cap the legs stop too")
	var far: Vector3 = last.position + Vector3(50.0, 0.0, 0.0)
	puppet.push_snapshot(last.time + 0.03, far, 0.0, 0.0, 0.0)
	check(puppet._snapshots.size() == 1 and puppet.global_position.distance_to(far) < 0.001, "a respawn cuts instead of running there")
	puppet.queue_free()
	await physics_frame
