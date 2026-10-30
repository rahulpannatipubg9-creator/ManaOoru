extends SceneTree

## Player v2 (tools/player_character_v2/scripts/export_ingame.py) must rest exactly like the old game rig,
## so the clip library and the procedural posing in test_character.gd mean the same thing on it.

const OLD_LIBRARY := "res://assets/models/characters/player_character_animations.glb"
const V2_MODEL := "res://assets/models/characters/player_v2_rigged.glb"
const V2_LIBRARY := "res://assets/models/characters/player_v2_animations.glb"
const MAX_REST_DEG := 0.5

var _failures := 0

func _init() -> void:
	var old_skeleton := _skeleton(OLD_LIBRARY)
	var model := (load(V2_MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var v2_skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var library := (load(V2_LIBRARY) as PackedScene).instantiate() as Node3D
	root.add_child(library)
	await process_frame
	var worst := 0.0
	var worst_bone := ""
	var compared := 0
	for bone in v2_skeleton.get_bone_count():
		var bone_name := v2_skeleton.get_bone_name(bone)
		var other := old_skeleton.find_bone(bone_name)
		if other < 0:
			continue
		var a := v2_skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion()
		var b := old_skeleton.get_bone_global_rest(other).basis.get_rotation_quaternion()
		var angle := rad_to_deg(a.angle_to(b))
		compared += 1
		if angle > worst:
			worst = angle
			worst_bone = bone_name
	print("Compared %d bones; worst rest difference %.3f deg (%s)" % [compared, worst, worst_bone])
	_check(compared >= 95, "v2 shares the CC_Base bone names (%d compared)" % compared)
	_check(worst < MAX_REST_DEG, "v2 rests like the old rig (worst %.3f deg at %s)" % [worst, worst_bone])
	var clips: Array = []
	for player: AnimationPlayer in library.find_children("*", "AnimationPlayer", true, false):
		clips.append_array(player.get_animation_list())
	for needed in ["WALK_Realistic", "WALK_Brisk", "JOG_Realistic", "SPRINT_Realistic", "IDLE_Natural", "CROUCH_Idle", "CROUCH_Walk", "RUN_Realistic"]:
		_check(clips.has(needed), "the v2 clip library has %s" % needed)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	print("v2 bounds ", bounds)
	_check(absf(bounds.position.y) < 0.01, "soles stand on y = 0 (%.3f)" % bounds.position.y)
	_check(bounds.size.y > 1.70 and bounds.size.y < 1.86, "true scale: 1.72 m in shoes plus hair (%.3f)" % bounds.size.y)
	if _failures > 0:
		print("FAIL player v2 conform: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS player v2 conform: same rest as the old rig, clip library present, true scale on the ground")
	quit()

func _skeleton(path: String) -> Skeleton3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(node)
	return node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
