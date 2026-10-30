extends Area3D

## A rifle lying on the street (BGMI-style loot). Walk into it to pick it up: the
## first one puts that rifle in your hands ready to fire, a rifle you don't have yet
## goes on your back (key 2 or the swap button brings it out), and either way the
## magazine is filled and spare rounds added. It comes back after RESPAWN_SECONDS.

const Weapons := preload("res://scripts/gameplay/weapon_catalog.gd")
const RESPAWN_SECONDS := 60.0
const MAGAZINE := 24
const RESERVE_BONUS := 60
const RESERVE_CAP := 999

var gameplay: Node
## Which rifle lies here (weapon_catalog.gd); set before it enters the tree.
var weapon_id := Weapons.M416
var _used := false
var _visual: Node3D

func _ready() -> void:
	add_to_group("weapon_pickups")
	collision_layer = 0
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.2
	collision.shape = shape
	collision.position.y = 0.6
	add_child(collision)
	_visual = Node3D.new()
	_visual.position.y = 0.35
	add_child(_visual)
	var rifle := Weapons.build(weapon_id)
	rifle.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	_visual.add_child(rifle)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.62
	ring.mesh = torus
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.82, 0.25, 0.9)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = glow
	ring.position.y = 0.04
	add_child(ring)
	body_entered.connect(_collect)

func _process(delta: float) -> void:
	if visible:
		_visual.rotate_y(delta * 1.2)

func is_available() -> bool:
	return not _used

func _collect(body: Node) -> void:
	if _used or gameplay == null or body != gameplay.game.person:
		return
	var first: bool = not gameplay.has_rifle
	var new_rifle: bool = not gameplay.rifles().has(weapon_id)
	if not new_rifle and gameplay.reserve >= RESERVE_CAP:
		return
	gameplay.give_rifle(weapon_id)
	var rifle_name := Weapons.display_name(weapon_id)
	if first:
		gameplay.select_rifle(weapon_id)
	gameplay.ammo = MAGAZINE
	gameplay.reserve = mini(RESERVE_CAP, gameplay.reserve + RESERVE_BONUS)
	if first:
		# Picking a rifle up means you want to use it: hands it over ready to fire.
		if not gameplay.action_mode:
			gameplay.set_action_mode(true)
		gameplay.game.person.set_weapon_equipped(true)
		gameplay.life.toast("Picked up %s" % rifle_name)
	elif new_rifle:
		gameplay.life.toast("Picked up %s" % rifle_name)
		gameplay.life.hint("rifle_swap", "Swap rifles with 2 or the swap button")
	else:
		gameplay.life.toast("%d %s rounds" % [RESERVE_BONUS, rifle_name])
	gameplay.life.save_progress()
	_used = true
	hide()
	set_deferred("monitoring", false)
	get_tree().create_timer(RESPAWN_SECONDS, false).timeout.connect(func() -> void:
		_used = false
		show()
		set_deferred("monitoring", true))
