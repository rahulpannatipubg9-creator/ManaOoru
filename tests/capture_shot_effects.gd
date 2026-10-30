extends SceneTree

## Windowed frame sequence of one shot's tracer, flash and impact puff against a wall, without booting the game:
##   godot --path . --script tests/capture_shot_effects.gd
## Writes outputs/feel_captures/shot_*.png.

const OUT := "res://outputs/feel_captures/"
const ShotEffects := preload("res://scripts/gameplay/shot_effects.gd")

func _init() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(960, 540)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.45, 0.55, 0.68)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	root.add_child(world)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(30.0, 8.0, 0.4)
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 2.0, -20.0)
	root.add_child(wall)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.position = Vector3(-1.6, 1.7, 2.5)
	camera.rotation.y = -0.08
	root.add_child(camera)
	camera.current = true
	var fx: Node3D = ShotEffects.new()
	root.add_child(fx)
	await process_frame
	var muzzle := Vector3(0.0, 1.4, 0.0)
	var impact := Vector3(0.6, 1.5, -19.8)
	fx.flash(muzzle)
	fx.tracer(muzzle, impact)
	fx.puff(impact, Vector3.BACK)
	for index in 8:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(OUT + "shot_%02d.png" % index))
		print("CAPTURE %d tracers %d flash %s" % [index, fx.active_tracers(), fx.flash_visible()])
	quit(0)
