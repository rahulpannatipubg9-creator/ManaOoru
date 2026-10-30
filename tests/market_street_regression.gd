extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.city_life.save_enabled = false
	var market = game.gameplay.market
	assert(market.shops.size() >= 2, "Market requires at least two safe stalls")
	assert(market.keepers.size() == market.shops.size())
	assert(market.start_delivery())
	assert(not market.start_delivery(), "Cannot overwrite an active job")
	game.person.set_physics_process(false)
	game.person.global_position = market.shops[1].position
	game.gameplay._update_mission(0.1)
	assert(game.gameplay.mission.index == 1)
	var coins: int = game.hud.coins_available()
	game.person.global_position = market.shops[0].position
	game.gameplay._update_mission(0.1)
	assert(game.gameplay.mission.is_empty())
	assert(game.hud.coins_available() == coins + 12)
	market.open_shop(market.shops[0])
	assert(paused and game.city_life.has_modal())
	game.city_life.close_modal()
	print("PASS market: safe stalls, keepers, delivery pickup/dropoff, exact reward, counter modal")
	game.queue_free()
	await process_frame
	quit()
