extends SceneTree

## Rahul's own locomotion (tools/rahul_character, 17_game_clips.py) must drive the default character:
## the speed-matched gait clips while moving, IDLE_Natural while standing, and the AK-47 stance set present.

var _failures := 0

func _init() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)
	var person: CharacterBody3D = (load("res://scenes/player/person.tscn") as PackedScene).instantiate()
	root.add_child(person)
	for _frame in 5:
		await physics_frame
	var visual: Node3D = person.get_node("TestCharacter")
	_check(visual.male_model != null and visual.male_model.visible, "Rahul is the default character")
	# Rahul's own set (tools/rahul_character, 17_game_clips.py): stepped clips carry one frame past the cycle.
	_check(visual._walk_clip != null and absf(visual._walk_clip.length - 31.0 / 30.0) < 0.02, "Walking uses WALK_Realistic (1.03 s)")
	_check(visual._run_clip != null, "A run clip is present for the walk/run fallback")
	_check(visual._idle_clip != null and absf(visual._idle_clip.length - 2.0) < 0.02, "Standing uses IDLE_Natural (2 s)")
	_check(visual._gait_clips.size() == visual.GAIT_CLIPS.size(), "Every speed-matched gait clip is present (%d)" % visual._gait_clips.size())
	_check(visual._crouch_walk != null and visual._crouch_idle != null, "CROUCH_Idle and CROUCH_Walk are present")
	_check(visual._rifle_clips.size() == visual.RIFLE_CLIPS.size(), "The AK-47 stance set is present (%d)" % visual._rifle_clips.size())
	for entry: Array in visual.GAIT_CLIPS:
		var clip: Dictionary = visual._gait_clips.filter(func(g: Dictionary) -> bool: return g.speed == entry[1])[0]
		_check(absf(clip.stride / clip.cycle - float(entry[1])) < 0.01, "%s steps at its listed %.2f m/s" % [entry[0], entry[1]])

	# Idle: the authored breathing/weight shift moves the spine while standing still.
	var skeleton: Skeleton3D = visual.male_skeleton
	var spine := skeleton.find_bone("CC_Base_Spine02")
	for _frame in 30:
		await process_frame
	var first := skeleton.get_bone_pose_rotation(spine)
	var widest := 0.0
	var idle_until := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < idle_until:
		await process_frame
		widest = maxf(widest, first.angle_to(skeleton.get_bone_pose_rotation(spine)))
	_check(visual._idle_weight > 0.8, "Standing on the ground fades the idle in (%.2f)" % visual._idle_weight)
	_check(widest > 0.002, "The idle clip animates the standing body (spine moved %.4f rad)" % widest)

	# Running: the gait clips take over and the limbs swing.
	person.set_touch_move_input(Vector2(0.0, -1.0))
	person.set_touch_run_pressed(true)
	for _frame in 40:
		await physics_frame
	_check(visual._clip_weight > 0.8, "Moving fades the gait clips in (%.2f)" % visual._clip_weight)
	var thigh := skeleton.find_bone("CC_Base_L_Thigh")
	var swing_low := INF
	var swing_high := -INF
	# The pose advances with real time, so sample a full second and a half of strides.
	var until := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < until:
		await process_frame
		var angle := skeleton.get_bone_rest(thigh).basis.get_rotation_quaternion().angle_to(skeleton.get_bone_pose_rotation(thigh))
		swing_low = minf(swing_low, angle)
		swing_high = maxf(swing_high, angle)
	_check(swing_high - swing_low > 0.3, "Running swings the legs through a stride (%.2f rad)" % (swing_high - swing_low))

	if _failures > 0:
		print("FAIL character clip library regression: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS character clip library regression: Rahul default; his gait, crouch, idle and AK-47 clips load; idle breathes, running strides")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
