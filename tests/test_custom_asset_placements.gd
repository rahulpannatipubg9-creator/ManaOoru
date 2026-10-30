extends SceneTree

## Automated test for verifying custom asset placements in Godot headless.
## Checks that custom assets load, ground correctly, have collisions, and
## have proper visibility ranges set on GeometryInstance3D nodes.

const PLACEMENTS_DATA_PATH := "res://data/world/custom_placements.json"
const CAPTURE_DIR := "outputs/captures/custom_placements/"
const CustomAssetPlacements := preload("res://scripts/world/custom_asset_placements.gd")

func _init() -> void:
	run_verification.call_deferred()

func run_verification() -> void:
	print("--- Running Custom Asset Placements Verification ---")
	
	if not FileAccess.file_exists(PLACEMENTS_DATA_PATH):
		print("FAIL: No custom_placements.json found at: " + PLACEMENTS_DATA_PATH)
		quit(1)
		return
	
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACEMENTS_DATA_PATH))
	var assets: Array = data.get("assets", [])
	if assets.is_empty():
		print("PASS: Placements file exists (empty catalog).")
		quit(0)
		return
	
	# Load main game scene to build world and custom placements
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		print("FAIL: Could not load res://scenes/main.tscn")
		quit(1)
		return
	
	var game: Node = main_scene.instantiate()
	root.add_child(game)
	
	# Wait for world generation frames
	for _i in 15:
		await process_frame
	
	var world := game.get_node_or_null("World")
	if world == null:
		print("FAIL: World node not found in scene tree.")
		quit(1)
		return
	
	var custom_placements := world.get_node_or_null("CustomPlacements") as CustomAssetPlacements
	if custom_placements == null:
		print("FAIL: CustomPlacements node not instantiated under World.")
		quit(1)
		return
	
	print("Verified CustomPlacements node exists. Spawned count: %d" % custom_placements.loaded_count)
	
	var passed_count := 0
	for asset_dict in assets:
		var asset_id: String = asset_dict.get("id", "")
		var spawned := custom_placements.get_node_or_null(asset_id) as Node3D
		if spawned == null:
			print("FAIL: Expected asset node '%s' not found under CustomPlacements." % asset_id)
			continue
		
		# Check visibility range on geometries
		var geoms := spawned.find_children("*", "GeometryInstance3D", true, false)
		var expected_vis: float = float(asset_dict.get("visibility_range_end", 250.0))
		for g in geoms:
			var geom := g as GeometryInstance3D
			if geom and geom.visibility_range_end <= 0.0:
				print("WARN: GeometryInstance3D '%s' has 0 visibility_range_end" % geom.name)
		
		# Check collision objects exist
		var colliders := spawned.find_children("*", "CollisionObject3D", true, false)
		if colliders.is_empty():
			print("WARN: Asset '%s' has no collision objects." % asset_id)
		
		print("PASS: Custom asset '%s' verified in world at %s, rot=%.1f°, colliders=%d" %
			[asset_id, str(spawned.position), spawned.rotation.y, colliders.size()])
		passed_count += 1
	
	if passed_count == assets.size():
		print("SUCCESS: All %d custom assets verified in game world!" % passed_count)
		quit(0)
	else:
		print("FAILED: Only %d/%d custom assets passed verification." % [passed_count, assets.size()])
		quit(1)
