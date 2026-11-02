import bpy, bmesh, math, pathlib, sys
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[2]
INPUT_GLB = "/Users/rahulpannati/Downloads/Rahul Animations/mana orru assests/bmw-s1000-rr/source/10211.glb"
OUT_LIB = pathlib.Path("/Users/rahulpannati/GameReadyLibrary/Motorcycles/BMW_S1000RR_2023")
OUT_GAME = ROOT / "assets/models/vehicles/bmw_s1000_rr"
OUT_LIB.mkdir(parents=True, exist_ok=True)
OUT_GAME.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=INPUT_GLB)

# 1. Bake world transforms on all meshes and clear parents
obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for o in obs:
    m = o.data.copy()
    m.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)
    o.data = m

# 2. Delete non-mesh objects (empties, cameras, lights)
for o in list(bpy.context.scene.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)

# 3. Delete bloat / 3D text objects (8k tris of speedometer text + icosphere)
bloat_names = ['Icosphere', '1', '2', '3', '4', '5', '6', '8', '9', 'N']
for name in bloat_names:
    o = bpy.context.scene.objects.get(name)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)

# 4. Rotate 180 degrees around Z so front (headlights) faces -Y and rear faces +Y (ManaOoru vehicle convention)
rot180 = Matrix.Rotation(math.pi, 4, 'Z')
for o in bpy.context.scene.objects:
    o.data.transform(rot180)

# 5. Ground the model so tires touch Z = 0.0
all_v = [v.co for o in bpy.context.scene.objects for v in o.data.vertices]
min_z = min(v.z for v in all_v)
shift_z = Matrix.Translation(Vector((0, 0, -min_z)))
for o in bpy.context.scene.objects:
    o.data.transform(shift_z)

# 6. Apply decimation to high-poly components
decimations = {
    'LBUTTONS': 0.01,    # 25,924 -> ~250 tris
    'handlebars': 0.05,  # 82,740 -> ~4,100 tris
    'bodyshell': 0.16,   # 73,378 -> ~11,700 tris
    'chassis': 0.18,     # 45,043 -> ~8,100 tris
    'forks_l': 0.20,     # 15,649 -> ~3,100 tris
    'swingarm': 0.25,    # 10,181 -> ~2,500 tris
    'engineblock': 0.25, # 10,747 -> ~2,600 tris
}

for name, ratio in decimations.items():
    o = bpy.context.scene.objects.get(name)
    if o:
        mod = o.modifiers.new(name="BudgetDecimate", type='DECIMATE')
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)

# 7. Locate wheel centers
fw = bpy.context.scene.objects.get('wheel_lf.child')
rw = bpy.context.scene.objects.get('wheel_lr.child')
c_fw = sum([v.co for v in fw.data.vertices], Vector((0,0,0))) / len(fw.data.vertices)
c_rw = sum([v.co for v in rw.data.vertices], Vector((0,0,0))) / len(rw.data.vertices)

print(f"Calculated Wheel Centers: Front={c_fw}, Rear={c_rw}")

# 8. Define the standard motorcycle assemblies
groups = {
    'BikeBody': [
        'bodyshell', 'chassis', 'engineblock', 'swingarm', 'seat',
        'rear-seat', 'rear-frame', 'mud-gaurd', 'brakelight_l', 'bikedisc_r'
    ],
    'Handlebars': [
        'handlebars', 'forks_l', 'forks_u', 'cockpit', 'headlight_l',
        'headlight_r', 'extra_7', 'ign', 'interior', 'takometro', 'dials', 'LBUTTONS'
    ],
    'FrontWheelMesh': [
        'wheel_lf.child', 'bikedisc_f'
    ],
    'RearWheelMesh': [
        'wheel_lr.child'
    ]
}

# 9. Consolidate into the 4 target meshes
final_objects = {}

for grp_name, obj_names in groups.items():
    members = [bpy.context.scene.objects.get(n) for n in obj_names if bpy.context.scene.objects.get(n)]
    if not members:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for m in members:
        m.select_set(True)
    bpy.context.view_layer.objects.active = members[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = grp_name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # Dissolve degenerate faces & recalculate normals
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    
    final_objects[grp_name] = obj

# Additional pass to guarantee <= 40,000 triangle budget
mod_body = final_objects['BikeBody'].modifiers.new(name="FinalDecimate", type="DECIMATE")
mod_body.ratio = 0.45
bpy.context.view_layer.objects.active = final_objects['BikeBody']
bpy.ops.object.modifier_apply(modifier=mod_body.name)

mod_hb = final_objects['Handlebars'].modifiers.new(name="FinalDecimate", type="DECIMATE")
mod_hb.ratio = 0.30
bpy.context.view_layer.objects.active = final_objects['Handlebars']
bpy.ops.object.modifier_apply(modifier=mod_hb.name)

# 10. Transform wheel meshes to axle-centered local space (same convention as bullet_rig)
# In Godot, wheels have rotation = Vector3(0, 0, 1.5708) and rotate around local X
final_objects['FrontWheelMesh'].data.transform(Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Translation(-c_fw))
final_objects['RearWheelMesh'].data.transform(Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Translation(-c_rw))

# Handlebars headset pivot offset:
# In Godot, Handlebars node is placed at (0, 0.888, 0.466)
h_pivot = Vector((0.0, -0.466, 0.888))
final_objects['Handlebars'].data.transform(Matrix.Translation(-h_pivot))

total_tris = sum(len(f.vertices)-2 for o in final_objects.values() for f in o.data.polygons)
print(f"=== OPTIMIZATION COMPLETE ===")
print(f"Total Triangles: {total_tris} (Target was <= 40,000)")
for name, o in final_objects.items():
    print(f"  {name}: {sum(len(f.vertices)-2 for f in o.data.polygons)} tris")

# Save master .blend to GameReadyLibrary
blend_path = str(OUT_LIB / "bmw_s1000rr_source.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"Saved master .blend to: {blend_path}")

# Export clean GLB to GameReadyLibrary and Game Assets
glb_lib = str(OUT_LIB / "bmw_s1000rr_rig.glb")
glb_game = str(OUT_GAME / "bmw_s1000rr_rig.glb")

bpy.ops.export_scene.gltf(filepath=glb_lib, export_format='GLB', export_animations=False, export_lights=False, export_cameras=False)
bpy.ops.export_scene.gltf(filepath=glb_game, export_format='GLB', export_animations=False, export_lights=False, export_cameras=False)

print(f"Exported GLB to: {glb_lib}")
print(f"Exported GLB to: {glb_game}")
