import bpy

# Preserve the supplied CC armature and mesh together. Applying scale to both
# objects as one selection keeps their bind relationship intact for Godot.
armature = bpy.data.objects.get("Armature")
male = bpy.data.objects.get("Mesh_0")
for obj in bpy.context.scene.objects:
    obj.select_set(obj in [armature, male])
bpy.context.view_layer.objects.active = armature
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male_rigged.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
