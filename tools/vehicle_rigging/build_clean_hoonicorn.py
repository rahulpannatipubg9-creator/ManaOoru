import bpy
import bmesh
import json
import math
import pathlib
from mathutils import Matrix, Vector

SRC_GLB = pathlib.Path("/Users/rahulpannati/Downloads/Rahul Animations/mana orru assests/hoonicorn-ken-block/source/hoonicorn-_a_tribute_to_ken_block_updated.glb")
OUT_ASSETS = pathlib.Path("/Users/rahulpannati/Downloads/AI Agents Practice/ManaOoru/assets/models/vehicles/hoonicorn_ken_block")
OUT_LIB = pathlib.Path("/Users/rahulpannati/GameReadyLibrary/Cars/Ford_Mustang_Hoonicorn")

OUT_ASSETS.mkdir(parents=True, exist_ok=True)
OUT_LIB.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC_GLB))
bpy.context.view_layer.update()

obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
print(f"Loaded {len(obs)} mesh objects from Hoonicorn GLB.")

# Capture world matrices and bake them into vertex data
for o in obs:
    m = o.data.copy()
    m.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
    o.data = m

for o in list(bpy.context.scene.objects):
    if o not in obs:
        bpy.data.objects.remove(o, do_unlink=True)

def bounds(objects):
    pts = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    min_c = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    max_c = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return min_c, max_c

lo, hi = bounds(obs)
print(f"Initial Bounds: min={lo}, max={hi}, length={hi.y - lo.y:.2f}m")

# Real 1965 Ford Mustang Hoonicorn V2 specs:
# Length: 4.54m, Width: 2.02m, Height: 1.25m, Wheelbase: 2.74m, Track: 1.66m
TARGET_LENGTH = 4.54
scale_factor = TARGET_LENGTH / (hi.y - lo.y)
print(f"Scale factor: {scale_factor:.6f}")

# Center X and center wheelbase in Y
# Raw tire centers:
# Front wheels Y ~ 0.00, Rear wheels Y ~ -7.43
# Scaled Y: Front ~ 0.00, Rear ~ -2.73
wheelbase_raw = 7.43
center_shift = Vector((-(lo.x + hi.x) / 2.0, (wheelbase_raw / 2.0), -lo.z))

t_matrix = Matrix.Scale(scale_factor, 4) @ Matrix.Translation(center_shift)

# In the raw file:
# Front wheels are at Y = 0.00, Rear wheels at Y = -7.43
# But in Godot vehicle coordinate system, +Z is FORWARD, -Z is REAR, X is RIGHT/LEFT.
# In Blender, forward is -Y.
# We will rotate so Front (+Y) points forward.
for o in obs:
    o.data.transform(t_matrix)

lo, hi = bounds(obs)
print(f"Scaled & Centered Bounds: min={lo}, max={hi}, size={hi - lo}")

# Wheels identification in scaled space:
# Front wheels: Y around +1.36m
# Rear wheels: Y around -1.36m
# Left wheels: X < -0.4m
# Right wheels: X > 0.4m
# Wheel radius: ~0.338m, axle height Z: ~0.34m

WHEEL_RADIUS = 0.338
WHEELBASE_HALF = (wheelbase_raw * scale_factor) / 2.0 # ~1.364m
TRACK_HALF = (2.26 * scale_factor) # ~0.83m

wheel_centers = {
    'Wheel_FL': Vector((-TRACK_HALF, WHEELBASE_HALF, WHEEL_RADIUS)),
    'Wheel_FR': Vector((TRACK_HALF, WHEELBASE_HALF, WHEEL_RADIUS)),
    'Wheel_RL': Vector((-TRACK_HALF, -WHEELBASE_HALF, WHEEL_RADIUS)),
    'Wheel_RR': Vector((TRACK_HALF, -WHEELBASE_HALF, WHEEL_RADIUS))
}

print("Target Wheel Centers:")
for k, v in wheel_centers.items():
    print(f"  {k}: ({v.x:.3f}, {v.y:.3f}, {v.z:.3f})")

# Separate wheel parts from body parts
wheel_groups = {'Wheel_FL': [], 'Wheel_FR': [], 'Wheel_RL': [], 'Wheel_RR': [], 'Body': []}

for o in obs:
    pts = [v.co for v in o.data.vertices]
    c = Vector((sum(p.x for p in pts)/len(pts), sum(p.y for p in pts)/len(pts), sum(p.z for p in pts)/len(pts)))
    
    # Check if this object belongs to a wheel
    matched_wheel = None
    for w_name, w_pos in wheel_centers.items():
        dist_2d = math.sqrt((c.y - w_pos.y)**2 + (c.z - w_pos.z)**2)
        dist_x = abs(c.x - w_pos.x)
        if dist_2d < 0.42 and dist_x < 0.35 and c.z < (WHEEL_RADIUS * 2.2):
            matched_wheel = w_name
            break
            
    if matched_wheel:
        wheel_groups[matched_wheel].append(o)
    else:
        wheel_groups['Body'].append(o)

for k, v in wheel_groups.items():
    print(f"Group {k}: {len(v)} mesh parts")

# Combine parts for each assembly
assembly_names = ['Body', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR']
final_objects = {}

for name in assembly_names:
    parts = wheel_groups[name]
    if not parts:
        print(f"Warning: No parts found for {name}!")
        continue
        
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    
    merged = parts[0]
    merged.name = f"{name}_Mesh"
    
    # Clean normals
    bm = bmesh.new()
    bm.from_mesh(merged.data)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.000001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(merged.data)
    bm.free()
    
    # If wheel, center its mesh geometry around (0, 0, 0) rotated by 90 deg around Y for axle alignment
    # As per ManaOoru convention:
    # o.data.transform(Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Translation(-c))
    if name != 'Body':
        c = wheel_centers[name]
        merged.data.transform(Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Translation(-c))
        
    parent_empty = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(parent_empty)
    merged.parent = parent_empty
    final_objects[name] = merged

# Decimate to fit under 50,000 triangle budget
total_tris = sum(len(o.data.loop_triangles) for o in [o for o in bpy.data.objects if o.type == 'MESH'])
print(f"Total triangles before decimation: {total_tris}")

TARGET_TRIS = 48500
if total_tris > TARGET_TRIS:
    ratio = float(TARGET_TRIS) / float(total_tris)
    print(f"Decimating with ratio: {ratio:.4f}")
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        mod = o.modifiers.new('GameBudget', 'DECIMATE')
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
        o.data.calc_loop_triangles()

final_tris = sum(len(o.data.loop_triangles) for o in [o for o in bpy.data.objects if o.type == 'MESH'])
print(f"Final triangles after decimation: {final_tris}")

# Save master .blend file
blend_out = str(OUT_LIB / "hoonicorn_clean.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_out)
print(f"Saved master clean blend: {blend_out}")

# Export game rig GLB to assets and library
glb_assets = str(OUT_ASSETS / "hoonicorn_ken_block_rig.glb")
glb_lib = str(OUT_LIB / "hoonicorn_rig.glb")

for out_path in [glb_assets, glb_lib]:
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=False,
        export_yup=True
    )
    print(f"Exported GLB rig: {out_path}")

# Write specs.json
specs = {
    "id": "hoonicorn_ken_block",
    "name": "1965 Ford Mustang Hoonicorn RTR V2 (Ken Block Tribute)",
    "triangles": final_tris,
    "dimensions": {
        "length_m": TARGET_LENGTH,
        "width_m": 2.02,
        "height_m": 1.25,
        "wheelbase_m": 2.73,
        "track_m": 1.66
    },
    "engine": {
        "type": "6.7L Twin-Turbo Roush-Yates V8",
        "horsepower": 1400,
        "torque_nm": 1600,
        "drivetrain": "AWD with Sadev 6-Speed Sequential Transmission"
    },
    "wheel_centers": {k: [round(x, 4) for x in v] for k, v in wheel_centers.items()}
}
(OUT_LIB / "specs.json").write_text(json.dumps(specs, indent=2))
print("Saved specs.json successfully!")

