extends RefCounted

## The rifles a player can carry, by id. The id is what goes over the network (bit 8 of the synced stance
## code, and the weapon argument of a Team Deathmatch hit claim), so never renumber an existing entry.
##
## Every rifle is presented in the M416's frame: a "Weapon" holder with the bore along +Z at x 0.097,
## y 0.109 (+x is the rifle's left), so the carry, aim and recoil code in person_controller.gd and
## network_player.gd works for all of them. Each model is shifted into that frame by its `offset`; the
## hand grips and the muzzle are given in the holder's space.

const M416 := 0
const AK47 := 1
const BREN2 := 2
const IDS: Array[int] = [M416, AK47, BREN2]

const STATS := {
	M416: {
		"name": "M416",
		# On the touch weapon slot, which is sized for "AR 24/120".
		"short": "M4",
		"scene": "res://assets/models/weapons/m416.glb",
		# Meshes of the M416 model that are not attached to the rifle (checked by measuring each part).
		"loose_parts": ["M416_part_2", "M416_part_3", "M416_part_4"],
		"offset": Vector3.ZERO,
		"muzzle": Vector3(0.10, 0.112, 0.50),
		"grip_right": Vector3(0.085, -0.03, -0.075),
		"grip_left": Vector3(0.135, 0.117, 0.22),
		"auto_interval": 0.11,
		"single_interval": 0.20,
		"body_damage": 28.0,
		"head_damage": 70.0,
		# The Team Deathmatch host refuses claims closer together than this (network jitter allowed for).
		"min_claim_interval": 0.075,
		"recoil": Vector2(0.022, 0.009),
		# Radians per second the view settles back after a burst (feel only; never checked by the host).
		"recoil_recovery": 0.38,
		"kick": 0.045,
	},
	# The AK hits harder and fires slower than the M416 and climbs more: three body hits kill (0.26 s)
	# against the M416's four (0.33 s), but only if the recoil is held. tools/export_ak47.py puts its
	# origin at the top of the pistol grip with the bore 0.04 m above it.
	AK47: {
		"name": "AK-47",
		"short": "AK",
		"scene": "res://assets/models/weapons/ak47.glb",
		"loose_parts": [],
		"offset": Vector3(0.097, 0.069, -0.08),
		"muzzle": Vector3(0.098, 0.109, 0.53),
		"grip_right": Vector3(0.085, 0.024, -0.08),
		"grip_left": Vector3(0.132, 0.104, 0.25),
		"auto_interval": 0.13,
		"single_interval": 0.22,
		"body_damage": 34.0,
		"head_damage": 85.0,
		"min_claim_interval": 0.09,
		"recoil": Vector2(0.034, 0.016),
		"recoil_recovery": 0.30,
		"kick": 0.06,
	},
	# The CZ Bren 2 is a modern 5.56 tactical rifle: fast, flat-shooting with tight recoil
	# and a built-in holographic red-dot sight, foregrip and suppressor.
	BREN2: {
		"name": "CZ Bren 2",
		"short": "Bren",
		"scene": "res://assets/models/weapons/bren2.glb",
		"loose_parts": [],
		"offset": Vector3(0.098, 0.082, -0.08),
		"muzzle": Vector3(0.097, 0.109, 0.503),
		"grip_right": Vector3(0.085, 0.033, -0.08),
		"grip_left": Vector3(0.125, -0.01, 0.23),
		"auto_interval": 0.11,
		"single_interval": 0.20,
		"body_damage": 30.0,
		"head_damage": 75.0,
		"min_claim_interval": 0.075,
		"recoil": Vector2(0.020, 0.008),
		"recoil_recovery": 0.45,
		"kick": 0.042,
	},
}

static func is_valid(id: int) -> bool:
	return STATS.has(id)

static func stats(id: int) -> Dictionary:
	return STATS.get(id, STATS[M416])

static func display_name(id: int) -> String:
	return String(stats(id).name)

static func short_name(id: int) -> String:
	return String(stats(id).short)

## A new "Weapon" holder with the model, its loose parts hidden, and a "Muzzle" marker at the barrel's end.
## The grips are stored as metadata for the character's hands. Loaded on first use, so a phone that never
## sees an AK never loads its textures.
static func build(id: int) -> Node3D:
	var entry := stats(id)
	var holder := Node3D.new()
	holder.name = "Weapon"
	holder.set_meta("weapon_id", id if is_valid(id) else M416)
	holder.set_meta("grip_right", entry.grip_right)
	holder.set_meta("grip_left", entry.grip_left)
	var scene := load(String(entry.scene)) as PackedScene
	if scene != null:
		var model := scene.instantiate() as Node3D
		model.position = entry.offset
		for loose: String in entry.loose_parts:
			var piece := model.find_child(loose, true, false) as Node3D
			if piece != null:
				piece.visible = false
		holder.add_child(model)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = entry.muzzle
	holder.add_child(muzzle)
	return holder
