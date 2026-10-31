import bpy,math,pathlib,json,sys
from mathutils import Vector,Matrix
bpy.ops.wm.read_factory_settings(use_empty=True)
parts={'BikeBody':[],'FrontWheelMesh':[],'RearWheelMesh':[],'Handlebars':[]}
def mat(name,color,metal=0,rough=.4):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);n=m.node_tree.nodes.get('Principled BSDF');n.inputs['Base Color'].default_value=(*color,1);n.inputs['Metallic'].default_value=metal;n.inputs['Roughness'].default_value=rough;return m
paint=mat('Bullet_MilitaryGreen',(.045,.075,.055),0,.28);black=mat('Bullet_FrameBlack',(.012,.016,.018),0,.35);rubber=mat('Bullet_TyreRubber',(.012,.014,.015),0,.85);chrome=mat('Bullet_Chrome',(.65,.69,.72),1,.22);alloy=mat('Bullet_EngineAlloy',(.28,.30,.32),1,.38);seat=mat('Bullet_BlackLeather',(.018,.014,.012),0,.75);lens=mat('Bullet_HeadlampLens',(.76,.73,.58),0,.16);red=mat('Bullet_TailLamp',(.3,.005,.003),0,.2);amber=mat('Bullet_Indicators',(.55,.12,.005),0,.25)
def register(o,name,material,group):
 o.name=name;o.data.materials.append(material);parts[group].append(o)
 for f in o.data.polygons:f.use_smooth=True
 return o
def ball(name,at,size,material,group='BikeBody'):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=at);o=bpy.context.object;o.scale=size;return register(o,name,material,group)
def box(name,at,size,material,group='BikeBody',bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=at);o=bpy.context.object;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('RoundedEdges','BEVEL');mod.width=bevel;mod.segments=3;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return register(o,name,material,group)
def tube(name,a,b,r,material,group='BikeBody',segments=16):
 a,b=Vector(a),Vector(b);delta=b-a;bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=delta.length,location=(a+b)/2);o=bpy.context.object;o.rotation_euler=delta.to_track_quat('Z','Y').to_euler();return register(o,name,material,group)
def torus(name,at,major,minor,material,group,rotation=(0,math.pi/2,0)):
 bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=at,rotation=rotation,major_radius=major,minor_radius=minor);return register(bpy.context.object,name,material,group)
# Two genuine spoked wheel assemblies, in the same local axle frame as the car rigs.
for group,y in [('FrontWheelMesh',-.695),('RearWheelMesh',.695)]:
 c=Vector((0,y,.335));torus(group+'_Tyre',c,.286,.049,rubber,group);torus(group+'_Rim',c,.246,.014,chrome,group)
 tube(group+'_Hub',(-.055,y,.335),(.055,y,.335),.065,alloy,group,24)
 for side in [-1,1]:
  for i in range(18):
   a=math.tau*i/18;b=math.tau*(i+1)/18
   tube('Spoke',(side*.038,y+.054*math.sin(a),.335+.054*math.cos(a)),(side*.008,y+.239*math.sin(b),.335+.239*math.cos(b)),.0023,chrome,group,6)
 # Brake rotor and caliper.
 torus('BrakeRotor',( .064,y,.335),.105,.014,alloy,group)
 box('Caliper',(.08,y+.075,.37),(.035,.065,.06),black,group,.008)
 for o in parts[group]:
  bpy.context.view_layer.update();o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);o.data.transform(Matrix.Rotation(math.pi/2,4,'Y')@Matrix.Translation(-c))
# Double-cradle frame and swing arm.
for x in [-.095,.095]:
 for a,b in [((x,-.41,.80),(x,-.25,.25)),((x,-.25,.25),(x,.43,.25)),((x,.43,.25),(x,.43,.74)),((x,.43,.74),(x,-.41,.80)),((x,.43,.25),(x,.695,.335))]:tube('TubularFrame',a,b,.018,black)
 tube('RearShock',(x*1.5,.68,.36),(x*1.5,.34,.77),.026,chrome)
 for z in [.46,.49,.52,.55,.58,.61,.64,.67]:torus('ShockSpring',(x*1.5,.68-(z-.36)/.41*.34,z),.029,.006,black,'BikeBody',rotation=(0,0,0))
# Teardrop tank, two saddle pads, side boxes and engine.
tank=ball('FuelTank',(0,-.16,.885),(.19,.32,.17),paint)
box('RiderSaddle',(0,.19,.785),(.34,.34,.085),seat,bevel=.04)
box('PillionSeatMount',(0,.53,.75),(.24,.3,.08),black,bevel=.01)
box('PillionSaddle',(0,.53,.82),(.31,.27,.08),seat,bevel=.04)
for x in [-.16,.16]:ball('SideCover',(x,.22,.59),(.065,.15,.16),paint)
ball('Crankcase',(0,-.03,.40),(.16,.19,.15),alloy)
tube('EngineCylinder',(0,-.11,.46),(0,-.11,.70),.085,alloy,segments=24)
for z in [.49,.515,.54,.565,.59,.615,.64]:box('CylinderCoolingFin',(0,-.11,z),(.25,.20,.012),alloy,bevel=.004)
box('CylinderHead',(0,-.1,.68),(.22,.20,.065),alloy,bevel=.018)
tube('SparkPlug',(0,-.10,.72),(0,-.08,.75),.012,chrome)
# Curved fenders as a thin arc shell.
for y in [-.695,.695]:
 vs=[];fs=[]
 for i in range(25):
  angle=math.pi*(.12+.76*i/24)
  for x in [-.085,.085]:vs.append((x,y+.355*math.cos(angle),.335+.355*math.sin(angle)))
 for i in range(24):fs.append((i*2,i*2+1,i*2+3,i*2+2))
 mesh=bpy.data.meshes.new('Mudguard');mesh.from_pydata(vs,[],fs);o=bpy.data.objects.new('Mudguard',mesh);bpy.context.scene.collection.objects.link(o);register(o,'Mudguard',paint,'Handlebars' if y<0 else 'BikeBody');mod=o.modifiers.new('MetalThickness','SOLIDIFY');mod.thickness=.008;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
for x in [-.085,.085]:tube('FrontFenderStay',(x,-.695,.335),(x,-.695,.69),.006,chrome,'Handlebars')
# Forks, headlamp and handlebar all steer as one assembly.
for x in [-.07,.07]:
 tube('ForkSlider',(x,-.695,.335),(x,-.55,.73),.026,chrome,'Handlebars')
 tube('ForkUpper',(x,-.55,.73),(x,-.43,.98),.021,black,'Handlebars')
tube('ForkCrown',(-.105,-.46,.91),(.105,-.46,.91),.027,alloy,'Handlebars')
tube('HeadlampHousing',(0,-.51,.91),(0,-.65,.91),.104,chrome,'Handlebars',32)
tube('HeadlampGlass',(0,-.649,.91),(0,-.66,.91),.094,lens,'Handlebars',32)
bar=[(-.365,-.17,.99),(-.24,-.2,1.03),(-.12,-.44,1.03),(.12,-.44,1.03),(.24,-.2,1.03),(.365,-.17,.99)]
for a,b in zip(bar,bar[1:]):tube('Handlebar',a,b,.012,chrome,'Handlebars')
for side in [-1,1]:
 tube('RubberGrip',(side*.26,-.19,1.02),(side*.365,-.17,.99),.019,rubber,'Handlebars')
 tube('MirrorStem',(side*.26,-.30,1.03),(side*.31,-.35,1.19),.007,chrome,'Handlebars')
 ball('Mirror',(side*.31,-.35,1.19),(.065,.014,.04),chrome,'Handlebars')
 tube('IndicatorStem',(side*.07,-.53,.86),(side*.20,-.53,.86),.009,chrome,'Handlebars');ball('Indicator',(side*.20,-.55,.86),(.025,.028,.025),amber,'Handlebars')
tube('InstrumentMount',(0,-.44,1.03),(0,-.39,1.0),.012,black,'Handlebars')
tube('Speedometer',(0,-.39,1.0),(0,-.39,1.04),.047,black,'Handlebars',24)
# Right-side exhaust, footrests, brake pedal and tail lighting.
for a,b in [((.15,-.15,.60),(.20,-.4,.42)),((.20,-.4,.42),(.24,-.15,.24)),((.24,-.15,.24),(.24,.62,.24))]:tube('Exhaust',a,b,.025,chrome)
tube('Silencer',(.24,.25,.24),(.24,.88,.24),.047,chrome,segments=24)
for side in [-1,1]:tube('Footpeg',(side*.12,.02,.32),(side*.24,.02,.32),.017,rubber)
tube('RearLampMount',(0,.69,.7),(0,.85,.66),.02,black);box('RearLight',(0,.855,.69),(.12,.035,.06),red,bevel=.012)
tube('PlateBracket',(0,.85,.66),(0,.88,.57),.012,black)
box('NumberPlate',(0,.88,.57),(.18,.015,.11),black,bevel=.005)
# Consolidate each rigid assembly and preserve an editable native source.
for group,objects in parts.items():
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join();o=bpy.context.object;o.name=group
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 if group=='Handlebars':o.data.transform(Matrix.Translation(Vector((0,.35,-.75))))
 # Remove accidental degenerate faces and recalculate normals after joining.
 import bmesh
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-6);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
bpy.ops.wm.save_as_mainfile(filepath=str(pathlib.Path(__file__).resolve().parents[2]/'work/vehicle_rigs/bullet_clean.blend'))
bpy.ops.export_scene.gltf(filepath=str(pathlib.Path(__file__).resolve().parents[2]/'work/vehicle_rigs/bullet_rig.glb'),export_format='GLB',export_animations=False,export_lights=False,export_cameras=False)
print('CLEAN_BULLET_TRIS',sum(sum(len(f.vertices)-2 for f in o.data.polygons)for o in bpy.context.scene.objects if o.type=='MESH'),flush=True)
