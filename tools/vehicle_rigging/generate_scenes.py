import json,pathlib,math,re
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'work/vehicle_scene_staging'
specs=json.loads((ROOT/'data/vehicles/imported_vehicle_profiles.json').read_text())
def write(p,s):
    p=OUT/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def vec(v):return 'Vector3('+', '.join(str(round(float(x),5))for x in v)+')'
for id,s in specs.items():
    if not pathlib.Path('/private/tmp/mana_rigs',id+'_rig.glb').exists():continue
    centres=s['wheel_centres'];radius=sum(c[1]for c in centres[:4])/4
    length=s['length'];width,height,_=s['actual_dimensions']
    heavy=s['kind']in ['bus','truck'];offroad=s['kind']in ['offroad','buggy']
    sport=s['mass']<1700 and s['torque']>330 and height<1.6
    electric=s['kind']=='electric';diesel=s.get('diesel',False)
    idle=1 if electric else 650 if heavy else 900 if s['redline']>8500 else 750
    red=s['redline'];peak=s.get('peak_rpm',red*.45 if not heavy else red*.55);torque=s['torque']
    if electric:curve=[(0,torque),(4000,torque),(8000,torque*.5),(red,torque*.2)]
    else:curve=[(idle,torque*.36),(max(idle+200,peak*.55),torque*.78),(peak,torque),(max(peak+1,red*.78),torque*.95),(red,torque*.58)]
    curve.sort()
    seatx=width*.19;seaty=max(.28,min(height-.72,.5 if sport else height*.39))
    seatz=sum(c[2]for c in centres[:2])/2-(1.0 if not heavy else .3)
    if heavy:seaty=1.4;seatz=length*.34
    hip=s.get('seat_hip',[seatx,seaty,seatz]);pedal=s.get('pedal_point',[seatx,max(.12,seaty-.35),seatz+.65])
    measured={}
    name=''.join(part.title()for part in id.split('_'))
    audio='electric_motor_audio.gd'if electric else '../player/engine_sound.gd'
    audio_path='res://scripts/vehicle/electric_motor_audio.gd'if electric else'res://scripts/player/engine_sound.gd'
    text=f'''[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="res://scripts/vehicle/imported_vehicle.gd" id="1"]
[ext_resource type="Script" path="res://scripts/camera/camera_controller.gd" id="2"]
[ext_resource type="PackedScene" path="{s['rig_path']}" id="3"]
[ext_resource type="Script" path="{audio_path}" id="4"]
[ext_resource type="Script" path="res://scripts/player/drivetrain_profile.gd" id="5"]

[sub_resource type="Resource" id="Drivetrain"]
script = ExtResource("5")
gear_ratios = Array[float]({s['gears']})
reverse_ratio = {s['gears'][0] if electric else 3.2}
final_drive = {s.get('final_drive',3.5)}
driveline_efficiency = {0.94 if electric else 0.88}
automatic_available = true
electric_motor = {str(electric).lower()}
shift_time = {0.0 if electric else .12 if sport else .3}
idle_rpm = {float(idle)}
redline_rpm = {float(red)}
torque_curve = Array[Vector2]([{', '.join('Vector2(%s, %s)'%(round(x,2),round(y,2))for x,y in curve)}])
launch_rpm = {float(0 if electric else 1700 if heavy else 2600 if sport else 1900)}
launch_torque_ratio = {1.0 if electric or sport else 1.4}
cylinders = {s['cylinders']}
diesel_clatter = {0.5 if diesel else 0.0}
turbo_whine = {0.0 if electric else 0.04}

[sub_resource type="BoxShape3D" id="BodyCollision"]
size = {vec([width*.87,max(.6,height-.25),length*.93])}

[node name="{name}" type="RigidBody3D" groups=["enterable_vehicle"]]
script = ExtResource("1")
vehicle_id = "{id}"
vehicle_mass = {float(s['mass'])}
wheel_radius = {round(radius,5)}
suspension_rest_length = {round(.9-radius,5)}
suspension_bump_travel = {0.22 if offroad else .16 if heavy else .1 if sport else .14}
suspension_droop_travel = {0.25 if offroad else .17 if heavy else .12 if sport else .18}
suspension_frequency = {1.25 if heavy else 1.4 if offroad else 2.1 if sport else 1.6}
suspension_damping_ratio = {0.6 if heavy else .52}
center_of_mass_height = {round(.6 if heavy else .55 if offroad else max(.3,min(.6,height*.32)),3)}
center_of_mass_forward = {-.12 if id in ['porsche_boxster','lamborghini_aventador_svj','lamborghini_diablo_sv','ford_mustang_mach_40']else .1}
braking_acceleration = {6.5 if heavy else 10.5 if sport else 9.2}
drag_area = {round(width*height*(.62 if heavy else .4 if offroad else .31),3)}
rolling_resistance = {0.02 if offroad else .012}
tyre_friction = {1.25 if heavy else 1.65 if sport else 1.45}
max_steer_angle = {0.52 if heavy else .61}
high_speed_steer_share = {0.17 if heavy else .23}
rear_wheel_drive = {str(s['drive']=='rwd').lower()}
front_wheel_drive = {str(s['drive']=='fwd').lower()}
front_drive_share = {0.33 if id=='alfa_romeo_155_v6' else .4 if s['drive']=='awd'else .5}
seat_hip = {vec(hip)}
pedal_point = {vec(pedal)}
entry_half_width = {round(width*.5,3)}
left_hand_grip = {vec([hip[0]+.17,hip[1]+.4,hip[2]+.42])}
right_hand_grip = {vec([hip[0]-.17,hip[1]+.4,hip[2]+.42])}
drivetrain = SubResource("Drivetrain")

[node name="Chassis" type="Node3D" parent="."]

[node name="FrontIndicator" type="Marker3D" parent="Chassis"]
position = {vec([0,.4,length*.5])}
'''
    for i,n in enumerate(['FrontLeft','FrontRight','RearLeft','RearRight']):
        text+=f'\n[node name="{n}Wheel" type="Node3D" parent="."]\nposition = {vec(centres[i])}\nrotation = Vector3(0, 0, 1.5707963)\n'
    text+=f'''
[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BodyCollision")
position = {vec([0,(height-.25)*.5+.12,0])}

[node name="Model" parent="." instance=ExtResource("3")]

[node name="CameraPivot" type="Node3D" parent="."]
position = {vec([0,height+.25,0])}
script = ExtResource("2")
first_person_offset = {vec([hip[0],hip[1]+.68,hip[2]+.1])}
first_person_follows_body = true
first_person_min_pitch = -0.6
first_person_max_pitch = 0.5

[node name="SpringArm3D" type="SpringArm3D" parent="CameraPivot"]
spring_length = {max(5.5,length*1.25)}
collision_mask = 1
margin = 0.2

[node name="Camera3D" type="Camera3D" parent="CameraPivot/SpringArm3D"]
fov = 68.0

[node name="EngineAudio" type="AudioStreamPlayer3D" parent="."]
script = ExtResource("4")
'''
    existing=(ROOT/'scenes/vehicles/imported')/(id+'.tscn')
    if existing.exists():
        limit=re.search(r'^road_speed_limit = (.+)$',existing.read_text(),re.M)
        if limit:text=text.replace('vehicle_id = "'+id+'"','vehicle_id = "'+id+'"\nroad_speed_limit = '+limit.group(1))
    write(pathlib.Path('scenes/vehicles/imported')/(id+'.tscn'),text)
    s['seat_hip']=hip;s['pedal_point']=pedal;s['seat_measurement_status']='modelled steering-wheel measurement and rendered seat fit'if id in measured else s.get('seat_measurement_status','initial bounds-based fit; visual validation required')
write(pathlib.Path('data/vehicles/imported_vehicle_profiles.json'),json.dumps(specs,indent=2)+'\n')
write(pathlib.Path('scripts/vehicle/imported_vehicle.gd'),(ROOT/'scripts/vehicle/imported_vehicle.gd').read_text())
write(pathlib.Path('scripts/vehicle/electric_motor_audio.gd'),(ROOT/'scripts/vehicle/electric_motor_audio.gd').read_text())
print('Generated',len(list((OUT/'scenes/vehicles/imported').glob('*.tscn'))),'vehicle scenes')
