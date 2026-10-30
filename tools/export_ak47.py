"""Convert the free BlenderKit "Ak47" .blend (by ReWork3D, asset 1231f34c-13a2-43a1-b28b-f7598440436c) into a game-ready glTF.

Output: ak47.glb with the rifle in metres, barrel along Godot +Z (the character's forward),
up = +Y, origin at the top of the pistol grip so it can be held in a hand, and the 2K PBR
textures (albedo, metallic/roughness, OpenGL normal) embedded.

Run: blender -b --factory-startup --disable-autoexec ~/blenderkit_data/models/ak47_55ab87b5-0c11-4124-85e9-2bccfc5df7db/ak47_2K_e8a8841f-e926-4d34-a499-032439cea7e1.blend --python tools/export_ak47.py -- assets/models/weapons
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# The rifle is one baked mesh; "cylinder bake.001" is a loose 6 cm cartridge used for the thumbnail.
GUN_OBJECT = "bake"
# Source axes: barrel along -Y (muzzle at y=-0.464, butt at y=+0.424), up +Z, 0.889 m long.
# An AKM is 0.88 m long.
TARGET_LENGTH = 0.88
# The grip shaft spans y 0.127..0.177 and meets the receiver underside at z 0.172, centred on x.
GRIP_TOP = Vector((0.0, 0.150, 0.172))
# A held weapon is seen up close but must stay cheap on phones.
TRI_BUDGET = 15000
# The source node tree halves the green (roughness) channel before the BSDF; bake that into the texture.
ROUGHNESS_SCALE = 0.5


def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def evaluate(mesh, configure):
    tmp = bpy.data.objects.new("tmp_decimate", mesh)
    bpy.context.scene.collection.objects.link(tmp)
    configure(tmp.modifiers.new("dec", "DECIMATE"))
    reduced = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bm = bmesh.new()
    bm.from_mesh(reduced)
    bm.to_mesh(mesh)
    bm.free()
    bpy.data.meshes.remove(reduced)


def planar(mod):
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(1.0)
    mod.delimit = {"UV", "SEAM", "SHARP"}


def decimate(mesh, budget):
    """Dissolve coplanar triangles first (free on a hard-surface mesh), then collapse only if still over budget."""
    if tri_count(mesh) <= budget:
        return
    evaluate(mesh, planar)
    tris = tri_count(mesh)
    if tris <= budget:
        return

    def collapse(mod):
        mod.ratio = budget / tris
        mod.use_collapse_triangulate = True

    evaluate(mesh, collapse)


def image_feeding(node_tree, node_type):
    for link in node_tree.links:
        if link.to_node.type == node_type and link.from_node.type == "TEX_IMAGE":
            return link.from_node.image
    raise KeyError(node_type)


def image_on_socket(node_tree, socket_name):
    for link in node_tree.links:
        if link.to_socket.name == socket_name and link.from_node.type == "TEX_IMAGE":
            return link.from_node.image
    raise KeyError(socket_name)


def pack_metal_rough(source):
    """glTF reads roughness from G and metallic from B; the source already has that layout but scales roughness in nodes."""
    width, height = source.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    source.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    pixels[:, 0] = 1.0
    pixels[:, 1] *= ROUGHNESS_SCALE
    pixels[:, 3] = 1.0
    image = bpy.data.images.new("ak47_metal_rough", width, height, alpha=False)
    image.colorspace_settings.name = "Non-Color"
    image.pixels.foreach_set(pixels.ravel())
    image.file_format = "PNG"
    image.pack()
    return image


def rebuild_material(mat):
    """Replace the baked node tree with the plain Principled layout the glTF exporter understands."""
    # A rifle is a closed shell; culling back faces halves the fragment work on phones.
    mat.use_backface_culling = True
    tree = mat.node_tree
    albedo = image_on_socket(tree, "Base Color")
    normal = image_feeding(tree, "NORMAL_MAP")
    metal_rough = pack_metal_rough(image_feeding(tree, "SEPARATE_COLOR"))
    nodes = tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    out = nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def texture(image, non_color):
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        if non_color:
            image.colorspace_settings.name = "Non-Color"
        return node

    tree.links.new(texture(albedo, False).outputs["Color"], bsdf.inputs["Base Color"])
    split = nodes.new("ShaderNodeSeparateColor")
    tree.links.new(texture(metal_rough, True).outputs["Color"], split.inputs["Color"])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    tree.links.new(texture(normal, True).outputs["Color"], normal_map.inputs["Color"])
    tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])


def main():
    gun = bpy.data.objects[GUN_OBJECT]
    for slot in gun.material_slots:
        rebuild_material(slot.material)
    mesh = bpy.data.meshes.new_from_object(gun.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.transform(gun.matrix_world)
    source_tris = tri_count(mesh)
    decimate(mesh, TRI_BUDGET)
    verts = [v.co for v in mesh.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    scale = TARGET_LENGTH / (hi.y - lo.y)
    # Barrel already along Blender -Y (glTF/Godot +Z); only metres and the grip origin remain.
    mesh.transform(Matrix.Scale(scale, 4) @ Matrix.Translation(-GRIP_TOP))
    bpy.ops.object.select_all(action="DESELECT")
    rifle = bpy.data.objects.new("AK47", mesh)
    bpy.context.scene.collection.objects.link(rifle)
    rifle.select_set(True)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "ak47.glb"), use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True, export_texcoords=True, export_normals=True,
                              export_image_format="AUTO", export_cameras=False, export_lights=False,
                              export_animations=False)
    # Muzzle tip in Godot axes (x, y, z) = Blender (x, z, -y), for the player's Muzzle marker.
    muzzle = [v.co for v in mesh.vertices if v.co.y < min(v.co.y for v in mesh.vertices) + 0.005]
    tip = sum(muzzle, Vector()) / len(muzzle)
    print(f"STAT ak47 tris={tri_count(mesh)} (source {source_tris}) length={TARGET_LENGTH} scale={scale:.5f} "
          f"muzzle_godot=({tip.x:.3f}, {tip.z:.3f}, {-tip.y:.3f})")


main()
