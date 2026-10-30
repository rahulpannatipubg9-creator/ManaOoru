#!/usr/bin/env python3
"""
Godavarikhani Godavari River Bridge 3D Recreation Script
Procedural Modeling, PBR Materials, Multi-Camera Setup, and GLB Export for Blender 5.x / 4.x

Visual Target: Godavarikhani Godavari River Bridge (Telangana, India)
- Full 1,100 m Real-World Scale (1 unit = 1 meter)
- Twin Parallel Carriageways with Open Central Separation (3.0 m gap)
- 4 Prestressed Concrete I-Girders per Carriageway + Diaphragms
- Repeating Twin-Shaft Piers with Cantilever Hammerhead Caps & Cross-Struts
- Stepped Foundation Footings resting in Riverbed
- Cambered Asphalt Deck with Crisp Lane & Edge Markings, Expansion Joints
- Concrete Parapets with Galvanized Steel Safety Railings
- Curved Mast Streetlights with Warm LED Luminaires
- Realistic Godavari River Valley: Water Surface, Sandbars, Granitic Boulders, Banks, Vegetation
- 8 Named Technical & Cinematic Cameras matching prompt specifications
- Simplified Collision Meshes for Game Physics
"""

import sys
import os
import json
import math
import random
import bpy
import bmesh
from mathutils import Vector, Euler, Matrix

# ---------------------------------------------------------------------------
# Collection Helpers
# ---------------------------------------------------------------------------

def get_or_create_collection(name, parent_collection=None):
    if name in bpy.data.collections:
        col = bpy.data.collections[name]
    else:
        col = bpy.data.collections.new(name)
        if parent_collection is None:
            bpy.context.scene.collection.children.link(col)
        else:
            parent_collection.children.link(col)
    return col

def link_object_to_collection(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)

# ---------------------------------------------------------------------------
# PBR Material Generators
# ---------------------------------------------------------------------------

def create_pbr_material(name, base_color=(0.8, 0.8, 0.8, 1.0), roughness=0.5, metallic=0.0,
                        transmission=0.0, ior=1.45, emission_color=(0,0,0,1), emission_strength=0.0,
                        noise_bump=None):
    if name in bpy.data.materials:
        return bpy.data.materials[name]

    mat = bpy.data.materials.new(name=name)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type='ShaderNodeOutputMaterial')
    out_node.location = (400, 0)

    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (100, 0)
    links.new(bsdf.outputs['BSDF'], out_node.inputs['Surface'])

    if 'Base Color' in bsdf.inputs:
        bsdf.inputs['Base Color'].default_value = base_color
    if 'Roughness' in bsdf.inputs:
        bsdf.inputs['Roughness'].default_value = roughness
    if 'Metallic' in bsdf.inputs:
        bsdf.inputs['Metallic'].default_value = metallic
    if 'IOR' in bsdf.inputs:
        bsdf.inputs['IOR'].default_value = ior
    if 'Transmission Weight' in bsdf.inputs and transmission > 0:
        bsdf.inputs['Transmission Weight'].default_value = transmission
    elif 'Transmission' in bsdf.inputs and transmission > 0:
        bsdf.inputs['Transmission'].default_value = transmission

    if emission_strength > 0:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission_color
        elif 'Emission' in bsdf.inputs:
            bsdf.inputs['Emission'].default_value = emission_color
        if 'Emission Strength' in bsdf.inputs:
            bsdf.inputs['Emission Strength'].default_value = emission_strength

    if noise_bump:
        tc = nodes.new(type='ShaderNodeTexCoord')
        tc.location = (-750, 0)
        mapping = nodes.new(type='ShaderNodeMapping')
        mapping.location = (-560, 0)
        mapping.inputs['Scale'].default_value = (noise_bump.get('scale_x', 1.0),
                                                noise_bump.get('scale_y', 1.0),
                                                noise_bump.get('scale_z', 1.0))
        links.new(tc.outputs['Object'], mapping.inputs['Vector'])

        tex_noise = nodes.new(type='ShaderNodeTexNoise')
        tex_noise.location = (-340, 0)
        tex_noise.inputs['Scale'].default_value = noise_bump.get('scale', 10.0)
        tex_noise.inputs['Detail'].default_value = noise_bump.get('detail', 4.0)
        tex_noise.inputs['Roughness'].default_value = noise_bump.get('roughness', 0.6)
        links.new(mapping.outputs['Vector'], tex_noise.inputs['Vector'])

        bump = nodes.new(type='ShaderNodeBump')
        bump.location = (-100, -150)
        bump.inputs['Strength'].default_value = noise_bump.get('strength', 0.15)
        bump.inputs['Distance'].default_value = noise_bump.get('distance', 0.05)
        links.new(tex_noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])

    return mat

def build_all_materials():
    materials = {}

    materials['Concrete_Deck'] = create_pbr_material(
        'Concrete_Deck',
        base_color=(0.62, 0.61, 0.58, 1.0),
        roughness=0.76,
        metallic=0.0,
        noise_bump={'scale': 6.0, 'scale_x': 0.5, 'scale_y': 2.0, 'scale_z': 1.0,
                    'detail': 4.0, 'roughness': 0.7, 'strength': 0.14,
                    'use_as_color_mix': True, 'mix_color': (0.46, 0.45, 0.42, 1.0), 'mix_factor': 0.4}
    )

    materials['Concrete_Pier'] = create_pbr_material(
        'Concrete_Pier',
        base_color=(0.58, 0.57, 0.54, 1.0),
        roughness=0.82,
        metallic=0.0,
        noise_bump={'scale': 5.0, 'scale_x': 1.0, 'scale_y': 1.0, 'scale_z': 0.25,
                    'detail': 5.0, 'roughness': 0.8, 'strength': 0.20,
                    'use_as_color_mix': True, 'mix_color': (0.38, 0.37, 0.34, 1.0), 'mix_factor': 0.45}
    )

    materials['Concrete_Footing'] = create_pbr_material(
        'Concrete_Footing',
        base_color=(0.46, 0.45, 0.40, 1.0),
        roughness=0.90,
        metallic=0.0,
        noise_bump={'scale': 10.0, 'strength': 0.28, 'detail': 5.0,
                    'use_as_color_mix': True, 'mix_color': (0.30, 0.32, 0.26, 1.0), 'mix_factor': 0.5}
    )

    materials['Road_Asphalt'] = create_pbr_material(
        'Road_Asphalt',
        base_color=(0.09, 0.09, 0.10, 1.0),
        roughness=0.88,
        metallic=0.02,
        noise_bump={'scale': 40.0, 'scale_x': 2.0, 'scale_y': 1.0, 'scale_z': 1.0,
                    'detail': 6.0, 'roughness': 0.85, 'strength': 0.22,
                    'use_as_color_mix': True, 'mix_color': (0.05, 0.05, 0.06, 1.0), 'mix_factor': 0.4}
    )

    materials['Road_Marking_White'] = create_pbr_material(
        'Road_Marking_White',
        base_color=(0.94, 0.94, 0.92, 1.0),
        roughness=0.40,
        metallic=0.0
    )

    materials['Road_Marking_Yellow'] = create_pbr_material(
        'Road_Marking_Yellow',
        base_color=(0.95, 0.72, 0.05, 1.0),
        roughness=0.42,
        metallic=0.0
    )

    materials['Steel_Galvanized'] = create_pbr_material(
        'Steel_Galvanized',
        base_color=(0.76, 0.76, 0.77, 1.0),
        roughness=0.28,
        metallic=0.96,
        noise_bump={'scale': 25.0, 'strength': 0.04}
    )

    materials['Streetlight_Paint'] = create_pbr_material(
        'Streetlight_Paint',
        base_color=(0.22, 0.24, 0.26, 1.0),
        roughness=0.38,
        metallic=0.85
    )

    materials['Streetlight_LED'] = create_pbr_material(
        'Streetlight_LED',
        base_color=(1.0, 0.98, 0.92, 1.0),
        roughness=0.1,
        emission_color=(1.0, 0.95, 0.88, 1.0),
        emission_strength=15.0
    )

    materials['Neoprene_Bearing'] = create_pbr_material(
        'Neoprene_Bearing',
        base_color=(0.10, 0.10, 0.10, 1.0),
        roughness=0.85,
        metallic=0.0
    )

    materials['River_Water'] = create_pbr_material(
        'River_Water',
        base_color=(0.03, 0.15, 0.17, 1.0),
        roughness=0.06,
        metallic=0.04,
        transmission=0.88,
        ior=1.333,
        noise_bump={'scale': 12.0, 'scale_x': 0.4, 'scale_y': 2.5, 'scale_z': 1.0,
                    'detail': 5.0, 'roughness': 0.45, 'strength': 0.08}
    )

    materials['River_Sand'] = create_pbr_material(
        'River_Sand',
        base_color=(0.69, 0.55, 0.38, 1.0),
        roughness=0.92,
        metallic=0.0,
        noise_bump={'scale': 16.0, 'detail': 5.0, 'roughness': 0.8, 'strength': 0.25,
                    'use_as_color_mix': True, 'mix_color': (0.50, 0.39, 0.26, 1.0), 'mix_factor': 0.5}
    )

    materials['River_Rock'] = create_pbr_material(
        'River_Rock',
        base_color=(0.40, 0.30, 0.24, 1.0),
        roughness=0.80,
        metallic=0.0,
        noise_bump={'scale': 7.0, 'detail': 6.0, 'roughness': 0.85, 'strength': 0.40,
                    'use_as_color_mix': True, 'mix_color': (0.24, 0.19, 0.16, 1.0), 'mix_factor': 0.55}
    )

    materials['Foliage_Green'] = create_pbr_material(
        'Foliage_Green',
        base_color=(0.13, 0.27, 0.09, 1.0),
        roughness=0.62,
        metallic=0.0,
        noise_bump={'scale': 10.0, 'strength': 0.16,
                    'use_as_color_mix': True, 'mix_color': (0.20, 0.34, 0.11, 1.0), 'mix_factor': 0.4}
    )

    return materials

# ---------------------------------------------------------------------------
# Procedural Mesh Builders: Substructure (Pillars, Caps, Footings)
# ---------------------------------------------------------------------------

def build_chamfered_column_mesh(name, width_x, width_y, height_z, chamfer=0.35):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()

    hx = width_x / 2.0
    hy = width_y / 2.0
    c = min(chamfer, hx * 0.4, hy * 0.4)

    verts_2d = [
        (hx - c, hy),
        (-hx + c, hy),
        (-hx, hy - c),
        (-hx, -hy + c),
        (-hx + c, -hy),
        (hx - c, -hy),
        (hx, -hy + c),
        (hx, hy - c),
    ]

    bot_verts = [bm.verts.new((x, y, 0.0)) for x, y in verts_2d]
    top_verts = [bm.verts.new((x, y, height_z)) for x, y in verts_2d]

    bm.faces.new(bot_verts[::-1])
    bm.faces.new(top_verts)

    n = len(verts_2d)
    for i in range(n):
        i_next = (i + 1) % n
        bm.faces.new([bot_verts[i], bot_verts[i_next], top_verts[i_next], top_verts[i]])

    for f in bm.faces:
        f.smooth = True

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    return mesh

def build_pier_cap_mesh(name, length_x, width_y, height_z, bottom_width_ratio=0.55):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()

    hx_top = length_x / 2.0
    hy_top = width_y / 2.0
    hx_bot = length_x / 2.0
    hy_bot = (width_y * bottom_width_ratio) / 2.0

    b0 = bm.verts.new((hx_bot, hy_bot, 0.0))
    b1 = bm.verts.new((-hx_bot, hy_bot, 0.0))
    b2 = bm.verts.new((-hx_bot, -hy_bot, 0.0))
    b3 = bm.verts.new((hx_bot, -hy_bot, 0.0))

    t0 = bm.verts.new((hx_top, hy_top, height_z))
    t1 = bm.verts.new((-hx_top, hy_top, height_z))
    t2 = bm.verts.new((-hx_top, -hy_top, height_z))
    t3 = bm.verts.new((hx_top, -hy_top, height_z))

    bm.faces.new([b3, b2, b1, b0])
    bm.faces.new([t0, t1, t2, t3])
    bm.faces.new([b0, b1, t1, t0])
    bm.faces.new([b1, b2, t2, t1])
    bm.faces.new([b2, b3, t3, t2])
    bm.faces.new([b3, b0, t0, t3])

    for f in bm.faces:
        f.smooth = True

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    return mesh

def build_pier_bent(bent_index, x_pos, config, materials, col_pillars):
    sub = config['substructure']
    br = config['bridge']
    sup = config['superstructure']

    z_water = config['environment']['water_level']
    footing_base_z = z_water + sub['footing_depth_below_water']
    footing_top_z = footing_base_z + sub['footing_height']
    shaft_bot_z = footing_top_z
    cap_bot_z = br['deck_height_above_water'] - sup['girder_height'] - sup['bearing_height'] - sub['pier_cap_height']
    shaft_height = cap_bot_z - shaft_bot_z
    cap_top_z = cap_bot_z + sub['pier_cap_height']

    half_gap = br['central_gap'] / 2.0
    half_carriageway = br['carriageway_width'] / 2.0
    y_north = half_gap + half_carriageway
    y_south = - (half_gap + half_carriageway)

    shaft_mesh = bpy.data.meshes.get('Mesh_Pier_Shaft')
    if not shaft_mesh:
        shaft_mesh = build_chamfered_column_mesh('Mesh_Pier_Shaft', sub['pier_shaft_width_x'],
                                                sub['pier_shaft_width_y'], shaft_height, chamfer=0.35)
        shaft_mesh.materials.append(materials['Concrete_Pier'])

    cap_mesh = bpy.data.meshes.get('Mesh_Pier_Cap')
    if not cap_mesh:
        cap_mesh = build_pier_cap_mesh('Mesh_Pier_Cap', sub['pier_cap_length_x'],
                                       sub['pier_cap_width_y'], sub['pier_cap_height'], bottom_width_ratio=0.55)
        cap_mesh.materials.append(materials['Concrete_Deck'])

    footing_mesh = bpy.data.meshes.get('Mesh_Pier_Footing')
    if not footing_mesh:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sub['footing_width_x'], sub['footing_width_y'], sub['footing_height']), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(0, 0, sub['footing_height']/2.0), verts=bm.verts)
        footing_mesh = bpy.data.meshes.new('Mesh_Pier_Footing')
        bm.to_mesh(footing_mesh)
        bm.free()
        footing_mesh.materials.append(materials['Concrete_Footing'])

    bearing_mesh = bpy.data.meshes.get('Mesh_Bearing_Pad')
    if not bearing_mesh:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(0.65, 0.65, sup['bearing_height']), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(0, 0, sup['bearing_height']/2.0), verts=bm.verts)
        bearing_mesh = bpy.data.meshes.new('Mesh_Bearing_Pad')
        bm.to_mesh(bearing_mesh)
        bm.free()
        bearing_mesh.materials.append(materials['Neoprene_Bearing'])

    for y_center, side_name in [(y_north, 'North'), (y_south, 'South')]:
        footing_obj = bpy.data.objects.new(f"Footing_{bent_index:02d}_{side_name}", footing_mesh)
        footing_obj.location = (x_pos, y_center, footing_base_z)
        link_object_to_collection(footing_obj, col_pillars)

        shaft_obj = bpy.data.objects.new(f"PierShaft_{bent_index:02d}_{side_name}", shaft_mesh)
        shaft_obj.location = (x_pos, y_center, shaft_bot_z)
        link_object_to_collection(shaft_obj, col_pillars)

        cap_obj = bpy.data.objects.new(f"PierCap_{bent_index:02d}_{side_name}", cap_mesh)
        cap_obj.location = (x_pos, y_center, cap_bot_z)
        link_object_to_collection(cap_obj, col_pillars)

        girder_spacing = (br['carriageway_width'] - 2.0) / (sup['girders_per_carriageway'] - 1)
        y_start = y_center - (br['carriageway_width'] - 2.0) / 2.0
        for g_idx in range(sup['girders_per_carriageway']):
            g_y = y_start + g_idx * girder_spacing
            bearing_obj = bpy.data.objects.new(f"Bearing_{bent_index:02d}_{side_name}_{g_idx}", bearing_mesh)
            bearing_obj.location = (x_pos, g_y, cap_top_z)
            link_object_to_collection(bearing_obj, col_pillars)

    strut_mesh = bpy.data.meshes.get('Mesh_Tie_Strut')
    if not strut_mesh:
        strut_len_y = 2.0 * half_gap + 1.2
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sub['tie_beam_width_x'], strut_len_y, sub['tie_beam_height']), verts=bm.verts)
        strut_mesh = bpy.data.meshes.new('Mesh_Tie_Strut')
        bm.to_mesh(strut_mesh)
        bm.free()
        strut_mesh.materials.append(materials['Concrete_Deck'])

    strut_z = cap_bot_z + sub['pier_cap_height'] * 0.4
    strut_obj = bpy.data.objects.new(f"TieStrut_{bent_index:02d}", strut_mesh)
    strut_obj.location = (x_pos, 0.0, strut_z)
    link_object_to_collection(strut_obj, col_pillars)

# ---------------------------------------------------------------------------
# Procedural Mesh Builders: Superstructure (Girders, Diaphragms, Deck, Road)
# ---------------------------------------------------------------------------

def build_i_girder_mesh(name, length_x, height_z, top_w, bot_w, web_w, top_flange_h=0.25, bot_flange_h=0.3):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hx = length_x / 2.0

    p_bot_l = -bot_w / 2.0
    p_bot_r =  bot_w / 2.0
    p_web_l = -web_w / 2.0
    p_web_r =  web_w / 2.0
    p_top_l = -top_w / 2.0
    p_top_r =  top_w / 2.0

    z0 = 0.0
    z1 = bot_flange_h
    z2 = height_z - top_flange_h
    z3 = height_z

    poly_yz = [
        (p_bot_r, z0),
        (p_bot_r, z1 * 0.7),
        (p_web_r, z1),
        (p_web_r, z2),
        (p_top_r, z2 + top_flange_h * 0.3),
        (p_top_r, z3),
        (p_top_l, z3),
        (p_top_l, z2 + top_flange_h * 0.3),
        (p_web_l, z2),
        (p_web_l, z1),
        (p_bot_l, z1 * 0.7),
        (p_bot_l, z0),
    ]

    front_verts = [bm.verts.new((hx, y, z)) for y, z in poly_yz]
    back_verts  = [bm.verts.new((-hx, y, z)) for y, z in poly_yz]

    bm.faces.new(front_verts)
    bm.faces.new(back_verts[::-1])

    n = len(poly_yz)
    for i in range(n):
        i_next = (i + 1) % n
        bm.faces.new([front_verts[i], front_verts[i_next], back_verts[i_next], back_verts[i]])

    for f in bm.faces:
        f.smooth = True

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    return mesh

def build_bridge_span(span_idx, x_start, x_end, config, materials, collections):
    br = config['bridge']
    sup = config['superstructure']

    span_len = x_end - x_start
    x_mid = (x_start + x_end) / 2.0

    g_len = span_len - sup['expansion_joint_gap']
    g_height = sup['girder_height']
    z_bearing_top = br['deck_height_above_water'] - g_height
    z_deck_bot = z_bearing_top + g_height
    z_deck_top = z_deck_bot + br['deck_thickness']
    z_asphalt_top = z_deck_top + br['asphalt_thickness']

    mesh_girder_key = f"Mesh_IGirder_{round(g_len, 2)}"
    girder_mesh = bpy.data.meshes.get(mesh_girder_key)
    if not girder_mesh:
        girder_mesh = build_i_girder_mesh(mesh_girder_key, g_len, g_height,
                                          sup['girder_top_flange_width'],
                                          sup['girder_bottom_flange_width'],
                                          sup['girder_web_thickness'])
        girder_mesh.materials.append(materials['Concrete_Deck'])

    girder_spacing = (br['carriageway_width'] - 2.0) / (sup['girders_per_carriageway'] - 1)
    diaphragm_len = girder_spacing - sup['girder_web_thickness']
    mesh_diaphragm = bpy.data.meshes.get('Mesh_Diaphragm')
    if not mesh_diaphragm:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(0.3, diaphragm_len, g_height * 0.7), verts=bm.verts)
        mesh_diaphragm = bpy.data.meshes.new('Mesh_Diaphragm')
        bm.to_mesh(mesh_diaphragm)
        bm.free()
        mesh_diaphragm.materials.append(materials['Concrete_Deck'])

    half_gap = br['central_gap'] / 2.0
    half_carriageway = br['carriageway_width'] / 2.0
    y_north = half_gap + half_carriageway
    y_south = - (half_gap + half_carriageway)

    # 1. Girders & Diaphragms
    for y_center, side_name in [(y_north, 'North'), (y_south, 'South')]:
        y_start_g = y_center - (br['carriageway_width'] - 2.0) / 2.0
        girder_y_coords = []
        for g_idx in range(sup['girders_per_carriageway']):
            g_y = y_start_g + g_idx * girder_spacing
            girder_y_coords.append(g_y)
            g_obj = bpy.data.objects.new(f"Girder_{span_idx:02d}_{side_name}_{g_idx}", girder_mesh)
            g_obj.location = (x_mid, g_y, z_bearing_top)
            link_object_to_collection(g_obj, collections['Bridge_Girders'])

        for x_diaph in [x_start + 1.2, x_mid, x_end - 1.2]:
            for d_idx in range(sup['girders_per_carriageway'] - 1):
                d_y = (girder_y_coords[d_idx] + girder_y_coords[d_idx + 1]) / 2.0
                d_obj = bpy.data.objects.new(f"Diaph_{span_idx:02d}_{side_name}_{d_idx}_{round(x_diaph)}", mesh_diaphragm)
                d_obj.location = (x_diaph, d_y, z_bearing_top + g_height * 0.45)
                link_object_to_collection(d_obj, collections['Bridge_Girders'])

    # 2. Deck Slabs
    mesh_deck = bpy.data.meshes.get(f"Mesh_DeckSlab_{round(span_len, 2)}")
    if not mesh_deck:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(span_len - sup['expansion_joint_gap'], br['carriageway_width'], br['deck_thickness']), verts=bm.verts)
        mesh_deck = bpy.data.meshes.new(f"Mesh_DeckSlab_{round(span_len, 2)}")
        bm.to_mesh(mesh_deck)
        bm.free()
        mesh_deck.materials.append(materials['Concrete_Deck'])

    # 3. Asphalt Wearing Course
    mesh_asphalt = bpy.data.meshes.get(f"Mesh_Asphalt_{round(span_len, 2)}")
    if not mesh_asphalt:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(span_len - sup['expansion_joint_gap'], br['carriageway_width'], br['asphalt_thickness']), verts=bm.verts)
        mesh_asphalt = bpy.data.meshes.new(f"Mesh_Asphalt_{round(span_len, 2)}")
        bm.to_mesh(mesh_asphalt)
        bm.free()
        mesh_asphalt.materials.append(materials['Road_Asphalt'])

    for y_center, side_name in [(y_north, 'North'), (y_south, 'South')]:
        deck_obj = bpy.data.objects.new(f"DeckSlab_{span_idx:02d}_{side_name}", mesh_deck)
        deck_obj.location = (x_mid, y_center, z_deck_bot + br['deck_thickness'] / 2.0)
        link_object_to_collection(deck_obj, collections['Bridge_Decks'])

        asphalt_obj = bpy.data.objects.new(f"Asphalt_{span_idx:02d}_{side_name}", mesh_asphalt)
        asphalt_obj.location = (x_mid, y_center, z_deck_top + br['asphalt_thickness'] / 2.0)
        link_object_to_collection(asphalt_obj, collections['Road_Asphalt'])

    # 4. Expansion Joint Cover
    mesh_joint = bpy.data.meshes.get('Mesh_ExpansionJoint')
    if not mesh_joint:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sup['expansion_joint_gap'] * 1.4, br['carriageway_width'] * 2.0 + br['central_gap'], 0.015), verts=bm.verts)
        mesh_joint = bpy.data.meshes.new('Mesh_ExpansionJoint')
        bm.to_mesh(mesh_joint)
        bm.free()
        mesh_joint.materials.append(materials['Steel_Galvanized'])

    joint_obj = bpy.data.objects.new(f"ExpJoint_{span_idx:02d}", mesh_joint)
    joint_obj.location = (x_end, 0.0, z_asphalt_top + 0.005)
    link_object_to_collection(joint_obj, collections['Road_Markings'])

# ---------------------------------------------------------------------------
# Road Markings
# ---------------------------------------------------------------------------

def build_road_markings(config, materials, col_markings):
    br = config['bridge']
    half_gap = br['central_gap'] / 2.0
    cw = br['carriageway_width']
    half_l = br['total_length'] / 2.0

    z_mark = br['deck_height_above_water'] + br['deck_thickness'] + br['asphalt_thickness'] + 0.005

    edge_y_coords = [
        half_gap + 0.35,
        half_gap + cw - 0.35,
        -(half_gap + 0.35),
        -(half_gap + cw - 0.35),
    ]

    mesh_solid_line = bpy.data.meshes.get('Mesh_Solid_EdgeLine')
    if not mesh_solid_line:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(br['total_length'], 0.18, 0.002), verts=bm.verts)
        mesh_solid_line = bpy.data.meshes.new('Mesh_Solid_EdgeLine')
        bm.to_mesh(mesh_solid_line)
        bm.free()
        mesh_solid_line.materials.append(materials['Road_Marking_White'])

    for idx, y_pos in enumerate(edge_y_coords):
        line_obj = bpy.data.objects.new(f"RoadEdgeLine_{idx}", mesh_solid_line)
        line_obj.location = (0.0, y_pos, z_mark)
        link_object_to_collection(line_obj, col_markings)

    y_center_north = half_gap + cw / 2.0
    y_center_south = -(half_gap + cw / 2.0)

    dash_len = 3.0
    space_len = 6.0
    cycle = dash_len + space_len
    num_dashes = int(br['total_length'] / cycle)

    mesh_dash = bpy.data.meshes.get('Mesh_Dash_Line')
    if not mesh_dash:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(dash_len, 0.18, 0.002), verts=bm.verts)
        mesh_dash = bpy.data.meshes.new('Mesh_Dash_Line')
        bm.to_mesh(mesh_dash)
        bm.free()
        mesh_dash.materials.append(materials['Road_Marking_White'])

    start_x = -half_l + cycle / 2.0
    for d_i in range(num_dashes):
        cur_x = start_x + d_i * cycle
        for s_idx, y_c in enumerate([y_center_north, y_center_south]):
            dash_obj = bpy.data.objects.new(f"LaneDash_{d_i:03d}_{s_idx}", mesh_dash)
            dash_obj.location = (cur_x, y_c, z_mark)
            link_object_to_collection(dash_obj, col_markings)

# ---------------------------------------------------------------------------
# Procedural Barriers & Railings
# ---------------------------------------------------------------------------

def build_crash_barriers(config, materials, col_barriers):
    br = config['bridge']
    bar = config['barriers']
    half_gap = br['central_gap'] / 2.0
    cw = br['carriageway_width']
    tot_len = br['total_length']

    z_deck = br['deck_height_above_water'] + br['deck_thickness'] + br['asphalt_thickness']
    barrier_base_h = bar['barrier_base_height']
    rail_h = bar['railing_total_height']

    barrier_y_positions = [
        (half_gap + cw - 0.22, 'Outer_North'),
        (half_gap + 0.22,      'Inner_North'),
        (-(half_gap + 0.22),     'Inner_South'),
        (-(half_gap + cw - 0.22), 'Outer_South'),
    ]

    mesh_barrier_base = bpy.data.meshes.get('Mesh_Barrier_Base')
    if not mesh_barrier_base:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(tot_len, bar['barrier_base_width'], barrier_base_h), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(0, 0, barrier_base_h / 2.0), verts=bm.verts)
        mesh_barrier_base = bpy.data.meshes.new('Mesh_Barrier_Base')
        bm.to_mesh(mesh_barrier_base)
        bm.free()
        mesh_barrier_base.materials.append(materials['Concrete_Deck'])

    mesh_rail_tubes = bpy.data.meshes.get('Mesh_Rail_Tubes')
    if not mesh_rail_tubes:
        bm = bmesh.new()
        pipe_r = bar['railing_pipe_diameter'] / 2.0
        top_cyl = bmesh.ops.create_cone(bm, cap_ends=True, radius1=pipe_r, radius2=pipe_r,
                                        depth=tot_len, segments=8)
        bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90), 4, 'Y'), verts=top_cyl['verts'])
        bmesh.ops.translate(bm, vec=(0, 0, rail_h), verts=top_cyl['verts'])

        mid_cyl = bmesh.ops.create_cone(bm, cap_ends=True, radius1=pipe_r, radius2=pipe_r,
                                        depth=tot_len, segments=8)
        bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90), 4, 'Y'), verts=mid_cyl['verts'])
        bmesh.ops.translate(bm, vec=(0, 0, barrier_base_h + (rail_h - barrier_base_h) * 0.45), verts=mid_cyl['verts'])

        for f in bm.faces:
            f.smooth = True

        mesh_rail_tubes = bpy.data.meshes.new('Mesh_Rail_Tubes')
        bm.to_mesh(mesh_rail_tubes)
        bm.free()
        mesh_rail_tubes.materials.append(materials['Steel_Galvanized'])

    mesh_rail_post = bpy.data.meshes.get('Mesh_Rail_Post')
    if not mesh_rail_post:
        bm = bmesh.new()
        post_h = rail_h - barrier_base_h
        cyl = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(0.06, 0.06, post_h), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(0, 0, barrier_base_h + post_h / 2.0), verts=bm.verts)
        mesh_rail_post = bpy.data.meshes.new('Mesh_Rail_Post')
        bm.to_mesh(mesh_rail_post)
        bm.free()
        mesh_rail_post.materials.append(materials['Steel_Galvanized'])

    for y_pos, name_suffix in barrier_y_positions:
        base_obj = bpy.data.objects.new(f"BarrierBase_{name_suffix}", mesh_barrier_base)
        base_obj.location = (0.0, y_pos, z_deck)
        link_object_to_collection(base_obj, col_barriers)

        rail_obj = bpy.data.objects.new(f"BarrierRails_{name_suffix}", mesh_rail_tubes)
        rail_obj.location = (0.0, y_pos, z_deck)
        link_object_to_collection(rail_obj, col_barriers)

    post_spacing = 5.0
    half_l = tot_len / 2.0
    num_posts = int(tot_len / post_spacing)
    start_x = -half_l + post_spacing / 2.0

    for p_i in range(num_posts):
        px = start_x + p_i * post_spacing
        for y_pos, name_suffix in barrier_y_positions:
            post_obj = bpy.data.objects.new(f"RailPost_{p_i:03d}_{name_suffix}", mesh_rail_post)
            post_obj.location = (px, y_pos, z_deck)
            link_object_to_collection(post_obj, col_barriers)

# ---------------------------------------------------------------------------
# Procedural Streetlights
# ---------------------------------------------------------------------------

def build_streetlight_mesh(pole_h=9.0, arm_reach=2.4):
    mesh_pole = bpy.data.meshes.new("Mesh_Streetlight_Pole")
    bm = bmesh.new()

    vert_h = pole_h - 1.5
    cyl = bmesh.ops.create_cone(bm, cap_ends=True, radius1=0.14, radius2=0.08, depth=vert_h, segments=12)
    bmesh.ops.translate(bm, vec=(0, 0, vert_h / 2.0), verts=cyl['verts'])

    curve_segs = 8
    last_z = vert_h
    last_y = 0.0
    arm_radius = 0.05
    for i in range(curve_segs):
        t = (i + 1) / float(curve_segs)
        ang = t * (math.pi / 2.4)
        cur_y = -math.sin(ang) * arm_reach
        cur_z = vert_h + (1.0 - math.cos(ang)) * 1.5
        seg_len = math.sqrt((cur_y - last_y)**2 + (cur_z - last_z)**2)
        mid_y = (cur_y + last_y) / 2.0
        mid_z = (cur_z + last_z) / 2.0

        arm_cyl = bmesh.ops.create_cone(bm, cap_ends=True, radius1=arm_radius, radius2=arm_radius, depth=seg_len, segments=8)
        pitch = math.atan2(cur_z - last_z, -(cur_y - last_y))
        bmesh.ops.rotate(bm, matrix=Matrix.Rotation(pitch - math.pi/2, 4, 'X'), verts=arm_cyl['verts'])
        bmesh.ops.translate(bm, vec=(0, mid_y, mid_z), verts=arm_cyl['verts'])

        last_y, last_z = cur_y, cur_z

    for f in bm.faces:
        f.smooth = True

    bm.normal_update()
    bm.to_mesh(mesh_pole)
    bm.free()

    mesh_lamp = bpy.data.meshes.new("Mesh_Luminaire_Head")
    bm2 = bmesh.new()
    bmesh.ops.create_cube(bm2, size=1.0)
    bmesh.ops.scale(bm2, vec=(0.28, 0.70, 0.12), verts=bm2.verts)
    bm2.normal_update()
    bm2.to_mesh(mesh_lamp)
    bm2.free()

    return mesh_pole, mesh_lamp, last_y, last_z

def place_streetlights(config, materials, col_lights):
    br = config['bridge']
    sl = config['streetlights']
    half_gap = br['central_gap'] / 2.0
    cw = br['carriageway_width']
    half_l = br['total_length'] / 2.0
    z_deck = br['deck_height_above_water'] + br['deck_thickness'] + br['asphalt_thickness']

    mesh_pole, mesh_lamp, tip_y, tip_z = build_streetlight_mesh(sl['pole_height'], sl['arm_reach'])
    mesh_pole.materials.append(materials['Streetlight_Paint'])
    mesh_lamp.materials.append(materials['Streetlight_LED'])

    spacing = sl['spacing']
    num_lights = int(br['total_length'] / spacing)
    start_x = -half_l + spacing / 2.0

    for i in range(num_lights):
        x = start_x + i * spacing

        y_north = half_gap + cw - 0.20
        pole_n = bpy.data.objects.new(f"Streetlight_Pole_N_{i:02d}", mesh_pole)
        pole_n.location = (x, y_north, z_deck)
        link_object_to_collection(pole_n, col_lights)

        lamp_n = bpy.data.objects.new(f"Streetlight_Lamp_N_{i:02d}", mesh_lamp)
        lamp_n.location = (x, y_north + tip_y, z_deck + tip_z)
        lamp_n.rotation_euler = (math.radians(-10), 0, 0)
        link_object_to_collection(lamp_n, col_lights)

        y_south = -(half_gap + cw - 0.20)
        pole_s = bpy.data.objects.new(f"Streetlight_Pole_S_{i:02d}", mesh_pole)
        pole_s.location = (x, y_south, z_deck)
        pole_s.rotation_euler = (0, 0, math.radians(180))
        link_object_to_collection(pole_s, col_lights)

        lamp_s = bpy.data.objects.new(f"Streetlight_Lamp_S_{i:02d}", mesh_lamp)
        lamp_s.location = (x, y_south - tip_y, z_deck + tip_z)
        lamp_s.rotation_euler = (math.radians(10), 0, math.radians(180))
        link_object_to_collection(lamp_s, col_lights)

# ---------------------------------------------------------------------------
# Abutments & Approach Wings
# ---------------------------------------------------------------------------

def build_bridge_abutments(config, materials, col_decks):
    br = config['bridge']
    half_l = br['total_length'] / 2.0
    z_deck = br['deck_height_above_water']
    abutment_len = 25.0
    abutment_width = br['total_width'] + 4.0

    mesh_abutment = bpy.data.meshes.get('Mesh_Abutment')
    if not mesh_abutment:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(abutment_len, abutment_width, z_deck + 1.2), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(0, 0, (z_deck + 1.2) / 2.0), verts=bm.verts)
        mesh_abutment = bpy.data.meshes.new('Mesh_Abutment')
        bm.to_mesh(mesh_abutment)
        bm.free()
        mesh_abutment.materials.append(materials['Concrete_Deck'])

    obj_west = bpy.data.objects.new("Abutment_Ramagundam_West", mesh_abutment)
    obj_west.location = (-half_l - abutment_len / 2.0, 0.0, 0.0)
    link_object_to_collection(obj_west, col_decks)

    obj_east = bpy.data.objects.new("Abutment_Godavarikhani_East", mesh_abutment)
    obj_east.location = (half_l + abutment_len / 2.0, 0.0, 0.0)
    link_object_to_collection(obj_east, col_decks)

# ---------------------------------------------------------------------------
# Godavari River Environment
# ---------------------------------------------------------------------------

def build_godavari_river_environment(config, materials, collections):
    env = config['environment']
    br = config['bridge']

    # 1. River Water Plane
    river_w = env['river_width']
    river_l = env['river_length_flow']

    bm_water = bmesh.new()
    bmesh.ops.create_grid(bm_water, x_segments=48, y_segments=36, size=1.0)
    bmesh.ops.scale(bm_water, vec=(river_w, river_l, 1.0), verts=bm_water.verts)
    mesh_water = bpy.data.meshes.new("Mesh_Godavari_Water")
    bm_water.to_mesh(mesh_water)
    bm_water.free()
    mesh_water.materials.append(materials['River_Water'])

    obj_water = bpy.data.objects.new("Godavari_River_WaterSurface", mesh_water)
    obj_water.location = (0.0, 0.0, env['water_level'])
    link_object_to_collection(obj_water, collections['Godavari_River'])

    # 2. River Valley & Riverbanks Terrain
    res_x = 90
    res_y = 60
    bm_terrain = bmesh.new()
    bmesh.ops.create_grid(bm_terrain, x_segments=res_x, y_segments=res_y, size=1.0)
    bmesh.ops.scale(bm_terrain, vec=(river_w * 1.15, river_l * 1.15, 1.0), verts=bm_terrain.verts)

    half_l = br['total_length'] / 2.0
    for v in bm_terrain.verts:
        x, y = v.co.x, v.co.y
        abs_x = abs(x)

        if abs_x < half_l * 0.76:
            sand_wave = math.sin(x * 0.025) * math.cos(y * 0.018) * 0.8
            sand_ridge = math.sin(x * 0.008 + y * 0.012) * 0.6
            z = -2.4 + sand_wave + sand_ridge
        elif abs_x < half_l:
            t = (abs_x - half_l * 0.76) / (half_l * 0.24)
            z = -1.5 + t * (env['bank_height'] + 1.5)
        else:
            dist = abs_x - half_l
            z = env['bank_height'] + math.sin(y * 0.015) * 1.5 + math.sin(dist * 0.03) * 0.8

        v.co.z = z

    for f in bm_terrain.faces:
        f.smooth = True

    bm_terrain.normal_update()
    mesh_terrain = bpy.data.meshes.new("Mesh_River_Terrain")
    bm_terrain.to_mesh(mesh_terrain)
    bm_terrain.free()
    mesh_terrain.materials.append(materials['River_Sand'])

    obj_terrain = bpy.data.objects.new("Godavari_River_Terrain", mesh_terrain)
    obj_terrain.location = (0.0, 0.0, 0.0)
    link_object_to_collection(obj_terrain, collections['River_Terrain'])

    # 3. Exposed Sandbars & Granite Boulder Outcrops
    random.seed(42)
    rock_mesh = bpy.data.meshes.get('Mesh_River_Rock_Chunk')
    if not rock_mesh:
        bm_rock = bmesh.new()
        bmesh.ops.create_icosphere(bm_rock, subdivisions=2, radius=1.0)
        for rv in bm_rock.verts:
            rv.co *= Vector((random.uniform(0.7, 1.3), random.uniform(0.7, 1.3), random.uniform(0.5, 0.9)))
        for f in bm_rock.faces:
            f.smooth = True
        bm_rock.normal_update()
        rock_mesh = bpy.data.meshes.new('Mesh_River_Rock_Chunk')
        bm_rock.to_mesh(rock_mesh)
        bm_rock.free()
        rock_mesh.materials.append(materials['River_Rock'])

    for r_i in range(env['num_rock_islands']):
        rx = random.uniform(-half_l * 0.72, half_l * 0.72)
        ry = random.uniform(-200.0, 200.0)
        rz = env['water_level'] - random.uniform(0.2, 0.8)
        scale_val = random.uniform(4.0, 14.0)

        r_obj = bpy.data.objects.new(f"RockIsland_{r_i:02d}", rock_mesh)
        r_obj.location = (rx, ry, rz)
        r_obj.scale = (scale_val, scale_val * random.uniform(0.8, 1.6), scale_val * random.uniform(0.3, 0.6))
        r_obj.rotation_euler = (random.uniform(0, math.pi), random.uniform(0, math.pi), random.uniform(0, math.pi))
        link_object_to_collection(r_obj, collections['River_Terrain'])

    # 4. Riverbank Trees & Vegetation
    tree_mesh = bpy.data.meshes.get('Mesh_River_Tree')
    if not tree_mesh:
        bm_tree = bmesh.new()
        trunk = bmesh.ops.create_cone(bm_tree, cap_ends=True, radius1=0.45, radius2=0.25, depth=4.0, segments=6)
        bmesh.ops.translate(bm_tree, vec=(0, 0, 2.0), verts=trunk['verts'])
        crown = bmesh.ops.create_icosphere(bm_tree, subdivisions=2, radius=3.2)
        bmesh.ops.translate(bm_tree, vec=(0, 0, 5.2), verts=crown['verts'])
        bmesh.ops.scale(bm_tree, vec=(1.3, 1.3, 0.85), verts=crown['verts'])
        for f in bm_tree.faces:
            f.smooth = True
        bm_tree.normal_update()
        tree_mesh = bpy.data.meshes.new('Mesh_River_Tree')
        bm_tree.to_mesh(tree_mesh)
        bm_tree.free()
        tree_mesh.materials.append(materials['Foliage_Green'])

    for t_i in range(env['num_bank_trees']):
        side = -1 if t_i % 2 == 0 else 1
        tx = side * (half_l + random.uniform(15.0, 220.0))
        ty = random.uniform(-380.0, 380.0)
        if abs(ty) < br['total_width'] / 2.0 + 10.0:
            ty += 30.0 * (1 if ty >= 0 else -1)
        tz = env['bank_height'] + random.uniform(-1.0, 2.5)
        t_scale = random.uniform(0.8, 1.5)

        t_obj = bpy.data.objects.new(f"BankTree_{t_i:03d}", tree_mesh)
        t_obj.location = (tx, ty, tz)
        t_obj.scale = (t_scale, t_scale, t_scale)
        t_obj.rotation_euler = (0, 0, random.uniform(0, 6.28))
        link_object_to_collection(t_obj, collections['Vegetation'])

# ---------------------------------------------------------------------------
# Collision Geometry for Game Engine Export
# ---------------------------------------------------------------------------

def build_collision_geometry(config, col_collisions):
    col_collisions.hide_render = True
    br = config['bridge']
    half_gap = br['central_gap'] / 2.0
    cw = br['carriageway_width']
    tot_len = br['total_length']
    z_road = br['deck_height_above_water'] + br['deck_thickness'] + br['asphalt_thickness']

    bm_road = bmesh.new()
    bmesh.ops.create_cube(bm_road, size=1.0)
    bmesh.ops.scale(bm_road, vec=(tot_len, cw, 0.4), verts=bm_road.verts)
    mesh_col_road = bpy.data.meshes.new("Mesh_Col_Road")
    bm_road.to_mesh(mesh_col_road)
    bm_road.free()

    y_north = half_gap + cw / 2.0
    y_south = -(half_gap + cw / 2.0)

    col_rn = bpy.data.objects.new("COL_Road_North", mesh_col_road)
    col_rn.location = (0.0, y_north, z_road - 0.22)
    col_rn.hide_render = True
    link_object_to_collection(col_rn, col_collisions)

    col_rs = bpy.data.objects.new("COL_Road_South", mesh_col_road)
    col_rs.location = (0.0, y_south, z_road - 0.22)
    col_rs.hide_render = True
    link_object_to_collection(col_rs, col_collisions)

    bar_y_coords = [
        half_gap + cw - 0.22,
        half_gap + 0.22,
        -(half_gap + 0.22),
        -(half_gap + cw - 0.22)
    ]
    bm_bar = bmesh.new()
    bmesh.ops.create_cube(bm_bar, size=1.0)
    bmesh.ops.scale(bm_bar, vec=(tot_len, 0.45, 1.0), verts=bm_bar.verts)
    mesh_col_bar = bpy.data.meshes.new("Mesh_Col_Barrier")
    bm_bar.to_mesh(mesh_col_bar)
    bm_bar.free()

    for idx, by in enumerate(bar_y_coords):
        c_bar = bpy.data.objects.new(f"COL_Barrier_{idx}", mesh_col_bar)
        c_bar.location = (0.0, by, z_road + 0.5)
        c_bar.hide_render = True
        link_object_to_collection(c_bar, col_collisions)

# ---------------------------------------------------------------------------
# Cameras & Lighting Setup
# ---------------------------------------------------------------------------

def create_camera(name, loc, rot_deg, lens=50.0, clip_end=4000.0, col=None):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_end = clip_end
    cam_data.clip_start = 0.2

    cam_obj = bpy.data.objects.new(name, cam_data)
    cam_obj.location = loc
    cam_obj.rotation_euler = (math.radians(rot_deg[0]),
                              math.radians(rot_deg[1]),
                              math.radians(rot_deg[2]))
    if col:
        link_object_to_collection(cam_obj, col)
    return cam_obj

def setup_all_cameras(config, col_cameras):
    br = config['bridge']
    half_l = br['total_length'] / 2.0
    z_deck = br['deck_height_above_water'] + br['deck_thickness'] + br['asphalt_thickness']

    cameras = {}

    # 1. Full-length Top-Down Aerial View
    cameras['Cam_01_Aerial_TopDown'] = create_camera(
        'Cam_01_Aerial_TopDown',
        loc=(0.0, 0.0, 950.0),
        rot_deg=(0.0, 0.0, 0.0),
        lens=32.0, col=col_cameras
    )

    # 2. Front Aerial View Looking Along Bridge (Ramagundam -> Godavarikhani)
    cameras['Cam_02_Aerial_FrontAlongBridge'] = create_camera(
        'Cam_02_Aerial_FrontAlongBridge',
        loc=(-half_l - 140.0, 0.0, 65.0),
        rot_deg=(75.0, 0.0, -90.0),
        lens=38.0, col=col_cameras
    )

    # 3. Reverse Aerial View (Godavarikhani -> Ramagundam)
    cameras['Cam_03_Aerial_Reverse'] = create_camera(
        'Cam_03_Aerial_Reverse',
        loc=(half_l + 140.0, 0.0, 65.0),
        rot_deg=(75.0, 0.0, 90.0),
        lens=38.0, col=col_cameras
    )

    # 4. Diagonal Drone View
    cameras['Cam_04_Drone_Diagonal'] = create_camera(
        'Cam_04_Drone_Diagonal',
        loc=(-half_l + 220.0, 260.0, 85.0),
        rot_deg=(68.0, 0.0, -148.0),
        lens=35.0, col=col_cameras
    )

    # 5. Road-Level Driving View
    cameras['Cam_05_RoadLevel_Driving'] = create_camera(
        'Cam_05_RoadLevel_Driving',
        loc=(-half_l + 80.0, 6.75, z_deck + 1.25),
        rot_deg=(88.0, 0.0, -90.0),
        lens=48.0, col=col_cameras
    )

    # 6. Side Elevation Showing Pillars
    cameras['Cam_06_SideElevation_Pillars'] = create_camera(
        'Cam_06_SideElevation_Pillars',
        loc=(-half_l + 140.0, -220.0, 16.0),
        rot_deg=(86.0, 0.0, 0.0),
        lens=55.0, col=col_cameras
    )

    # 7. Underneath-Bridge Structural View (Looking up at pier caps, elastomeric bearings, and prestressed I-girders)
    cameras['Cam_07_UnderDeck_Structural'] = create_camera(
        'Cam_07_UnderDeck_Structural',
        loc=(-half_l + 10.0, -15.0, 2.0),
        rot_deg=(101.05, 0.0, -64.78),
        lens=22.0, col=col_cameras
    )

    # 8. Wide Cinematic River View
    cameras['Cam_08_River_Cinematic'] = create_camera(
        'Cam_08_River_Cinematic',
        loc=(-half_l + 180.0, 280.0, 9.0),
        rot_deg=(82.0, 0.0, -145.0),
        lens=28.0, col=col_cameras
    )

    return cameras

def setup_lighting_and_environment(config, col_lighting):
    sun_data = bpy.data.lights.new(name="Sun_KeyLight", type='SUN')
    sun_data.energy = 5.2
    sun_data.color = (1.0, 0.96, 0.91)
    sun_data.angle = math.radians(1.2)

    sun_obj = bpy.data.objects.new("Sun_KeyLight", sun_data)
    sun_obj.rotation_euler = (math.radians(52), math.radians(22), math.radians(-48))
    link_object_to_collection(sun_obj, col_lighting)

    fill_data = bpy.data.lights.new(name="Sun_FillLight", type='SUN')
    fill_data.energy = 1.4
    fill_data.color = (0.76, 0.88, 1.0)
    fill_obj = bpy.data.objects.new("Sun_FillLight", fill_data)
    fill_obj.rotation_euler = (math.radians(-65), math.radians(15), math.radians(120))
    link_object_to_collection(fill_obj, col_lighting)

    world = bpy.context.scene.world
    if not world:
        world = bpy.data.worlds.new("World_Godavari")
        bpy.context.scene.world = world

    wnodes = world.node_tree.nodes
    wlinks = world.node_tree.links
    wnodes.clear()

    w_out = wnodes.new(type='ShaderNodeOutputWorld')
    w_out.location = (300, 0)

    try:
        sky_tex = wnodes.new(type='ShaderNodeTexSky')
        sky_tex.sky_type = 'NISHITA'
        sky_tex.sun_elevation = math.radians(45.0)
        sky_tex.sun_rotation = math.radians(65.0)
        sky_tex.altitude = 150.0
        sky_tex.air_density = 1.15
        sky_tex.dust_density = 1.35
        sky_tex.ozone_density = 1.0
        wlinks.new(sky_tex.outputs['Color'], w_out.inputs['Surface'])
    except Exception:
        bg = wnodes.new(type='ShaderNodeBackground')
        bg.inputs['Color'].default_value = (0.55, 0.72, 0.88, 1.0)
        bg.inputs['Strength'].default_value = 1.2
        wlinks.new(bg.outputs['Background'], w_out.inputs['Surface'])

# ---------------------------------------------------------------------------
# Master Bridge Scene Generator
# ---------------------------------------------------------------------------

def clear_existing_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat, do_unlink=True)
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col, do_unlink=True)

def generate_godavarikhani_bridge(config_path, test_section_only=False):
    print(f"=== Loading configuration from {config_path} ===")
    with open(config_path, 'r') as f:
        config = json.load(f)

    if test_section_only:
        print(">>> MODE: Generating Representative 3-Span Test Section <<<")
        config['bridge']['num_spans'] = 3
        config['bridge']['total_length'] = 3 * config['bridge']['span_length']
        config['environment']['num_bank_trees'] = 16
        config['environment']['num_rock_islands'] = 8
    else:
        print(">>> MODE: Generating FULL 1,100 METRE GODAVARIKHANI BRIDGE <<<")

    clear_existing_scene()

    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.unit_settings.length_unit = 'METERS'

    engine_name = config['render'].get('engine', 'BLENDER_EEVEE')
    bpy.context.scene.render.engine = engine_name
    bpy.context.scene.render.resolution_x = config['render'].get('resolution_x', 1920)
    bpy.context.scene.render.resolution_y = config['render'].get('resolution_y', 1080)
    bpy.context.scene.render.image_settings.file_format = 'PNG'

    if hasattr(bpy.context.scene, 'eevee'):
        ee = bpy.context.scene.eevee
        if hasattr(ee, 'use_raytracing'):
            ee.use_raytracing = True
        if hasattr(ee, 'use_shadows'):
            ee.use_shadows = True
        if hasattr(ee, 'use_fast_gi'):
            ee.use_fast_gi = True
        if hasattr(ee, 'taa_render_samples'):
            ee.taa_render_samples = config['render'].get('samples', 64)

    collection_names = [
        'Bridge_Decks',
        'Bridge_Pillars',
        'Bridge_Girders',
        'Road_Asphalt',
        'Road_Markings',
        'Safety_Barriers',
        'Streetlights',
        'Godavari_River',
        'River_Terrain',
        'Vegetation',
        'Cameras',
        'Lighting',
        'Collisions'
    ]
    collections = {name: get_or_create_collection(name) for name in collection_names}

    print("Building PBR Materials...")
    materials = build_all_materials()

    br = config['bridge']
    num_spans = br['num_spans']
    tot_len = br['total_length']
    span_len = tot_len / float(num_spans)
    half_l = tot_len / 2.0

    print(f"Generating Bridge: Total Length = {tot_len:.1f}m, Spans = {num_spans}, Span Length = {span_len:.2f}m")

    # 1. Substructure Pier Bents
    print(f"Building {num_spans + 1} Pier Bents & Foundations...")
    for b_i in range(num_spans + 1):
        x_bent = -half_l + b_i * span_len
        build_pier_bent(b_i, x_bent, config, materials, collections['Bridge_Pillars'])

    # 2. Superstructure Spans
    print(f"Building {num_spans} Superstructure Spans (Girders, Decks, Asphalt)...")
    for s_i in range(num_spans):
        x_start = -half_l + s_i * span_len
        x_end = x_start + span_len
        build_bridge_span(s_i, x_start, x_end, config, materials, collections)

    # 3. Abutments
    print("Building Abutments...")
    build_bridge_abutments(config, materials, collections['Bridge_Decks'])

    # 4. Road Markings
    print("Building Road Markings...")
    build_road_markings(config, materials, collections['Road_Markings'])

    # 5. Barriers & Railings
    print("Building Barriers & Railings...")
    build_crash_barriers(config, materials, collections['Safety_Barriers'])

    # 6. Streetlights
    print("Placing Streetlights...")
    place_streetlights(config, materials, collections['Streetlights'])

    # 7. River Environment
    print("Generating Godavari River, Valley Terrain, Rocks & Vegetation...")
    build_godavari_river_environment(config, materials, collections)

    # 8. Collision Geometry
    print("Generating Collision Geometry...")
    build_collision_geometry(config, collections['Collisions'])

    # 9. Lighting & Sky
    print("Setting up Sun and Atmospheric Sky...")
    setup_lighting_and_environment(config, collections['Lighting'])

    # 10. Cameras
    print("Setting up Cameras...")
    cameras = setup_all_cameras(config, collections['Cameras'])

    print("=== Bridge Generation Completed Successfully! ===")
    return cameras

# ---------------------------------------------------------------------------
# Rendering & Export
# ---------------------------------------------------------------------------

def render_all_cameras(output_dir, cameras):
    os.makedirs(output_dir, exist_ok=True)
    print(f"=== Rendering {len(cameras)} Camera Previews to {output_dir} ===")

    for cam_name, cam_obj in cameras.items():
        bpy.context.scene.camera = cam_obj
        render_path = os.path.join(output_dir, f"{cam_name}.png")
        bpy.context.scene.render.filepath = render_path
        print(f"Rendering {cam_name} -> {render_path}...")
        bpy.ops.render.render(write_still=True)
    print("=== All Camera Renders Finished! ===")

def export_scene_glb(filepath):
    print(f"=== Exporting Optimized GLB to {filepath} ===")
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False
    )
    print(f"GLB Model exported successfully! File size: {os.path.getsize(filepath) / (1024*1024):.2f} MB")

# ---------------------------------------------------------------------------
# Main CLI
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    args = sys.argv
    script_args = []
    if '--' in args:
        script_args = args[args.index('--') + 1:]

    test_mode = '--test' in script_args or '--test-section' in script_args
    render_mode = '--render' in script_args
    export_mode = '--export' in script_args or not test_mode

    base_dir = os.path.dirname(os.path.abspath(__file__))
    config_file = os.path.join(base_dir, 'bridge_config.json')
    if not os.path.exists(config_file):
        config_file = os.path.join(base_dir, 'Godavarikhani_Bridge_3D', 'bridge_config.json')

    cameras = generate_godavarikhani_bridge(config_file, test_section_only=test_mode)

    blend_name = 'Godavarikhani_Bridge_Test.blend' if test_mode else 'Godavarikhani_Bridge.blend'
    out_blend = os.path.join(base_dir, blend_name)
    if 'Godavarikhani_Bridge_3D' not in base_dir:
        out_blend = os.path.join(base_dir, 'Godavarikhani_Bridge_3D', blend_name)

    os.makedirs(os.path.dirname(os.path.abspath(out_blend)), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print(f"Blender project saved to: {out_blend}")

    if render_mode:
        renders_dir = os.path.join(os.path.dirname(out_blend), 'renders_test' if test_mode else 'renders')
        render_all_cameras(renders_dir, cameras)

    if export_mode and not test_mode:
        out_glb = os.path.join(os.path.dirname(out_blend), 'Godavarikhani_Bridge.glb')
        export_scene_glb(out_glb)
