import bpy
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHAR_PATH = "/Users/rahulpannati/Downloads/Rahul Animations/mana orru assests/Ch35_nonPBR.fbx"
ANIM_DIR = pathlib.Path("/Users/rahulpannati/Downloads/Rahul Animations")
OUT_LIB = pathlib.Path("/Users/rahulpannati/GameReadyLibrary/Characters/GasMask_SWAT")
OUT_LIB.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

# 1. Import Gas Mask character
print("Importing Gas Mask Character...")
bpy.ops.import_scene.fbx(filepath=CHAR_PATH)

char_armature = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
char_armature.name = "GasMask_Armature"

char_mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
char_mesh.name = "GasMask_Mesh"

# 2. Decimate mesh to meet <= 25,000 triangle budget
char_mesh.data.calc_loop_triangles()
initial_tris = len(char_mesh.data.loop_triangles)
print(f"Initial Triangles: {initial_tris}")

target_ratio = 24000.0 / float(initial_tris)
if target_ratio < 1.0:
    mod = char_mesh.modifiers.new(name="BudgetDecimate", type='DECIMATE')
    mod.ratio = target_ratio
    bpy.context.view_layer.objects.active = char_mesh
    bpy.ops.object.modifier_apply(modifier=mod.name)
    char_mesh.data.calc_loop_triangles()
    print(f"Decimated to: {len(char_mesh.data.loop_triangles)} triangles")

# 3. Batch import all animations from Rahul Animations
fbx_files = sorted([f for f in os.listdir(ANIM_DIR) if f.endswith('.fbx') and not f.startswith('.')])
print(f"Found {len(fbx_files)} animation FBX files to load...")

loaded_actions = []

for idx, fbx_file in enumerate(fbx_files):
    anim_path = str(ANIM_DIR / fbx_file)
    action_name = fbx_file.replace(".fbx", "").strip()
    
    # Import animation FBX
    bpy.ops.import_scene.fbx(filepath=anim_path)
    
    # Locate newly imported armature
    temp_arm = next((o for o in bpy.context.scene.objects if o != char_armature and o.type == 'ARMATURE'), None)
    if temp_arm and temp_arm.animation_data and temp_arm.animation_data.action:
        act = temp_arm.animation_data.action
        act.name = action_name
        act.use_fake_user = True
        loaded_actions.append(action_name)
    
    # Clean up imported temp objects
    for o in list(bpy.context.scene.objects):
        if o != char_armature and o != char_mesh:
            if o.type in {'ARMATURE', 'MESH'}:
                bpy.data.objects.remove(o, do_unlink=True)

print(f"Successfully bound {len(loaded_actions)} Actions to Gas Mask!")

# Set default action to Idle Crouching or Jogging if available
default_act = bpy.data.actions.get("Jogging") or (bpy.data.actions[0] if len(bpy.data.actions) > 0 else None)
if default_act:
    char_armature.animation_data.action = default_act
    print(f"Default Active Action set to: {default_act.name}")

# 4. Save master .blend file with all 78 animations
blend_path = str(OUT_LIB / "gas_mask_all_animations.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"Saved master animation workspace to: {blend_path}")

# 5. Export clean GLB character
glb_path = str(OUT_LIB / "gas_mask_tpose.glb")
bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    export_animations=False,
    export_lights=False,
    export_cameras=False
)
print(f"Exported clean T-pose GLB to: {glb_path}")

