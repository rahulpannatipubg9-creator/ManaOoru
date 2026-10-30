extends RefCounted

## Who is in the match, on which team, with what score. Host-side only.
## Players who drop keep their slot (and a reconnect token) until the hold expires.

enum Team { RED, BLUE }
const NO_TEAM := -1
const TEAM_NAMES: Array[String] = ["Red", "Blue"]

class Member:
	var peer_id := 0
	var nickname := ""
	var team := Team.RED
	var kills := 0
	var deaths := 0
	var assists := 0
	var token := ""
	var connected := true
	var disconnected_at := 0.0

var team_kills: Array[int] = [0, 0]
var _members: Dictionary = {}

static func other_team(team: int) -> int:
	return Team.BLUE if team == Team.RED else Team.RED

## Adds a player to the smaller team (ties go to the team with fewer kills, then Red).
func add_member(peer_id: int, nickname: String) -> Member:
	var member := Member.new()
	member.peer_id = peer_id
	member.nickname = _unique_nickname(nickname.strip_edges() if not nickname.strip_edges().is_empty() else "Player %d" % peer_id)
	member.team = _team_for_new_player()
	member.token = Crypto.new().generate_random_bytes(8).hex_encode()
	_members[peer_id] = member
	return member

func member(peer_id: int) -> Member:
	return _members.get(peer_id) as Member

func has_member(peer_id: int) -> bool:
	return _members.has(peer_id)

func peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _members:
		ids.append(id)
	return ids

func remove_member(peer_id: int) -> void:
	_members.erase(peer_id)

## Everyone holding a slot on the team, including dropped players inside their hold window.
func team_count(team: int) -> int:
	var count := 0
	for m: Member in _members.values():
		if m.team == team:
			count += 1
	return count

func connected_count(team: int) -> int:
	var count := 0
	for m: Member in _members.values():
		if m.team == team and m.connected:
			count += 1
	return count

func can_start() -> bool:
	return connected_count(Team.RED) > 0 and connected_count(Team.BLUE) > 0

## A player may swap only if the teams stay within one player of each other.
func can_swap(peer_id: int) -> bool:
	var m := member(peer_id)
	if m == null:
		return false
	var difference := team_count(m.team) - team_count(other_team(m.team))
	return difference >= 1 and difference <= 3

## The host may move anyone; players need can_swap().
func swap_team(peer_id: int, by_host := false) -> bool:
	var m := member(peer_id)
	if m == null or not (by_host or can_swap(peer_id)):
		return false
	m.team = other_team(m.team)
	return true

func record_kill(killer_id: int, victim_id: int, assist_ids: Array[int]) -> void:
	var killer := member(killer_id)
	var victim := member(victim_id)
	if killer != null:
		killer.kills += 1
		team_kills[killer.team] += 1
	if victim != null:
		victim.deaths += 1
	for id in assist_ids:
		var assister := member(id)
		if assister != null:
			assister.assists += 1

func record_death(victim_id: int) -> void:
	var victim := member(victim_id)
	if victim != null:
		victim.deaths += 1

func mark_disconnected(peer_id: int, at_seconds: float) -> void:
	var m := member(peer_id)
	if m != null:
		m.connected = false
		m.disconnected_at = at_seconds

## Re-keys a dropped player to their new peer id. Returns the old peer id, or 0 if the token is unknown.
func reconnect(token: String, new_peer_id: int) -> int:
	for m: Member in _members.values():
		if not m.connected and m.token == token:
			_members.erase(m.peer_id)
			var old_id := m.peer_id
			m.peer_id = new_peer_id
			m.connected = true
			_members[new_peer_id] = m
			return old_id
	return 0

## Frees the slots of players who stayed away past the hold. Returns the freed peer ids.
func expire_disconnected(now_seconds: float, hold_seconds: float) -> Array[int]:
	var freed: Array[int] = []
	for m: Member in _members.values():
		if not m.connected and now_seconds - m.disconnected_at >= hold_seconds:
			freed.append(m.peer_id)
	for id in freed:
		_members.erase(id)
	return freed

## The winning team by kills, or NO_TEAM when level.
func leading_team() -> int:
	if team_kills[Team.RED] == team_kills[Team.BLUE]:
		return NO_TEAM
	return Team.RED if team_kills[Team.RED] > team_kills[Team.BLUE] else Team.BLUE

## Zeroes scores for a rematch, optionally swapping everyone's side.
func reset_scores(swap_sides := false) -> void:
	team_kills = [0, 0]
	for m: Member in _members.values():
		m.kills = 0
		m.deaths = 0
		m.assists = 0
		if swap_sides:
			m.team = other_team(m.team)

## Best player first: kills, then fewest deaths, then assists.
func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for m: Member in _members.values():
		rows.append({"peer_id": m.peer_id, "nickname": m.nickname, "team": m.team,
			"kills": m.kills, "deaths": m.deaths, "assists": m.assists, "connected": m.connected})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.kills != b.kills:
			return a.kills > b.kills
		if a.deaths != b.deaths:
			return a.deaths < b.deaths
		return a.assists > b.assists)
	return rows

func _team_for_new_player() -> int:
	var red := team_count(Team.RED)
	var blue := team_count(Team.BLUE)
	if red != blue:
		return Team.RED if red < blue else Team.BLUE
	if team_kills[Team.RED] != team_kills[Team.BLUE]:
		return Team.RED if team_kills[Team.RED] < team_kills[Team.BLUE] else Team.BLUE
	return Team.RED

func _unique_nickname(wanted: String) -> String:
	var taken: Dictionary = {}
	for m: Member in _members.values():
		taken[m.nickname] = true
	if not taken.has(wanted):
		return wanted
	var suffix := 2
	while taken.has("%s %d" % [wanted, suffix]):
		suffix += 1
	return "%s %d" % [wanted, suffix]
