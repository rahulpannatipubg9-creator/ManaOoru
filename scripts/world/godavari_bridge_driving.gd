class_name GodavariBridgeDriving
extends Node3D

## Dedicated driving showcase scene for the 1,100 m Godavarikhani Godavari River Bridge.
## Allows immediate testing of high-speed vehicle driving, collisions, barriers, and river views.

const BRIDGE_SCENE := preload("res://Godavarikhani_Bridge_3D/Godavarikhani_Bridge.glb")
const THAR_SCENE := preload("res://scenes/vehicles/rigid_thar.tscn")
const PORSCHE_SCENE := preload("res://scenes/vehicles/porsche_911.tscn")

var driven_vehicle: RigidVehicle
var bridge_instance: Node3D

func _ready() -> void:
	# 1. Atmospheric Environment & Natural Daylight Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	light.light_color = Color("#fff8ee")
	light.light_energy = 0.85
	light.shadow_enabled = true
	add_child(light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#2e6a9e")
	sky_mat.sky_horizon_color = Color("#7ab0d3")
	sky_mat.ground_bottom_color = Color("#2c343b")
	sky_mat.ground_horizon_color = Color("#5f798a")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color("#9bb5c4")
	env.fog_density = 0.0003
	env.fog_sky_affect = 0.1
	env_node.environment = env
	add_child(env_node)

	# 2. Bridge Model
	bridge_instance = BRIDGE_SCENE.instantiate() as Node3D
	# The .glb carries Blender's sun lamps (energy 3,551 and 956); they blow the whole scene out to white.
	# The light and environment above are the scene's lighting.
	for lamp in bridge_instance.find_children("*", "Light3D", true, false):
		lamp.get_parent().remove_child(lamp)
		lamp.free()
	bridge_instance.position = Vector3(0.0, 0.0, 0.0)
	# Orient along -Z (local +X becomes world -Z)
	bridge_instance.rotation_degrees.y = 90.0
	_apply_bridge_materials(bridge_instance)
	_setup_collisions(bridge_instance)
	add_child(bridge_instance)

	# 3. Spawn Player Vehicle on the Northbound Carriageway
	# Local North carriageway center is local Z = -6.75 (maps to world X = -6.75)
	# South Abutment is at local X = -550 (maps to world Z = +550)
	var spawn_pos := Vector3(-6.75, 12.6, 530.0)
	driven_vehicle = spawn_vehicle(THAR_SCENE, spawn_pos, deg_to_rad(180.0), true)

	# Add on-screen UI hint
	var canvas := CanvasLayer.new()
	var label := Label.new()
	label.text = "GODAVARI RIVER BRIDGE (1,100 METRES)\nWASD: Drive | Space: Handbrake | R: Reset | 1: Thar | 2: Porsche | M: Full City Game"
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	canvas.add_child(label)
	add_child(canvas)

func spawn_vehicle(scene: PackedScene, pos: Vector3, yaw: float, drivable: bool) -> RigidVehicle:
	var car := scene.instantiate() as RigidVehicle
	car.paint_color = Color(0.72, 0.05, 0.05)
	car.position = pos
	car.rotation.y = yaw
	add_child(car)
	car.respawn_position = pos
	car.set_driving_enabled(drivable)
	car.set_input_authority(drivable)
	car.set_keyboard_input_enabled(drivable)
	var cam_pivot := car.get_node_or_null("CameraPivot")
	if cam_pivot:
		cam_pivot.set("_yaw", yaw + PI)
		if cam_pivot.has_method("_apply_orbit_rotation"):
			cam_pivot.call("_apply_orbit_rotation")
	var cam := car.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if cam:
		cam.current = drivable
	return car

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_R and driven_vehicle:
		driven_vehicle.recover_vehicle()
	elif event.keycode == KEY_1:
		_switch_vehicle(THAR_SCENE)
	elif event.keycode == KEY_2:
		_switch_vehicle(PORSCHE_SCENE)
	elif event.keycode == KEY_M:
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _switch_vehicle(scene: PackedScene) -> void:
	if not driven_vehicle:
		return
	var cur_trans := driven_vehicle.global_transform
	driven_vehicle.queue_free()
	driven_vehicle = spawn_vehicle(scene, cur_trans.origin + Vector3.UP * 0.2, cur_trans.basis.get_euler().y, true)

func _setup_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.name.begins_with("COL_"):
			var static_body := StaticBody3D.new()
			static_body.name = child.name + "_Static"
			static_body.transform = child.transform
			var is_road := child.name.begins_with("COL_Road")
			static_body.collision_layer = 3 if is_road else 1
			static_body.collision_mask = 0
			var col_shape := CollisionShape3D.new()
			col_shape.shape = child.mesh.create_trimesh_shape()
			static_body.add_child(col_shape)
			child.get_parent().add_child(static_body)
			child.visible = false
		else:
			_setup_collisions(child)

func _apply_bridge_materials(root: Node) -> void:
	var mat_asphalt := StandardMaterial3D.new()
	mat_asphalt.resource_name = "Road_Asphalt"
	mat_asphalt.albedo_color = Color(0.11, 0.11, 0.12)
	mat_asphalt.roughness = 0.86
	mat_asphalt.metallic = 0.02

	var mat_marking := StandardMaterial3D.new()
	mat_marking.resource_name = "Road_Marking_White"
	mat_marking.albedo_color = Color(0.94, 0.94, 0.91)
	mat_marking.roughness = 0.42

	var mat_deck := StandardMaterial3D.new()
	mat_deck.resource_name = "Concrete_Deck"
	mat_deck.albedo_color = Color(0.62, 0.61, 0.58)
	mat_deck.roughness = 0.76

	var mat_pier := StandardMaterial3D.new()
	mat_pier.resource_name = "Concrete_Pier"
	mat_pier.albedo_color = Color(0.58, 0.57, 0.54)
	mat_pier.roughness = 0.82

	var mat_footing := StandardMaterial3D.new()
	mat_footing.resource_name = "Concrete_Footing"
	mat_footing.albedo_color = Color(0.46, 0.45, 0.40)
	mat_footing.roughness = 0.90

	var mat_steel := StandardMaterial3D.new()
	mat_steel.resource_name = "Steel_Galvanized"
	mat_steel.albedo_color = Color(0.76, 0.77, 0.78)
	mat_steel.metallic = 0.95
	mat_steel.roughness = 0.28

	var mat_water := StandardMaterial3D.new()
	mat_water.resource_name = "River_Water"
	mat_water.albedo_color = Color(0.04, 0.20, 0.24, 0.90)
	mat_water.roughness = 0.08
	mat_water.metallic = 0.05
	mat_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mat_sand := StandardMaterial3D.new()
	mat_sand.resource_name = "River_Sand"
	mat_sand.albedo_color = Color(0.69, 0.55, 0.38)
	mat_sand.roughness = 0.92

	var mat_rock := StandardMaterial3D.new()
	mat_rock.resource_name = "River_Rock"
	mat_rock.albedo_color = Color(0.40, 0.30, 0.24)
	mat_rock.roughness = 0.80

	var mat_foliage := StandardMaterial3D.new()
	mat_foliage.resource_name = "Foliage_Green"
	mat_foliage.albedo_color = Color(0.18, 0.34, 0.12)
	mat_foliage.roughness = 0.65

	var mat_pole := StandardMaterial3D.new()
	mat_pole.resource_name = "Streetlight_Paint"
	mat_pole.albedo_color = Color(0.22, 0.24, 0.26)
	mat_pole.metallic = 0.85
	mat_pole.roughness = 0.38

	var mat_led := StandardMaterial3D.new()
	mat_led.resource_name = "Streetlight_LED"
	mat_led.albedo_color = Color(1.0, 0.98, 0.92)
	mat_led.emission_enabled = true
	mat_led.emission = Color(1.0, 0.95, 0.88)
	mat_led.emission_energy_multiplier = 4.0

	var mat_bearing := StandardMaterial3D.new()
	mat_bearing.resource_name = "Neoprene_Bearing"
	mat_bearing.albedo_color = Color(0.10, 0.10, 0.10)
	mat_bearing.roughness = 0.85

	var mat_map: Dictionary = {
		"Road_Asphalt": mat_asphalt,
		"Road_Marking_White": mat_marking,
		"Road_Marking_Yellow": mat_marking,
		"Concrete_Deck": mat_deck,
		"Concrete_Pier": mat_pier,
		"Concrete_Footing": mat_footing,
		"Steel_Galvanized": mat_steel,
		"River_Water": mat_water,
		"River_Sand": mat_sand,
		"River_Rock": mat_rock,
		"Foliage_Green": mat_foliage,
		"Streetlight_Paint": mat_pole,
		"Streetlight_LED": mat_led,
		"Neoprene_Bearing": mat_bearing
	}
	_assign_surface_materials(root, mat_map)

func _assign_surface_materials(node: Node, mat_map: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for surface in mi.mesh.get_surface_count():
				var orig_mat := mi.mesh.surface_get_material(surface)
				var mat_name := ""
				if orig_mat:
					mat_name = orig_mat.resource_name
				if mat_map.has(mat_name):
					mi.set_surface_override_material(surface, mat_map[mat_name])
				else:
					var n := mi.name.to_lower()
					if n.contains("asphalt"):
						mi.set_surface_override_material(surface, mat_map["Road_Asphalt"])
					elif n.contains("line") or n.contains("dash"):
						mi.set_surface_override_material(surface, mat_map["Road_Marking_White"])
					elif n.contains("rail") or n.contains("joint"):
						mi.set_surface_override_material(surface, mat_map["Steel_Galvanized"])
					elif n.contains("pier") or n.contains("shaft"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Pier"])
					elif n.contains("footing"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Footing"])
					elif n.contains("water"):
						mi.set_surface_override_material(surface, mat_map["River_Water"])
					elif n.contains("terrain") or n.contains("sand"):
						mi.set_surface_override_material(surface, mat_map["River_Sand"])
					elif n.contains("rock"):
						mi.set_surface_override_material(surface, mat_map["River_Rock"])
					elif n.contains("tree") or n.contains("foliage"):
						mi.set_surface_override_material(surface, mat_map["Foliage_Green"])
					elif n.contains("pole"):
						mi.set_surface_override_material(surface, mat_map["Streetlight_Paint"])
					elif n.contains("lamp") or n.contains("head"):
						mi.set_surface_override_material(surface, mat_map["Streetlight_LED"])
					elif n.contains("bearing"):
						mi.set_surface_override_material(surface, mat_map["Neoprene_Bearing"])
					elif n.contains("deck") or n.contains("girder") or n.contains("barrier") or n.contains("diaphragm") or n.contains("cap") or n.contains("strut") or n.contains("abutment"):
						mi.set_surface_override_material(surface, mat_map["Concrete_Deck"])

	for child in node.get_children():
		_assign_surface_materials(child, mat_map)
