extends SceneTree

func _init():
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var game := main_scene.instantiate()
	root.add_child(game)
	
	for frame in range(15):
		await physics_frame
	
	var player = game.person
	var car = game.active_vehicle
	assert(player != null, "Player must exist")
	assert(car != null, "Vehicle must exist")
	
	var initial_player_pos: Vector3 = player.global_position
	print("Initial player position at Chowrastha: ", initial_player_pos)
	
	# Trigger teleport to bridge
	game._teleport_to_godavari_bridge()
	for frame in range(5):
		await physics_frame
	
	var bridge_player_pos: Vector3 = player.global_position
	var bridge_car_pos: Vector3 = car.global_position
	print("Player position after teleport: ", bridge_player_pos)
	print("Car position after teleport: ", bridge_car_pos)
	
	assert(bridge_player_pos.z < -3000.0, "Player must be at Godavari Bridge (Z < -3000)")
	assert(bridge_car_pos.z < -3000.0, "Vehicle must be at Godavari Bridge (Z < -3000)")
	print("PASS: Bridge forward teleport successfully moved player and car to bridge!")
	
	# Trigger teleport back to Chowrastha
	game._teleport_to_godavari_bridge()
	for frame in range(5):
		await physics_frame
		
	var return_player_pos: Vector3 = player.global_position
	print("Player position after return teleport: ", return_player_pos)
	assert(return_player_pos.distance_to(initial_player_pos) < 5.0, "Player must return to Chowrastha")
	print("PASS: Bridge return teleport successfully returned to Chowrastha!")
	
	game.queue_free()
	quit()

