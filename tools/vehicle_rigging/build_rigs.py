import bpy,bmesh,json,pathlib,math,sys,numpy as np
from mathutils import Matrix,Vector
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'work/vehicle_rigs';OUT.mkdir(parents=True,exist_ok=True)
S=json.loads((ROOT/'data/vehicles/imported_vehicle_profiles.json').read_text())
report={}
def bounds(obs):
    pts=[v.co for o in obs for v in o.data.vertices]
    return Vector(tuple(min(v[i] for v in pts) for i in range(3))),Vector(tuple(max(v[i] for v in pts) for i in range(3)))
def bake(o):
    mat=o.matrix_world.copy();m=o.data.copy();m.transform(mat)
    o.parent=None;o.matrix_world=Matrix.Identity(4);o.data=m
def split_components(o):
    bm=bmesh.new();bm.from_mesh(o.data)
    # glTF splits vertices at UV/normal seams; weld only position duplicates.
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00003)
    bmesh.ops.split_edges(bm,edges=[e for e in bm.edges if len({f.material_index for f in e.link_faces})>1])
    bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
    groups=[];seen=set()
    for v in bm.verts:
        if v.index in seen:continue
        stack=[v];seen.add(v.index);vs=[];faces=set()
        while stack:
            a=stack.pop();vs.append(a)
            faces.update(a.link_faces)
            for e in a.link_edges:
                b=e.other_vert(a)
                if b.index not in seen:seen.add(b.index);stack.append(b)
        if not faces:continue
        lo=Vector(tuple(min(v.co[i]for v in vs)for i in range(3)));hi=Vector(tuple(max(v.co[i]for v in vs)for i in range(3)))
        groups.append((list(faces),lo,hi))
    return bm,groups
def mesh_from_faces(bm,faces,name,mats):
    vs=list({v for f in faces for v in f.verts});indices={v:i for i,v in enumerate(vs)}
    m=bpy.data.meshes.new(name);m.from_pydata([v.co[:]for v in vs],[],[[indices[v]for v in f.verts]for f in faces])
    for mat in mats:m.materials.append(mat)
    for dst,src in zip(m.polygons,faces):dst.material_index=src.material_index;dst.use_smooth=src.smooth
    # Preserve material textures and their UVs when extracting wheel islands.
    for uv in bm.loops.layers.uv.values():
        layer=m.uv_layers.new(name=uv.name)
        for poly,src in zip(m.polygons,faces):
            for li,loop in zip(poly.loop_indices,src.loops):layer.data[li].uv=loop[uv].uv
    ob=bpy.data.objects.new(name,m);bpy.context.scene.collection.objects.link(ob);return ob
def run(id,s):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/vehicles'/id/(id+'.glb')))
    bpy.context.view_layer.update()
    obs=[o for o in bpy.context.scene.objects if o.type=='MESH' and 'shadow' not in o.name.lower()]
    # Capture all world transforms before clearing any hierarchy.
    worlds={o:o.matrix_world.copy()for o in obs}
    if id in ['tesla_model_x','can_am_maverick']:
        worlds={o:Matrix.Identity(4)for o in obs}
    for o in obs:
        m=o.data.copy();m.transform(worlds[o]);o.parent=None;o.matrix_world=Matrix.Identity(4);o.data=m
    for o in list(bpy.context.scene.objects):
        if o not in obs:bpy.data.objects.remove(o,do_unlink=True)
    if s.get('crop_pack'):
        lo,hi=bounds(obs);cut=lo.y+(hi.y-lo.y)*(.70 if id=='mercedes_sedan' else .70)
        for o in obs:
            bm=bmesh.new();bm.from_mesh(o.data)
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_center_median().y<cut],context='FACES')
            bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(o.data);bm.free()
        obs=[o for o in obs if o.data.polygons]
    # Remove overlapping duplicate XC40 variant; retain the complete first set.
    if id=='volvo_xc40':
        remove=[o for o in obs if o.name.endswith(('001','002','003')) and not o.name.endswith('Object001')]
        for o in remove:bpy.data.objects.remove(o,do_unlink=True)
        obs=[o for o in obs if o not in remove]
    lo,hi=bounds(obs)
    rotate=Matrix.Rotation(math.pi/2,4,'Z')if hi.x-lo.x>hi.y-lo.y else Matrix.Identity(4)
    if s.get('flip'):rotate=Matrix.Rotation(math.pi,4,'Z')@rotate
    for o in obs:o.data.transform(rotate)
    lo,hi=bounds(obs);span=hi-lo
    # Uniform scale preserves the source silhouette. Bad pack scale is corrected once here.
    scale=s['length']/span.y
    t=Matrix.Scale(scale,4)@Matrix.Translation(Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z)))
    for o in obs:o.data.transform(t)
    lo,hi=bounds(obs)
    if id in ['tesla_model_x','can_am_maverick','mercedes_sedan','range_rover_classic']:
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(id+'_normalized.blend')))
    # Wheel stations are extracted from actual named assemblies when available.
    r=s['radius'];track=s['track'];wb=s['wheelbase']
    centres=[Vector((x,yy,r))for yy in [-wb/2,wb/2]for x in [-track/2,track/2]]
    circular=[]
    for o in obs:
        bm,parts=split_components(o)
        for fs,pl,ph in parts:
            dim=ph-pl;at=(pl+ph)/2
            if dim.z>r*1.05 and dim.y>r*1.05 and .65<dim.y/max(dim.z,.0001)<1.5 and dim.z<r*3 and dim.x<s['width']*.32 and abs(at.x)>(hi.x-lo.x)*.25 and at.z<r*1.8:
                circular.append(dict(at=at,lo=pl,hi=ph,faces=len(fs)))
        bm.free()
    for i,c in enumerate(centres):
        options=[v for v in circular if v['at'].x*c.x>0 and v['at'].y*c.y>0]
        if options:
            best=max(options,key=lambda v:v['faces'])
            centres[i]=best['at']
    print('CENTRES',id,[[round(x,3)for x in c]for c in centres], 'CIRCULAR',len(circular), 'DIMS',[round(x,3)for x in hi-lo],flush=True)
    if id=='scania_haul_truck':
        stations=[]
        for v in sorted(circular,key=lambda v:v['at'].y):
            if not stations or abs(v['at'].y-stations[-1])>.3:stations.append(v['at'].y)
        resolved=[]
        for station in stations:
            for side in [-1,1]:
                options=[v for v in circular if v['at'].x*side>0 and abs(v['at'].y-station)<.3]
                if options:resolved.append(max(options,key=lambda v:v['faces'])['at'])
        if len(resolved)>=4:
            centres=resolved[:2]+resolved[-2:]+resolved[2:-2]
    groups=[[]for _ in range(1+len(centres))];counts=[0]*len(centres);notes=[]
    for o in obs:
        bm,parts=split_components(o)
        fs=[[]for _ in range(1+len(centres))]
        for faces,pl,ph in parts:
            size=ph-pl;at=(pl+ph)/2
            assigned=0
            for i,c in enumerate(centres):
                dist=((at.y-c.y)**2+(at.z-c.z)**2)**.5
                # Whole disconnected tire/rim islands only, never slice through body panels.
                if abs(at.x-c.x)<max(.25,s['width']*.17)and dist<r*.55 and size.y<r*2.9 and size.z<r*2.9 and size.x<s['width']*.42 and ph.z<max(c.z+r*1.5,r*2.5):
                    assigned=i+1;break
            fs[assigned].extend(faces)
        for index,faces in enumerate(fs):
            if not faces:continue
            ob=mesh_from_faces(bm,faces,f'{id}_{index}_{o.name}',list(o.data.materials))
            groups[index].append(ob)
        bm.free();bpy.data.objects.remove(o,do_unlink=True)
    for i in range(len(centres)):
        parts=groups[i+1]
        if not parts:raise RuntimeError('No actual wheel geometry extracted at '+str(i))
        wl,wh=bounds(parts);centre=(wl+wh)/2
        # Radial bounds reflect actual tire geometry, not a generic replacement wheel.
        counts[i]=sum(len(o.data.polygons)for o in parts)
    # Keep axle midpoint at origin so handling and collision match the rig.
    axle_y=sum(c.y for c in centres[:4])/4
    shift=Vector((0,-axle_y,0))
    for o in groups[0]:o.data.transform(Matrix.Translation(shift))
    for c in centres:c.y-=axle_y
    names=['Body','Wheel_FL','Wheel_FR','Wheel_RL','Wheel_RR']+['ExtraWheel'+str(i) for i in range(len(centres)-4)]
    for index,parts in enumerate(groups):
        parent=bpy.data.objects.new(names[index],None);bpy.context.scene.collection.objects.link(parent)
        for o in parts:
            if index:
                c=centres[index-1]-shift
                o.data.transform(Matrix.Rotation(math.pi/2,4,'Y')@Matrix.Translation(-c))
            o.parent=parent
            # Recalculate inconsistent source normals without changing shape.
            bm=bmesh.new();bm.from_mesh(o.data)
            bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.000001)
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
    # Consolidate draw calls within each assembly by material (join keeps UV/material data).
    for index,parts in enumerate(groups):
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join();parts[0].name=names[index]+'_Mesh'
    for index in range(5,len(groups)):
        c=centres[index-1]
        bpy.data.objects[names[index]].matrix_world=Matrix.Translation(c)@Matrix.Rotation(-math.pi/2,4,'Y')
    bpy.context.view_layer.update()
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons)for o in bpy.context.scene.objects if o.type=='MESH')
    # The imported vehicle budget is 50k total, including its own wheels.
    if tris>50000:
        ratio=49000/tris
        for o in list(bpy.context.scene.objects):
            if o.type!='MESH':continue
            bpy.context.view_layer.objects.active=o
            mod=o.modifiers.new('MobileBudget','DECIMATE');mod.ratio=ratio;mod.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=mod.name)
    for material in bpy.data.materials:
        if not material.node_tree:continue
        glass=any(w in material.name.lower()for w in ['glass','window','windwos','windscreen','стекло'])
        for node in material.node_tree.nodes:
            if node.type!='BSDF_PRINCIPLED':continue
            alpha=node.inputs.get('Alpha')
            if not glass:
                for link in list(alpha.links):material.node_tree.links.remove(link)
                alpha.default_value=1
            elif 'red'not in material.name.lower() and 'light'not in material.name.lower():
                for link in list(alpha.links):material.node_tree.links.remove(link)
                alpha.default_value=.28
    bpy.ops.object.select_all(action='SELECT')
    path=OUT/(id+'_rig.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_cameras=False,export_lights=False,export_animations=False)
    s.update(rig_path='res://assets/models/vehicles/'+id+'/'+path.name,wheel_centres=[[round(c.x,5),round(c.z,5),round(-c.y,5)]for c in centres],actual_dimensions=[round(hi.x-lo.x,4),round(hi.z-lo.z,4),s['length']],axle_shift=round(axle_y,5))
    report[id]=dict(wheel_faces=counts,source_dimensions=[float(x)for x in span],dimensions=s['actual_dimensions'],bytes=path.stat().st_size,triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons)for o in bpy.context.scene.objects if o.type=='MESH'))
    (OUT/'rigged_profiles.json').write_text(json.dumps(S,indent=2))
    (OUT/'rig_report.json').write_text(json.dumps(report,indent=2))
    print('RIGGED',id,report[id],flush=True)
for id,s in S.items():
    if '--' in sys.argv and id not in sys.argv[sys.argv.index('--')+1:]:continue
    try:run(id,s)
    except Exception as e:
        print('RIG_FAILED',id,str(e),flush=True)
        import traceback;traceback.print_exc()
