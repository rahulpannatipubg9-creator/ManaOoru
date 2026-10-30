extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.city_life.save_enabled = false
	game.set_process(false)
	game.gameplay.set_process(false)
	game.person.set_physics_process(false)
	var g = game.gameplay
	assert(g.start_mission("taxi"))
	assert(is_instance_valid(g.passenger) and g.passenger.state == "waiting")
	var taxi: Node3D
	for car in game.vehicles:
		if "Tuk" in str(car.name): taxi=car
	assert(taxi != null)
	game.active_vehicle = taxi
	game.control_state = game.ControlState.DRIVING
	taxi.current_speed = 0
	taxi.global_position = g.mission.points[0]
	g._update_mission(.1)
	assert(g.passenger.state == "boarding" and g.mission.index == 0)
	g.passenger._process(1.6)
	g._update_mission(.1)
	assert(g.mission.index == 1 and g.passenger.state == "riding")
	taxi.global_position = g.mission.points[1]
	g.passenger._process(.1)
	g._update_mission(.1)
	assert(g.passenger.state == "alighting")
	var coins: int = game.hud.coins_available()
	g.passenger._process(1.6)
	g._update_mission(.1)
	assert(g.mission.is_empty() and game.hud.coins_available() == coins + 20)
	game.control_state = game.ControlState.ON_FOOT
	assert(g.start_mission("ambulance"))
	assert(g._service_visual.get_node_or_null("PatientStretcher") != null)
	g.end_mission(false)
	assert(g.start_mission("firefighter"))
	assert(g._service_visual.get_node_or_null("Extinguisher") != null)
	g.end_mission(false)
	for kind in ["scooter","police","ambulance"]:
		var v = load("res://scripts/gameplay/arcade_vehicle.gd").new()
		v.kind = kind
		v.position = Vector3(0,100,0)
		root.add_child(v)
		v.set_physics_process(false)
		assert(v.gearbox != null)
		assert(v.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") != null)
		v.queue_free()
	var residents := get_nodes_in_group("city_residents")
	assert(residents.size()>0 and residents[0].get_node_or_null("Hair") != null)
	print("PASS city content: tuk-tuk boarding/riding/alighting/fare, emergency equipment, extra vehicles, resident variation")
	game.queue_free()
	await process_frame
	quit()
