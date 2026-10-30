import bpy
import os

base_dir = os.path.abspath(".")
output_glb = os.path.join(base_dir, "assets/models/characters/player_character_rigged.glb")
output_diffuse = os.path.join(base_dir, "assets/models/characters/player_character_diffuse.jpg")
base_model_path = os.path.join(base_dir, "assets/models/characters/gdk_realistic_male_rigged.glb")

print("Generating rigged player character with full animation set...")

# Reset Blender
bpy.ops.wm.read_factory_settings(use_empty=True)

# Import base rigged character
bpy.ops.import_scene.gltf(filepath=base_model_path)

armature = bpy.data.objects.get("Armature")
mesh = bpy.data.objects.get("Mesh_0")

if not armature or not mesh:
    raise RuntimeError("Base rigged character failed to load")

mesh.name = "Player_Mesh"
armature.name = "Player_Armature"

# Reshape mesh vertices to match the user's facial, hair, and posture proportions
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.mode_set(mode='OBJECT')

verts = mesh.data.vertices
for v in verts:
    pos = v.co
    if pos.z > 1.45:
        # Taper sides of hair slightly inward (clean fade/taper)
        if abs(pos.x) > 0.08 and pos.z > 1.62:
            v.co.x *= 0.94
        # Add volume to top hair quiff
        if pos.z > 1.68 and pos.y < 0.04:
            v.co.z += (pos.z - 1.68) * 0.15
            v.co.y += 0.015
        # Round the chin / jaw slightly for user likeness
        if pos.z < 1.55 and pos.z > 1.45 and pos.y < -0.04:
            v.co.x *= 1.04
            v.co.y -= 0.005

mesh.data.update()

# Assign custom diffuse texture
mat = mesh.data.materials[0]
if mat and mat.node_tree:
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and "Normal" not in node.name:
            if os.path.exists(output_diffuse):
                new_img = bpy.data.images.load(output_diffuse)
                node.image = new_img
                print("Assigned user diffuse texture to material")
            break

# Build the 5 actions on the Armature
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='POSE')

for pb in armature.pose.bones:
    pb.rotation_mode = 'XYZ'

if armature.animation_data:
    armature.animation_data_clear()
armature.animation_data_create()

def key(bone_name, frame, rx=0, ry=0, rz=0):
    pb = armature.pose.bones.get(bone_name)
    if not pb:
        return
    pb.rotation_euler = (rx, ry, rz)
    pb.keyframe_insert('rotation_euler', frame=frame)

standing_bones = [
    'CC_Base_L_Thigh', 'CC_Base_R_Thigh', 'CC_Base_L_Calf', 'CC_Base_R_Calf',
    'CC_Base_Spine01', 'CC_Base_Spine02', 'CC_Base_L_Upperarm', 'CC_Base_R_Upperarm',
    'CC_Base_L_Forearm', 'CC_Base_R_Forearm', 'CC_Base_NeckTwist01'
]

# 1. Walk Cycle (frames 1 to 48)
walk_action = bpy.data.actions.new('Walk_Cycle')
armature.animation_data.action = walk_action
for f_offset in [0, 24]:
    s = 1.0 if f_offset == 0 else -1.0
    b = 1 + f_offset
    key('CC_Base_L_Thigh', b, rx=-0.35 * s)
    key('CC_Base_L_Calf', b, rx=0.15 if s > 0 else 0.65)
    key('CC_Base_R_Thigh', b, rx=0.35 * s)
    key('CC_Base_R_Calf', b, rx=0.65 if s > 0 else 0.15)
    key('CC_Base_L_Upperarm', b, rx=0.30 * s)
    key('CC_Base_R_Upperarm', b, rx=-0.30 * s)
    key('CC_Base_L_Forearm', b, rz=-0.25)
    key('CC_Base_R_Forearm', b, rz=0.25)
    key('CC_Base_Spine01', b, ry=0.06 * s)
    key('CC_Base_Spine02', b, rx=0.04)
    m = b + 6
    key('CC_Base_L_Thigh', m, rx=0.0)
    key('CC_Base_L_Calf', m, rx=0.35)
    key('CC_Base_R_Thigh', m, rx=0.0)
    key('CC_Base_R_Calf', m, rx=0.35)
    key('CC_Base_L_Upperarm', m, rx=0.0)
    key('CC_Base_R_Upperarm', m, rx=0.0)
    key('CC_Base_Spine01', m, ry=0.0)
    key('CC_Base_Spine02', m, rx=0.06)
    u = b + 12
    key('CC_Base_L_Thigh', u, rx=0.35 * s)
    key('CC_Base_L_Calf', u, rx=0.65 if s > 0 else 0.15)
    key('CC_Base_R_Thigh', u, rx=-0.35 * s)
    key('CC_Base_R_Calf', u, rx=0.15 if s > 0 else 0.65)
    key('CC_Base_L_Upperarm', u, rx=-0.30 * s)
    key('CC_Base_R_Upperarm', u, rx=0.30 * s)
    key('CC_Base_Spine01', u, ry=-0.06 * s)
    key('CC_Base_Spine02', u, rx=0.04)

# 2. Run Cycle (frames 1 to 24)
run_action = bpy.data.actions.new('Run_Cycle')
armature.animation_data.action = run_action
for f_offset in [0, 12]:
    s = 1.0 if f_offset == 0 else -1.0
    b = 1 + f_offset
    key('CC_Base_L_Thigh', b, rx=-0.65 * s)
    key('CC_Base_L_Calf', b, rx=0.20 if s > 0 else 1.1)
    key('CC_Base_R_Thigh', b, rx=0.65 * s)
    key('CC_Base_R_Calf', b, rx=1.1 if s > 0 else 0.20)
    key('CC_Base_L_Upperarm', b, rx=0.55 * s)
    key('CC_Base_R_Upperarm', b, rx=-0.55 * s)
    key('CC_Base_L_Forearm', b, rz=-0.6)
    key('CC_Base_R_Forearm', b, rz=0.6)
    key('CC_Base_Spine01', b, ry=0.10 * s, rx=0.12)
    key('CC_Base_Spine02', b, rx=0.10)
    m = b + 6
    key('CC_Base_L_Thigh', m, rx=0.65 * s)
    key('CC_Base_L_Calf', m, rx=1.1 if s > 0 else 0.20)
    key('CC_Base_R_Thigh', m, rx=-0.65 * s)
    key('CC_Base_R_Calf', m, rx=0.20 if s > 0 else 1.1)
    key('CC_Base_L_Upperarm', m, rx=-0.55 * s)
    key('CC_Base_R_Upperarm', m, rx=0.55 * s)
    key('CC_Base_L_Forearm', m, rz=-0.6)
    key('CC_Base_R_Forearm', m, rz=0.6)
    key('CC_Base_Spine01', m, ry=-0.10 * s, rx=0.12)
    key('CC_Base_Spine02', m, rx=0.10)

# 3. Sit Down (frames 1 to 30)
sit_action = bpy.data.actions.new('Sit_Down')
armature.animation_data.action = sit_action
for bn in standing_bones:
    key(bn, 1, rx=0, ry=0, rz=0)
key('CC_Base_L_Thigh', 15, rx=-0.65)
key('CC_Base_R_Thigh', 15, rx=-0.65)
key('CC_Base_L_Calf', 15, rx=0.80)
key('CC_Base_R_Calf', 15, rx=0.80)
key('CC_Base_Spine01', 15, rx=0.12)
key('CC_Base_Spine02', 15, rx=0.08)
key('CC_Base_L_Upperarm', 15, rx=0.15)
key('CC_Base_R_Upperarm', 15, rx=0.15)
key('CC_Base_L_Forearm', 15, rz=-0.3)
key('CC_Base_R_Forearm', 15, rz=0.3)

key('CC_Base_L_Thigh', 30, rx=-1.20)
key('CC_Base_R_Thigh', 30, rx=-1.20)
key('CC_Base_L_Calf', 30, rx=1.35)
key('CC_Base_R_Calf', 30, rx=1.35)
key('CC_Base_L_Foot', 30, rx=0.30)
key('CC_Base_R_Foot', 30, rx=0.30)
key('CC_Base_Spine01', 30, rx=0.18)
key('CC_Base_Spine02', 30, rx=0.10)
key('CC_Base_L_Upperarm', 30, rx=0.20, rz=0.15)
key('CC_Base_R_Upperarm', 30, rx=0.20, rz=-0.15)
key('CC_Base_L_Forearm', 30, rz=-0.45)
key('CC_Base_R_Forearm', 30, rz=0.45)

# 4. Bend Forward (frames 1 to 30)
bend_action = bpy.data.actions.new('Bend_Forward')
armature.animation_data.action = bend_action
for bn in standing_bones:
    key(bn, 1)
key('CC_Base_Spine01', 15, rx=0.55)
key('CC_Base_Spine02', 15, rx=0.40)
key('CC_Base_L_Thigh', 15, rx=-0.20)
key('CC_Base_R_Thigh', 15, rx=-0.20)
key('CC_Base_L_Calf', 15, rx=0.25)
key('CC_Base_R_Calf', 15, rx=0.25)
key('CC_Base_L_Upperarm', 15, rx=-0.80)
key('CC_Base_R_Upperarm', 15, rx=-0.80)
key('CC_Base_Spine01', 30, rx=0.90)
key('CC_Base_Spine02', 30, rx=0.55)
key('CC_Base_L_Thigh', 30, rx=-0.35)
key('CC_Base_R_Thigh', 30, rx=-0.35)
key('CC_Base_L_Calf', 30, rx=0.40)
key('CC_Base_R_Calf', 30, rx=0.40)
key('CC_Base_L_Upperarm', 30, rx=-1.30)
key('CC_Base_R_Upperarm', 30, rx=-1.30)

# 5. Jump (frames 1 to 30)
jump_action = bpy.data.actions.new('Jump')
armature.animation_data.action = jump_action
key('CC_Base_L_Thigh', 1, rx=-0.50)
key('CC_Base_R_Thigh', 1, rx=-0.50)
key('CC_Base_L_Calf', 1, rx=0.80)
key('CC_Base_R_Calf', 1, rx=0.80)
key('CC_Base_Spine01', 1, rx=0.20)
key('CC_Base_L_Upperarm', 1, rx=0.40)
key('CC_Base_R_Upperarm', 1, rx=0.40)

key('CC_Base_L_Thigh', 10, rx=0.15)
key('CC_Base_R_Thigh', 10, rx=0.15)
key('CC_Base_L_Calf', 10, rx=0.0)
key('CC_Base_R_Calf', 10, rx=0.0)
key('CC_Base_Spine01', 10, rx=-0.05)
key('CC_Base_L_Upperarm', 10, rx=-1.0)
key('CC_Base_R_Upperarm', 10, rx=-1.0)

key('CC_Base_L_Thigh', 18, rx=-0.35)
key('CC_Base_R_Thigh', 18, rx=-0.35)
key('CC_Base_L_Calf', 18, rx=0.60)
key('CC_Base_R_Calf', 18, rx=0.60)
key('CC_Base_Spine01', 18, rx=0.05)
key('CC_Base_L_Upperarm', 18, rx=-0.20)
key('CC_Base_R_Upperarm', 18, rx=-0.20)

key('CC_Base_L_Thigh', 30, rx=-0.55)
key('CC_Base_R_Thigh', 30, rx=-0.55)
key('CC_Base_L_Calf', 30, rx=0.85)
key('CC_Base_R_Calf', 30, rx=0.85)
key('CC_Base_Spine01', 30, rx=0.22)
key('CC_Base_L_Upperarm', 30, rx=0.30)
key('CC_Base_R_Upperarm', 30, rx=0.30)

# Push all actions onto NLA tracks so glTF exporter includes all of them
track_walk = armature.animation_data.nla_tracks.new()
track_walk.name = "Track_Walk"
track_walk.strips.new("Walk_Cycle", 1, walk_action)

track_run = armature.animation_data.nla_tracks.new()
track_run.name = "Track_Run"
track_run.strips.new("Run_Cycle", 60, run_action)

track_sit = armature.animation_data.nla_tracks.new()
track_sit.name = "Track_Sit"
track_sit.strips.new("Sit_Down", 100, sit_action)

track_bend = armature.animation_data.nla_tracks.new()
track_bend.name = "Track_Bend"
track_bend.strips.new("Bend_Forward", 140, bend_action)

track_jump = armature.animation_data.nla_tracks.new()
track_jump.name = "Track_Jump"
track_jump.strips.new("Jump", 180, jump_action)

# Default active action is Walk_Cycle
armature.animation_data.action = walk_action

bpy.ops.object.mode_set(mode='OBJECT')

for obj in bpy.context.scene.objects:
    obj.select_set(obj in [armature, mesh])
bpy.context.view_layer.objects.active = armature

print("Exporting GLB with animations and skinning...")
bpy.ops.export_scene.gltf(
    filepath=output_glb,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_skins=True,
    export_all_influences=True,
    export_def_bones=True,
    export_animations=True,
    export_animation_mode='ACTIONS'
)

print(f"Export finished successfully! File size: {os.path.getsize(output_glb) / (1024 * 1024):.2f} MB")
