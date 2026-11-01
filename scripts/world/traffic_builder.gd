class_name TrafficBuilder
extends TrafficManager

## Preserve the world's existing TrafficBuilder entry point.
func build(world: Node, data: MapData) -> void:
	setup(world as Node3D, data)
