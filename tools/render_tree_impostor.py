"""Renders the four-view tree impostor used for every tree in the game.

Source model: "Jacaranda Tree" from Poly Haven (CC0), https://polyhaven.com/a/jacaranda_tree, 1K glTF.
The model is rendered from 0, 45, 90 and 135 degrees, orthographic, on a transparent
background; the four 512 px views are then placed side by side in one 2048x512 atlas
(assets/textures/trees/broadleaf_impostor.png), base at the bottom edge, frame FRAME
metres square (printed as "frame").
Run: blender -b --disable-autoexec --python tools/render_tree_impostor.py -- jacaranda_tree_1k.gltf out/jacaranda
then paste out/jacaranda_0..3.png left to right into the atlas.
"""
import bpy, sys, math, mathutils
args = sys.argv[sys.argv.index("--") + 1:]
src, out_prefix = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
tree = [o for o in bpy.data.objects if o.type == "MESH"][0]
# Put the base at the origin.
bb = [tree.matrix_world @ mathutils.Vector(c) for c in tree.bound_box]
minz = min(v.z for v in bb); cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2; cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
tree.location -= mathutils.Vector((cx, cy, minz))
bpy.context.view_layer.update()
bb = [tree.matrix_world @ mathutils.Vector(c) for c in tree.bound_box]
height = max(v.z for v in bb); radius = max(max(abs(v.x), abs(v.y)) for v in bb)
size = max(height, radius * 2) * 1.02
print("TREE height %.2f radius %.2f frame %.2f" % (height, radius, size))
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.65, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
sun.data.energy = 2.5; sun.rotation_euler = (math.radians(35), 0, math.radians(30))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = size
for index, angle in enumerate([0, 45, 90, 135]):
    a = math.radians(angle)
    cam.location = (math.sin(a) * 100, -math.cos(a) * 100, size / 2)
    cam.rotation_euler = (math.radians(90), 0, a)
    scene.render.filepath = f"{out_prefix}_{index}.png"
    bpy.ops.render.render(write_still=True)
