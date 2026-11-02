import bpy
import bmesh
import json
import math
import pathlib
from mathutils import Matrix, Vector

SRC = pathlib.Path("/Users/rahulpannati/Downloads/Rahul Animations/mana orru assests/arcane_x_pubg_m416_gun_skin/scene.gltf")
OUT_ASSETS = pathlib.Path("/Users/rahulpannati/Downloads/AI Agents Practice/ManaOoru/assets/models/weapons")
OUT_LIB = pathlib.Path("/Users/rahulpannati/GameReadyLibrary/Weapons/M416_Arcane")

OUT_ASSETS.mkdir(parents=True, exist_ok=True)
OUT_LIB.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
bpy.context.view_layer.update()

obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
print(f"Loaded {len(obs)} parts from Arcane M416.")

# Bake transforms
for o in obs:
    m = o.data.copy()
    m.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
    o.data = m

for o in list(bpy.context.scene.objects):
    if o not in obs:
        bpy.data.objects.remove(o, do_unlink=True)

def get_bounds(objects):
    pts = [v.co for o in objects for v in o.data.vertices]
    min_c = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    max_c = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return min_c, max_c

lo, hi = get_bounds(obs)
print(f"Raw Arcane Bounds: min={lo}, max={hi}, size={hi - lo}")

# Length is along X: stock at -29.32, muzzle at +64.67
# In Blender M416 coordinates, length is along Y: stock at -0.499, muzzle at +0.351
# Rotation: 90 deg around Z so X -> Y, Y -> -X
rot = Matrix.Rotation(math.radians(-90), 4, 'Z')
for o in obs:
    o.data.transform(rot)

lo, hi = get_bounds(obs)
print(f"After Rotation Bounds: min={lo}, max={hi}, size={hi - lo}")

# Scale so length along Y is 0.85m (standard M416 length)
scale = 0.850 / (hi.y - lo.y)
# Center X at 0.0, align Y so muzzle is at +0.351, align Z
shift = Vector((-((lo.x + hi.x) / 2.0) * scale, 0.351 - (hi.y * scale), -lo.z * scale - 0.075))
t = Matrix.Translation(shift) @ Matrix.Scale(scale, 4)

for o in obs:
    o.data.transform(t)

lo, hi = get_bounds(obs)
print(f"Final Scaled Bounds: min={lo}, max={hi}, size={hi - lo}")

# Join into single clean weapon mesh
bpy.ops.object.select_all(action='DESELECT')
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
bpy.ops.object.join()

rifle = obs[0]
rifle.name = "M416_Arcane"

# Check triangles
rifle.data.calc_loop_triangles()
tris = len(rifle.data.loop_triangles)
print(f"Clean M416 Arcane Mesh: {tris} triangles.")

# Save master .blend file
blend_out = str(OUT_LIB / "m416_arcane.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_out)
print(f"Saved master blend: {blend_out}")

# Export GLB to assets and GameReadyLibrary
glb_assets = str(OUT_ASSETS / "m416_arcane.glb")
glb_lib = str(OUT_LIB / "m416_arcane.glb")

for out_path in [glb_assets, glb_lib]:
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True
    )
    print(f"Exported clean GLB: {out_path}")

specs = {
    "name": "M416 Arcane Edition",
    "triangles": tris,
    "dimensions": [round(x, 4) for x in (hi - lo)],
    "source": "arcane_x_pubg_m416_gun_skin"
}
(OUT_LIB / "specs.json").write_text(json.dumps(specs, indent=2))
print("Saved M416 Arcane specs.json successfully!")
