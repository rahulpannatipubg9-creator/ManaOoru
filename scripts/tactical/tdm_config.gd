extends Resource

## Rules for one Team Deathmatch match. The host picks the lobby options
## (team size, kill limit, time limit); the rest are fixed in v1.
## See docs/TDM_DESIGN.md.

@export_group("Lobby options")
@export_range(1, 8) var team_size := 4
@export_enum("20", "40", "60") var kill_limit_choice := 1
@export_enum("300", "600", "900") var time_limit_choice := 1
@export_enum("Morning", "Afternoon", "Night") var time_of_day := 1

@export_group("Arena")
@export var arena_center := Vector3.ZERO
@export var arena_radius := 125.0
## Seconds a player may stay outside the ring before dying.
@export var out_of_bounds_seconds := 5.0

@export_group("Flow")
@export var countdown_seconds := 5.0
@export var respawn_seconds := 5.0
@export var spawn_protection_seconds := 3.0
@export var sudden_death_seconds := 60.0
## A team with nobody connected for this long forfeits.
@export var forfeit_seconds := 30.0
## How long a dropped player's slot is held (they are an untargetable ghost meanwhile).
@export var reconnect_hold_seconds := 60.0

@export_group("Combat")
@export var max_health := 100.0
@export var regen_delay_seconds := 5.0
@export var regen_per_second := 10.0
## The host rejects a hit claiming more than this in one shot.
@export var max_hit_damage := 100.0
## Fastest believable fire interval for the M416 (auto fire is 0.11 s in free-roam).
@export var min_shot_interval := 0.075
@export var assist_damage := 30.0
@export var assist_window_seconds := 8.0
## A fall or out-of-bounds death within this window of an enemy hit credits that enemy.
@export var suicide_credit_window_seconds := 5.0

func kill_limit() -> int:
	return [20, 40, 60][kill_limit_choice]

func time_limit_seconds() -> float:
	return [300.0, 600.0, 900.0][time_limit_choice]
