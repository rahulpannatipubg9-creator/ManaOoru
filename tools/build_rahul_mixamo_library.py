import bpy
import os
import re

def clean_action_name(filename):
    name = os.path.splitext(filename)[0]
    name = re.sub(r'\s*\(\d+\)', '', name)
    name = re.sub(r'[^a-zA-Z0-9_]', '_', name)
    name = re.sub(r'_+', '_', name).strip('_')
    return name

def build_library():
    source_dir = "/Users/rahulpannati/Downloads/Rahul Animations"
    base_character_file = os.path.join(source_dir, "Air Squat Bent Arms.fbx")

    if not os.path.exists(base_character_file):
        print(f"ERROR: Base character file {base_character_file} not found!")
        return

    # Start with empty scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    print(f"Importing base character from {base_character_file}...")
    bpy.ops.import_scene.fbx(filepath=base_character_file)

    # Clean stray nodes (keep Armature and Soldier meshes)
    for o in list(bpy.data.objects):
        if o.name.lower() in ["camera", "light", "cube", "icosphere", "geo"]:
            bpy.data.objects.remove(o, do_unlink=True)

    arm_obj = None
    for o in bpy.data.objects:
        if o.type == 'ARMATURE':
            arm_obj = o
            break

    if not arm_obj:
        print("ERROR: Armature not found in base character!")
        return

    arm_obj.name = "Armature"
    print(f"Base Armature found: {arm_obj.name} with {len(arm_obj.data.bones)} bones")

    # Verify and report character meshes
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    print(f"Base character meshes: {[m.name for m in meshes]}")

    seen_actions = set()

    # Process first action from base file
    first_action = arm_obj.animation_data.action if arm_obj.animation_data else None
    if first_action:
        first_name = clean_action_name("Air Squat Bent Arms.fbx")
        first_action.name = first_name
        first_action.use_fake_user = True
        seen_actions.add(first_name)
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = first_name
        track.strips.new(first_name, int(first_action.frame_range[0]), first_action)
        print(f"Added base action [1]: {first_name}")

    # Gather all FBX files
    fbx_files = sorted([f for f in os.listdir(source_dir) if f.endswith(".fbx") and not f.startswith(".")])
    print(f"Found {len(fbx_files)} total animation files in {source_dir}")

    # Import the rest of the animations
    for i, fbx_name in enumerate(fbx_files, start=1):
        action_name = clean_action_name(fbx_name)
        if action_name in seen_actions:
            continue

        fbx_path = os.path.join(source_dir, fbx_name)
        before_objs = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.fbx(filepath=fbx_path)
        except Exception as e:
            print(f"Error importing {fbx_name}: {e}")
            continue

        new_objs = set(bpy.data.objects) - before_objs

        # Find the newly imported armature with its action
        imported_arm = None
        for o in new_objs:
            if o.type == 'ARMATURE' and o != arm_obj:
                imported_arm = o
                break

        if imported_arm and imported_arm.animation_data and imported_arm.animation_data.action:
            act = imported_arm.animation_data.action
            act.name = action_name
            act.use_fake_user = True
            seen_actions.add(action_name)
            track = arm_obj.animation_data.nla_tracks.new()
            track.name = action_name
            track.strips.new(action_name, int(act.frame_range[0]), act)
            print(f"Added action [{len(seen_actions)}]: {action_name} ({int(act.frame_range[1] - act.frame_range[0])} frames)")

        # Remove temporary imported objects
        for o in new_objs:
            bpy.data.objects.remove(o, do_unlink=True)

    print(f"Total unique actions assembled into master library: {len(seen_actions)}")

    # Set active default action
    default_act = (
        bpy.data.actions.get("Arm_Stretching") or
        bpy.data.actions.get("Flying_Knee_Punch_Combo") or
        bpy.data.actions.get("Boxing")
    )
    if default_act:
        arm_obj.animation_data.action = default_act

    out_glb = os.path.abspath("assets/models/characters/rahul/rahul_mixamo.glb")
    print(f"Exporting master GLB to {out_glb}...")
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format='GLB',
        use_selection=False,
        export_animations=True,
        export_nla_strips=True
    )
    print(f"Successfully exported {out_glb} ({os.path.getsize(out_glb)} bytes)")

if __name__ == "__main__":
    build_library()
