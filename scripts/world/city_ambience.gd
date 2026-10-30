class_name CityAmbience
extends Node
## Original offline synthesized loops. No downloaded audio or recorded voices.
var volume := 0.65
var _players: Dictionary = {}
var _world: Node
var _elapsed := 0.0

func setup(world: Node) -> void:
	_world = world
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for kind: String in ["rain", "birds", "market", "traffic", "industry"]:
		var player := AudioStreamPlayer.new()
		var stream := load("res://assets/audio/city/%s.wav" % kind) as AudioStreamWAV
		if stream == null:
			continue
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2
		player.stream = stream
		player.volume_db = -80.0
		add_child(player)
		player.play()
		_players[kind] = player

func update_mix(position: Vector3, night: float, rain: float, indoors: bool, delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var point := Vector2(position.x, position.z)
	var market := 0.0
	for entry: Dictionary in _world.local_activity.shop_entries:
		market = maxf(market, 1.0 - point.distance_to(Vector2(entry.position.x, entry.position.z)) / 55.0)
	var road: Dictionary = _world.signage._nearest_road(point, 70.0)
	var traffic := 0.0 if road.is_empty() else clampf(1.0 - point.distance_to(road.point) / 70.0, 0.0, 1.0)
	var industrial := 0.0
	if _world.coal_mine:
		industrial = clampf(1.0 - point.distance_to(Vector2(_world.coal_mine.position.x, _world.coal_mine.position.z)) / 350.0, 0.0, 1.0)
	var shelter := 0.18 if indoors else 1.0
	var mix := {"rain": rain * (0.3 if indoors else 1.0), "birds": (1.0 - night) * (1.0 - rain * 0.85) * 0.30 * shelter,
		"market": market * lerpf(0.65, 0.12, night) * shelter, "traffic": traffic * lerpf(0.28, 0.08, night) * shelter, "industry": industrial * 0.38 * shelter}
	for key: String in _players:
		var gain: float = clampf(float(mix[key]) * volume, 0.0, 1.0)
		_players[key].volume_db = linear_to_db(maxf(gain, 0.0001))
