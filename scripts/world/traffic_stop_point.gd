class_name TrafficStopPoint
extends Marker3D

const TrafficLightController := preload("res://scripts/world/traffic_light_controller.gd")

@export var phase_group: int = 0
var progress: float = 0.0
var controller: TrafficLightController

func must_stop() -> bool:
	return controller != null and controller.phase_for_group(phase_group) != "green"
