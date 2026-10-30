import bpy

for obj in list(bpy.context.scene.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.import_scene.gltf(filepath="assets/models/characters/gdk_realistic_male_static.glb")
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new("MobileGameLOD", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = 0.12
        bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male_static_mobile.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
