import bpy

# Start from the user-supplied packed-texture .blend. Bake the rest mesh, then
# decimate it for mobile/Apple-M1 play. The source file is never modified.
male = bpy.data.objects.get("Mesh_0")
for obj in list(bpy.context.scene.objects):
    if obj != male:
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.context.view_layer.objects.active = male
male.select_set(True)
if male.parent:
    matrix = male.matrix_world.copy()
    male.parent = None
    male.matrix_world = matrix
while male.data.shape_keys and male.data.shape_keys.key_blocks:
    male.shape_key_remove(male.data.shape_keys.key_blocks[-1])
for modifier in list(male.modifiers):
    male.modifiers.remove(modifier)
lod = male.modifiers.new("MobileGameLOD", "DECIMATE")
lod.decimate_type = "COLLAPSE"
lod.ratio = 0.12
bpy.ops.object.modifier_apply(modifier=lod.name)
# 1K packed textures are sufficient for a third-person town game and avoid
# loading two 4K textures every time the player switches character.
for image in bpy.data.images:
    if image.size[0] > 1024 or image.size[1] > 1024:
        image.scale(1024, 1024)
bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male_textured_mobile.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
