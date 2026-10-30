import bpy
import os

base_dir = os.path.abspath(".")
output_glb = os.path.join(base_dir, "assets/models/characters/player_character_rigged.glb")
output_diffuse = os.path.join(base_dir, "assets/models/characters/player_character_diffuse.jpg")
base_model_path = os.path.join(base_dir, "assets/models/characters/gdk_realistic_male_rigged.glb")

print("Building character replica in Blender...")

# Reset Blender
bpy.ops.wm.read_factory_settings(use_empty=True)

# Import base rigged male model
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
    # Head & Hair region adjustments (z > 1.45m)
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

# Assign the new custom diffuse texture
mat = mesh.data.materials[0]
if mat and mat.node_tree:
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and "Normal" not in node.name:
            if os.path.exists(output_diffuse):
                new_img = bpy.data.images.load(output_diffuse)
                node.image = new_img
                print("Updated material texture node with user diffuse texture")
            break

# Ensure Armature and Mesh are selected for export
for obj in bpy.context.scene.objects:
    obj.select_set(obj in [armature, mesh])
bpy.context.view_layer.objects.active = armature

# Export rigged GLB with complete skins, def bones, and influences
bpy.ops.export_scene.gltf(
    filepath=output_glb,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_skins=True,
    export_all_influences=True,
    export_def_bones=True
)

print(f"Successfully generated rigged character at: {output_glb}")
print(f"Output GLB size: {os.path.getsize(output_glb) / (1024 * 1024):.2f} MB")
