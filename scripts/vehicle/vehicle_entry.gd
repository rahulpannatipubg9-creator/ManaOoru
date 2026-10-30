extends Node

## GTA-style getting in and out of a car. Entering: the person walks to the
## driver's door, the door opens, they climb into the seat and the door shuts.
## Exiting is the reverse. While driving the person stays in the seat, following
## the car every frame, with the test character (if loaded) posed at the wheel.
## main.gd owns control authority; this node only moves the person and plays
## the door sounds, then reports `finished`.
##
## Runs per rendered frame against the car's *interpolated* transform, with the
## person's own physics interpolation switched off while scripted, so the driver
## stays glued to the seat instead of trailing the car by one physics tick.

signal finished(entered: bool)

const DOOR_OPEN := preload("res://assets/audio/car_doors/door_open.wav")
const DOOR_CLOSE := preload("res://assets/audio/car_doors/door_close.wav")
const WALK_SPEED := 1.8
## Longest walk to the door before the person is placed there directly.
const MAX_WALK_TIME := 1.6
const OPEN_TIME := 0.4
const CLIMB_TIME := 0.6
const CLOSE_TIME := 0.3
## Height of the hips above the person's feet in the standing model (block figure).
const HIP_HEIGHT := 0.95
## Where the driver's eye sits relative to the hips, for cars without seat measurements.
const EYE_ABOVE_HIP := Vector3(0.0, 0.68, 0.1)
## Car-local hip point on the seat cushion and heel point at the pedals, measured
## by raycasting each car's body mesh. Cars can override with `seat_hip` / `pedal_point`.
const SEATS := {
	"rigid_thar.tscn": [Vector3(-0.36, 0.88, -0.55), Vector3(-0.36, 0.55, 0.15)],
	"player.tscn": [Vector3(-0.36, 0.88, -0.55), Vector3(-0.36, 0.55, 0.15)],
	"porsche_911.tscn": [Vector3(0.32, 0.46, -0.3), Vector3(0.32, 0.38, 0.45)],
	"jeep_compass.tscn": [Vector3(0.37, 0.8, -0.35), Vector3(0.37, 0.66, 0.25)],
}
const DOOR_GAP := 0.5

enum Phase { IDLE, WALK, OPEN, CLIMB, CLOSE, SEATED, EXIT_OPEN, EXIT_CLIMB, EXIT_CLOSE }

var phase := Phase.IDLE
var person: CharacterBody3D
var vehicle: PhysicsBody3D
var _timer := 0.0
var _from := Transform3D()
var _exit_target := Transform3D()
var _door_audio: AudioStreamPlayer3D

func _ready() -> void:
	_door_audio = AudioStreamPlayer3D.new()
	_door_audio.unit_size = 6.0
	add_child(_door_audio)

func is_busy() -> bool:
	return phase != Phase.IDLE and phase != Phase.SEATED

func is_seated() -> bool:
	return phase == Phase.SEATED

func begin_enter(who: CharacterBody3D, car: PhysicsBody3D) -> void:
	person = who
	vehicle = car
	_set_phase(Phase.WALK)

## `exit_position` is a clear spot beside the car chosen by main.gd.
func begin_exit(exit_position: Vector3) -> void:
	var facing := vehicle.global_basis.z
	_exit_target = Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), exit_position)
	_set_phase(Phase.EXIT_OPEN)

## Abandons any sequence (recovery, scene teardown) without touching the person.
func cancel() -> void:
	_set_phase(Phase.IDLE)

## Person root in the driver's seat, in world space.
func seat_transform(car: PhysicsBody3D) -> Transform3D:
	return car.get_global_transform_interpolated() * Transform3D(Basis(), _seat_root_local(car))

## [hip on the cushion, heel at the pedals] in the car's local space.
func seat_points(car: PhysicsBody3D) -> Array[Vector3]:
	if car.get("seat_hip") is Vector3 and car.get("pedal_point") is Vector3 and car.get("seat_hip") != Vector3.ZERO:
		return [car.get("seat_hip"), car.get("pedal_point")]
	var measured: Array = SEATS.get(car.scene_file_path.get_file(), [])
	if measured.size() == 2:
		return [measured[0], measured[1]]
	var pivot := car.get_node_or_null("CameraPivot")
	var eye: Vector3 = pivot.get("first_person_offset") if pivot else Vector3(-0.4, 1.3, 0.0)
	var hip := eye - EYE_ABOVE_HIP
	return [hip, hip + Vector3(0.0, -0.4, 0.75)]

func _seat_root_local(car: PhysicsBody3D) -> Vector3:
	return seat_points(car)[0] - Vector3(0.0, _hip_height(), 0.0)

func _hip_height() -> float:
	var character := _character()
	if character and character.has_method("hip_height") and character.is_active():
		return character.hip_height()
	return HIP_HEIGHT

## Standing spot outside the driver's door, facing the car.
func door_transform(car: PhysicsBody3D) -> Transform3D:
	var car_transform := car.get_global_transform_interpolated()
	var seat_local := car_transform.affine_inverse() * seat_transform(car).origin
	var side := signf(seat_local.x) if absf(seat_local.x) > 0.05 else -1.0
	var spot := car_transform * Vector3(side * (_half_width(car) + DOOR_GAP), 0.0, seat_local.z)
	spot.y = person.global_position.y if person else car.global_position.y
	var towards_car := -car.global_basis.x * side
	return Transform3D(Basis(Vector3.UP, atan2(towards_car.x, towards_car.z)), spot)

func _process(delta: float) -> void:
	if phase == Phase.IDLE or person == null or vehicle == null:
		return
	_timer += delta
	match phase:
		Phase.WALK:
			_walk_to_door(delta)
		Phase.OPEN:
			if _timer >= OPEN_TIME:
				_from = person.global_transform
				_set_phase(Phase.CLIMB)
		Phase.CLIMB:
			_glide(_from, seat_transform(vehicle), _timer / CLIMB_TIME)
			if _timer >= CLIMB_TIME:
				_set_phase(Phase.CLOSE)
		Phase.CLOSE:
			_follow_seat()
			if _timer >= CLOSE_TIME:
				_set_phase(Phase.SEATED)
				finished.emit(true)
		Phase.SEATED:
			_follow_seat()
		Phase.EXIT_OPEN:
			_follow_seat()
			if _timer >= OPEN_TIME:
				_from = person.global_transform
				_set_phase(Phase.EXIT_CLIMB)
		Phase.EXIT_CLIMB:
			_glide(_from, _exit_target, _timer / CLIMB_TIME)
			if _timer >= CLIMB_TIME:
				_set_phase(Phase.EXIT_CLOSE)
		Phase.EXIT_CLOSE:
			if _timer >= CLOSE_TIME:
				_set_phase(Phase.IDLE)
				finished.emit(false)

func _walk_to_door(delta: float) -> void:
	var door := door_transform(vehicle)
	var to_door := door.origin - person.global_position
	to_door.y = 0.0
	var step := WALK_SPEED * delta
	if to_door.length() <= step or _timer >= MAX_WALK_TIME:
		person.global_transform = door
		_set_phase(Phase.OPEN)
		return
	person.global_position += to_door.normalized() * step
	person.rotation.y = lerp_angle(person.rotation.y, atan2(to_door.x, to_door.z), minf(1.0, delta * 12.0))

func _glide(from: Transform3D, to: Transform3D, weight: float) -> void:
	person.global_transform = from.interpolate_with(to, smoothstep(0.0, 1.0, clampf(weight, 0.0, 1.0)))

func _follow_seat() -> void:
	person.global_transform = seat_transform(vehicle)
	var character := _character()
	if character:
		character.set("steering", _steering())
		var left: Variant = vehicle.get("left_hand_grip")
		var right: Variant = vehicle.get("right_hand_grip")
		character.set("use_vehicle_grips", left is Vector3 and right is Vector3 and left != Vector3.ZERO and right != Vector3.ZERO)
		var visual := vehicle.get_node_or_null("TukTukVisual")
		if visual and visual.has_method("driver_grip_points"):
			var contacts: Array[Vector3] = visual.driver_grip_points()
			left = contacts[0]
			right = contacts[1]
		if character.get("use_vehicle_grips"):
			character.set("left_grip_target", left - _seat_root_local(vehicle))
			character.set("right_grip_target", right - _seat_root_local(vehicle))
		# Feet reach for the pedals; the person faces the car's forward axis, so car and person axes match.
		character.set("foot_target", seat_points(vehicle)[1] - _seat_root_local(vehicle))

func _steering() -> float:
	var steer = vehicle.get("_steer")
	var lock = vehicle.get("max_steer_angle")
	if steer is float and lock is float and lock > 0.0:
		return clampf(-steer / lock, -1.0, 1.0)
	return Input.get_axis("left", "right")

func _set_phase(next: Phase) -> void:
	phase = next
	_timer = 0.0
	if person:
		person.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT if next == Phase.IDLE else Node.PHYSICS_INTERPOLATION_MODE_OFF
		if next == Phase.IDLE:
			person.reset_physics_interpolation()
	var character := _character()
	if character:
		character.set("scripted_speed", WALK_SPEED if next == Phase.WALK else -1.0)
		character.set("seated", next in [Phase.CLIMB, Phase.CLOSE, Phase.SEATED, Phase.EXIT_OPEN])
	if next in [Phase.OPEN, Phase.EXIT_OPEN]:
		_play_door(DOOR_OPEN)
	elif next in [Phase.CLOSE, Phase.EXIT_CLOSE]:
		_play_door(DOOR_CLOSE)

func _play_door(sound: AudioStream) -> void:
	if vehicle == null:
		return
	_door_audio.global_position = door_transform(vehicle).origin + Vector3.UP
	_door_audio.stream = sound
	_door_audio.play()

func _character() -> Node:
	return person.get_node_or_null("TestCharacter") if person else null

static func _half_width(car: PhysicsBody3D) -> float:
	var custom_width: Variant = car.get("entry_half_width")
	if custom_width is float and custom_width > 0.0:
		return float(custom_width)
	for child in car.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			return ((child as CollisionShape3D).shape as BoxShape3D).size.x * 0.5
	return 0.95
