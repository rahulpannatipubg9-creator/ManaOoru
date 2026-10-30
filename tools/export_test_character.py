"""Turn the "Chubby magic girl" .blend into a light, game-ready skinned glTF for LOCAL TESTING ONLY.

The source has no licence and contains third-party parts (see ASSET_LICENSES.md, "Rejected
downloads"), so the output goes to assets/test_only/, which is gitignored and excluded from
exports. The game only shows it when that file exists.

Steps: face-rig weights folded onto the head bone, hair/hat skinned to the head, shape keys
dropped, meshes decimated, 4K-8K PBR maps reduced to one small base-colour (+alpha) map per
material, and only the Rigify DEF bones exported.

Run: blender -b --disable-autoexec "Chubby magic girl.blend" --python tools/export_test_character.py -- assets/test_only/magic_girl
"""
import sys

import bpy
import numpy as np

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
RIG = "magic girl  pbr_Rigify"
HEAD_BONE = "DEF-spine.006"
KEEP = {"chubby_body": 14000, "top": 2500, "skirt": 1200, "Corset": 2500, "bra": 800, "boot": 3000,
        "hat": 2000, "hair": 7000, "eyes_L": 400, "eyes_R": 400, "eyes_brow": 600, "eyes_lashes": 600}
TEXTURE_SIZE = {"BODY": 1024}
DEFAULT_TEXTURE_SIZE = 512
ALPHA_MATERIALS = {"hair", "eyesbrow", "hat", "Corset"}


def tri_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def fold_unknown_groups(obj: bpy.types.Object, deform: set[str]) -> None:
    """Groups for bones the export will not contain (the face rig, Faceit masks) are dropped.
    Vertices that only the face rig moved (eyes, lashes, inner face) follow the head bone."""
    head = obj.vertex_groups.get(HEAD_BONE) or obj.vertex_groups.new(name=HEAD_BONE)
    foreign = {g.index for g in obj.vertex_groups if g.name not in deform}
    for vertex in obj.data.vertices:
        if not any(g.group not in foreign and g.weight > 0.0 for g in vertex.groups):
            head.add([vertex.index], 1.0, "REPLACE")
    for group in [g for g in obj.vertex_groups if g.index in foreign]:
        obj.vertex_groups.remove(group)


def skin_to_head(obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.matrix_world = world
    group = obj.vertex_groups.new(name=HEAD_BONE)
    group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig


def find_image(material: bpy.types.Material, words: tuple[str, ...]) -> bpy.types.Image | None:
    for node in material.node_tree.nodes:
        if node.bl_idname == "ShaderNodeTexImage" and node.image:
            name = node.image.name.lower()
            if any(word in name for word in words):
                return node.image
    return None


def baked_texture(material: bpy.types.Material) -> bpy.types.Image | None:
    base = find_image(material, ("basecolor", "base_color", "albedo"))
    alpha = find_image(material, ("alpha",)) if material.name in ALPHA_MATERIALS else None
    if base is None:
        return None
    size = TEXTURE_SIZE.get(material.name, DEFAULT_TEXTURE_SIZE)
    colour = base.copy()
    colour.scale(size, size)
    pixels = np.empty(size * size * 4, dtype=np.float32)
    colour.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    if alpha is not None:
        mask = alpha.copy()
        mask.scale(size, size)
        mask_pixels = np.empty(size * size * 4, dtype=np.float32)
        mask.pixels.foreach_get(mask_pixels)
        pixels[:, 3] = mask_pixels.reshape(-1, 4)[:, 0]
    else:
        pixels[:, 3] = 1.0
    out = bpy.data.images.new("Test_" + material.name, size, size, alpha=True)
    out.pixels.foreach_set(pixels.ravel())
    out.file_format = "PNG"
    out.pack()
    return out


def simple_material(material: bpy.types.Material) -> bpy.types.Material:
    texture = baked_texture(material)
    mat = bpy.data.materials.new("Test_" + material.name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.6
    if texture:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = texture
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if material.name in ALPHA_MATERIALS:
            mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.surface_render_method = "DITHERED"
    return mat


def main() -> None:
    rig = bpy.data.objects[RIG]
    deform = {b.name for b in rig.data.bones if b.use_deform}
    keep = [bpy.data.objects[name] for name in KEEP]
    for obj in keep:
        bpy.context.view_layer.objects.active = obj
        if obj.data.shape_keys:
            obj.shape_key_clear()
        if obj.name in ("hair", "hat"):
            skin_to_head(obj, rig)
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE" and m.object != rig]:
            obj.modifiers.remove(mod)
        fold_unknown_groups(obj, deform)
        if tri_count(obj) > KEEP[obj.name]:
            dec = obj.modifiers.new("Decimate", "DECIMATE")
            dec.ratio = KEEP[obj.name] / tri_count(obj)
            dec.use_collapse_triangulate = True
            bpy.ops.object.modifier_move_to_index(modifier=dec.name, index=0)
            bpy.ops.object.modifier_apply(modifier=dec.name)
        obj.data.materials[0] = simple_material(obj.data.materials[0])
        for index in range(1, len(obj.data.materials)):
            obj.data.materials[index] = obj.data.materials[0]
        print("STAT", obj.name, tri_count(obj))
    rig.data.pose_position = "REST"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in keep + [rig]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=f"{OUT_DIR}/magic_girl.glb", use_selection=True, export_format="GLB",
                              export_yup=True, export_skins=True, export_def_bones=True, export_animations=False,
                              export_morph=False, export_cameras=False, export_lights=False,
                              export_image_format="AUTO")
    print("STAT total", sum(tri_count(o) for o in keep), "height", round(rig.dimensions.z, 3))


main()
