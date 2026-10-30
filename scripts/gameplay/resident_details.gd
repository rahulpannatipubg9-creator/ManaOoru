extends RefCounted
const Assets := preload("res://scripts/gameplay/city_assets.gd")
static func dress(resident: Node3D, index: int) -> void:
	var hair := Assets.box(resident,Vector3(0,1.98,0),Vector3(.43,.13,.4),Color("24201c"))
	hair.name = "Hair"
	if index % 3 == 0:
		Assets.cylinder(resident,Vector3(0,2.06,0),.27,.1,Color("c9ad7d"))
	if index % 3 == 1:
		Assets.box(resident,Vector3(.25,1.0,-.15),Vector3(.12,.42,.32),Color("ad7142"))
	if index % 3 == 2:
		Assets.box(resident,Vector3(0,1.27,-.19),Vector3(.5,.14,.07),Color("e5ab48"))
	for x in [-.09,.09]:
		Assets.box(resident,Vector3(x,1.88,.245),Vector3(.045,.04,.02),Color("21262b"))
	# Minor size variation keeps the same ground origin and shared animation rig.
	resident.scale *= 0.94 + (index % 4) * .025
static func officer(parent: Node3D) -> Node3D:
	var person := load("res://scenes/world/pedestrian.tscn").instantiate() as Node3D
	person.idle_mode = true
	person.shirt_color = Color("b89f72")
	person.pants_color = Color("8f7955")
	parent.add_child(person)
	person.set_process(false)
	Assets.box(person,Vector3(.12,1.23,.24),Vector3(.08,.1,.02),Color("d4b04b"))
	return person
