extends RefCounted

## Automatic gearbox with a manual (tiptronic) mode, driven by a drivetrain
## profile. Turns pedal and road speed into engine rpm and wheel force.

enum Mode { AUTOMATIC, MANUAL }

const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
const REVERSE_GEAR := -1
## Shift points as a share of redline, from light to full pedal.
const UPSHIFT_SHARE := Vector2(0.43, 0.88)
const DOWNSHIFT_SHARE := Vector2(0.27, 0.62)
## Closed-throttle drag torque as a share of peak torque, at redline.
const ENGINE_BRAKE_SHARE := 0.2
const SHIFT_TORQUE_SCALE := 0.5
const MIN_SHIFT_INTERVAL := 0.8
## Coming down through the box while braking is quicker than climbing it.
const MIN_DOWNSHIFT_INTERVAL := 0.4
## Below this multiple of idle the box drops a gear even in Manual, as a real tiptronic does.
const ANTI_STALL_IDLE_MULTIPLE := 1.4

var profile: DrivetrainProfile
var mode := Mode.AUTOMATIC
## 1 to gear count forward, REVERSE_GEAR for reverse.
var gear := 1
var rpm := 0.0
var _shift_timer := 0.0
var _since_shift := MIN_SHIFT_INTERVAL
var _peak_torque := 0.0

func _init(drivetrain: DrivetrainProfile = null) -> void:
	profile = drivetrain if drivetrain else DrivetrainProfile.new()
	for point in profile.torque_curve:
		_peak_torque = maxf(_peak_torque, point.y)
	if not profile.automatic_available:
		mode = Mode.MANUAL
	reset()

## Every drive pulls away in first.
func reset() -> void:
	gear = 1
	rpm = profile.idle_rpm
	_shift_timer = 0.0
	_since_shift = MIN_SHIFT_INTERVAL

func toggle_mode() -> void:
	if profile.automatic_available:
		mode = Mode.MANUAL if mode == Mode.AUTOMATIC else Mode.AUTOMATIC

## Tiptronic up-shift; from Automatic it takes manual control, like the real lever.
func request_shift_up() -> void:
	mode = Mode.MANUAL
	if gear >= 1 and gear < gear_count():
		_shift_to(gear + 1)

## Refused when the lower gear would over-rev the engine.
func request_shift_down(speed: float, wheel_radius: float) -> void:
	mode = Mode.MANUAL
	if gear > 1 and _road_rpm(speed, wheel_radius, gear - 1) < profile.redline_rpm * 0.95:
		_shift_to(gear - 1)

func gear_count() -> int:
	return profile.gear_ratios.size()

func label() -> String:
	if gear == REVERSE_GEAR:
		return "R"
	return ("D%d" if mode == Mode.AUTOMATIC else "M%d") % gear

func overall_ratio(selected_gear: int = gear) -> float:
	var ratio := profile.reverse_ratio if selected_gear == REVERSE_GEAR else profile.gear_ratios[selected_gear - 1]
	return ratio * profile.final_drive

## Spinning engine, gears and wheels add to the mass the drive has to accelerate.
func inertia_factor() -> float:
	var ratio := overall_ratio()
	return 1.04 + 0.0015 * ratio * ratio

func engine_torque(engine_rpm: float) -> float:
	var curve := profile.torque_curve
	if engine_rpm <= curve[0].x:
		return curve[0].y
	for index in range(1, curve.size()):
		var point := curve[index]
		if engine_rpm <= point.x:
			var previous := curve[index - 1]
			return lerpf(previous.y, point.y, (engine_rpm - previous.x) / (point.x - previous.x))
	return curve[-1].y

## Advances the driveline one physics step. `throttle` is the car's W/S axis:
## positive drives forward, negative selects reverse once the car has stopped.
## Returns the drive force at the tyres in newtons along the car's forward axis.
func update(speed: float, throttle: float, wheel_radius: float, delta: float) -> float:
	_since_shift += delta
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	if throttle < -0.05 and speed < 0.5 and gear != REVERSE_GEAR:
		_shift_to(REVERSE_GEAR)
	elif throttle > 0.05 and speed > -0.5 and gear == REVERSE_GEAR:
		_shift_to(1)
	var pedal := clampf(-throttle if gear == REVERSE_GEAR else throttle, 0.0, 1.0)
	if gear != REVERSE_GEAR:
		if mode == Mode.AUTOMATIC:
			_automatic_shift(speed, pedal, wheel_radius)
		else:
			_manual_guard(speed, wheel_radius)

	var redline := profile.redline_rpm
	var road_rpm := _road_rpm(speed, wheel_radius, gear)
	# The converter (or slipping clutch) lets the engine run above road speed until it locks up.
	var launch_rpm := lerpf(profile.idle_rpm, profile.launch_rpm, pedal)
	rpm = minf(maxf(road_rpm, launch_rpm), redline)
	var speed_ratio := clampf(road_rpm / rpm, 0.0, 1.0)
	var multiplication := lerpf(profile.launch_torque_ratio, 1.0, speed_ratio)

	var torque := engine_torque(rpm) * pedal * multiplication
	if road_rpm >= redline:
		torque = 0.0
	elif pedal < 0.05 and road_rpm > profile.idle_rpm + 100.0:
		torque = -_peak_torque * ENGINE_BRAKE_SHARE * road_rpm / redline
	if _shift_timer > 0.0:
		torque *= SHIFT_TORQUE_SCALE
	var force := torque * overall_ratio() * profile.driveline_efficiency / wheel_radius
	return -force if gear == REVERSE_GEAR else force

func _road_rpm(speed: float, wheel_radius: float, selected_gear: int) -> float:
	return absf(speed) / (TAU * wheel_radius) * 60.0 * overall_ratio(selected_gear)

## Shift points rise with the pedal: short shifts when cruising, near redline when floored.
func _automatic_shift(speed: float, pedal: float, wheel_radius: float) -> void:
	if _since_shift < MIN_DOWNSHIFT_INTERVAL:
		return
	var road_rpm := _road_rpm(speed, wheel_radius, gear)
	var upshift_rpm := profile.redline_rpm * lerpf(UPSHIFT_SHARE.x, UPSHIFT_SHARE.y, pedal)
	if gear < gear_count() and road_rpm > upshift_rpm:
		if _since_shift >= MIN_SHIFT_INTERVAL:
			_shift_to(gear + 1)
		return
	if gear > 1:
		var lower_rpm := _road_rpm(speed, wheel_radius, gear - 1)
		var downshift_rpm := profile.redline_rpm * lerpf(DOWNSHIFT_SHARE.x, DOWNSHIFT_SHARE.y, pedal)
		if road_rpm < downshift_rpm and lower_rpm < upshift_rpm * 0.85:
			_shift_to(gear - 1)

func _manual_guard(speed: float, wheel_radius: float) -> void:
	if gear > 1 and _road_rpm(speed, wheel_radius, gear) < profile.idle_rpm * ANTI_STALL_IDLE_MULTIPLE:
		_shift_to(gear - 1)

func _shift_to(new_gear: int) -> void:
	if new_gear == gear:
		return
	gear = new_gear
	_shift_timer = profile.shift_time
	_since_shift = 0.0
