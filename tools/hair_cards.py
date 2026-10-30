"""Hair cards for the player's FaceBuilder head.

Grows a few hundred textured strips ("cards") from the hair shell over the scalp, styled after the
player's photos: a swept-up, full front and crown, shorter sides and back. Each card is a ribbon that
follows a short strand path, lies roughly along the scalp, and carries a generated alpha-masked strand
texture, so from any angle the head reads as hair with volume rather than a painted cap.

Used by tools/build_user_character.py.
"""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

TEXTURE_SIZE = (512, 1024)  # width (across the card), height (along the strands)
# Linear colours of the player's hair: near-black roots, a little brown-grey in the highlights.
HAIR_ROOT = (0.006, 0.005, 0.005)
HAIR_TIP = (0.022, 0.019, 0.017)
SEGMENTS = 4
SEED = 7


def make_texture(name="player_hair"):
    """Strand clumps with alpha: opaque, wavy dark strands on a transparent background, thinning at
    the tips. Several clumps sit side by side so each card can use a different one."""
    rng = np.random.default_rng(SEED)
    w, h = TEXTURE_SIZE
    v = np.linspace(0.0, 1.0, h)[:, None]           # 0 at the root, 1 at the tip
    u = np.arange(w)[None, :].astype(np.float32)
    alpha = np.zeros((h, w), np.float32)
    shade = np.zeros((h, w), np.float32)
    for _ in range(260):
        x0 = rng.uniform(0, w)
        amp = rng.uniform(2.0, 9.0)
        freq = rng.uniform(1.5, 4.0)
        phase = rng.uniform(0, 2 * math.pi)
        width = rng.uniform(1.2, 3.2)
        length = rng.uniform(0.65, 1.0)
        x = x0 + amp * np.sin(freq * 2 * math.pi * v + phase) + rng.uniform(-6, 6) * v
        d = np.abs(((u - x) + w / 2) % w - w / 2)    # wraps across the texture edge
        strand = np.clip(1.0 - d / width, 0.0, 1.0)
        strand *= np.clip((length - v) / 0.12, 0.0, 1.0)  # each strand ends at its own length
        alpha = np.maximum(alpha, strand)
        shade = np.maximum(shade, strand * rng.uniform(0.3, 1.0))
    root = np.array(HAIR_ROOT, np.float32)
    tip = np.array(HAIR_TIP, np.float32)
    colour = root + (tip - root) * (0.35 * v + 0.65 * shade)[:, :, None]
    # Image rows run bottom-up in Blender: row 0 is v = 0 (the root end of the card).
    rgba = np.concatenate([colour, alpha[:, :, None]], axis=2).astype(np.float32)
    image = bpy.data.images.new(name, w, h, alpha=True)
    image.colorspace_settings.name = "sRGB"
    srgb = np.where(rgba[:, :, :3] <= 0.0031308, rgba[:, :, :3] * 12.92,
                    1.055 * np.power(rgba[:, :, :3], 1 / 2.4) - 0.055)
    out = np.concatenate([srgb, rgba[:, :, 3:]], axis=2)
    image.pixels.foreach_set(out.ravel())
    image.file_format = "PNG"
    image.pack()
    return image


def make_material(image):
    mat = bpy.data.materials.new("player_hair")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.7
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # Round on the alpha is what the glTF exporter writes as alphaMode MASK (cutoff 0.5).
    clip = nt.nodes.new("ShaderNodeMath")
    clip.operation = "ROUND"
    nt.links.new(tex.outputs["Alpha"], clip.inputs[0])
    nt.links.new(clip.outputs[0], bsdf.inputs["Alpha"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.use_backface_culling = False
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "DITHERED"
    else:
        mat.blend_method = "CLIP"
    return mat


def _sample_roots(tris, count, rng):
    """Random points on triangles [(a, b, c, normal), ...], weighted by area and, twice over, by how
    much the surface faces up (the crown carries most of the player's hair) and forward."""
    # The forehead hairline (shell facing forward) gets extra roots so no smooth shell edge shows there.
    areas = np.array([((b - a).cross(c - a)).length * 0.5 * (0.5 + 1.5 * max(0.0, n.z) + 2.5 * max(0.0, -n.y - 0.3))
                      for a, b, c, n in tris])
    picks = rng.choice(len(tris), size=count, p=areas / areas.sum())
    roots = []
    for i in picks:
        a, b, c, n = tris[i]
        r1, r2 = rng.random(), rng.random()
        if r1 + r2 > 1.0:
            r1, r2 = 1.0 - r1, 1.0 - r2
        roots.append((a + (b - a) * r1 + (c - a) * r2, n.copy()))
    return roots


def _style(p, n, centre, eyes_z):
    """Strand length, lift off the scalp and flow direction at a root, after the player's photos."""
    up = max(0.0, min(1.0, (n.z - 0.1) / 0.8))             # 0 on the sides, 1 on the crown
    front = max(0.0, min(1.0, (centre.y - p.y) / 0.08))     # 1 at the forehead, 0 behind the crown
    back = max(0.0, min(1.0, (p.y - centre.y) / 0.07))
    length = 0.03 + 0.04 * up + 0.02 * front * up - 0.008 * back
    lift = 0.004 + 0.022 * up * (0.4 + 0.6 * front)
    # Front and crown sweep up and back (the pompadour); sides and back fall down and back.
    flow = Vector((0.0, 0.55, 0.25)) * up + Vector((0.0, 0.35, -0.8)) * (1.0 - up)
    if front > 0.5:
        # The fringe is brushed up and back off the forehead, never down over it.
        flow = Vector((0.0, 0.35, 0.75))
    return length, lift, flow.normalized()


# Strands stay between `lift` and `lift + LOOSE` off the scalp, which rounds the silhouette instead of
# letting them stick out like spikes; WAVE is the sideways curl of the player's wavy hair.
LOOSE = 0.012
WAVE = 0.35


def build(head, hair_tris, eyes_z, count, rng_seed=SEED):
    """Hair-card object over hair_tris (world-space shell triangles with normals). The cards are
    weighted fully to CC_Base_Head so they turn with the head."""
    rng = np.random.default_rng(rng_seed)
    random.seed(rng_seed)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    head_bvh = BVHTree.FromObject(head, depsgraph)
    verts = [v.co for v in head.data.vertices]
    centre = sum(verts, Vector()) / len(verts)
    roots = _sample_roots(hair_tris, count, rng)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    clumps = 4
    for root, normal in roots:
        length, lift, flow = _style(root, normal, centre, eyes_z)
        length *= rng.uniform(0.8, 1.2)
        width = rng.uniform(0.012, 0.022)
        # Strand path: leave the scalp along the normal, bend into the flow, stay `lift` off the head.
        points = [root - normal * 0.004]
        direction = (normal * 0.45 + flow).normalized()
        curl_axis = flow.cross(normal)
        if curl_axis.length < 1e-6:
            curl_axis = normal.orthogonal()
        curl_axis.normalize()
        phase = rng.uniform(0, 2 * math.pi)
        step = length / SEGMENTS
        for s in range(1, SEGMENTS + 1):
            t = s / SEGMENTS
            direction = (direction * 0.6 + flow * 0.4).normalized()
            curl = curl_axis * (WAVE * math.sin(phase + t * 2.5 * math.pi))
            wobble = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.08
            nxt = points[-1] + (direction + curl + wobble).normalized() * step
            loc, n_surf, _, dist = head_bvh.find_nearest(nxt)
            if loc is not None:
                want = lift * min(1.0, t * 2.0)
                outside = (nxt - loc).dot(n_surf) > 0.0
                if not outside or dist < want:
                    nxt = loc + n_surf * want
                elif dist > want + LOOSE:
                    nxt = loc + n_surf * (want + LOOSE)
            points.append(nxt)
        # Ribbon across the strand, lying along the scalp (width perpendicular to path and normal).
        clump = int(rng.integers(clumps))
        u0, u1 = clump / clumps, (clump + 1) / clumps
        ring = []
        for i, p in enumerate(points):
            t = i / SEGMENTS
            tangent = (points[min(i + 1, SEGMENTS)] - points[max(i - 1, 0)]).normalized()
            loc, n_surf, _, _ = head_bvh.find_nearest(p)
            side = tangent.cross(n_surf if loc is not None else normal)
            if side.length < 1e-6:
                side = tangent.orthogonal()
            side.normalize()
            half = width * 0.5 * (1.0 - 0.6 * t)
            ring.append((bm.verts.new(p - side * half), bm.verts.new(p + side * half), t))
        for (a0, b0, t0), (a1, b1, t1) in zip(ring, ring[1:]):
            face = bm.faces.new((a0, b0, b1, a1))
            for loop, (u, v) in zip(face.loops, ((u0, t0), (u1, t0), (u1, t1), (u0, t1))):
                loop[uv_layer].uv = (u, v)
    mesh = bpy.data.meshes.new("player_hair")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Player_Hair", mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = obj.vertex_groups.new(name="CC_Base_Head")
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    return obj
