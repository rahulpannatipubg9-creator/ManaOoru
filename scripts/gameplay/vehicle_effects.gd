extends Node3D
var vehicle: Node3D
var gameplay: Node
var smoke: GPUParticles3D
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
func _process(_delta: float) -> void:
	smoke.emitting = vehicle.condition < 35.0
	if vehicle.condition > 0:
		wrecked = false
	elif not wrecked:
		wrecked = true
		gameplay.explode(vehicle.global_position)
