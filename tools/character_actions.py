"""Animation clips for the CC_Base skeleton: walk and run cycles, plus placeholder sit, bend, jump.

Walk_Cycle and Run_Cycle are in-place gait cycles authored from human gait data (hip, knee and ankle
angles through the stride, pelvis bob, yaw and sway, spine counter-rotation, arms swinging against
the legs). Each pose is built by rotating bones about armature-space axes at their joints, so the
clips do not depend on how the glTF import oriented each bone's local axes. Sit, bend and jump are
the placeholder keyframes the first player build shipped with.

Frames are at 30 fps; frame 1 and the last frame hold the same pose so the cycles loop cleanly.
"""
import math

import bpy
from mathutils import Euler, Matrix, Vector

STANDING_BONES = [
    "CC_Base_L_Thigh", "CC_Base_R_Thigh", "CC_Base_L_Calf", "CC_Base_R_Calf",
    "CC_Base_Spine01", "CC_Base_Spine02", "CC_Base_L_Upperarm", "CC_Base_R_Upperarm",
    "CC_Base_L_Forearm", "CC_Base_R_Forearm", "CC_Base_NeckTwist01",
]


# Armature space: +Z up, the character faces -Y, its left side is +X.
X_AXIS = Vector((1.0, 0.0, 0.0))
Y_AXIS = Vector((0.0, 1.0, 0.0))
Z_AXIS = Vector((0.0, 0.0, 1.0))
# Rest pose is a T-pose: this brings each arm down to hang at the side.
ARM_DOWN_DEG = 72.0

# Angle curves over one cycle (phase 0..1, left heel strike at 0), degrees, from typical gait data.
WALK = {
    "frames": 30,
    "hip_flex": [(0.0, 24), (0.25, 8), (0.5, -10), (0.62, -6), (0.85, 22), (1.0, 24)],
    "knee_flex": [(0.0, 4), (0.15, 18), (0.4, 6), (0.6, 38), (0.73, 60), (0.9, 22), (1.0, 4)],
    "ankle_plantar": [(0.0, -2), (0.08, 6), (0.4, -10), (0.6, 18), (0.72, 4), (0.9, -4), (1.0, -2)],
    "bob": 0.022, "sway": 0.018, "pelvis_yaw": 5.0, "spine_counter": 7.0, "lean": 3.0,
    "arm_swing": 16.0, "elbow": 14.0, "elbow_swing": 10.0, "arm_back_bias": 2.0, "forearm_in": 0.0,
}
RUN = {
    "frames": 20,
    "hip_flex": [(0.0, 32), (0.2, 8), (0.4, -18), (0.55, -10), (0.8, 45), (1.0, 32)],
    "knee_flex": [(0.0, 18), (0.12, 38), (0.35, 22), (0.5, 60), (0.68, 110), (0.88, 55), (1.0, 18)],
    "ankle_plantar": [(0.0, 2), (0.1, -10), (0.35, 22), (0.55, 10), (0.8, -6), (1.0, 2)],
    "bob": 0.045, "sway": 0.012, "pelvis_yaw": 7.0, "spine_counter": 11.0, "lean": 11.0,
    "arm_swing": 30.0, "elbow": 78.0, "elbow_swing": 0.0, "arm_back_bias": 10.0, "forearm_in": 14.0,
}


def _curve(points, t):
    """Smooth periodic interpolation through (phase, value) points."""
    t %= 1.0
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            u = u * u * (3.0 - 2.0 * u)
            return v0 + (v1 - v0) * u
    return points[-1][1]


def _rotate(armature, name, axis, degrees):
    """Rotate a pose bone about an armature-space axis through its (posed) head."""
    bone = armature.pose.bones.get(name)
    if bone is None or abs(degrees) < 1e-6:
        return
    bpy.context.view_layer.update()
    head = bone.head.copy()
    bone.matrix = (Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees), 4, axis)
                   @ Matrix.Translation(-head) @ bone.matrix)


def _gait_pose(armature, g, phase):
    """Pose the rig at `phase` of the gait `g` (left heel strike at phase 0)."""
    for bone in armature.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    two_pi = 2.0 * math.pi
    # Pelvis: lowest at each heel strike, highest at mid-stance; shifts over the stance leg; turns
    # its forward hip with the forward leg.
    bob = -g["bob"] * math.cos(2.0 * two_pi * phase)
    sway = g["sway"] * math.sin(two_pi * phase - math.pi / 2.0) * -1.0
    hip = armature.pose.bones["CC_Base_Hip"]
    hip.matrix = Matrix.Translation((sway, 0.0, bob)) @ hip.matrix
    yaw = g["pelvis_yaw"] * math.cos(two_pi * phase)          # left hip forward at phase 0
    _rotate(armature, "CC_Base_Pelvis", Z_AXIS, -yaw)
    for side, offset in (("L", 0.0), ("R", 0.5)):
        t = phase + offset
        _rotate(armature, f"CC_Base_{side}_Thigh", X_AXIS, -_curve(g["hip_flex"], t))
        _rotate(armature, f"CC_Base_{side}_Calf", X_AXIS, _curve(g["knee_flex"], t))
        _rotate(armature, f"CC_Base_{side}_Foot", X_AXIS, _curve(g["ankle_plantar"], t))
    # Torso leans into the motion and counter-rotates against the pelvis; the head stays level.
    _rotate(armature, "CC_Base_Waist", X_AXIS, g["lean"] * 0.5)
    _rotate(armature, "CC_Base_Spine01", X_AXIS, g["lean"] * 0.5)
    _rotate(armature, "CC_Base_Spine02", Z_AXIS, yaw + g["spine_counter"] * math.cos(two_pi * phase))
    _rotate(armature, "CC_Base_NeckTwist01", Z_AXIS, -g["spine_counter"] * 0.8 * math.cos(two_pi * phase))
    _rotate(armature, "CC_Base_NeckTwist01", X_AXIS, -g["lean"] * 0.8)
    # Arms hang, then swing opposite their leg (right arm forward with the left leg); elbows bend
    # more as the arm swings forward.
    for side, sign, offset in (("L", 1.0, 0.5), ("R", -1.0, 0.0)):
        # Arms swing a little further back than forward (`arm_back_bias`); running forearms also tuck
        # in toward the body's midline instead of reaching out to the side.
        swing = g["arm_swing"] * math.cos(two_pi * (phase + offset)) - g["arm_back_bias"]
        _rotate(armature, f"CC_Base_{side}_Upperarm", Y_AXIS, sign * ARM_DOWN_DEG)
        _rotate(armature, f"CC_Base_{side}_Upperarm", X_AXIS, -swing)
        _rotate(armature, f"CC_Base_{side}_Forearm", X_AXIS, -(g["elbow"] + g["elbow_swing"] * max(0.0, swing) / g["arm_swing"]))
        _rotate(armature, f"CC_Base_{side}_Forearm", Z_AXIS, -sign * g["forearm_in"])
    bpy.context.view_layer.update()


def _gait_action(armature, name, g):
    action = bpy.data.actions.new(name)
    armature.animation_data.action = action
    frames = g["frames"]
    for frame in range(1, frames + 2):
        _gait_pose(armature, g, (frame - 1) / frames)
        for bone in armature.pose.bones:
            bone.rotation_mode = "QUATERNION"
            bone.keyframe_insert("rotation_quaternion", frame=frame)
        armature.pose.bones["CC_Base_Hip"].keyframe_insert("location", frame=frame)
    return action


def _key(armature, bone_name, frame, rx=0.0, ry=0.0, rz=0.0):
    bone = armature.pose.bones.get(bone_name)
    if bone is None:
        return
    # All clips key quaternions: the exporter only reads the channel matching the bone's rotation mode.
    bone.rotation_quaternion = Euler((rx, ry, rz)).to_quaternion()
    bone.keyframe_insert("rotation_quaternion", frame=frame)


def _pose(armature, frame, pose):
    for bone_name, rotation in pose.items():
        _key(armature, bone_name, frame, *rotation)


def build_actions(armature):
    """Create the clips on NLA tracks and return them; Walk_Cycle stays the active action."""
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for bone in armature.pose.bones:
        bone.rotation_mode = "QUATERNION"
    if armature.animation_data:
        armature.animation_data_clear()
    armature.animation_data_create()

    walk = _gait_action(armature, "Walk_Cycle", WALK)
    run = _gait_action(armature, "Run_Cycle", RUN)
    for bone in armature.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)

    sit = bpy.data.actions.new("Sit_Down")
    armature.animation_data.action = sit
    _pose(armature, 1, {name: (0.0, 0.0, 0.0) for name in STANDING_BONES})
    _pose(armature, 15, {
        "CC_Base_L_Thigh": (-0.65,), "CC_Base_R_Thigh": (-0.65,), "CC_Base_L_Calf": (0.80,), "CC_Base_R_Calf": (0.80,),
        "CC_Base_Spine01": (0.12,), "CC_Base_Spine02": (0.08,), "CC_Base_L_Upperarm": (0.15,), "CC_Base_R_Upperarm": (0.15,),
        "CC_Base_L_Forearm": (0.0, 0.0, -0.3), "CC_Base_R_Forearm": (0.0, 0.0, 0.3),
    })
    _pose(armature, 30, {
        "CC_Base_L_Thigh": (-1.20,), "CC_Base_R_Thigh": (-1.20,), "CC_Base_L_Calf": (1.35,), "CC_Base_R_Calf": (1.35,),
        "CC_Base_L_Foot": (0.30,), "CC_Base_R_Foot": (0.30,), "CC_Base_Spine01": (0.18,), "CC_Base_Spine02": (0.10,),
        "CC_Base_L_Upperarm": (0.20, 0.0, 0.15), "CC_Base_R_Upperarm": (0.20, 0.0, -0.15),
        "CC_Base_L_Forearm": (0.0, 0.0, -0.45), "CC_Base_R_Forearm": (0.0, 0.0, 0.45),
    })

    bend = bpy.data.actions.new("Bend_Forward")
    armature.animation_data.action = bend
    _pose(armature, 1, {name: (0.0, 0.0, 0.0) for name in STANDING_BONES})
    _pose(armature, 15, {
        "CC_Base_Spine01": (0.55,), "CC_Base_Spine02": (0.40,), "CC_Base_L_Thigh": (-0.20,), "CC_Base_R_Thigh": (-0.20,),
        "CC_Base_L_Calf": (0.25,), "CC_Base_R_Calf": (0.25,), "CC_Base_L_Upperarm": (-0.80,), "CC_Base_R_Upperarm": (-0.80,),
    })
    _pose(armature, 30, {
        "CC_Base_Spine01": (0.90,), "CC_Base_Spine02": (0.55,), "CC_Base_L_Thigh": (-0.35,), "CC_Base_R_Thigh": (-0.35,),
        "CC_Base_L_Calf": (0.40,), "CC_Base_R_Calf": (0.40,), "CC_Base_L_Upperarm": (-1.30,), "CC_Base_R_Upperarm": (-1.30,),
    })

    jump = bpy.data.actions.new("Jump")
    armature.animation_data.action = jump
    for frame, thigh, calf, spine, arm in ((1, -0.50, 0.80, 0.20, 0.40), (10, 0.15, 0.0, -0.05, -1.0),
                                           (18, -0.35, 0.60, 0.05, -0.20), (30, -0.55, 0.85, 0.22, 0.30)):
        _pose(armature, frame, {
            "CC_Base_L_Thigh": (thigh,), "CC_Base_R_Thigh": (thigh,), "CC_Base_L_Calf": (calf,), "CC_Base_R_Calf": (calf,),
            "CC_Base_Spine01": (spine,), "CC_Base_L_Upperarm": (arm,), "CC_Base_R_Upperarm": (arm,),
        })

    for name, start, action in (("Track_Walk", 1, walk), ("Track_Run", 60, run), ("Track_Sit", 100, sit),
                                ("Track_Bend", 140, bend), ("Track_Jump", 180, jump)):
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(action.name, start, action)
    armature.animation_data.action = walk
    bpy.ops.object.mode_set(mode="OBJECT")
    return [walk, run, sit, bend, jump]
