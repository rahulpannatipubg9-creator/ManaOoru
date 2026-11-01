#!/usr/bin/env python3
"""
tools/asset_pipeline/colorize_tdm.py
Applies authentic BGMI-inspired tactical TDM PBR colors to the TDM compound.
Injects rich team colors (Blue vs Red containers), industrial concrete, weathered wood,
dark gunmetal rods, and hazard amber accents to replace the untextured chalk-white default.
"""
import sys
import os
import bpy

def colorize_materials():
    # Palette definition: (RGBA, metallic, roughness)
    PALETTE = {
        # --- Containers & Shipping Yard (Blue vs Red Tactical Layout) ---
        "container.color": ([0.10, 0.36, 0.68, 1.0], 0.45, 0.42),    # Azure Blue Team Container
        "container": ([0.68, 0.14, 0.12, 1.0], 0.40, 0.45),          # Crimson Red Team Container
        "container.001": ([0.14, 0.42, 0.32, 1.0], 0.35, 0.50),      # Emerald / Olive Green Container
        "old_blue_metal_box_baked": ([0.12, 0.28, 0.48, 1.0], 0.60, 0.40), # Weathered Blue Navy Box
        "rusty_metal_plate": ([0.46, 0.22, 0.12, 1.0], 0.35, 0.75),   # Corroded Rust Iron Plate
        "container.metallocks": ([0.15, 0.16, 0.18, 1.0], 0.85, 0.28),# Dark Galvanized Steel Locks
        "container_rods_mat.001": ([0.15, 0.16, 0.18, 1.0], 0.85, 0.28), # Steel Rods
        "container.decals": ([0.88, 0.88, 0.84, 1.0], 0.10, 0.50),   # White Stencil Decals
        "container_paper.001": ([0.78, 0.74, 0.65, 1.0], 0.00, 0.90), # Shipping Cargo Manifests

        # --- Stencil & Hazard Markings ---
        "png-transparent-irritation-hazard-symbol-safety-warning-sig": ([0.88, 0.62, 0.08, 1.0], 0.05, 0.45), # Hazard Amber
        "text.001": ([0.88, 0.88, 0.85, 1.0], 0.10, 0.50),           # Off-white stenciled letters
        "numbers.001": ([0.88, 0.88, 0.85, 1.0], 0.10, 0.50),
        "letters.001": ([0.88, 0.88, 0.85, 1.0], 0.10, 0.50),
        "evergreen.001": ([0.18, 0.30, 0.16, 1.0], 0.30, 0.60),      # Military Camo Olive
        "red_carpet": ([0.60, 0.10, 0.10, 1.0], 0.05, 0.85),         # Tactical Crimson Red Banner

        # --- Ground, Concrete & Road Surfaces ---
        "concrete_chipped_cracked": ([0.32, 0.31, 0.30, 1.0], 0.05, 0.92), # Weathered Gray Concrete Slab
        "material": ([0.44, 0.40, 0.34, 1.0], 0.02, 0.95),           # Dusty Riverbed Ground / Sand
        "old_mossy_tiles": ([0.36, 0.28, 0.24, 1.0], 0.05, 0.80),    # Weathered Terracotta Tiles

        # --- Buildings & Structural Sheds ---
        "house_1_baked": ([0.54, 0.52, 0.48, 1.0], 0.25, 0.65),      # Industrial Warehouse Sheet Metal
        "straw-pergula_baked": ([0.60, 0.50, 0.30, 1.0], 0.00, 0.95),# Golden Thatch
        "straw-fence_baked": ([0.58, 0.48, 0.28, 1.0], 0.00, 0.95),  # Thatch / Reed Fence
        "pottery": ([0.58, 0.28, 0.18, 1.0], 0.02, 0.85),            # Earthenware Red Clay
        "pottery.2": ([0.54, 0.26, 0.16, 1.0], 0.02, 0.85),

        # --- Wooden Crates, Props & Barrels ---
        "wood": ([0.45, 0.30, 0.16, 1.0], 0.00, 0.78),               # Tactical Ammo Crate Timber
        "rough_wood": ([0.42, 0.27, 0.14, 1.0], 0.00, 0.82),
        "old_wood": ([0.38, 0.25, 0.14, 1.0], 0.00, 0.85),
        "medieval_box_5": ([0.48, 0.32, 0.18, 1.0], 0.00, 0.75),     # Wooden Supply Crate
        "medieval_wood": ([0.44, 0.29, 0.15, 1.0], 0.00, 0.80),
        "stylized_wood": ([0.46, 0.30, 0.16, 1.0], 0.00, 0.78),
        "wood_parquet": ([0.50, 0.34, 0.20, 1.0], 0.00, 0.70),
        "rope": ([0.60, 0.50, 0.36, 1.0], 0.00, 0.90),               # Tactical Hemp Rope
    }

    colored_count = 0
    for mat in bpy.data.materials:
        name_lower = mat.name.lower().strip()
        
        # Match from palette or infer sensible default
        rule = None
        for key, val in PALETTE.items():
            if key in name_lower:
                rule = val
                break
        
        if not rule:
            if "wood" in name_lower:
                rule = ([0.44, 0.29, 0.16, 1.0], 0.0, 0.8)
            elif "metal" in name_lower or "iron" in name_lower or "steel" in name_lower:
                rule = ([0.22, 0.23, 0.25, 1.0], 0.75, 0.35)
            elif "box" in name_lower or "crate" in name_lower:
                rule = ([0.46, 0.32, 0.18, 1.0], 0.0, 0.75)
            else:
                # Default non-white industrial tint (warm sandy gray)
                rule = ([0.42, 0.40, 0.38, 1.0], 0.1, 0.85)

        color, metallic, roughness = rule

        # Ensure node tree
        if not mat.use_nodes:
            mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf:
            bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
            output = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None)
            if not output:
                output = nodes.new(type='ShaderNodeOutputMaterial')
            mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])

        # Set viewport color & BSDF properties
        mat.diffuse_color = tuple(color)
        if 'Base Color' in bsdf.inputs:
            bsdf.inputs['Base Color'].default_value = tuple(color)
        if 'Metallic' in bsdf.inputs:
            bsdf.inputs['Metallic'].default_value = float(metallic)
        if 'Roughness' in bsdf.inputs:
            bsdf.inputs['Roughness'].default_value = float(roughness)

        colored_count += 1
        print(f"  Colored: {mat.name} -> RGB({color[0]:.2f}, {color[1]:.2f}, {color[2]:.2f}) M={metallic} R={roughness}")

    print(f"Total materials colorized: {colored_count}")

def main():
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
    else:
        args = []
    
    if len(args) < 2:
        print("Usage: blender -b --python colorize_tdm.py -- <input_glb> <output_glb>")
        sys.exit(1)

    input_path = os.path.abspath(args[0])
    output_path = os.path.abspath(args[1])

    # Clean default scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    print(f"Importing GLB: {input_path}")
    bpy.ops.import_scene.gltf(filepath=input_path)

    print("Applying tactical TDM color palette...")
    colorize_materials()

    print(f"Exporting colorized GLB to: {output_path}")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True
    )
    print("Colorization complete!")

if __name__ == "__main__":
    main()
