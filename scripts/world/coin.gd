extends Area3D

signal collected

var _collected := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	rotate_y(delta * 2.5)

func _on_body_entered(body: Node3D) -> void:
	if _collected or not body is CharacterBody3D:
		return
	_collected = true
	collected.emit()
	queue_free()
