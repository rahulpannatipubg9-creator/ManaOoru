import bpy

# Bake the supplied high-detail character into its rest pose. Its exported
# armature has invalid scale/origin data in Godot, which stretched the body;
# the static mesh is stable for this game's current non-animated avatar path.
for obj in list(bpy.context.scene.objects):
    if obj.name != "Mesh_0":
        bpy.data.objects.remove(obj, do_unlink=True)

male = bpy.data.objects.get("Mesh_0")
bpy.context.view_layer.objects.active = male
male.select_set(True)
while male.data.shape_keys and male.data.shape_keys.key_blocks:
    male.shape_key_remove(male.data.shape_keys.key_blocks[-1])
for modifier in list(male.modifiers):
    male.modifiers.remove(modifier)

bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male_static.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
