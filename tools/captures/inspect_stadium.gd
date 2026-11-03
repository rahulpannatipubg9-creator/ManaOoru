extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(10):
		await process_frame
	
	var world = game.get_node("World")
	var stadium = world.find_child("stadium_with_swimming_pool", true, false)
	if stadium:
		print("stadium node global pos: ", stadium.global_position, " rot: ", stadium.rotation)
		for child in stadium.get_children():
			print("  stadium child: ", child.name, " scale: ", child.scale, " pos: ", child.position)

	# Let's inspect roads near (600, 900)
	var map_data = world.map_data
	print("--- ROADS NEAR STADIUM ---")
	for road in map_data.roads:
		for pt in road.points:
			if pt.distance_to(Vector2(600.0, 920.0)) < 150.0:
				print("Road: ", road.name if road.has("name") else "unnamed", " kind: ", road.kind, " pts: ", road.points.size())
				break

	quit()
