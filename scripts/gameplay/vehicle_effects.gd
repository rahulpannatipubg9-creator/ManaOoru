extends Node3D
var vehicle: Node3D
var gameplay: Node
var smoke: GPUParticles3D
var tire_smoke: GPUParticles3D
var wrecked := false

func _ready() -> void:
	smoke = GPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 1.6
	smoke.position = Vector3(0, 1.0, 1.1)
	smoke.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 24
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 0.3, 0)
	process.scale_min = 0.4
	process.scale_max = 1.2
	process.color = Color(0.22, 0.23, 0.25, 0.35)
	smoke.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.85, 0.85)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	smoke.draw_pass_1 = mesh
	smoke.emitting = false
	add_child(smoke)

	# Dynamic tire smoke puffs on drift / wheel slip
	tire_smoke = GPUParticles3D.new()
	tire_smoke.amount = 20
	tire_smoke.lifetime = 0.75
	tire_smoke.position = Vector3(0, 0.3, -1.2)
	tire_smoke.local_coords = false
	var tire_process := ParticleProcessMaterial.new()
	tire_process.direction = Vector3.UP
	tire_process.spread = 40.0
	tire_process.initial_velocity_min = 0.6
	tire_process.initial_velocity_max = 1.4
	tire_process.gravity = Vector3(0, 0.4, 0)
	tire_process.scale_min = 0.3
	tire_process.scale_max = 0.9
	tire_process.color = Color(0.9, 0.9, 0.9, 0.26)
	tire_smoke.process_material = tire_process
	var tire_mesh := QuadMesh.new()
	tire_mesh.size = Vector2(0.7, 0.7)
	var tire_mat := StandardMaterial3D.new()
	tire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	tire_mat.vertex_color_use_as_albedo = true
	tire_mesh.material = tire_mat
	tire_smoke.draw_pass_1 = tire_mesh
	tire_smoke.emitting = false
	add_child(tire_smoke)

func _process(_delta: float) -> void:
	if not vehicle:
		return
	smoke.emitting = vehicle.get("condition") != null and float(vehicle.condition) < 35.0
	if vehicle.get("tyre_slip") != null:
		var slip: float = float(vehicle.tyre_slip)
		var speed: float = absf(float(vehicle.get("current_speed"))) if vehicle.get("current_speed") != null else 0.0
		tire_smoke.emitting = slip > 0.16 and speed > 1.2
	if vehicle.get("condition") != null and float(vehicle.condition) > 0:
		wrecked = false
	elif not wrecked and gameplay:
		wrecked = true
		gameplay.explode(vehicle.global_position)
