extends RefCounted

## Spawn zones per team and the "safest spawn" choice. The zone positions are
## placed in the engine (docs/TDM_DESIGN.md, section 3); this class only chooses.

## A zone this close to a living player counts as occupied.
const OCCUPIED_RADIUS := 2.0

var _zones: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
## Optional: func(point: Vector3, enemy_positions: PackedVector3Array) -> bool.
## True when an enemy has a clear line of sight to the point.
var enemy_line_of_sight: Callable

func set_zones(team: int, points: PackedVector3Array) -> void:
	_zones[team] = points

func zone_count(team: int) -> int:
	return _zones[team].size()

## Prefers a free zone that no enemy can see, as far from enemies as possible.
## Falls back (see-through first, then occupied) so a respawn is never blocked.
func pick(team: int, enemy_positions: PackedVector3Array, occupied: PackedVector3Array) -> Vector3:
	var zones := _zones[team]
	if zones.is_empty():
		push_warning("TDM: no spawn zones for team %d" % team)
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_rank := -1
	var best_distance := -1.0
	for point in zones:
		var rank := 0
		if not _is_occupied(point, occupied):
			rank += 2
		if not _enemy_sees(point, enemy_positions):
			rank += 1
		var distance := _nearest_distance(point, enemy_positions)
		if rank > best_rank or (rank == best_rank and distance > best_distance):
			best = point
			best_rank = rank
			best_distance = distance
	return best

func _is_occupied(point: Vector3, occupied: PackedVector3Array) -> bool:
	for other in occupied:
		if point.distance_to(other) < OCCUPIED_RADIUS:
			return true
	return false

func _enemy_sees(point: Vector3, enemy_positions: PackedVector3Array) -> bool:
	return enemy_line_of_sight.is_valid() and enemy_line_of_sight.call(point, enemy_positions)

## Distance to the nearest enemy; very large when there are none.
func _nearest_distance(point: Vector3, enemy_positions: PackedVector3Array) -> float:
	var nearest := 1.0e9
	for enemy in enemy_positions:
		nearest = minf(nearest, point.distance_to(enemy))
	return nearest
