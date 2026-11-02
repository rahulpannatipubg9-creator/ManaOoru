import bpy
import os

def prepare_rahul_for_mixamo():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    gltf_path = os.path.abspath("assets/models/characters/rahul/rahul.glb")
    out_dir = os.path.abspath("assets/models/characters/rahul/mixamo_ready")
    os.makedirs(out_dir, exist_ok=True)

    print(f"Loading {gltf_path}...")
    bpy.ops.import_scene.gltf(filepath=gltf_path)

    # Remove stray helper objects
    for obj in list(bpy.data.objects):
        if obj.name.lower() in ["camera", "light", "cube", "icosphere"]:
            bpy.data.objects.remove(obj, do_unlink=True)

    mesh_obj = bpy.data.objects.get("Rahul_Rodin")
    arm_obj = bpy.data.objects.get("Rahul_Skeleton")

    if not mesh_obj:
        print("ERROR: Rahul_Rodin mesh not found!")
        return

    # Convert WEBP texture to PNG for Mixamo compatibility
    diffuse_img = None
    for img in bpy.data.images:
        if "diffuse" in img.name.lower():
            diffuse_img = img
            break

    png_path = os.path.join(out_dir, "rahul_diffuse.png")
    if diffuse_img:
        diffuse_img.filepath_raw = png_path
        diffuse_img.file_format = 'PNG'
        diffuse_img.save()
        print(f"Saved diffuse PNG texture to: {png_path}")

        # Update material node to use PNG
        for mat in mesh_obj.data.materials:
            if mat and mat.use_nodes:
                for node in mat.node_tree.nodes:
                    if node.type == 'TEX_IMAGE' and "diffuse" in node.image.name.lower():
                        node.image = bpy.data.images.load(png_path)
                        print(f"Assigned PNG texture to material {mat.name}")

    # Set Armature to Rest Pose
    if arm_obj:
        arm_obj.animation_data_clear()
        if arm_obj.pose:
            for pb in arm_obj.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.rotation_euler = (0, 0, 0)
                pb.scale = (1, 1, 1)

    # 1. Export Rigged FBX with embedded media
    fbx_rigged_path = os.path.join(out_dir, "rahul_rigged_mixamo.fbx")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.fbx(
        filepath=fbx_rigged_path,
        use_selection=False,
        axis_forward='-Z',
        axis_up='Y',
        path_mode='COPY',
        embed_textures=True,
        bake_anim=False
    )
    print(f"Exported Rigged FBX: {fbx_rigged_path} ({os.path.getsize(fbx_rigged_path)} bytes)")

    # 2. Export Mesh-Only FBX (Ideal for Mixamo's Auto-Rigger with 5 marker dots)
    bpy.ops.object.select_all(action='DESELECT')
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_obj

    # Remove armature modifier for clean unrigged mesh
    arm_mod = None
    for mod in mesh_obj.modifiers:
        if mod.type == 'ARMATURE':
            arm_mod = mod
            break
    if arm_mod:
        mesh_obj.modifiers.remove(arm_mod)

    # Remove vertex groups for clean auto-rigging
    mesh_obj.vertex_groups.clear()

    # Unparent from armature
    mesh_obj.parent = None

    fbx_mesh_path = os.path.join(out_dir, "rahul_mesh_for_autorigger.fbx")
    bpy.ops.export_scene.fbx(
        filepath=fbx_mesh_path,
        use_selection=True,
        axis_forward='-Z',
        axis_up='Y',
        path_mode='COPY',
        embed_textures=True,
        bake_anim=False
    )
    print(f"Exported Mesh-only FBX: {fbx_mesh_path} ({os.path.getsize(fbx_mesh_path)} bytes)")

    # Create ZIP archive containing FBX + Texture (most resilient for Mixamo web uploader)
    import zipfile
    zip_path = os.path.join(out_dir, "rahul_for_mixamo.zip")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.write(fbx_mesh_path, arcname="rahul.fbx")
        if os.path.exists(png_path):
            zf.write(png_path, arcname="rahul_diffuse.png")
    print(f"Exported ZIP for Mixamo: {zip_path} ({os.path.getsize(zip_path)} bytes)")

    # Copy files to ~/Downloads so user can drag-and-drop into Mixamo in 1 click
    downloads_dir = os.path.expanduser("~/Downloads")
    if os.path.exists(downloads_dir):
        import shutil
        shutil.copy(fbx_rigged_path, os.path.join(downloads_dir, "rahul_rigged_mixamo.fbx"))
        shutil.copy(fbx_mesh_path, os.path.join(downloads_dir, "rahul_mesh_for_autorigger.fbx"))
        shutil.copy(zip_path, os.path.join(downloads_dir, "rahul_for_mixamo.zip"))
        print(f"Copied Mixamo upload files directly to {downloads_dir}!")

if __name__ == "__main__":
    prepare_rahul_for_mixamo()

