import bpy
import os
import math

def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_studio():
    # Studio floor / stage
    bpy.ops.mesh.primitive_plane_add(size=50.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.name = "Studio_Floor"
    
    mat = bpy.data.materials.new(name="M_Studio_Floor")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.07, 0.08, 0.10, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.38
    floor.data.materials.append(mat)

    # Curved Backdrop
    bpy.ops.mesh.primitive_plane_add(size=50.0, location=(0.0, 7.0, 6.0), rotation=(math.radians(90.0), 0.0, 0.0))
    backdrop = bpy.context.active_object
    backdrop.name = "Studio_Backdrop"
    backdrop.data.materials.append(mat)

    # Key light (Warm sun)
    bpy.ops.object.light_add(type='SUN', location=(6.0, -10.0, 14.0))
    sun = bpy.context.active_object
    sun.name = "Key_Sun"
    sun.data.energy = 4.5
    sun.data.color = (1.0, 0.96, 0.92)
    sun.rotation_euler = (math.radians(52.0), math.radians(12.0), math.radians(-25.0))

    # Fill light (Soft blue sky fill)
    bpy.ops.object.light_add(type='AREA', location=(0.0, -9.0, 5.0))
    fill = bpy.context.active_object
    fill.name = "Fill_Area"
    fill.data.energy = 1200.0
    fill.data.size = 24.0
    fill.data.color = (0.88, 0.94, 1.0)
    fill.rotation_euler = (math.radians(65.0), 0.0, 0.0)

    # Rim light from behind (Separates character silhouettes from dark backdrop)
    bpy.ops.object.light_add(type='AREA', location=(0.0, 6.0, 6.0))
    rim = bpy.context.active_object
    rim.name = "Rim_Area"
    rim.data.energy = 1800.0
    rim.data.size = 26.0
    rim.data.color = (1.0, 0.92, 0.80)
    rim.rotation_euler = (math.radians(-65.0), 0.0, math.radians(180.0))

    # Frontal Camera framing the complete 7-character lineup
    bpy.ops.object.camera_add(location=(0.0, -11.8, 1.80), rotation=(math.radians(85.0), 0.0, 0.0))
    cam = bpy.context.active_object
    cam.name = "Showcase_Camera"
    cam.data.lens = 28.0
    bpy.context.scene.camera = cam

def add_nameplate(title_text, subtitle_text, x_pos):
    # Main Title (Gold metallic 3D text)
    bpy.ops.object.text_add(location=(x_pos, -1.0, 0.03), rotation=(math.radians(90.0), 0.0, 0.0))
    text_obj = bpy.context.active_object
    text_obj.name = f"Title_{title_text.replace(' ', '_')}"
    text_obj.data.body = title_text
    text_obj.data.size = 0.20
    text_obj.data.align_x = 'CENTER'
    text_obj.data.extrude = 0.02
    
    mat = bpy.data.materials.new(name=f"M_{text_obj.name}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.95, 0.76, 0.22, 1.0) # Gold
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.25
    text_obj.data.materials.append(mat)

    # Subtitle / Specs Info (Crisp cyan-white 3D text)
    if subtitle_text:
        bpy.ops.object.text_add(location=(x_pos, -1.35, 0.02), rotation=(math.radians(90.0), 0.0, 0.0))
        sub_obj = bpy.context.active_object
        sub_obj.name = f"Sub_{title_text.replace(' ', '_')}"
        sub_obj.data.body = subtitle_text
        sub_obj.data.size = 0.10
        sub_obj.data.align_x = 'CENTER'
        sub_obj.data.extrude = 0.01

        mat_sub = bpy.data.materials.new(name=f"M_{sub_obj.name}")
        mat_sub.use_nodes = True
        bsdf_sub = mat_sub.node_tree.nodes.get("Principled BSDF")
        if bsdf_sub:
            bsdf_sub.inputs["Base Color"].default_value = (0.75, 0.84, 0.92, 1.0)
            bsdf_sub.inputs["Metallic"].default_value = 0.2
            bsdf_sub.inputs["Roughness"].default_value = 0.5
        sub_obj.data.materials.append(mat_sub)

def cleanup_stray_helpers(new_objs):
    to_remove = []
    for o in new_objs:
        lower = o.name.lower()
        if "icosphere" in lower or "cube" in lower:
            to_remove.append(o)
        elif o.type in ["CAMERA", "LIGHT"]:
            to_remove.append(o)
    for o in to_remove:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
            if o in new_objs:
                new_objs.remove(o)

def import_and_place_gltf(filepath, x_pos, target_name, action_name=None, scale_factor=1.0):
    before_objs = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=filepath)
    new_objs = list(set(bpy.data.objects) - before_objs)
    
    cleanup_stray_helpers(new_objs)

    empty = bpy.data.objects.new(target_name, None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = (x_pos, 0.0, 0.0)

    roots = [o for o in new_objs if o.parent is None and o != empty]
    for r in roots:
        r.parent = empty
        if scale_factor != 1.0:
            r.scale = (scale_factor, scale_factor, scale_factor)

    return empty

def import_and_place_fbx(filepath, x_pos, target_name, scale_factor=1.0):
    before_objs = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=filepath)
    new_objs = list(set(bpy.data.objects) - before_objs)

    cleanup_stray_helpers(new_objs)

    empty = bpy.data.objects.new(target_name, None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = (x_pos, 0.0, 0.0)

    roots = [o for o in new_objs if o.parent is None and o != empty]
    for r in roots:
        r.parent = empty
        if scale_factor != 1.0:
            r.scale = (scale_factor, scale_factor, scale_factor)

    return empty

def append_from_blend(filepath, x_pos, target_name):
    before_objs = set(bpy.data.objects)
    with bpy.data.libraries.load(filepath) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name not in ['Camera', 'Light']]

    new_objs = []
    for obj in data_to.objects:
        if obj is not None:
            bpy.context.scene.collection.objects.link(obj)
            new_objs.append(obj)

    cleanup_stray_helpers(new_objs)

    empty = bpy.data.objects.new(target_name, None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = (x_pos, 0.0, 0.0)

    roots = [o for o in new_objs if o.parent is None and o != empty]
    for r in roots:
        r.parent = empty

    return empty

def build_procedural_pedestrian(x_pos):
    empty = bpy.data.objects.new("7. City Pedestrian", None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = (x_pos, 0.0, 0.0)

    m_shirt = bpy.data.materials.new("M_Pedestrian_Shirt")
    m_shirt.use_nodes = True
    m_shirt.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.14, 0.42, 0.26, 1.0)

    m_skin = bpy.data.materials.new("M_Pedestrian_Skin")
    m_skin.use_nodes = True
    m_skin.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.68, 0.42, 0.25, 1.0)

    m_pants = bpy.data.materials.new("M_Pedestrian_Pants")
    m_pants.use_nodes = True
    m_pants.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.08, 0.09, 0.12, 1.0)

    # Torso
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.8, location=(x_pos, 0.0, 0.95))
    torso = bpy.context.active_object
    torso.name = "Ped_Torso"
    torso.data.materials.append(m_shirt)
    torso.parent = empty

    # Head
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(x_pos, 0.0, 1.62))
    head = bpy.context.active_object
    head.name = "Ped_Head"
    head.data.materials.append(m_skin)
    head.parent = empty

    # Legs & Arms
    for side, offset_x in [("L", -0.16), ("R", 0.16)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.65, location=(x_pos + offset_x, 0.0, 0.36))
        leg = bpy.context.active_object
        leg.name = f"Ped_Leg_{side}"
        leg.data.materials.append(m_pants)
        leg.parent = empty

    for side, offset_x in [("L", -0.36), ("R", 0.36)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.60, location=(x_pos + offset_x, 0.0, 1.05))
        arm = bpy.context.active_object
        arm.name = f"Ped_Arm_{side}"
        arm.data.materials.append(m_shirt)
        arm.parent = empty

def configure_viewport_shading():
    for ws in bpy.data.workspaces:
        for screen in ws.screens:
            for area in screen.areas:
                if area.type == 'VIEW_3D':
                    for space in area.spaces:
                        if space.type == 'VIEW_3D':
                            space.shading.type = 'MATERIAL'

def main():
    print("Building comprehensive ManaOoru Characters Showcase...")
    clean_scene()
    setup_studio()

    # Master Lineup arranged along the X axis from -5.55 to +5.55 (compact spacing 1.85m)
    lineup = [
        {
            "name": "6. Realistic Male Scan",
            "title": "REALISTIC MALE",
            "sub": "Photogrammetry Scan • 485k Tris",
            "type": "gltf",
            "path": "assets/models/characters/gdk_realistic_male_rigged.glb",
            "x": -5.55,
            "scale": 1.0
        },
        {
            "name": "2. Player v2 (Previous)",
            "title": "PLAYER V2",
            "sub": "Previous Hero • 40k Tris • 17 Materials",
            "type": "gltf",
            "path": "assets/models/characters/player_v2_rigged.glb",
            "x": -3.70,
            "scale": 1.0
        },
        {
            "name": "3. Lady Character",
            "title": "MAGIC GIRL",
            "sub": "Rigify Lady • 35k Tris • 12 Materials",
            "type": "gltf",
            "path": "assets/test_only/magic_girl/magic_girl.glb",
            "x": -1.85,
            "scale": 0.55
        },
        {
            "name": "1. Rahul (Current Hero)",
            "title": "RAHUL",
            "sub": "Current Hero • 30k Tris • 1 Material",
            "type": "gltf",
            "path": "assets/models/characters/rahul/rahul.glb",
            "x": 0.0,
            "scale": 1.0
        },
        {
            "name": "4. Facial Animated Girl",
            "title": "ANIMATED GIRL",
            "sub": "FBX Download • Facial Morph Keys",
            "type": "fbx",
            "path": os.path.expanduser("~/Downloads/facial-animation-of-a-sexy-girl/source/FBX.fbx"),
            "x": 1.85,
            "scale": 1.0
        },
        {
            "name": "5. Heels Character",
            "title": "HEELS GIRL",
            "sub": "CC Rigged • High Heels Mesh",
            "type": "blend",
            "path": os.path.expanduser("~/Downloads/topless-sexy-girl-with-heels/source/untitled.blend"),
            "x": 3.70,
            "scale": 1.0
        }
    ]

    for item in lineup:
        path = item["path"]
        if not os.path.exists(path):
            print(f"Skipping {item['name']}, path not found: {path}")
            continue

        print(f"Importing {item['name']} at X={item['x']}...")
        if item["type"] == "gltf":
            import_and_place_gltf(path, item["x"], item["name"], scale_factor=item.get("scale", 1.0))
        elif item["type"] == "fbx":
            import_and_place_fbx(path, item["x"], item["name"], scale_factor=item.get("scale", 1.0))
        elif item["type"] == "blend":
            append_from_blend(path, item["x"], item["name"])

        add_nameplate(item["title"], item["sub"], item["x"])

    # Add the city resident pedestrian at X = 5.55
    print("Building 7. City Pedestrian at X=5.55...")
    build_procedural_pedestrian(5.55)
    add_nameplate("CITY RESIDENT", "Ambient Pedestrian • 1.2k Tris", 5.55)

    # In Blender 5.0+, bind slotted actions across armatures
    idle_act = bpy.data.actions.get("IDLE_Natural")
    if idle_act and len(idle_act.slots) > 0:
        target_slot = idle_act.slots[0]
        for char_name in ["1. Rahul (Current Hero)", "2. Player v2 (Previous)", "6. Realistic Male Scan"]:
            parent_empty = bpy.data.objects.get(char_name)
            if parent_empty:
                for child in parent_empty.children_recursive:
                    if child.type == 'ARMATURE':
                        if not child.animation_data:
                            child.animation_data_create()
                        child.animation_data.action = idle_act
                        child.animation_data.action_slot = target_slot
                        print(f"Bound action {idle_act.name} (slot: {target_slot.identifier}) to {char_name} -> {child.name}")

    # Set frame range for looping animation playback (1 to 240 frames = 10s at 24fps)
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 240
    bpy.context.scene.frame_current = 1

    configure_viewport_shading()

    out_path = os.path.abspath("ManaOoru_Characters_Showcase.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out_path)
    print(f"Successfully saved master showcase scene to: {out_path}")

if __name__ == "__main__":
    main()
