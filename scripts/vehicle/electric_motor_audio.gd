extends AudioStreamPlayer3D
## Motor/inverter whine, road noise and horn. No combustion starter or exhaust.
const MIX_RATE := 22050.0
var engine_running := false
var rpm := 0.0
var gear := 1
var _speed := 0.0
var _load := 0.0
var _horn := false
var _phase := 0.0
var _horn_phase := 0.0
var _road := 0.0
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.15
	stream = generator
	volume_db = -15.0
	unit_size = 10.0

func configure(_profile: Resource) -> void:
	pass

func set_running(value: bool) -> void:
	if value == engine_running:
		return
	engine_running = value
	if value:
		play()
		_playback = get_stream_playback()
	else:
		mute()

func mute() -> void:
	engine_running = false
	_horn = false
	stop()
	_playback = null

func set_engine_rpm(value: float, selected_gear: int) -> void:
	rpm = value
	gear = selected_gear

func update_drive_state(speed: float, throttle: float, _slip: float, horn: bool, _delta: float) -> void:
	_speed = absf(speed)
	_load = absf(throttle)
	_horn = horn

func _process(_delta: float) -> void:
	if not engine_running or _playback == null:
		return
	var count := mini(_playback.get_frames_available(), 4096)
	var buffer := PackedVector2Array()
	buffer.resize(count)
	for index in count:
		_phase = fmod(_phase + (160.0 + rpm * 0.07) / MIX_RATE, 1.0)
		_horn_phase = fmod(_horn_phase + 440.0 / MIX_RATE, 1.0)
		_road = lerpf(_road, randf_range(-1.0, 1.0), 0.04)
		var moving := clampf(_speed / 4.0, 0.0, 1.0)
		var sample := sin(_phase * TAU) * moving * (0.03 + _load * 0.10)
		sample += _road * clampf(_speed / 50.0, 0.0, 0.3)
		if _horn:
			sample += sin(_horn_phase * TAU) * 0.35
		buffer[index] = Vector2(sample, sample)
	_playback.push_buffer(buffer)
