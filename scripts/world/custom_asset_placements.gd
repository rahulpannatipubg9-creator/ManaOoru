class_name CustomAssetPlacements
extends Node3D

## Dynamic loader and spawner for custom 3D assets imported into ManaOoru.
## Reads asset configurations from res://data/world/custom_placements.json.
## Follows all ManaOoru engineering rules and lessons:
## - Enforces level ground height to avoid floating or sunken assets.
## - Strips any accidental Light3D nodes to prevent scene burnout.
## - Sets visibility_range_end strictly on GeometryInstance3D children.
## - Generates proper static colliders so vehicles and player interact with them.

const PLACEMENTS_DATA_PATH := "res://data/world/custom_placements.json"
const DEFAULT_VISIBILITY := 250.0

var loaded_count := 0
var spawned_nodes: Array[Node3D] = []

func _init() -> void:
	name = "CustomPlacements"

func build(world: Node) -> void:
	if not FileAccess.file_exists(PLACEMENTS_DATA_PATH):
		print("CustomAssetPlacements: No custom placements file found. Skipping.")
		return
	
	var content := FileAccess.get_file_as_string(PLACEMENTS_DATA_PATH)
	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary) or not parsed.has("assets"):
		push_warning("CustomAssetPlacements: Invalid JSON format in " + PLACEMENTS_DATA_PATH)
		return
	
	var assets_array: Array = parsed["assets"]
	for item in assets_array:
		if not (item is Dictionary):
			continue
		var asset_dict: Dictionary = item
		_spawn_asset(world, asset_dict)
	
	print("CustomAssetPlacements: Successfully spawned %d custom assets into the world." % loaded_count)

func _spawn_asset(world: Node, data: Dictionary) -> void:
	var model_path: String = data.get("model_path", "")
	if model_path.is_empty() or not (FileAccess.file_exists(model_path) or ResourceLoader.exists(model_path)):
		push_warning("CustomAssetPlacements: Model path not found: " + model_path)
		return
	
	var scene := load(model_path) as PackedScene
	if scene == null:
		push_warning("CustomAssetPlacements: Failed to load scene: " + model_path)
		return
	
	var instance := scene.instantiate() as Node3D
	if instance == null:
		push_warning("CustomAssetPlacements: Instantiated root is not Node3D: " + model_path)
		return
	
	var asset_id: String = data.get("id", "custom_asset")
	instance.name = asset_id
	
	# Strip any accidental lights or cameras that might exist
	for light in instance.find_children("*", "Light3D", true, false):
		light.queue_free()
	for cam in instance.find_children("*", "Camera3D", true, false):
		cam.queue_free()
	
	# Determine Position
	var pos_arr: Array = data.get("position", [0.0, 0.0, 0.0])
	var map_x: float = float(pos_arr[0])
	var map_z: float = float(pos_arr[2]) if pos_arr.size() > 2 else float(pos_arr[1])
	
	var ground_y := 0.0
	if data.get("use_ground_height", true) and world.has_method("ground_height"):
		ground_y = float(world.ground_height(Vector2(map_x, map_z)))
	else:
		ground_y = float(pos_arr[1])
	
	var ground_offset: float = float(data.get("ground_offset_y", 0.02))
	instance.position = Vector3(map_x, ground_y + ground_offset, map_z)
	
	# Rotation & Scale
	var yaw_deg: float = float(data.get("rotation_y_deg", 0.0))
	instance.rotation.y = deg_to_rad(yaw_deg)
	
	var scale_arr: Array = data.get("scale", [1.0, 1.0, 1.0])
	if scale_arr.size() == 3:
		instance.scale = Vector3(float(scale_arr[0]), float(scale_arr[1]), float(scale_arr[2]))
	
	# Visibility range (Lesson: Set only on GeometryInstance3D, never on base Node3D)
	var vis_dist: float = float(data.get("visibility_range_end", DEFAULT_VISIBILITY))
	for geom in instance.find_children("*", "GeometryInstance3D", true, false):
		var g := geom as GeometryInstance3D
		if g:
			g.visibility_range_end = vis_dist
	
	# Collision Setup
	var collision_type: String = data.get("collision_type", "trimesh")
	var existing_bodies := instance.find_children("*", "CollisionObject3D", true, false)
	if existing_bodies.is_empty():
		_setup_collision(instance, collision_type, data)
	
	# Metadata tagging
	instance.set_meta("custom_asset", true)
	instance.set_meta("location_name", data.get("location_name", "Unknown"))
	instance.set_meta("district", data.get("district", "Godavarikhani"))
	
	add_child(instance)
	spawned_nodes.append(instance)
	loaded_count += 1

func _setup_collision(root: Node3D, collision_type: String, data: Dictionary) -> void:
	if collision_type == "trimesh":
		for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
			var m := mesh_node as MeshInstance3D
			if m and m.mesh:
				m.create_trimesh_collision()
	elif collision_type == "box":
		var aabb := _calculate_aabb(root)
		var body := StaticBody3D.new()
		body.name = "AutoBoxCollider"
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		col.shape = box
		col.position = aabb.get_center()
		body.add_child(col)
		root.add_child(body)
	elif collision_type == "cylinder":
		var aabb := _calculate_aabb(root)
		var body := StaticBody3D.new()
		body.name = "AutoCylinderCollider"
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(aabb.size.x, aabb.size.z) * 0.4
		cyl.height = maxf(aabb.size.y, 0.5)
		col.shape = cyl
		col.position = aabb.get_center()
		body.add_child(col)
		root.add_child(body)

func _calculate_aabb(root: Node3D) -> AABB:
	var total_aabb := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh and mesh.mesh:
			var box := mesh.get_aabb()
			if first:
				total_aabb = box
				first = false
			else:
				total_aabb = total_aabb.merge(box)
	if first:
		# Fallback if no meshes found
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return total_aabb
