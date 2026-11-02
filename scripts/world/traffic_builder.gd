class_name TrafficBuilder
extends "res://scripts/world/traffic_manager.gd"

## Preserve the world's existing TrafficBuilder entry point.
func build(world: Node, data: MapData) -> void:
	setup(world as Node3D, data)
