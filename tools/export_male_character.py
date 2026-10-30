import bpy

# The package's native Blender file preserves the rig and embedded materials.
# Godot's Y-up coordinate system needs the character's Z-up source rotated.
for obj in bpy.context.scene.objects:
    obj.select_set(obj.type in {"MESH", "ARMATURE"})
    if obj.type in {"MESH", "ARMATURE"}:
        obj.rotation_euler.rotate_axis("X", -1.57079632679)
bpy.ops.export_scene.gltf(
    filepath="assets/models/characters/gdk_realistic_male.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
