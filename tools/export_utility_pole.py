"""Export the user-supplied utility-pole Blender scene for Godot use.

The source is a downloaded CGTrader archive. This script exports only the pole,
light, transformer and connector assemblies; cameras, ground planes and the
model's baked wire spans are omitted because game wiring is laid out from real
road geometry at runtime.
"""

import bpy
import os
import sys

OUTPUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "utility_pole", "gdk_utility_pole.glb")
ROOTS = {"Estrutura Poste", "Iluminação", "Ripas Conectores"}


def belongs_to_pole(obj):
    current = obj
    while current:
        if current.name in ROOTS:
            return True
        current = current.parent
    return False


def main():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and belongs_to_pole(obj):
            obj.select_set(True)
    active = next((o for o in bpy.context.selected_objects if o.type == "MESH"), None)
    bpy.context.view_layer.objects.active = active
    # One shared mesh is much cheaper than instancing the Blender hierarchy at
    # every roadside location. A gentle decimation keeps its street-level form.
    bpy.ops.object.join()
    decimate = active.modifiers.new("Godot street-pole reduction", "DECIMATE")
    decimate.ratio = 0.35
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT")
    print("wrote", OUTPUT)


if __name__ == "__main__":
    main()
