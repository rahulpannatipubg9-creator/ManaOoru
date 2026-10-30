extends RefCounted
## Procedural interpretation of the user-supplied October 2025 frontage photo.
## Dimensions are illustrative and constrained to the existing mapped wall.
static func build(a: Vector2, b: Vector2, normal: Vector2, base: float) -> Node3D:
	var root := Node3D.new()
	root.name = "NewAshokTheatreFrontage"
	root.set_meta("reference", "User supplied Google Street View screenshot, October 2025")
	root.set_meta("dimensions", "approximate; existing footprint retained")
	var width := a.distance_to(b)
	var along := (b-a).normalized()
	var middle := (a+b)*0.5
	root.position = Vector3(middle.x,base,middle.y)
	root.basis = Basis(Vector3(-along.x,0,-along.y),Vector3.UP,Vector3(normal.x,0,normal.y))
	assert(root.basis.determinant() > 0.99,"Theatre lettering must not use a mirrored basis")
	box(root,"GreyFront",Vector3(width,3.6,0.10),Vector3(0,3.45,0.08),Color("657077"))
	for y in [1.68,5.23]:
		box(root,"OrangeTrim",Vector3(width,0.12,0.13),Vector3(0,y,0.15),Color("d39139"))
	for i in 18:
		box(root,"VerticalRib",Vector3(0.035,2.5,0.04),Vector3(-width*.23+i*width*.025,3.3,0.16),Color("acb3b5"))
	# Curved yellow wing, kept within the facade span; no guessed forecourt walls.
	var surface := MeshSurface.new()
	var left := -width*.5
	for i in 12:
		var x0 := left+width*.18*i/12.0
		var x1 := left+width*.18*(i+1)/12.0
		var h0 := 5.25+1.7*pow(1.0-float(i)/12.0,2)
		var h1 := 5.25+1.7*pow(1.0-float(i+1)/12.0,2)
		surface.quad(Vector3(x0,1.7,.19),Vector3(x1,1.7,.19),Vector3(x1,h1,.19),Vector3(x0,h0,.19),Vector3.BACK,Color("d8c16e"),Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,false)
	var wing := MeshInstance3D.new()
	wing.name = "CurvedYellowWing"
	wing.mesh = surface.to_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing.material_override = mat
	root.add_child(wing)
	var label := Label3D.new()
	label.name = "TheatreLettering"
	label.text = "NEW ASHOK TALKIES"
	label.font_size = 64
	label.pixel_size = minf(.008,width/850.0)
	label.position = Vector3(width*.08,4.8,.23)
	label.outline_size = 2
	label.modulate = Color.WHITE
	root.add_child(label)
	return root

static func box(root: Node3D,title: String,size: Vector3,at: Vector3,paint: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = paint
	node.material_override = material
	root.add_child(node)
