extends SceneTree

## The realistic male carries Walk_Cycle / Run_Cycle clips and test_character.gd samples them by
## stride phase: thighs and arms must move through the cycle, and walk and run must differ.

func _init() -> void:
	var body := CharacterBody3D.new()
	root.add_child(body)
	var character := Node3D.new()
	character.set_script(load("res://scripts/player/test_character.gd"))
	body.add_child(character)
	await process_frame
	if character.male_skeleton == null:
		print("FAIL: realistic male skeleton not loaded")
		quit(1)
		return
	if character._walk_clip == null or character._run_clip == null:
		print("FAIL: Walk_Cycle / Run_Cycle clips missing from the player model")
		quit(1)
		return
	var skeleton: Skeleton3D = character.male_skeleton
	var thigh := skeleton.find_bone("CC_Base_L_Thigh")
	var arm := skeleton.find_bone("CC_Base_R_Upperarm")
	var hip := skeleton.find_bone("CC_Base_Hip")
	character._clip_weight = 1.0
	var samples := {}
	for case in [["walk", 4.2], ["run", 7.0]]:
		for phase in [0.0, 0.5]:
			skeleton.reset_bone_poses()
			character._male_phase = phase
			character._apply_male_clips(case[1])
			samples["%s_%s" % [case[0], phase]] = [skeleton.get_bone_pose_rotation(thigh),
				skeleton.get_bone_pose_rotation(arm), skeleton.get_bone_pose_position(hip)]
	var failures := []
	for name in ["walk", "run"]:
		var a: Array = samples[name + "_0.0"]
		var b: Array = samples[name + "_0.5"]
		var thigh_swing := rad_to_deg(a[0].angle_to(b[0]))
		var arm_swing := rad_to_deg(a[1].angle_to(b[1]))
		print("%s: thigh swings %.1f deg, arm swings %.1f deg over half a cycle" % [name, thigh_swing, arm_swing])
		if thigh_swing < 15.0:
			failures.append(name + " thigh barely moves")
		if arm_swing < 10.0:
			failures.append(name + " arm barely moves")
	var walk_vs_run := rad_to_deg(samples["walk_0.0"][0].angle_to(samples["run_0.0"][0]))
	print("walk vs run thigh at heel strike differs by %.1f deg" % walk_vs_run)
	if walk_vs_run < 3.0:
		failures.append("walk and run clips are identical")
	if failures.is_empty():
		print("PASS: player gait clips drive the realistic male")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
