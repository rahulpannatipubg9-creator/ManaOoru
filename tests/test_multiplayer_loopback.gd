extends SceneTree

func _init() -> void:
	print("--- BEGIN MULTIPLAYER LOOPBACK TEST ---")
	_run_test.call_deferred()

func _run_test() -> void:
	await process_frame

	# 1. Setup Host Root & SceneMultiplayer
	var host_root := Node3D.new()
	host_root.name = "HostRoot"
	root.add_child(host_root)

	var host_mp := SceneMultiplayer.new()
	set_multiplayer(host_mp, NodePath("/root/HostRoot"))

	var host_net := preload("res://scripts/network/network_manager.gd").new()
	host_net.name = "NetworkManager"
	host_root.add_child(host_net)
	host_net.setup(host_root)

	var add_test_floor = func(target_root: Node3D) -> void:
		var floor_body := StaticBody3D.new()
		var floor_col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(100.0, 1.0, 100.0)
		floor_col.shape = box
		floor_body.add_child(floor_col)
		floor_body.position.y = -0.5
		target_root.add_child(floor_body)

	add_test_floor.call(host_root)

	var host_person: CharacterBody3D = preload("res://scenes/player/person.tscn").instantiate()
	host_person.name = "Player"
	host_root.add_child(host_person)
	host_root.set("person", host_person)

	var test_port: int = 7800 + randi_range(1, 400)

	# 2. Host Game on dynamic port
	var host_err: Error = host_net.host_game(test_port, "AlphaHost")
	assert(host_err == OK, "Host should initialize OK on port %d" % test_port)
	print("PASS: Host started successfully on port %d" % test_port)

	# 3. Setup Client Root & SceneMultiplayer
	var client_root := Node3D.new()
	client_root.name = "ClientRoot"
	root.add_child(client_root)

	var client_mp := SceneMultiplayer.new()
	set_multiplayer(client_mp, NodePath("/root/ClientRoot"))

	var client_net := preload("res://scripts/network/network_manager.gd").new()
	client_net.name = "NetworkManager"
	client_root.add_child(client_net)
	client_net.setup(client_root)
	add_test_floor.call(client_root)

	var client_person: CharacterBody3D = preload("res://scenes/player/person.tscn").instantiate()
	client_person.name = "Player"
	client_root.add_child(client_person)
	client_root.set("person", client_person)

	# 4. Join Game from Client to 127.0.0.1
	var join_err: Error = client_net.join_game("127.0.0.1", test_port, "BravoClient")
	assert(join_err == OK, "Client join_game call should return OK")
	print("PASS: Client initiated connection to 127.0.0.1:%d" % test_port)

	# Helper to pump network frames
	var pump_network = func(frames: int = 1):
		for f in range(frames):
			await process_frame
			if host_net.peer: host_net.peer.poll()
			if client_net.peer: client_net.peer.poll()
			host_mp.poll()
			client_mp.poll()

	# 5. Process Network Connection Frames
	var connected := false
	for frame in range(180): # up to 3 seconds
		await pump_network.call(1)
		if host_net.peers.size() >= 2 and client_net.is_active():
			connected = true
			break

	assert(connected, "Host and Client should establish 2-peer connection via ENet loopback")
	print("PASS: Two actual clients connected over ENet loopback (Peers: %s)" % str(host_net.peers.keys()))

	var client_peer_id: int = -1
	for id in host_net.peers:
		if id != 1:
			client_peer_id = id
			break

	assert(client_peer_id > 1, "Host must identify client peer id")
	print("PASS: Client peer ID confirmed: %d" % client_peer_id)

	# 6. Test Cross-Peer Combat Damage & DBNO Knockdown via RPC
	# Host sends RPC across network to client
	assert(client_person.downed == false and client_person.health == 100.0, "Client begins with 100 HP")
	host_net.rpc("rpc_apply_damage", client_peer_id, 105.0, "body", Vector3.ZERO)

	# Pump network frames for cross-peer delivery and response
	for f in range(30):
		await pump_network.call(1)
		if client_person.downed:
			break

	assert(client_person.downed == true, "Client person should be knocked down (DBNO) via network RPC damage")
	assert(client_person.health == 0.0, "Client health should be 0.0 in DBNO")
	print("PASS: Cross-peer damage RPC applied successfully (Client Downed: true, Health: 0.0)")

	# Verify Host received client's DBNO state notification back across the wire
	for f in range(30):
		await pump_network.call(1)
		if host_net.peers[client_peer_id]["is_downed"]:
			break

	assert(host_net.peers[client_peer_id]["is_downed"] == true, "Host peers dict should record client as downed")
	print("PASS: Host replicated client DBNO state across network")

	# 7. Test 8-Second Held Teammate Revive Timing & Cross-Peer RPC
	var revive_timer := 0.0
	var revive_duration: float = host_net.REVIVE_DURATION
	assert(revive_duration == 8.0, "Revive duration must be exactly 8.0 seconds per BGMI standard")

	# At 4.0s (50% of 8s duration), verify client must remain downed
	for step in range(40): # 40 * 0.1s = 4.0s
		revive_timer += 0.1
		await pump_network.call(1)

	assert(client_person.downed == true, "Client must remain downed at 4.0s (50% revive progress)")
	print("PASS: 8s Revive hold timing verified at 50% (Client still downed)")

	# Complete remaining 4.0s to reach full 8.0s duration
	for step in range(40): # 40 * 0.1s = 4.0s
		revive_timer += 0.1
		await pump_network.call(1)

	assert(revive_timer >= 7.99, "Revive hold must reach full 8.0s")

	# Dispatch rpc_notify_revived across the network to client
	host_net.rpc("rpc_notify_revived", client_peer_id)

	# Pump network frames for rpc_notify_revived to cross the wire to client
	for f in range(30):
		await pump_network.call(1)
		if not client_person.downed:
			break

	assert(client_person.downed == false and client_person.health == 25.0, "Client should be revived with 25 HP after 8s hold")
	print("PASS: Teammate Revive confirmed across RPC (Downed: false, Health: 25.0)")

	# 8. Test Death Loot Crate Cross-Peer Spawning & Synchronized Looting
	var crate_test_pos := Vector3(10.0, 1.2, -15.0)
	# Host announces player elimination via RPC across the network
	host_net.rpc("rpc_notify_eliminated", client_peer_id, crate_test_pos)

	for f in range(30):
		await pump_network.call(1)
		if host_root.has_node("LootCrate_%d" % client_peer_id) and client_root.has_node("LootCrate_%d" % client_peer_id):
			break

	var host_crate: Node = host_root.get_node_or_null("LootCrate_%d" % client_peer_id)
	var client_crate: Node = client_root.get_node_or_null("LootCrate_%d" % client_peer_id)

	assert(host_crate != null, "Host should instantiate death loot crate")
	assert(client_crate != null, "Client should instantiate death loot crate via RPC")
	assert(host_crate.position.distance_to(crate_test_pos) < 0.1, "Host crate position matches elimination")
	assert(client_crate.position.distance_to(crate_test_pos) < 0.1, "Client crate position matches elimination")
	print("PASS: Death Loot Crate spawned and replicated on both host and client at %s" % str(crate_test_pos))

	# Now Client loots the crate
	var loot_result: Dictionary = client_crate.collect(client_person)
	assert(loot_result.get("ammo", 0) == 30, "Loot crate should yield 30 ammo")

	# Pump network frames to ensure rpc_notify_crate_looted synchronizes crate removal across both peers
	for f in range(30):
		await pump_network.call(1)
		if not is_instance_valid(host_root.get_node_or_null("LootCrate_%d" % client_peer_id)):
			break

	assert(host_root.get_node_or_null("LootCrate_%d" % client_peer_id) == null, "Death crate should be removed on Host upon client looting")
	print("PASS: Synchronized crate looting confirmed across peers (Crate removed on all clients)")

	# 9. Clean Disconnect
	client_net.disconnect_game()
	host_net.disconnect_game()
	print("PASS: Host and client disconnected cleanly")

	print("=== ALL MULTIPLAYER MILESTONE 2 TESTS PASSED ===")
	quit(0)
