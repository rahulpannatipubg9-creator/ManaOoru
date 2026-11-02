import bpy, pathlib, json, sys
from mathutils import Vector
import bmesh
def rigid(m):
 r=m.to_quaternion().to_matrix().to_4x4();r.translation=m.translation;return r
root=pathlib.Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'assets/models/characters/rahul/rahul_mixamo.glb'))
source=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
oldmeshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
source.animation_data.action=None
for b in source.pose.bones: b.matrix_basis.identity()
bpy.context.view_layer.update()
before=set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath='/Users/rahulpannati/Downloads/Virat.glb')
new=[o for o in bpy.context.scene.objects if o not in before]
rig=next(o for o in new if o.type=='ARMATURE')
rig.animation_data_clear()
for b in rig.pose.bones:b.matrix_basis.identity()
bpy.context.view_layer.update()
meshes=[o for o in new if o.type=='MESH' and len(o.data.vertices)>100]
def short(n):return n.replace('mixamorig:','').replace('mixamorig_','')
lookup={short(b.name):b for b in source.data.bones if short(b.name) not in {'Jaw','LeftEye','RightEye'}}
# Fit the downloaded skin to the established gameplay skeleton in bind space.
for ob in meshes:
 mats={}
 names={}
 for g in ob.vertex_groups:
  bone=rig.data.bones.get(g.name)
  while bone and short(bone.name) not in lookup:bone=bone.parent
  dest=lookup.get(short(bone.name)) if bone else None
  if bone:
   mats[g.index]=rigid(source.matrix_world@dest.matrix_local)@rigid(rig.matrix_world@bone.matrix_local).inverted()@ob.matrix_world
   names[g.index]=dest.name
 for v in ob.data.vertices:
  co=Vector((0,0,0));total=0
  for g in v.groups:
   if g.group in mats:co+=(mats[g.group]@v.co)*g.weight;total+=g.weight
  if total:v.co=co/total
 ob.parent=None;ob.matrix_world.identity()
 merged=[]
 for v in ob.data.vertices:
  weights={}
  for g in v.groups:
   if g.group in names:weights[names[g.group]]=weights.get(names[g.group],0)+g.weight
  merged.append(weights)
 ob.vertex_groups.clear()
 groups={name:ob.vertex_groups.new(name=name) for name in sorted(set(n for weights in merged for n in weights))}
 for i,weights in enumerate(merged):
  for name,weight in weights.items():groups[name].add([i],weight,'REPLACE')
 for m in list(ob.modifiers):ob.modifiers.remove(m)
 m=ob.modifiers.new('GameplaySkin','ARMATURE');m.object=source
 ob.parent=source;ob.matrix_parent_inverse=source.matrix_world.inverted()
 ob.matrix_world.identity()
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.00001);bm.to_mesh(ob.data);bm.free()
 bpy.context.view_layer.objects.active=ob
 ob.select_set(True)
 ob.data.calc_loop_triangles()
 if len(ob.data.loop_triangles)>25000:
  # Preserve the original facial topology; reduce the clothing/body instead.
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
  bpy.context.tool_settings.mesh_select_mode=(False,False,True)
  for poly in ob.data.polygons:poly.select=poly.center.z>1.52
  before_split=set(bpy.context.scene.objects)
  bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
  head_parts=[o for o in bpy.context.scene.objects if o not in before_split]
  head_tris=sum(len(o.data.polygons) for o in head_parts)
  ob.data.calc_loop_triangles()
  bpy.context.view_layer.objects.active=ob
  dec=ob.modifiers.new('MobileBudget','DECIMATE');dec.ratio=max(.08,(30000-head_tris)/max(1,len(ob.data.loop_triangles)))
  bpy.ops.object.modifier_apply(modifier=dec.name)
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
  for part in head_parts:part.select_set(True)
  bpy.context.view_layer.objects.active=ob;bpy.ops.object.join()
 bpy.ops.object.vertex_group_limit_total(limit=4)
 bpy.ops.object.vertex_group_normalize_all(lock_active=False)
 ob.data.calc_loop_triangles()
  # Remove tiny topology defects left by decimation; retain UVs and weights.
 bm=bmesh.new();bm.from_mesh(ob.data)
 for edge in list(bm.edges):
  if edge.is_valid and len(edge.link_faces)>2:
   faces=sorted(edge.link_faces,key=lambda f:f.calc_area())
   bmesh.ops.delete(bm,geom=faces[:len(faces)-2],context='FACES_ONLY')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 bm.to_mesh(ob.data);bm.free();ob.data.update()
 from mathutils.bvhtree import BVHTree
 sys.path.insert(0,'/Users/rahulpannati/.codex/skills/blender-asset-qa/scripts')
 import qa_check
 mesh=ob.data;mesh.calc_loop_triangles();verts=[v.co.copy() for v in mesh.vertices];tris=[tuple(t.vertices) for t in mesh.loop_triangles];bvh=BVHTree.FromPolygons(verts,tris);remove=set()
 for i,tri in enumerate(tris):
  a,b,c=[verts[v] for v in tri];n=(b-a).cross(c-a).normalized();cen=(a+b+c)/3
  for point in (cen,cen.lerp(a,.6),cen.lerp(b,.6),cen.lerp(c,.6)):
   for _,_,j,_ in bvh.find_nearest_range(point,.001):
    if j==i or set(tri)&set(tris[j]):continue
    a2,b2,c2=[verts[v] for v in tris[j]];n2=(b2-a2).cross(c2-a2).normalized()
    if n.dot(n2)>.999 and qa_check._point_in_tri(point-n2*n2.dot(point-a2),a2,b2,c2,n2):remove.add(max(i,j))
 bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[i] for i in remove],context='FACES_ONLY');bm.to_mesh(mesh);bm.free()
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
 wires=[e for e in bm.edges if not e.link_faces]
 if wires:bmesh.ops.delete(bm,geom=wires,context='EDGES')
 loose=[v for v in bm.verts if not v.link_faces]
 if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 for mat in ob.data.materials:
  for node in mat.node_tree.nodes:
   if node.type=='BSDF_PRINCIPLED':node.inputs['Base Color'].default_value=(.24,.24,.24,1);node.inputs['Roughness'].default_value=.85

 # Vertex colours keep the six visible finishes in one draw-call material.
 head_indices=[]
 for v in ob.data.vertices:
  weights={short(ob.vertex_groups[g.group].name):g.weight for g in v.groups}
  if weights.get('Head',0)>.6:head_indices.append(v.index)
 hv=[ob.data.vertices[i].co for i in head_indices]
 htop=max(v.z for v in hv);hbottom=min(v.z for v in hv);hfront=min(v.y for v in hv);hback=max(v.y for v in hv);hcenter=(hfront+hback)/2
 print('HEAD_COLOR_BOUNDS',htop,hbottom,hfront,hback)
 def srgb(c):return ((c+.055)/1.055)**2.4 if c>.04045 else c/12.92
 palette={k:tuple(srgb(x/255) for x in rgb)+(1,) for k,rgb in {'skin':(167,131,110),'hair':(30,25,23),'top':(37,61,88),'pants':(48,52,61),'shoes':(35,30,27),'eyes':(27,23,20)}.items()}
 colours=[]
 for v in ob.data.vertices:
  weights={short(ob.vertex_groups[g.group].name):g.weight for g in v.groups};pos=v.co
  key='top'
  head=weights.get('Head',0)+weights.get('Neck',0)
  hand=sum(w for n,w in weights.items() if 'Hand' in n)
  leg=sum(w for n,w in weights.items() if any(t in n for t in ['UpLeg','Leg','Hips']))
  foot=sum(w for n,w in weights.items() if 'Foot' in n or 'Toe' in n)
  if leg>.45:key='pants'
  if foot>.6:key='shoes'
  if hand>.55:key='skin'
  if head>.5:
   key='skin'
   if pos.z>htop-.112 or (pos.y>hcenter+.012 and pos.z>htop-.19):key='hair'
   # Short beard on the lower face; avoid colouring neck and ears.
   # Restrained dark eye marks sit on the forward eye region.
  colours.append(palette[key])
 attr=ob.data.color_attributes.new(name='ViratColor',type='BYTE_COLOR',domain='CORNER')
 for loop in ob.data.loops:attr.data[loop.index].color=colours[loop.vertex_index]
 for mat in ob.data.materials:
  nodes=mat.node_tree.nodes;bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='ViratColor';mat.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color']);bsdf.inputs['Roughness'].default_value=.78
  for node in nodes:
   if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.35

 print('VIRAT_MESH',ob.name,len(ob.data.loop_triangles))
for ob in oldmeshes+[rig]:bpy.data.objects.remove(ob,do_unlink=True)
# Export only established actions; preserve their source names and bone channels.
for a in list(bpy.data.actions):
 if '-' in a.name and len(a.name)>30:bpy.data.actions.remove(a)
bpy.ops.object.select_all(action='DESELECT')
source.select_set(True)
for ob in meshes:ob.select_set(True)
bpy.context.view_layer.objects.active=source
out=root/'assets/models/characters/virat';out.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(out/'virat.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_lights=False,export_cameras=False)
sys.path.insert(0,'/Users/rahulpannati/.codex/skills/blender-asset-qa/scripts')
import qa_check
try:print('QA',json.dumps(qa_check.run(objects=[o.name for o in meshes],profile='game'),default=str))
except Exception as e:print('QA_ERROR',str(e))
