extends SceneTree
## Screenshot-only markers identify newly imported footprints. No map edits.
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(960,600)
	DisplayServer.window_set_size(Vector2i(960,600))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.visible = false
	var world = game.get_node("World")
	var additions: Array[Dictionary] = []
	for building: Dictionary in world.map_data.buildings:
		if building.source == "overture":
			additions.append(building)
	assert(additions.size() == 11, "Expected the integrated source-backed supplement")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 60
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var caption := Label.new()
	caption.position = Vector2(16,16)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(caption)
	var marker := Node3D.new()
	root.add_child(marker)
	var indices := [2,3,4,7]
	for shot in indices.size():
		for child in marker.get_children():
			child.free()
		var building: Dictionary = additions[indices[shot]]
		var points: PackedVector2Array = building.points
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= points.size()
		world.buildings.build_around(center,160.0)
		var base: float = world.ground_height(center)
		var roof: float = base + 4.0
		var nearest := INF
		for i in world.buildings.footprints.size():
			var ring: PackedVector2Array = world.buildings.footprints[i]
			var c := Vector2.ZERO
			for p in ring:
				c += p
			c /= ring.size()
			if c.distance_to(center) < nearest:
				nearest = c.distance_to(center)
				var meta: Dictionary = world.buildings.building_metadata[i]
				roof = float(meta.base) + float(meta.floors)*BuildingBuilder.FLOOR_HEIGHT + BuildingBuilder.PARAPET_HEIGHT + 0.3
		assert(nearest < 0.1, "Source addition must exist in generated building geometry")
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ffc438")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_LINES)
		for i in points.size():
			for p in [points[i],points[(i+1)%points.size()]]:
				st.add_vertex(Vector3(p.x,roof,p.y))
		var outline := MeshInstance3D.new()
		outline.mesh = st.commit()
		outline.material_override = material
		marker.add_child(outline)
		var pin := Label3D.new()
		pin.text = "NEW FOOTPRINT %d" % (shot+1)
		pin.position = Vector3(center.x,roof+1.5,center.y)
		pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pin.font_size = 28
		pin.pixel_size = 0.025
		pin.modulate = Color("ffc438")
		marker.add_child(pin)
		caption.text = "VIDYA NAGAR 2 — NEW OVERTURE BUILDING %d/4\nYellow identifies the imported roof outline · Paint/windows/height remain approximate\nSource ID: %s" % [shot+1,building.overture_id]
		var target := Vector3(center.x,base+3.0,center.y)
		camera.position = target + Vector3(22,18,25)
		camera.look_at(target)
		for i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://outputs/building_sources/new_building_%02d.png" % (shot+1)
		root.get_texture().get_image().save_png(path)
		print("Saved ",path," ",building.overture_id)
	quit()
