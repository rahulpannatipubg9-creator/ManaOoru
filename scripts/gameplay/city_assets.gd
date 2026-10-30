extends RefCounted
## Original reusable low-poly assets; no external downloads or dependencies.
static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

static func label(parent: Node3D, text: String, at: Vector3, size := 30) -> void:
	var node := Label3D.new()
	node.text = text
	node.position = at
	node.font_size = size
	node.pixel_size = 0.007
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.visibility_range_end = 80
	parent.add_child(node)

static func vehicle(parent: Node3D, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize() + "Visual"
	parent.add_child(root)
	var white := Color("e0e5e7")
	var dark := Color("202b37")
	box(root, Vector3(0,.65,0), Vector3(1.8,.65,3.8), white)
	box(root, Vector3(0,1.25,-.2), Vector3(1.65,.7,2.4), white if kind == "ambulance" else dark)
	box(root, Vector3(0,1.35,1.02), Vector3(1.45,.5,.04), Color("496d80"))
	for x in [-.95,.95]:
		for z in [-1.15,1.15]:
			var wheel := cylinder(root, Vector3(x,.4,z), .35,.2,Color("16191b"))
			wheel.rotation.z = PI/2
	for x in [-.6,.6]:
		box(root, Vector3(x,.83,1.93),Vector3(.4,.2,.05),Color("ffe8a5"))
		box(root, Vector3(x,.8,-1.93),Vector3(.3,.15,.05),Color("af2525"))
	if kind in ["police", "ambulance"]:
		box(root,Vector3(0,1.85,0),Vector3(1.2,.14,.25),dark)
		box(root,Vector3(-.4,1.95,0),Vector3(.4,.15,.25),Color.RED)
		box(root,Vector3(.4,1.95,0),Vector3(.4,.15,.25),Color.BLUE)
		for side in [-1,1]:
			box(root,Vector3(side*.92,.9,0),Vector3(.04,.22,3.2),Color("c63333") if kind == "ambulance" else Color("33559a"))
		if kind == "ambulance":
			box(root,Vector3(0,1.35,-1.43),Vector3(.5,.12,.04),Color("bd2828"))
			box(root,Vector3(0,1.35,-1.44),Vector3(.12,.5,.04),Color("bd2828"))
	label(root,kind.to_upper(),Vector3(0,2.2,0))
	return root

static func stretcher(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "PatientStretcher"
	parent.add_child(root)
	box(root,Vector3(0,.55,0),Vector3(.75,.12,1.9),Color("2e8793"))
	for x in [-.38,.38]:
		box(root,Vector3(x,.55,0),Vector3(.04,.04,2.25),Color("a1aab1"))
		for z in [-.65,.65]:
			cylinder(root,Vector3(x,.25,z),.035,.5,Color("a1aab1"))
	box(root,Vector3(0,.72,0),Vector3(.5,.25,1.15),Color("596fa3"))
	var head := cylinder(root,Vector3(0,.79,.73),.16,.23,Color("ad7856"))
	head.rotation.x = PI/2
	box(root,Vector3(.85,.18,.2),Vector3(.4,.36,.3),Color("e1e1df"))
	box(root,Vector3(.85,.38,.2),Vector3(.28,.02,.07),Color.RED)
	return root

static func extinguisher(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Extinguisher"
	parent.add_child(root)
	cylinder(root,Vector3(0,.3,0),.12,.55,Color("bd2828"))
	box(root,Vector3(0,.62,0),Vector3(.2,.07,.08),Color("20252b"))
	box(root,Vector3(.14,.45,0),Vector3(.035,.4,.035),Color("25282b"))
	box(root,Vector3(0,.32,-.125),Vector3(.12,.2,.02),Color("ede6d7"))
	return root

static func barricade(parent: Node3D) -> void:
	for x in [-2.0,2.0]:
		box(parent,Vector3(x,-.25,0),Vector3(.15,1.2,.15),Color("30343a"))
	box(parent,Vector3.ZERO,Vector3(4.5,.7,.15),Color("e4ae30"))
	for i in 8:
		var stripe := box(parent,Vector3(-2+i*.55,0,.09),Vector3(.22,.68,.02),Color("25282d"))
		stripe.rotation.z = -.35
	label(parent,"POLICE • STOP",Vector3(0,.75,0),24)
