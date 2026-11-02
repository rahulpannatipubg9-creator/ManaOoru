class_name TrafficLightController
extends Node3D

signal phase_changed(group: int, phase: String)
@export var green_seconds: float = 12.0
@export var yellow_seconds: float = 3.0
var elapsed: float = 0.0
var _last_stage: int = -1

func _physics_process(delta: float) -> void:
	elapsed = fmod(elapsed + delta, 2.0 * (green_seconds + yellow_seconds))
	var stage := int(elapsed / (green_seconds + yellow_seconds)) * 2
	if fmod(elapsed, green_seconds + yellow_seconds) >= green_seconds:
		stage += 1
	if stage != _last_stage:
		_last_stage = stage
		phase_changed.emit(0, phase_for_group(0))
		phase_changed.emit(1, phase_for_group(1))

func phase_for_group(group: int) -> String:
	var half := green_seconds + yellow_seconds
	var time := fmod(elapsed + float(group) * half, half * 2.0)
	if time >= half:
		return "red"
	return "green" if time < green_seconds else "amber"
