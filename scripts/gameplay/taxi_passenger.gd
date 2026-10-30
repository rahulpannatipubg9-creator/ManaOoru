extends Node3D
## Passenger lifecycle: waiting -> boarding -> riding -> alighting -> complete.
var game: Node
var actor: Node3D
var vehicle: Node3D
var state := "waiting"
var _time := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _start := Vector3.ZERO
func setup(owner_game: Node, at: Vector3) -> void:
	game = owner_game
	actor = load("res://scenes/world/pedestrian.tscn").instantiate()
	actor.idle_mode = true
	add_child(actor)
	actor.global_position = at
	actor.set_process(false)
	_start = at
func board(car: Node3D) -> void:
	vehicle = car
	_from = actor.global_position
	state = "boarding"
	_time = 0
func seat_position() -> Vector3:
	var hip: Vector3 = game.entry.seat_points(vehicle)[0]
	# A rear bench passenger sits behind the driver, including in the tuk-tuk.
	return vehicle.to_global(Vector3(0.25, maxf(.1,hip.y-.7), hip.z-0.75))
func alight() -> void:
	_from = actor.global_position
	_to = vehicle.to_global(Vector3(2.1,0,0))
	var point := Vector2(_to.x,_to.z)
	_to.y = game.get_node("World").ground_height(point)
	state = "alighting"
	_time = 0
func _process(delta: float) -> void:
	if not is_instance_valid(actor): return
	_time += delta
	if state in ["boarding","riding","alighting"] and not is_instance_valid(vehicle):
		state = "waiting"
		actor.global_position = _start
		return
	if state == "boarding":
		actor.global_position = _from.lerp(seat_position(),smoothstep(0,1,minf(_time/1.5,1)))
		if _time >= 1.5: state = "riding"
	elif state == "riding":
		actor.global_position = seat_position()
		actor.global_rotation.y = vehicle.global_rotation.y
		actor.get_node("LeftLegPivot").rotation.x = -PI/2
		actor.get_node("RightLegPivot").rotation.x = -PI/2
	elif state == "alighting":
		actor.global_position = _from.lerp(_to,smoothstep(0,1,minf(_time/1.5,1)))
		if _time >= 1.5:
			state = "complete"
			actor.get_node("LeftLegPivot").rotation.x = 0
			actor.get_node("RightLegPivot").rotation.x = 0
