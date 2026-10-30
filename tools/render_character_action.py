import bpy
import math

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='assets/models/characters/player_character_rigged.glb')

scene = bpy.context.scene
scene.render.resolution_x = 768
scene.render.resolution_y = 1024
scene.render.filepath = '/Users/rahulpannati/.gemini/antigravity-ide/brain/c95a9af8-1b37-48c7-afc7-e26ebf4e4938/player_replica_action.png'

armature = bpy.data.objects.get('Player_Armature') or bpy.data.objects.get('Armature')
mesh = bpy.data.objects.get('Player_Mesh') or bpy.data.objects.get('Mesh_0')

# Pose the character: dynamic walking/ready action pose
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='POSE')

def rotate_bone(name, angle_rad, axis=(1, 0, 0)):
    pb = armature.pose.bones.get(name)
    if pb:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (angle_rad * axis[0], angle_rad * axis[1], angle_rad * axis[2])

# Left leg forward, right leg back
rotate_bone("CC_Base_L_Thigh", -0.45, (1, 0, 0))
rotate_bone("CC_Base_L_Calf", 0.55, (1, 0, 0))
rotate_bone("CC_Base_R_Thigh", 0.35, (1, 0, 0))
rotate_bone("CC_Base_R_Calf", 0.15, (1, 0, 0))

# Arms swinging naturally: right arm forward, left arm back
rotate_bone("CC_Base_R_Upperarm", -0.40, (1, 0, 0))
rotate_bone("CC_Base_R_Forearm", 0.35, (0, 0, 1))
rotate_bone("CC_Base_L_Upperarm", 0.30, (1, 0, 0))
rotate_bone("CC_Base_L_Forearm", -0.35, (0, 0, 1))

# Torso twist & head look
rotate_bone("CC_Base_Spine01", 0.08, (0, 1, 0))
rotate_bone("CC_Base_Neck", 0.05, (1, 0, 0))

bpy.ops.object.mode_set(mode='OBJECT')

# Camera setup
cam_data = bpy.data.cameras.new('ActionCam')
cam_obj = bpy.data.objects.new('ActionCam', cam_data)
bpy.context.collection.objects.link(cam_obj)
scene.camera = cam_obj
cam_obj.location = (0.5, -2.6, 1.05)
cam_obj.rotation_euler = (1.52, 0, 0.2)

# Sun lighting with soft fill
sun_data = bpy.data.lights.new('KeyLight', type='SUN')
sun_data.energy = 3.5
sun_obj = bpy.data.objects.new('KeyLight', sun_data)
bpy.context.collection.objects.link(sun_obj)
sun_obj.rotation_euler = (0.6, -0.3, 0.4)

fill_data = bpy.data.lights.new('FillLight', type='SUN')
fill_data.energy = 1.2
fill_obj = bpy.data.objects.new('FillLight', fill_data)
bpy.context.collection.objects.link(fill_obj)
fill_obj.rotation_euler = (0.3, 0.4, -0.8)

bpy.ops.render.render(write_still=True)
print('Rendered player_replica_action.png successfully')
