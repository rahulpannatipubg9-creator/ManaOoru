extends Area3D
class_name LootCrate

@export var ammo_amount := 30
@export var medkits_amount := 1
@export var coins_amount := 15

## The same ceiling as the shop (city_gameplay.gd buy_supply).
const MAX_RESERVE := 999

var crate_id: int = -1
var network_manager: Node = null

var _mesh: MeshInstance3D
var _beacon: MeshInstance3D
var _label: Label3D
var _lifetime := 180.0
var _pulse := 0.0
var _collected := false

func _ready() -> void:
	add_to_group("loot_crates")
	collision_layer = 1
	collision_mask = 1
	monitoring = true

	# Crate Box
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.5, 0.7)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.35, 0.22, 1.0) # Military olive green
	mat.roughness = 0.8
	_mesh.material_override = mat
	_mesh.position.y = 0.25
	add_child(_mesh)

	# Collision Shape for Area3D interaction
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.0, 0.8, 1.0)
	col.shape = box_shape
	col.position.y = 0.25
	add_child(col)

	# Glowing beacon beam (BGMI style green loot crate pillar)
	_beacon = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.08
	cylinder.height = 3.5
	_beacon.mesh = cylinder
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.65)
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon.material_override = beacon_mat
	_beacon.position.y = 1.8
	add_child(_beacon)

	# 3D Billboard label
	_label = Label3D.new()
	_label.text = "Loot"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 20
	_label.modulate = Color(1.0, 0.95, 0.4, 1.0)
	_label.position.y = 1.0
	_label.no_depth_test = true
	add_child(_label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	_pulse += delta * 3.0
	if _beacon and _beacon.material_override is StandardMaterial3D:
		var alpha := 0.4 + 0.3 * sin(_pulse)
		(_beacon.material_override as StandardMaterial3D).albedo_color.a = alpha

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("is_weapon_equipped"):
		_label.text = "[L] Loot"
		_label.modulate = Color(0.3, 1.0, 0.5, 1.0)

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("is_weapon_equipped"):
		_label.text = "Loot"
		_label.modulate = Color(1.0, 0.95, 0.4, 1.0)

## Gives the loot once and leaves the world for this player at once; the host removes it for everyone.
func collect(_by_player: Node3D, gameplay: Node = null) -> Dictionary:
	if _collected:
		return {}
	_collected = true
	remove_from_group("loot_crates")
	visible = false
	var loot := {
		"ammo": ammo_amount,
		"medkits": medkits_amount,
		"coins": coins_amount
	}
	if gameplay:
		if "reserve" in gameplay: gameplay.reserve = mini(MAX_RESERVE, gameplay.reserve + ammo_amount)
		if "medkits" in gameplay: gameplay.medkits += medkits_amount
		var game: Node = gameplay.get("game")
		if game != null and game.get("hud") != null:
			game.hud.add_coins(coins_amount)
	if network_manager and network_manager.is_active():
		network_manager.request_loot(crate_id)
	else:
		queue_free()
	return loot
