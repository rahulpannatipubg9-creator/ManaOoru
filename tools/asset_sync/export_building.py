import bpy, sys, json
from mathutils import Vector
args=sys.argv[sys.argv.index('--')+1:]
output, metadata=args
# Prefer the named theatre scene over the preserved startup scene.
scenes=list(bpy.data.scenes)
scene=bpy.context.scene
bpy.context.window.scene=scene
bpy.ops.object.select_all(action='DESELECT')
objects=[o for o in scene.objects if o.type in {'MESH','FONT','CURVE','SURFACE'} and not o.hide_render]
for o in objects:
 o.hide_set(False); o.select_set(True)
if not objects: raise RuntimeError('No exportable geometry')
points=[o.matrix_world @ Vector(p) for o in objects for p in o.bound_box]
lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
bpy.ops.export_scene.gltf(filepath=output,export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
with open(metadata,'w') as f: json.dump({'scene':scene.name,'objects':len(objects),'bounds_blender':{'min':lo,'max':hi},'triangles_source':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH'),'placement':'review_only','dimensions_estimated':True},f,indent=2)
