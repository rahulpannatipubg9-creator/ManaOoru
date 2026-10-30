extends SceneTree

## Team Deathmatch inside the real game scene: hosting from the lobby path, the arena (spawn zones, cover,
## fog, far plane, trimmed city), the cover-versus-highway sight line, practice mode, a live match, the
## weapon in TDM, and a clean return to free roam.
## Run: godot --headless --path . --script tests/tdm_integration_regression.gd

const Config := preload("res://scripts/tactical/tdm_config.gd")
const Arena := preload("res://scripts/tactical/tdm_arena.gd")
const Match := preload("res://scripts/tactical/tdm_match.gd")

var failures := 0
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(30)
	var person: CharacterBody3D = game.person
	var home := person.global_transform
	var stream_before: float = game.get_node("World").buildings.stream_radius
	var gameplay: Node = game.gameplay
	var ammo_before: int = gameplay.ammo
	var resident_visibility: Dictionary = {}
	for node in get_nodes_in_group("city_residents"):
		resident_visibility[node] = node.process_mode
	var local: Node = game.tdm_local
	var session: Node = game.tdm_session
	check(local != null and session != null and game.network_manager.tdm == session, "main.gd wires up the TDM session and view")
	check(not local.in_match and not gameplay.tdm_active, "free roam starts with TDM off")

	# Host exactly as the SQUAD screen does: open the room, then begin the match.
	var config := Config.new()
	config.countdown_seconds = 1.0
	config.spawn_protection_seconds = 0.3
	check(game.network_manager.host_game(17878, "Tester") == OK, "the room opens on a free port")
	local.host_match(config, "Tester")
	await frames(30)
	check(local.in_match and session.active and session.is_host, "hosting enters the match")
	var arena: Node = local.arena
	check(arena != null, "the arena is built")
	for team in 2:
		check(arena.zones[team].size() >= 3, "team %d has at least three spawn zones (found %d)" % [team, arena.zones[team].size()])
		for zone in arena.zones[team]:
			check(Vector2(zone.x, zone.z).length() < Arena.RADIUS - 5.0, "a spawn zone lies inside the ring")
	check(arena.cover_count >= 8, "cover was placed (%d pieces)" % arena.cover_count)
	check(gameplay.tdm_active and gameplay.mag_size == 30 and gameplay.reload_seconds == 2.0 and gameplay.ammo == 30,
		"the M416 setup is a 30-round magazine with a 2 s reload")
	check(not person.movement_enabled, "the player is frozen in the lobby")
	var near_zone: bool = Vector2(person.global_position.x, person.global_position.z).distance_to(Vector2(arena.zones[0][0].x, arena.zones[0][0].z)) < 3.0
	check(near_zone, "the host waits at its team's spawn zone")
	var environment: Environment = game.get_node("DayEnvironment").environment
	await frames(5)
	check(environment.fog_enabled and is_equal_approx(environment.fog_density, Arena.FOG_DENSITY), "fog trims the view to the arena")
	var camera := root.get_viewport().get_camera_3d()
	check(camera != null and camera.far <= Arena.VIEW_FAR + 0.1, "the far plane culls beyond the arena")
	var residents := get_nodes_in_group("city_residents")
	check(residents.all(func(node: Node) -> bool: return not node.visible), "ambient residents are hidden (%d)" % residents.size())
	check(game.get_node("World").buildings.stream_radius <= Arena.RADIUS + 91.0, "buildings stream only around the arena")

	# The highway must not be a shooting gallery from one spawn to the other.
	await frames(10)
	var space: PhysicsDirectSpaceState3D = person.get_world_3d().direct_space_state
	var open_lines := 0
	var open_pairs: Array = []
	var lines := 0
	for red: Vector3 in arena.zones[0]:
		for blue: Vector3 in arena.zones[1]:
			lines += 1
			var query := PhysicsRayQueryParameters3D.create(red + Vector3.UP * 1.6, blue + Vector3.UP * 1.6, 0xFFFFFFFF, [person.get_rid()])
			if space.intersect_ray(query).is_empty():
				open_lines += 1
				open_pairs.append([red.snapped(Vector3.ONE), blue.snapped(Vector3.ONE)])
	check(open_lines == 0, "no spawn zone sees an enemy zone (%d of %d lines open): %s" % [open_lines, lines, open_pairs])

	# The game's minimap stays up in a match and carries team-mates, firing enemies and pings.
	check(game.hud.minimap.visible and game.hud.minimap.markers.is_valid(), "the minimap shows match markers")
	# Killcam: the view follows the killer for a moment, then returns.
	var killer: CharacterBody3D = preload("res://scripts/network/network_player.gd").new()
	killer.position = person.global_position + Vector3(6, 0, 6)
	game.add_child(killer)
	game.network_manager.puppets[55] = killer
	var camera_before := root.get_viewport().get_camera_3d()
	local._start_killcam(55)
	await frames(3)
	check(root.get_viewport().get_camera_3d() == local._killcam, "the killcam takes over the view")
	check(local._killcam.global_position.distance_to(killer.global_position) < 4.0, "the killcam is beside the killer")
	local._end_killcam()
	await frames(2)
	check(root.get_viewport().get_camera_3d() == camera_before, "the view returns after the killcam")
	game.network_manager.puppets.erase(55)
	killer.queue_free()

	# Practice mode: a lone host shoots dummies.
	local.start_practice()
	await frames(10)
	check(local.practicing and local._dummies.size() == 6, "practice mode stands up six dummies")
	check(local.can_fire(), "the weapon works in practice")
	var dummy: Node = local._dummies[0]
	dummy.tdm_dummy_hit(dummy.global_position + Vector3(0, 1.7, 0))
	dummy.tdm_dummy_hit(dummy.global_position + Vector3(0, 1.0, 0))
	check(local._practice_stats.hits == 2 and local._practice_stats.headshots == 1, "practice counts hits and headshots")
	local.stop_practice()
	check(not local.practicing and local._dummies.is_empty(), "stopping practice removes the dummies")

	# A match with only the host: start is allowed only with both teams, so add a bot-free check of the guard.
	check(not session.host_start(), "a match needs players on both teams")
	# Put a second player on Blue directly in the host's rules, then run the countdown.
	session.rules.join(2, "Guest")
	check(session.host_start(), "with both teams populated the host can start")
	await _until(func() -> bool: return session.state == Match.State.LIVE, 6.0)
	check(session.state == Match.State.LIVE, "the match goes live after the countdown")
	await frames(10)
	check(local._alive and person.movement_enabled, "the host player is alive and free to move")
	check(local.can_fire(), "firing is allowed in a live match")
	await _until(func() -> bool: return not session.rules.is_protected(1), 3.0)
	var ammo_before_shot: int = gameplay.ammo
	gameplay._shot_cooldown = 0.0
	var fired: bool = gameplay.attack()
	check(fired and gameplay.ammo == ammo_before_shot - 1, "the player can fire the rifle")
	check(gameplay.wanted_level == 0 and gameplay.heat == 0.0, "firing in TDM raises no wanted level")

	# Leaving puts free roam back exactly.
	local.leave_match()
	await frames(20)
	check(not local.in_match and not gameplay.tdm_active, "leaving ends TDM")
	check(person.global_position.distance_to(home.origin) < 0.5, "the player is back where free roam left them")
	check(gameplay.mag_size == 24 and gameplay.reload_seconds == 1.5, "the free-roam weapon numbers are restored")
	check(gameplay.ammo <= 24 and ammo_before <= 24, "free-roam ammo is restored")
	check(not environment.fog_enabled or environment.fog_density < 0.01, "fog is restored")
	check(game.get_node("World").buildings.stream_radius == stream_before, "building streaming is restored")
	check(residents.all(func(node: Node) -> bool: return node.process_mode == resident_visibility.get(node, node.process_mode)), "ambient residents are running again")
	check(not is_instance_valid(local.arena), "the arena is removed")
	check(not game.hud.minimap.markers.is_valid(), "the minimap drops the match markers")
	print("TDM integration regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await physics_frame
