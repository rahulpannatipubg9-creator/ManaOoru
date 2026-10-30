"""Build the player's own character from the GDK rigged male and the player's photos.

The body, CC_Base skeleton and UV layout come from gdk_realistic_male_rigged.glb. The front
photo is projected onto the head and baked into a fresh 2K diffuse together with the player's
skin tone on the neck and hands, a beige polo-coloured top and black joggers. The mesh is then
decimated to the mobile budget (head kept dense), scaled to 1.70 m, given the placeholder clips
and exported as player_character_rigged.glb, the file test_character.gd loads.

Run: blender -b --factory-startup --disable-autoexec --python tools/build_user_character.py -- assets/models/characters
"""
import glob
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from character_actions import build_actions  # noqa: E402
import hair_cards  # noqa: E402

OUT_DIR = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
BASE_GLB = os.path.join(OUT_DIR, "gdk_realistic_male_rigged.glb")
# macOS puts a narrow no-break space before "AM" in screenshot names, so match the time instead.
FRONT_PHOTO = glob.glob(os.path.join(OUT_DIR, "references", "Screenshot 2026-10-27 at 5.48.15*.png"))[0]
OUTPUT = os.path.join(OUT_DIR, "player_character_rigged.glb")
# KeenTools FaceBuilder head fitted to the player's photos (tools/facebuilder_head/facebuilder_session.blend
# holds the editable FaceBuilder head; player_head_facebuilder.blend is the mesh and baked skin exported from it).
FB_HEAD_BLEND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "facebuilder_head",
                             "player_head_facebuilder.blend")

TARGET_HEIGHT = 1.70
TRI_BUDGET = 28000
TEXTURE_SIZE = 2048
# Front photo (740 x 1326): pixel midpoint between the pupils and the pupil distance.
PHOTO_EYES = Vector((362.0, 385.0))
PHOTO_IPD = 155.0
# Head ellipse in the photo (centre, radii, feather) separating the player from the street behind.
PHOTO_HEAD = (Vector((362.0, 410.0)), Vector((160.0, 290.0)), 30.0)
# Photo rows (top-down) over which the projection fades in below the hairline.
PHOTO_HAIRLINE = (240.0, 290.0)
# Base head in the T-pose: eye midpoint (x, z) and pupil distance, read off an orthographic render.
HEAD_EYES = Vector((0.0, 1.655))
HEAD_IPD = 0.058
# Rest-pose bands, metres. The chin sits at z 1.56 and the bare neck runs down to the tee collar
# at 1.50: above HEAD_Z the front takes the photo, above NECK_Z and on the hands the base skin is
# tinted to the player's tone, the hoodie becomes the polo colour and the trousers the joggers.
HEAD_Z = (1.50, 1.52)
NECK_Z = (1.485, 1.50)
# The hoodie cuffs end at |x| 0.62 in the T-pose; everything outward is hand.
HAND_X = (0.62, 0.645)
TOP_Z = (0.96, 0.99)
BOOT_Z = (0.13, 0.16)
POLO = (0.62, 0.52, 0.41)
JOGGERS = (0.035, 0.035, 0.04)
# FaceBuilder topology vertices on the front of the player's right and left eye. The topology is the
# same for every FaceBuilder head, so these stay valid when the head is refitted.
FB_EYE_VERTS = (10060, 10292)
# Front of the base head's eyes in the rest pose, metres (the eyes sit at HEAD_EYES in x and z).
BASE_EYE_Y = -0.120
# Base hair cards starting above this height belong to the old head and are dropped.
FB_NECK_CUT_Z = 1.49
# The FaceBuilder neck is trimmed level here, just above its own ragged bottom edge (1.45 front,
# 1.46 back), so it reaches down inside the T-shirt collar; trimmed at FB_NECK_CUT_Z it left an open
# ring between chin and collar.
FB_HEAD_CUT_Z = 1.47
# Base-head vertices inside the FaceBuilder head, or closer than this outside it, are removed; the base
# hair cards further out stay and give the head its volume.
FB_CLEARANCE = 0.006
FB_HEAD_TRIS = 6000
# Hair cards grown from the hair shell (tools/hair_cards.py): count and the triangles they cost.
FB_HAIR_CARDS = 700
FB_HAIR_CARD_TRIS = FB_HAIR_CARDS * hair_cards.SEGMENTS * 2
# Head size: chin (menton) to crown on the finished TARGET_HEIGHT character, about 1/7.7 of the
# player's height as in a real adult (the base model's head is ~1/9.5 and looked too small).
FB_HEAD_HEIGHT_M = 0.22
# FaceBuilder topology vertices at the bottom of the chin and the top of the skull.
FB_MENTON_VERT = 9344
FB_CROWN_VERT = 15329
# Base hair cards reaching below this height in front of the ears hang over the FaceBuilder face and go.
FB_FRINGE_Z = HEAD_EYES.y + 0.05
FB_FRINGE_Y = -0.03
# FaceBuilder topology vertex at the front of the chin.
FB_CHIN_VERT = 8484
# The FaceBuilder photos show shirts below the jaw: the neck fades to the player's skin over this band,
# measured down from the chin.
FB_NECK_SKIN_BELOW_CHIN = (0.04, 0.01)
# Shirt collar caught by the photos along the jaw: bright (display luminance), unsaturated (red minus
# blue) texels below the cheeks are painted skin.
FB_SHIRT_LUMINANCE = (0.58, 0.68)
FB_SHIRT_RED_MINUS_BLUE = (0.10, 0.16)
FB_SHIRT_BELOW_Z = (HEAD_EYES.y - 0.06, HEAD_EYES.y - 0.03)
# The neck sits in the jaw's shadow, a little darker than the forehead and cheeks the skin is read from.
FB_NECK_SHADE = 0.8
# The base model's hair does not fit the player's skull, so everything of the base above this height
# goes (below it the hood and collar sit away from the head); the hair is rebuilt from the scalp.
FB_HAIR_TRIM_Z = HEAD_EYES.y - 0.02
# Base hair cards at the nape: islands behind the ears reaching above this height go too.
FB_NAPE_Z = HEAD_EYES.y - 0.07
# Hair volume rebuilt as a shell over the FaceBuilder scalp, textured with the photographed hair.
# Thickness grows from the sides to the top as the scalp turns upward (normal z over FB_HAIR_UP), the
# front-top gets the extra lift of the player's swept-up fringe, and the shell feathers to nothing
# over FB_HAIR_FEATHER edge rings before being smoothed.
FB_HAIR_THICKNESS = (0.012, 0.020)
FB_HAIR_UP = (0.15, 0.85)
FB_HAIR_FRONT_LIFT = 0.0
FB_HAIR_FEATHER = 8
FB_HAIR_SMOOTH = 12
# A scalp vertex is hair where the photo texture is darker than this (display luminance) above
# FB_HAIR_MIN_Z; in front of the ears the hairline starts higher so the eyebrows stay skin.
FB_HAIR_DARK = 0.22
FB_HAIR_MIN_Z = HEAD_EYES.y - 0.02
FB_HAIRLINE_FRONT_Z = HEAD_EYES.y + 0.05
# Facing (dot of the normal with -Y) over which the front photo fades in.
FRONT_FACING = (0.10, 0.60)
# Blue/green of the player's skin after white balance (sRGB); warm brown skin sits around here.
SKIN_BLUE_TO_GREEN = 0.78


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def image_pixels(image):
    pixels = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(image.size[1], image.size[0], 4)


def sample(pixels, uvs):
    """Mean linear colour of a byte image at the given UVs."""
    h, w = pixels.shape[:2]
    cols = [pixels[min(h - 1, int(v * h)) % h, min(w - 1, int(u * w)) % w, :3] for u, v in uvs]
    return srgb_to_linear(np.mean(cols, axis=0))


def mask_photo(path):
    """Load the photo into a float image with the phone's cool cast neutralised and a feathered
    head ellipse in its alpha, so the wall behind never reaches the mesh.
    Returns the image and the player's linear skin colour."""
    source = bpy.data.images.load(path)
    source.colorspace_settings.name = "sRGB"
    pixels = image_pixels(source)
    bpy.data.images.remove(source)
    h, w = pixels.shape[:2]
    # Forehead between the brows and the hairline: evenly lit, no stubble.
    forehead = pixels[h - 350:h - 310, 300:420, :3].reshape(-1, 3).mean(axis=0)
    # Skin has clearly less blue than green; the photo's grey wall says the white balance is cold.
    blue = min(1.0, SKIN_BLUE_TO_GREEN * forehead[1] / forehead[2])
    pixels[:, :, 2] *= blue
    centre, radii, feather = PHOTO_HEAD
    ys, xs = np.mgrid[0:h, 0:w]
    # Blender stores rows bottom-up; the landmarks are top-down pixel coordinates.
    rows = h - 1 - ys
    dist = np.sqrt(((xs - centre.x) / radii.x) ** 2 + ((rows - centre.y) / radii.y) ** 2)
    pixels[:, :, 3] = np.clip((1.0 - dist) * (radii.y / feather) + 1.0, 0.0, 1.0)
    # Nothing above the hairline: the base hair cards keep their own texture instead of sky.
    pixels[:, :, 3] *= np.clip((rows - PHOTO_HAIRLINE[0]) / (PHOTO_HAIRLINE[1] - PHOTO_HAIRLINE[0]), 0.0, 1.0)
    # Byte images sample like the original screenshot; the mask travels as its own non-colour image
    # rather than as alpha, which a repacked PNG can lose.
    image = bpy.data.images.new("front_photo", w, h)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels.ravel())
    mask = bpy.data.images.new("front_mask", w, h)
    mask.colorspace_settings.name = "Non-Color"
    mask_pixels = np.repeat(pixels[:, :, 3:4], 4, axis=2)
    mask_pixels[:, :, 3] = 1.0
    mask.pixels.foreach_set(mask_pixels.ravel())
    return image, mask, srgb_to_linear(forehead * (1.0, 1.0, blue))


def project_front(mesh):
    """UV layer mapping the rest-pose head onto the front photo (orthographic, eyes aligned)."""
    layer = mesh.uv_layers.new(name="proj_front")
    width, height = 740.0, 1326.0
    metres_per_pixel = HEAD_IPD / PHOTO_IPD
    for poly in mesh.polygons:
        for loop_index, vertex_index in zip(poly.loop_indices, poly.vertices):
            co = mesh.vertices[vertex_index].co
            px = PHOTO_EYES.x + (co.x - HEAD_EYES.x) / metres_per_pixel
            py = PHOTO_EYES.y - (co.z - HEAD_EYES.y) / metres_per_pixel
            layer.data[loop_index].uv = (px / width, 1.0 - py / height)
    return layer


def vertices_in(mesh, predicate):
    return [v for v in mesh.vertices if predicate(v.co)]


def uvs_of(mesh, verts):
    uv = mesh.uv_layers["UVMap"].data
    wanted = {v.index for v in verts}
    return [tuple(uv[li].uv) for p in mesh.polygons for li, vi in zip(p.loop_indices, p.vertices) if vi in wanted]


class Nodes:
    """Thin helper over a node tree for the bake material."""

    def __init__(self, tree):
        self.tree = tree
        self.nodes = tree.nodes
        self.links = tree.links

    def new(self, kind, **props):
        node = self.nodes.new(kind)
        for key, value in props.items():
            setattr(node, key, value)
        return node

    def link(self, out, node, socket):
        self.links.new(out, node.inputs[socket])
        return node

    def band(self, value, lo, hi):
        """0 below lo, 1 above hi, linear between (a soft step on a scalar)."""
        node = self.new("ShaderNodeMapRange", clamp=True)
        node.inputs["From Min"].default_value = lo
        node.inputs["From Max"].default_value = hi
        self.link(value, node, "Value")
        return node.outputs["Result"]

    def math(self, op, a, b=None, value=None):
        node = self.new("ShaderNodeMath", operation=op)
        self.link(a, node, 0)
        if b is not None:
            self.link(b, node, 1)
        if value is not None:
            node.inputs[1].default_value = value
        return node.outputs["Value"]

    def one_minus(self, a):
        node = self.new("ShaderNodeMath", operation="SUBTRACT")
        node.inputs[0].default_value = 1.0
        self.link(a, node, 1)
        return node.outputs["Value"]

    def mix(self, factor, a, b, blend="MIX"):
        node = self.new("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_factor=True)
        if isinstance(factor, float):
            node.inputs[0].default_value = factor
        else:
            self.link(factor, node, 0)
        if isinstance(a, tuple):
            node.inputs[6].default_value = (*a, 1.0)
        else:
            self.link(a, node, 6)
        if isinstance(b, tuple):
            node.inputs[7].default_value = (*b, 1.0)
        else:
            self.link(b, node, 7)
        return node.outputs[2]

    def recolour(self, base, target, mean_luminance):
        """Flat `target` shaded by the base texture's own light and wrinkles."""
        lum = self.new("ShaderNodeRGBToBW")
        self.link(base, lum, "Color")
        shade = self.new("ShaderNodeMapRange", clamp=True)
        shade.inputs["From Min"].default_value = 0.0
        shade.inputs["From Max"].default_value = mean_luminance * 2.0
        # Keep the range tight: the hoodie's stitching highlights would otherwise bleach to white.
        shade.inputs["To Min"].default_value = 0.45
        shade.inputs["To Max"].default_value = 1.35
        self.link(lum.outputs["Val"], shade, "Value")
        tint = self.new("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY", clamp_factor=True)
        tint.inputs[0].default_value = 1.0
        tint.inputs[6].default_value = (*target, 1.0)
        grey = self.new("ShaderNodeCombineColor")
        for socket in ("Red", "Green", "Blue"):
            self.link(shade.outputs["Result"], grey, socket)
        self.link(grey.outputs["Color"], tint, 7)
        return tint.outputs[2]


def bake_material(mat, base_image, photo, photo_mask, skin_colour, skin_luminance, top_luminance, trouser_luminance,
                  target, use_photo=True):
    """Rebuild `mat` as an emission of the composed colour and return the target image node.
    With use_photo off the head keeps the base colours (the FaceBuilder head replaces the face)."""
    tree = mat.node_tree
    tree.nodes.clear()
    n = Nodes(tree)
    base_uv = n.new("ShaderNodeUVMap", uv_map="UVMap")
    photo_uv = n.new("ShaderNodeUVMap", uv_map="proj_front")
    base_tex = n.link(base_uv.outputs["UV"], n.new("ShaderNodeTexImage", image=base_image), "Vector")
    photo_tex = n.link(photo_uv.outputs["UV"], n.new("ShaderNodeTexImage", image=photo, extension="CLIP"), "Vector")
    mask_tex = n.link(photo_uv.outputs["UV"], n.new("ShaderNodeTexImage", image=photo_mask, extension="CLIP"), "Vector")
    geometry = n.new("ShaderNodeNewGeometry")
    position = n.link(geometry.outputs["Position"], n.new("ShaderNodeSeparateXYZ"), "Vector")
    abs_x = n.math("ABSOLUTE", position.outputs["X"])
    facing = n.new("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    facing.inputs[1].default_value = (0.0, -1.0, 0.0)
    n.link(geometry.outputs["Normal"], facing, 0)

    head = n.band(position.outputs["Z"], *HEAD_Z)
    neck = n.band(position.outputs["Z"], *NECK_Z)
    hands = n.band(abs_x, *HAND_X)
    top = n.math("MULTIPLY", n.band(position.outputs["Z"], *TOP_Z), n.one_minus(neck))
    top = n.math("MULTIPLY", top, n.one_minus(hands))
    trousers = n.math("MULTIPLY", n.band(position.outputs["Z"], *BOOT_Z), n.one_minus(n.band(position.outputs["Z"], *TOP_Z)))
    photo_weight = n.math("MULTIPLY", n.band(facing.outputs["Value"], *FRONT_FACING), head)
    photo_weight = n.math("MULTIPLY", photo_weight, mask_tex.outputs["Color"])
    # Only the hands: the base neck is gone under the FaceBuilder head, and above NECK_Z the body is
    # hood, which must keep its own dark lining.
    skin = hands if not use_photo else n.math("MAXIMUM", neck, hands)

    base = base_tex.outputs["Color"]
    # Recoloured like the clothes, not ratio-tinted: the base hands are a paler, pinker skin than the base
    # neck, so a neck-to-player ratio left them pink beside the player's face.
    colour = n.mix(skin, base, n.recolour(base, tuple(float(c) for c in skin_colour), skin_luminance))
    colour = n.mix(top, colour, n.recolour(base, POLO, top_luminance))
    colour = n.mix(trousers, colour, n.recolour(base, JOGGERS, trouser_luminance))
    if use_photo:
        colour = n.mix(photo_weight, colour, photo_tex.outputs["Color"])
    emission = n.link(colour, n.new("ShaderNodeEmission"), "Color")
    out = n.new("ShaderNodeOutputMaterial")
    n.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    target_node = n.new("ShaderNodeTexImage", image=target)
    tree.nodes.active = target_node
    return target_node


def final_material(mat, diffuse, normal):
    tree = mat.node_tree
    tree.nodes.clear()
    n = Nodes(tree)
    bsdf = n.new("ShaderNodeBsdfPrincipled")
    # Matte like the source (specular 0): any gloss turns the thousands of hair-card facets grey.
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    bsdf.inputs["Metallic"].default_value = 0.0
    out = n.new("ShaderNodeOutputMaterial")
    n.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    n.links.new(n.new("ShaderNodeTexImage", image=diffuse).outputs["Color"], bsdf.inputs["Base Color"])
    normal.colorspace_settings.name = "Non-Color"
    normal_map = n.new("ShaderNodeNormalMap")
    n.links.new(n.new("ShaderNodeTexImage", image=normal).outputs["Color"], normal_map.inputs["Color"])
    n.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    # Hair cards are single quads seen from both sides.
    mat.use_backface_culling = False


def load_facebuilder_head(base_height):
    """Append the FaceBuilder head and move it onto the base head: FB_HEAD_HEIGHT_M tall once the rig is
    scaled from base_height to TARGET_HEIGHT, eyes on the base eyes, neck trimmed at the collar."""
    with bpy.data.libraries.load(FB_HEAD_BLEND, link=False) as (_, dst):
        dst.objects = ["FBHead_export"]
    head = dst.objects[0]
    bpy.context.scene.collection.objects.link(head)
    head.name = "Player_Head"
    head.matrix_world = Matrix.Identity(4)
    mesh = head.data
    right, left = (mesh.vertices[i].co.copy() for i in FB_EYE_VERTS)
    head_units = mesh.vertices[FB_CROWN_VERT].co.z - mesh.vertices[FB_MENTON_VERT].co.z
    scale = FB_HEAD_HEIGHT_M / head_units * base_height / TARGET_HEIGHT
    target = Vector((HEAD_EYES.x, BASE_EYE_Y, HEAD_EYES.y))
    mesh.transform(Matrix.Translation(target) @ Matrix.Scale(scale, 4) @ Matrix.Translation(-(right + left) / 2))
    head["fb_chin_z"] = mesh.vertices[FB_CHIN_VERT].co.z  # before the neck trim renumbers vertices
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # A plane bisect leaves a clean edge loop; deleting vertices below the height leaves a staircase.
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                           plane_co=(0.0, 0.0, FB_HEAD_CUT_Z), plane_no=(0.0, 0.0, 1.0), clear_inner=True)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return head


def facebuilder_skin(head):
    """The player's linear skin colour, read off the FaceBuilder texture on the forehead and upper cheeks."""
    mat = head.material_slots[0].material
    image = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    eyes_z = HEAD_EYES.y
    forehead = vertices_in(head.data, lambda c: eyes_z + 0.02 < c.z < eyes_z + 0.04 and abs(c.x) < 0.025 and c.y < -0.06)
    cheeks = vertices_in(head.data, lambda c: eyes_z - 0.045 < c.z < eyes_z - 0.025 and 0.025 < abs(c.x) < 0.045
                         and c.y < -0.05)
    verts = forehead + cheeks
    if len(verts) < 20:
        raise RuntimeError(f"Only {len(verts)} skin sample vertices on the FaceBuilder head")
    pixels = image_pixels(image)
    uvs = uvs_of(head.data, verts)
    h, w = pixels.shape[:2]
    cols = np.array([pixels[min(h - 1, int(v * h)), min(w - 1, int(u * w)), :3] for u, v in uvs])
    return srgb_to_linear(np.median(cols, axis=0))


def add_hair_shell(head):
    """Give the photographed hair volume: copy the dark scalp faces of the FaceBuilder head and push
    them out along the normals, thick on the crown, close at the sides, feathered at the hairline.
    Returns the number of shell faces."""
    mesh = head.data
    mat = head.material_slots[0].material
    image = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    pixels = image_pixels(image)
    h, w = pixels.shape[:2]
    uv = mesh.uv_layers["UVMap"].data
    dark = np.zeros(len(mesh.vertices), dtype=np.float32)
    count = np.zeros(len(mesh.vertices), dtype=np.float32)
    for loop in mesh.loops:
        u, v = uv[loop.index].uv
        rgb = pixels[min(h - 1, max(0, int(v * h))), min(w - 1, max(0, int(u * w))), :3]
        dark[loop.vertex_index] += float(np.dot(rgb, (0.2126, 0.7152, 0.0722)))
        count[loop.vertex_index] += 1.0
    luminance = dark / np.maximum(count, 1.0)

    def is_hair(v):
        c = v.co
        if c.z < FB_HAIR_MIN_Z or luminance[v.index] > FB_HAIR_DARK:
            return False
        in_front = c.y < -0.04
        return not in_front or c.z > FB_HAIRLINE_FRONT_Z

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    hair_verts = {v.index for v in bm.verts if is_hair(mesh.vertices[v.index])}
    faces = [f for f in bm.faces if all(v.index in hair_verts for v in f.verts)]
    if not faces:
        bm.free()
        return 0
    copied = bmesh.ops.duplicate(bm, geom=faces)
    new_faces = [g for g in copied["geom"] if isinstance(g, bmesh.types.BMFace)]
    new_verts = {g for g in copied["geom"] if isinstance(g, bmesh.types.BMVert)}
    bm.normal_update()
    # Rings in from the shell's open edge, for feathering.
    rings = {v: None for v in new_verts}
    frontier = [v for v in new_verts if any(e.is_boundary for e in v.link_edges)]
    for v in frontier:
        rings[v] = 0
    while frontier:
        nxt = []
        for v in frontier:
            for e in v.link_edges:
                o = e.other_vert(v)
                if o in rings and rings[o] is None:
                    rings[o] = rings[v] + 1
                    nxt.append(o)
        frontier = nxt
    thickness = {}
    for v in new_verts:
        n = v.normal
        up = min(1.0, max(0.0, (n.z - FB_HAIR_UP[0]) / (FB_HAIR_UP[1] - FB_HAIR_UP[0])))
        up = up * up * (3.0 - 2.0 * up)
        thick = FB_HAIR_THICKNESS[0] + (FB_HAIR_THICKNESS[1] - FB_HAIR_THICKNESS[0]) * up
        if n.y < -0.2:
            thick += FB_HAIR_FRONT_LIFT * up * min(1.0, -n.y / 0.6)
        ring = rings[v] if rings[v] is not None else FB_HAIR_FEATHER
        thickness[v] = thick * min(1.0, ring / FB_HAIR_FEATHER) ** 0.7
    for v, t in thickness.items():
        v.co += v.normal * t
    interior = [v for v in new_verts if rings[v] != 0]
    for _ in range(FB_HAIR_SMOOTH):
        bmesh.ops.smooth_vert(bm, verts=interior, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    # Shell triangles (head space is world space here) for the hair-card roots.
    tris = []
    for f in new_faces:
        corners = [v.co.copy() for v in f.verts]
        for i in range(1, len(corners) - 1):
            tris.append((corners[0], corners[i], corners[i + 1], f.normal.copy()))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(new_faces), tris


def remove_base_head(body, head, diffuse, skin):
    """Delete the base head's skin under the FaceBuilder head and cap the opening with the baked texel
    nearest the linear skin colour. Returns the number of vertices removed."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(head, depsgraph)
    doomed = set()
    for v in body.data.vertices:
        if v.co.z < FB_HEAD_CUT_Z:
            continue
        loc, normal, _, dist = bvh.find_nearest(v.co)
        if loc is None:
            continue
        if v.co.z > FB_HAIR_TRIM_Z or (v.co - loc).dot(normal) <= 0.0 or dist < FB_CLEARANCE:
            doomed.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    # Whole hair cards (loose islands above the collar) that hang in front of the face.
    seen = set()
    for start in bm.verts:
        if start.index in seen or start.co.z < FB_NECK_CUT_Z:
            continue
        island, stack = [], [start]
        seen.add(start.index)
        while stack:
            v = stack.pop()
            island.append(v.index)
            for e in v.link_edges:
                other = e.other_vert(v)
                if other.index not in seen:
                    seen.add(other.index)
                    stack.append(other)
        hangs_over_face = any(FB_NECK_CUT_Z < bm.verts[i].co.z < FB_FRINGE_Z and bm.verts[i].co.y < FB_FRINGE_Y
                              for i in island)
        reaches_scalp = any(bm.verts[i].co.z > FB_HAIR_TRIM_Z
                            or (bm.verts[i].co.z > FB_NAPE_Z and (bm.verts[i].co.y > 0.0 or abs(bm.verts[i].co.x) > 0.06))
                            for i in island)
        if len(island) < 5000 and (hangs_over_face or reaches_scalp):
            doomed.update(island)
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed], context="VERTS")
    cap_neck(bm, diffuse, skin)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return len(doomed)


def cap_neck(bm, diffuse, skin):
    """Close the openings left where the base head was cut away, so no gap between the FaceBuilder neck
    and the collar looks into the hollow body. The rim crosses several UV islands, so the caps take one
    texel of the baked diffuse, the one closest to the FaceBuilder neck's skin, rather than the rim's UVs."""
    # The merged base is one closed surface, so anything cut off from the largest piece is a scrap of the
    # old mouth, eyes or scalp left hidden inside the new head.
    pieces, seen = [], set()
    for start in bm.verts:
        if start in seen:
            continue
        piece, stack = [], [start]
        seen.add(start)
        while stack:
            v = stack.pop()
            piece.append(v)
            for e in v.link_edges:
                other = e.other_vert(v)
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
        pieces.append(piece)
    pieces.sort(key=len)
    bmesh.ops.delete(bm, geom=[v for piece in pieces[:-1] for v in piece], context="VERTS")
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if e.is_wire], context="EDGES")
    uv = bm.loops.layers.uv["UVMap"]
    pixels = image_pixels(diffuse)
    h, w = pixels.shape[:2]
    # Match on 16-texel blocks, so mipmapped samples of the chosen centre stay the same colour.
    block = 16
    blocks = srgb_to_linear(pixels[:h // block * block, :w // block * block, :3]
                            .reshape(h // block, block, w // block, block, 3).mean(axis=(1, 3)))
    row, col = np.unravel_index(np.argmin(np.linalg.norm(blocks - skin, axis=2)), blocks.shape[:2])
    skin_uv = ((col + 0.5) * block / w, (row + 0.5) * block / h)
    for _ in range(4):
        caps = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)["faces"]
        for face in caps:
            for loop in face.loops:
                loop[uv].uv = skin_uv
        bmesh.ops.triangulate(bm, faces=caps)
        rim = {v for e in bm.edges if e.is_boundary for v in e.verts}
        if not rim:
            return
        # A rim that touches itself (two loops sharing a vertex) cannot be filled; open it by one ring of
        # faces and fill again.
        bmesh.ops.delete(bm, geom=list({f for v in rim for f in v.link_faces}), context="FACES_ONLY")
        bmesh.ops.delete(bm, geom=[e for e in bm.edges if e.is_wire], context="EDGES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context="VERTS")
    raise RuntimeError("Body still has open edges after capping the neck")


def skin_head(head, body):
    """Copy the body's bone weights onto the head from the nearest base surface."""
    for group in body.vertex_groups:
        head.vertex_groups.new(name=group.name)
    mod = head.modifiers.new("BodyWeights", "DATA_TRANSFER")
    mod.object = body
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    mod.vert_mapping = "POLYINTERP_NEAREST"
    mod.layers_vgroup_select_src = "ALL"
    mod.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = head
    with bpy.context.temp_override(object=head, active_object=head):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    unweighted = sum(1 for v in head.data.vertices if not any(g.weight > 0.0 for g in v.groups))
    if unweighted:
        raise RuntimeError(f"{unweighted} FaceBuilder head vertices got no bone weights")
    for group in list(head.vertex_groups):
        if not any(g.group == group.index and g.weight > 0.0 for v in head.data.vertices for g in v.groups):
            head.vertex_groups.remove(group)


def bake_head_skin(head, skin):
    """Re-bake the FaceBuilder texture with the neck below the jaw faded to the player's skin.
    Expects Cycles to be the render engine. Returns the new image."""
    mat = head.material_slots[0].material
    source = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    target = bpy.data.images.new("player_head_diffuse", TEXTURE_SIZE, TEXTURE_SIZE)
    tree = mat.node_tree
    tree.nodes.clear()
    n = Nodes(tree)
    tex = n.link(n.new("ShaderNodeUVMap", uv_map="UVMap").outputs["UV"], n.new("ShaderNodeTexImage", image=source),
                 "Vector")
    position = n.link(n.new("ShaderNodeNewGeometry").outputs["Position"], n.new("ShaderNodeSeparateXYZ"), "Vector")
    chin_z = head["fb_chin_z"]
    neck = n.one_minus(n.band(position.outputs["Z"], chin_z - FB_NECK_SKIN_BELOW_CHIN[0],
                              chin_z - FB_NECK_SKIN_BELOW_CHIN[1]))
    rgb = n.link(tex.outputs["Color"], n.new("ShaderNodeSeparateColor"), "Color")
    red, green, blue = (n.math("POWER", rgb.outputs[c], value=1.0 / 2.2) for c in ("Red", "Green", "Blue"))
    luminance = n.math("ADD", n.math("ADD", n.math("MULTIPLY", red, value=0.2126),
                                     n.math("MULTIPLY", green, value=0.7152)),
                       n.math("MULTIPLY", blue, value=0.0722))
    shirt = n.math("MULTIPLY", n.band(luminance, *FB_SHIRT_LUMINANCE),
                   n.one_minus(n.band(n.math("SUBTRACT", red, blue), *FB_SHIRT_RED_MINUS_BLUE)))
    shirt = n.math("MULTIPLY", shirt, n.one_minus(n.band(position.outputs["Z"], *FB_SHIRT_BELOW_Z)))
    colour = n.mix(n.math("MAXIMUM", neck, shirt), tex.outputs["Color"], tuple(float(c) for c in skin))
    emission = n.link(colour, n.new("ShaderNodeEmission"), "Color")
    n.links.new(emission.outputs["Emission"], n.new("ShaderNodeOutputMaterial").inputs["Surface"])
    target_node = n.new("ShaderNodeTexImage", image=target)
    tree.nodes.active = target_node
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.bake(type="EMIT")
    bpy.data.images.remove(source)
    return target


def head_material(head, image):
    mat = head.material_slots[0].material
    image.pack()
    mat.name = "player_head_skin"
    tree = mat.node_tree
    tree.nodes.clear()
    n = Nodes(tree)
    bsdf = n.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Specular IOR Level"].default_value = 0.25
    out = n.new("ShaderNodeOutputMaterial")
    n.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    n.links.new(n.new("ShaderNodeTexImage", image=image).outputs["Color"], bsdf.inputs["Base Color"])
    mat.use_backface_culling = True


def decimate_head(head, budget):
    tris = sum(len(p.vertices) - 2 for p in head.data.polygons)
    mod = head.modifiers.new("MobileGameLOD", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, budget / tris)
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=head, active_object=head):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def decimate(obj, budget):
    """Collapse to the budget, spending most of it on the head and hands."""
    mesh = obj.data
    while mesh.shape_keys and mesh.shape_keys.key_blocks:
        obj.shape_key_remove(mesh.shape_keys.key_blocks[-1])
    group = obj.vertex_groups.new(name="decimate_weight")
    # Low weights collapse least: the head (hair cards) and the hands keep their detail so the fingers
    # still bend into a clean grip or fist.
    keep = [v.index for v in mesh.vertices if v.co.z > HEAD_Z[0] or abs(v.co.x) > HAND_X[0]]
    kept = set(keep)
    body = [v.index for v in mesh.vertices if v.index not in kept]
    group.add(body, 1.0, "REPLACE")
    group.add(keep, 0.15, "REPLACE")
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    mod = obj.modifiers.new("MobileGameLOD", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = budget / tris
    mod.vertex_group = group.name
    mod.vertex_group_factor = 1.0
    mod.use_collapse_triangulate = True
    # Evaluate the collapse on the rest mesh alone (armature deform off) and keep the result,
    # with its weights and UVs, as the object's mesh.
    armature_mods = [m for m in obj.modifiers if m.type == "ARMATURE"]
    for m in armature_mods:
        m.show_viewport = m.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                              depsgraph=depsgraph)
    reduced.name = "Player_Mesh"
    obj.modifiers.remove(mod)
    for m in armature_mods:
        m.show_viewport = m.show_render = True
    obj.data = reduced
    bpy.data.meshes.remove(mesh)
    obj.vertex_groups.remove(obj.vertex_groups["decimate_weight"])
    return reduced


def scale_rig(armature, body, factor):
    """Scale mesh and rest pose in place so the export carries no node scale."""
    body.data.transform(Matrix.Scale(factor, 4))
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in armature.data.edit_bones:
        bone.head *= factor
        bone.tail *= factor
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # glTF stores a vertex per UV seam corner; unmerged, the seams decimate independently and tear the
    # clothes into shards with open cracks. Merged, the base body is one closed surface.
    bpy.ops.import_scene.gltf(filepath=BASE_GLB, merge_vertices=True)
    armature = bpy.data.objects["Armature"]
    body = bpy.data.objects["Mesh_0"]
    for obj in list(bpy.data.objects):
        if obj not in (armature, body):
            bpy.data.objects.remove(obj, do_unlink=True)
    body.name, armature.name = "Player_Mesh", "Player_Armature"
    mesh = body.data
    if any(abs(a - b) > 1e-4 for row_a, row_b in zip(body.matrix_world, Matrix.Identity(4)) for a, b in zip(row_a, row_b)):
        raise RuntimeError(f"Body is not at identity; bands below assume rest-pose metres:\n{body.matrix_world}")
    mat = body.material_slots[0].material
    images = {n.image.name: n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
    base_image = next(img for name, img in images.items() if "Diffuse" in name)
    normal_image = next(img for name, img in images.items() if "Normal" in name)

    base_top = max(v.co.z for v in mesh.vertices)
    photo, photo_mask, _ = mask_photo(FRONT_PHOTO)
    head = load_facebuilder_head(base_top)
    player_skin = facebuilder_skin(head)
    head_image = next(n.image for n in head.material_slots[0].material.node_tree.nodes if n.type == "TEX_IMAGE")
    project_front(mesh)
    mesh.uv_layers["UVMap"].active = True
    mesh.uv_layers["UVMap"].active_render = True

    # Colour references: the brightness of the base hands and clothes, which the recolour keeps as shading.
    base_px = image_pixels(base_image)
    hands = vertices_in(mesh, lambda c: abs(c.x) > HAND_X[1])
    torso = vertices_in(mesh, lambda c: 1.1 < c.z < 1.3 and c.y < -0.05 and abs(c.x) < 0.15)
    legs = vertices_in(mesh, lambda c: 0.4 < c.z < 0.8 and c.y < 0.0)
    luminance = lambda rgb: float(np.dot(rgb, (0.2126, 0.7152, 0.0722)))
    hand_lum = luminance(sample(base_px, uvs_of(mesh, hands)))
    top_lum = luminance(sample(base_px, uvs_of(mesh, torso)))
    trouser_lum = luminance(sample(base_px, uvs_of(mesh, legs)))
    del base_px
    print(f"STAT samples hands={len(hands)} torso={len(torso)} legs={len(legs)}")
    print(f"STAT skin player={np.round(player_skin, 3)} hand_lum={hand_lum:.3f} "
          f"top_lum={top_lum:.3f} trouser_lum={trouser_lum:.3f}")

    diffuse = bpy.data.images.new("player_character_diffuse", TEXTURE_SIZE, TEXTURE_SIZE)
    # Shaded like the FaceBuilder neck, so hands, neck and the cap inside the collar are one skin tone.
    bake_material(mat, base_image, photo, photo_mask, player_skin * FB_NECK_SHADE, hand_lum, top_lum, trouser_lum,
                  diffuse, use_photo=False)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.margin = 8
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type="EMIT")
    diffuse.pack()
    normal_image.scale(TEXTURE_SIZE, TEXTURE_SIZE)
    normal_image.pack()
    final_material(mat, diffuse, normal_image)
    for image in list(bpy.data.images):
        if image not in (diffuse, normal_image, head_image):
            bpy.data.images.remove(image)

    shell_faces, shell_tris = add_hair_shell(head)
    hair = hair_cards.build(head, shell_tris, HEAD_EYES.y, FB_HAIR_CARDS)
    hair.data.materials.append(hair_cards.make_material(hair_cards.make_texture()))
    # Weights come from the intact base head, so the new head follows CC_Base_Head and the neck bones.
    skin_head(head, body)
    removed = remove_base_head(body, head, diffuse, player_skin * FB_NECK_SHADE)
    head_material(head, bake_head_skin(head, player_skin * FB_NECK_SHADE))
    mesh = decimate(body, TRI_BUDGET - FB_HEAD_TRIS - FB_HAIR_CARD_TRIS)
    mesh.uv_layers.remove(mesh.uv_layers["proj_front"])
    decimate_head(head, FB_HEAD_TRIS)
    print(f"STAT facebuilder head: base vertices removed={removed} hair shell faces={shell_faces} "
          f"hair cards={FB_HAIR_CARDS} ({len(hair.data.polygons) * 2} tris) "
          f"head tris={sum(len(p.vertices) - 2 for p in head.data.polygons)}")
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    hair.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    mesh = body.data
    # Scale by the base model's height, not the new top (hair volume must not shrink the body).
    scale_rig(armature, body, TARGET_HEIGHT / base_top)
    build_actions(armature)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = armature
    # JPEG export keeps images that need alpha (the hair strands) as PNG.
    bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_image_format="JPEG", export_jpeg_quality=88,
                              export_cameras=False, export_lights=False)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print(f"STAT player_character tris={tris} top={max(v.co.z for v in mesh.vertices):.3f} "
          f"bones={len(armature.data.bones)} size={os.path.getsize(OUTPUT) / 1e6:.1f}MB")


main()
