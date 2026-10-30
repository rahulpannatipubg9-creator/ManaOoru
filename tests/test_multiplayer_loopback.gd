extends SceneTree

## Free-roam squad play over real ENet on localhost, with two clients and the host in one process (each has its
## own SceneMultiplayer). The real city_gameplay.gd runs on Bravo, so knock-downs are tested with the home respawn
## wired in. Proves: real name tags, downed without a home respawn, revive through the host, elimination that
## keeps the player visible, unique crates, the version check, and that forged client RPCs change nothing.
## The forged RPCs make the engine print "RPC ... is not allowed" errors: those are the test working.

const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const GameplayScript := preload("res://scripts/gameplay/city_gameplay.gd")
const PersonScene := preload("res://scenes/player/person.tscn")
const HOME := Vector3(30, 0, 30)
const STUB_GAME := """extends Node
enum ControlState { ON_FOOT, DRIVING, EXITING }
var person
var control_state := 0
var hud
var network_manager
"""
const STUB_HUD := """extends Node
var coins := 50
func coins_available() -> int: return coins
func spend_coins(amount: int) -> bool:
	coins -= amount
	return true
func add_coins(amount: int) -> void: coins += amount
"""
const STUB_LIFE := """extends Node
func toast(_text: String) -> void: pass
"""

var checks := 0
var failures := 0

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _stub(source: String) -> Node:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var node := Node.new()
	node.set_script(script)
	return node

## One device: its own multiplayer branch, manager, floor and player.
func _device(device_name: String, spot: Vector3) -> Dictionary:
	var branch := Node3D.new()
	branch.name = device_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + device_name))
	var net: Node = NetworkManagerScript.new()
	branch.add_child(net)
	net.setup(branch)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	branch.add_child(floor_body)
	var person: CharacterBody3D = PersonScene.instantiate()
	person.name = "Player"
	branch.add_child(person)
	person.global_position = spot
	person.respawn_position = HOME
	return {"branch": branch, "net": net, "person": person}

func _until(condition: Callable, seconds := 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame

## Long enough for a message there and back.
func _settle(seconds := 0.3) -> void:
	await create_timer(seconds).timeout

func _crates_in(branch: Node) -> Array:
	return branch.get_children().filter(func(node: Node) -> bool: return node is LootCrate and not node.is_queued_for_deletion())

func _hurt(person: CharacterBody3D, amount: float) -> void:
	person.health = maxf(0.0, person.health - amount)
	person.health_changed.emit(person.health, person.max_health)

func run() -> void:
	await process_frame
	var port := 7800 + randi_range(1, 400)
	var host := _device("HostRoot", Vector3(0, 0.1, 0))
	var bravo := _device("BravoRoot", Vector3(1, 0.1, 0))
	var charlie := _device("CharlieRoot", Vector3(60, 0.1, 60))
	var host_net: Node = host.net
	var bravo_net: Node = bravo.net
	var charlie_net: Node = charlie.net
	var bravo_person: CharacterBody3D = bravo.person
	var host_person: CharacterBody3D = host.person

	check(host_net.host_game(port, "AlphaHost") == OK, "the host opens a room")
	check(bravo_net.join_game("127.0.0.1", port, "BravoClient") == OK, "Bravo starts joining")
	await _until(func() -> bool: return host_net.peers.size() == 2 and bravo_net.peers.size() == 2)
	check(charlie_net.join_game("127.0.0.1", port, "  Charlie\nThe Very Long Name Indeed ") == OK, "Charlie starts joining")
	await _until(func() -> bool: return host_net.peers.size() == 3 and bravo_net.peers.size() == 3 and charlie_net.peers.size() == 3)
	check(host_net.peers.size() == 3, "three players are in the room")
	var bravo_id: int = bravo_net.get_local_peer_id()
	var charlie_id: int = charlie_net.get_local_peer_id()

	# Bug 7: real names, on every peer, whichever order they joined in.
	var charlie_name: String = host_net.peers[charlie_id].nickname
	check(host_net.puppets[bravo_id].nickname == "BravoClient", "the host's tag shows Bravo's real name")
	check(bravo_net.puppets[1].nickname == "AlphaHost", "a client's tag shows the host's real name")
	check(bravo_net.puppets[charlie_id].nickname == charlie_name and charlie_net.puppets[bravo_id].nickname == "BravoClient", "clients see each other's real names")
	check(not charlie_name.contains("\n") and charlie_name.length() <= NetworkManagerScript.MAX_NICKNAME_LENGTH, "the host cleans a client's name (%s)" % charlie_name)
	await _settle()
	check(host_net.puppets[bravo_id]._overhead_label.text == "BravoClient", "the label itself shows the name")

	# The version check: another build is told why and never enters the room.
	var outsider := _device("OutsiderRoot", Vector3(5, 0.1, 5))
	var refused := []
	outsider.net.join_failed.connect(func(reason: String) -> void: refused.append(reason))
	outsider.net.protocol_version = NetworkManagerScript.PROTOCOL_VERSION + 1
	outsider.net.join_game("127.0.0.1", port, "Oldie")
	await _until(func() -> bool: return not refused.is_empty())
	check(refused == [NetworkManagerScript.DIFFERENT_VERSION], "a different version is refused with a reason (%s)" % str(refused))
	check(host_net.peers.size() == 3 and not outsider.net.is_active(), "the refused peer is not in the room")
	await _settle(0.6)
	check(host_net.multiplayer.get_peers().size() == 2, "the host closes the refused connection")

	# A peer that never says hello (an older build) is dropped.
	var silent := _device("SilentRoot", Vector3(5, 0.1, 5))
	silent.net.multiplayer.connected_to_server.disconnect(silent.net._on_connected_to_server)
	silent.net.join_game("127.0.0.1", port, "Silent")
	await _until(func() -> bool: return host_net.multiplayer.get_peers().size() == 3)
	check(host_net.multiplayer.get_peers().size() == 3, "the silent peer connects")
	await _until(func() -> bool: return host_net.multiplayer.get_peers().size() == 2, 8.0)
	check(host_net.multiplayer.get_peers().size() == 2 and host_net.peers.size() == 3, "a peer that never says hello is dropped")
	silent.net.disconnect_game()

	# Bravo plays with the real gameplay layer, whose home respawn must stay out of a squad knock-down.
	var game := _stub(STUB_GAME)
	var hud := _stub(STUB_HUD)
	game.person = bravo_person
	game.hud = hud
	game.network_manager = bravo_net
	bravo.branch.add_child(game)
	var gameplay: Node = GameplayScript.new()
	gameplay.game = game
	gameplay.life = _stub(STUB_LIFE)
	bravo_person.health_changed.connect(gameplay._health_changed)

	# Forged host messages from a client: the engine refuses them on every receiver.
	await _until(func() -> bool: return host_net._positions.has(bravo_id) and host_net._positions.has(charlie_id))
	var host_health: float = host_person.health
	bravo_net.rpc_id(1, "rpc_apply_damage", 1, 40.0, "body")
	bravo_net.rpc_id(charlie_id, "rpc_apply_damage", charlie_id, 40.0, "body")
	bravo_net.rpc_id(1, "rpc_notify_eliminated", charlie_id, 99, Vector3(1, 0, 1))
	bravo_net.rpc_id(charlie_id, "rpc_notify_eliminated", 1, 99, Vector3(1, 0, 1))
	bravo_net.rpc_id(1, "rpc_notify_downed", charlie_id)
	bravo_net.rpc_id(1, "rpc_receive_room_state", {bravo_id: {"nickname": "Owner"}})
	bravo_net.rpc_id(charlie_id, "rpc_peer_joined", 666, "Ghost")
	await _settle()
	check(host_person.health == host_health and charlie.person.health == 100.0, "a client's forged damage hurts nobody")
	check(_crates_in(host.branch).is_empty() and _crates_in(charlie.branch).is_empty(), "a client cannot spawn crates")
	check(not host_net.peers[charlie_id].is_downed, "a client cannot report someone else down")
	check(host_net.peers.size() == 3 and not charlie_net.peers.has(666), "a client cannot rewrite the room")

	# Requests the host must turn down.
	bravo_net.rpc_id(1, "rpc_request_damage", 1, 100000.0, "body")
	bravo_net.rpc_id(1, "rpc_request_damage", 1, -50.0, "body")
	bravo_net.rpc_id(1, "rpc_request_damage", bravo_id, 10.0, "body")
	bravo_net.rpc_id(1, "rpc_request_revive", charlie_id)
	await _settle()
	check(host_person.health == host_health, "impossible damage is refused")
	for _shot in NetworkManagerScript.MAX_HITS_PER_SECOND * 3:
		charlie_net.rpc_id(1, "rpc_request_damage", bravo_id, 0.001, "body")
	await _settle()
	check(bravo_person.health > 100.0 - 0.001 * (NetworkManagerScript.MAX_HITS_PER_SECOND * 2 + 1), "a flood of hits is capped (%.3f)" % bravo_person.health)
	bravo_person.heal_full()

	# A genuine hit goes shooter -> host -> victim. Armour that saves the victim leaves them standing.
	var hits := []
	host_net.hit_confirmed.connect(func(target: String, _damage: float, _head: bool) -> void: hits.append(target))
	host_net.report_hit(bravo_id, 30.0, "body", Vector3.ZERO)
	await _until(func() -> bool: return bravo_person.health < 100.0)
	check(is_equal_approx(bravo_person.health, 70.0), "a valid hit lands through the host (%.1f)" % bravo_person.health)
	check(hits == ["BravoClient"], "the shooter is told of the hit")
	await _settle()
	check(not charlie_net.puppets[bravo_id].is_downed, "a hit that leaves them alive does not down the puppet")

	# Bug 5: the knock-down, without a home respawn.
	var knocked_at := bravo_person.global_position
	var coins_before: int = hud.coins
	charlie_net.report_hit(bravo_id, 100.0, "body", Vector3.ZERO)
	await _until(func() -> bool: return bravo_person.downed)
	await _until(func() -> bool: return host_net.peers[bravo_id].is_downed and charlie_net.peers[bravo_id].is_downed)
	await _settle()
	check(bravo_person.downed and bravo_person.health == 0.0, "Bravo is down at zero health (%.1f)" % bravo_person.health)
	check(bravo_person.global_position.distance_to(knocked_at) < 1.0, "the knock-down leaves them where they fell")
	check(hud.coins == coins_before, "no medical fee is charged")
	check(host_net.peers[bravo_id].is_downed and charlie_net.puppets[bravo_id].is_downed, "everyone sees Bravo down")
	# World damage while down must not send them home either.
	bravo_person.health_changed.emit(0.0, bravo_person.max_health)
	await _settle(0.1)
	check(bravo_person.downed and bravo_person.global_position.distance_to(knocked_at) < 1.0, "more damage while down changes nothing")

	# Bravo cannot revive themself and Charlie is far away: the host refuses both.
	bravo_net.rpc_id(1, "rpc_request_revive", bravo_id)
	charlie_net.rpc_id(1, "rpc_request_revive", bravo_id)
	await _settle()
	check(bravo_person.downed, "a forged revive changes nothing")

	# The real revive: the host holds the key beside Bravo for the full 8 seconds.
	check(NetworkManagerScript.REVIVE_DURATION == 8.0, "a revive takes 8 seconds")
	var revive_started := Time.get_ticks_msec()
	Input.action_press("revive")
	await _settle(4.0)
	check(bravo_person.downed, "still down halfway through the hold")
	await _until(func() -> bool: return not bravo_person.downed, 6.0)
	Input.action_release("revive")
	var held := (Time.get_ticks_msec() - revive_started) / 1000.0
	check(not bravo_person.downed and bravo_person.health == NetworkManagerScript.REVIVED_HEALTH, "the hold revives with 25 health")
	check(held > 7.0 and held < 9.5, "the revive took about 8 seconds (%.1f)" % held)
	await _settle()
	check(not host_net.peers[bravo_id].is_downed and not charlie_net.puppets[bravo_id].is_downed, "everyone sees Bravo back")

	# World damage in a squad also ends in a knock-down, not a trip home.
	coins_before = hud.coins
	_hurt(bravo_person, 500.0)
	await _until(func() -> bool: return host_net.peers[bravo_id].is_downed)
	check(bravo_person.downed and hud.coins == coins_before and bravo_person.health == 0.0, "any lethal damage in a squad knocks down without a respawn")

	# Bug 6: the host's clock runs out; Bravo goes home and stays visible to everyone.
	host_net._down[bravo_id].left = 0.01
	await _until(func() -> bool: return not bravo_person.downed)
	await _settle()
	check(bravo_person.global_position.distance_to(HOME) < 3.0, "the eliminated player respawns at home")
	check(bravo_person.health == bravo_person.max_health, "the eliminated player has full health")
	check(not host_net.peers[bravo_id].is_downed, "the room no longer lists them as down")
	check(host_net.puppets.has(bravo_id) and charlie_net.puppets.has(bravo_id), "the puppet survives elimination")
	var charlie_view: Node3D = charlie_net.puppets[bravo_id]
	await _until(func() -> bool: return not charlie_view.is_eliminated(), NetworkPlayer.BODY_SECONDS + 2.0)
	await _settle()
	check(charlie_view.visible and host_net.puppets[bravo_id].visible, "the player is visible after elimination")
	check(charlie_view.global_position.distance_to(bravo_person.global_position) < 3.0, "they appear where they respawned")
	var health_before: float = bravo_person.health
	charlie_net.report_hit(bravo_id, 10.0, "body", Vector3.ZERO)
	await _until(func() -> bool: return bravo_person.health < health_before)
	check(bravo_person.health < health_before, "the respawned player can be hit again")
	bravo_person.heal_full()

	# Bug 15: a second elimination while the first crate exists; two crates with their own ids.
	check(_crates_in(charlie.branch).size() == 1 and _crates_in(host.branch).size() == 1, "one crate on each peer")
	bravo_net.knock_down_local()
	await _until(func() -> bool: return host_net.peers[bravo_id].is_downed)
	host_net._down[bravo_id].left = 0.01
	await _until(func() -> bool: return _crates_in(charlie.branch).size() == 2 and _crates_in(host.branch).size() == 2)
	var crates := _crates_in(host.branch)
	check(crates.size() == 2 and crates[0].crate_id != crates[1].crate_id, "repeat deaths give crates unique ids")
	check(String(crates[0].name) != String(crates[1].name) and not String(crates[1].name).contains("@"), "and unique names")

	# Looting needs to be near the crate, and removes that crate only, everywhere.
	var target_id: int = crates[1].crate_id
	var target_spot: Vector3 = crates[1].global_position
	charlie_net.rpc_id(1, "rpc_request_loot", target_id)
	await _settle()
	check(_crates_in(host.branch).size() == 2, "a crate cannot be looted from afar")
	var stand_at := target_spot + Vector3(1.0, 0.2, 0.0)
	bravo_person.global_position = stand_at
	await _until(func() -> bool: return host_net._positions[bravo_id].distance_to(stand_at) < 1.0)
	var coins_at_loot: int = hud.coins
	gameplay.reserve = 980
	gameplay.ammo = gameplay.mag_size
	var medkits_at_loot: int = gameplay.medkits
	var bravo_crate: Node = bravo_net._crates[target_id]
	var loot: Dictionary = bravo_crate.collect(bravo_person, gameplay)
	check(loot.get("ammo") == 30 and loot.get("coins") == 15 and loot.get("medkits") == 1, "the crate reports its loot")
	check(gameplay.reserve == 999 and gameplay.ammo == gameplay.mag_size, "ammo goes to the reserve, capped, not the magazine")
	check(hud.coins == coins_at_loot + 15 and gameplay.medkits == medkits_at_loot + 1, "coins and medkits really arrive")
	check(bravo_crate.collect(bravo_person, gameplay).is_empty() and hud.coins == coins_at_loot + 15, "a crate pays out once")
	await _until(func() -> bool: return _crates_in(host.branch).size() == 1 and _crates_in(charlie.branch).size() == 1)
	var left_on_host := _crates_in(host.branch)
	check(left_on_host.size() == 1 and left_on_host[0].crate_id != target_id, "looting removes the right crate on every peer")

	# Leaving while down stands the player up; crates and puppets go with the session.
	bravo_net.knock_down_local()
	await _until(func() -> bool: return host_net.peers[bravo_id].is_downed)
	bravo_net.disconnect_game()
	check(not bravo_person.downed and bravo_person.health > 0.0, "a session ending frees a downed player")
	check(bravo_net._crates.is_empty() and bravo_net.puppets.is_empty(), "leaving clears crates and puppets")
	await _until(func() -> bool: return host_net.peers.size() == 2)
	check(not host_net._down.has(bravo_id) and host_net.peers.size() == 2, "the host forgets a player who left")
	await _until(func() -> bool: return not charlie_net.peers.has(bravo_id))
	check(not charlie_net.puppets.has(bravo_id), "other clients drop their puppet")

	# Without a session the home respawn still works: the guard above is what kept Bravo in place.
	bravo_person.health = 0.0
	bravo_person.global_position = knocked_at
	bravo_person.health_changed.emit(0.0, bravo_person.max_health)
	await _settle(0.1)
	check(bravo_person.global_position.distance_to(HOME) < 1.0 and bravo_person.health > 0.0, "alone, zero health still goes home")

	# Bug 20: leaving the tree closes the connection, whoever changed the scene.
	var charlie_mp: MultiplayerAPI = charlie_net.multiplayer
	charlie.branch.remove_child(charlie_net)
	check(not charlie_mp.has_multiplayer_peer(), "leaving the tree closes the connection")
	await _until(func() -> bool: return host_net.peers.size() == 1)
	check(host_net.peers.size() == 1, "the host hears them go")
	charlie_net.free()

	host_net.disconnect_game()
	check(not host_net.is_active(), "the host closes cleanly")

	print("Multiplayer loopback regression: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
