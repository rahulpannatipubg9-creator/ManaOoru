import bpy

for obj in list(bpy.context.scene.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.import_scene.gltf(filepath="assets/models/characters/gdk_realistic_male.glb")
for obj in bpy.context.scene.objects:
    obj.select_set(obj.type in {"MESH", "ARMATURE"})
    if obj.type == "MESH" and obj.name != "Cube":
        bpy.context.view_layer.objects.active = obj
        # Facial blend shapes are not driven by this game and prevent topology
        # reduction. Keep the skeleton weights, discard only unused morph targets.
        while obj.data.shape_keys and obj.data.shape_keys.key_blocks:
            obj.shape_key_remove(obj.data.shape_keys.key_blocks[-1])
        decimate = obj.modifiers.new("MobileGameLOD", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        # ~58k triangles: visually credible at third-person distance while
        # avoiding an expensive half-million-triangle character every frame.
        decimate.ratio = 0.12
        bpy.ops.object.modifier_apply(modifier=decimate.name)
bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male_mobile.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
