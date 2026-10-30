import bpy
from mathutils import Vector

# The native .blend and its Alembic export describe the same helicopter. Its
# Blender part origins are malformed, while the supplied Alembic has stable
# baked geometry; use that geometry as the reliable conversion source.
bpy.ops.wm.alembic_import(filepath="/Users/rahulpannati/Downloads/untitled.abc")
keep = {"Body", "Door_L", "Door_R", "Main_rotor", "Tail__rotor"}
for obj in list(bpy.context.scene.objects):
	obj.select_set(obj.name in keep)
for obj in list(bpy.context.selected_objects):
	obj.scale *= 0.032
	obj.rotation_euler.rotate_axis("X", -1.57079632679)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# This source has per-part origins far away from their visible geometry. Merge
# their evaluated transforms before centring, or Godot receives rotor nodes at
# impossible coordinates. A native rotor disc is added in the Godot scene.
bpy.context.view_layer.objects.active = bpy.data.objects["Body"]
bpy.ops.object.join()
aircraft = bpy.context.active_object
vertices = aircraft.data.vertices
centre = (Vector((min(v.co.x for v in vertices), min(v.co.y for v in vertices), min(v.co.z for v in vertices)))
	+ Vector((max(v.co.x for v in vertices), max(v.co.y for v in vertices), max(v.co.z for v in vertices)))) * 0.5
for vertex in vertices:
	vertex.co -= centre
aircraft.location = Vector((0.0, 0.0, 0.0))
bpy.ops.export_scene.gltf(
    filepath="assets/models/helicopter/gdk_chowrasta_helicopter.glb",
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
