extends AudioStreamPlayer3D

## Engine sound driven by the real rpm and gear from the car's gearbox, plus
## starter crank, turbo whistle, road noise, tyre squeal and a dual-tone horn.
## Cars with an engine recording play real recorded loops, crossfaded and pitched
## to the rpm; others use a synthesised engine (gruff diesel by default, or smooth
## petrol firing with harmonics and induction roar). Everything is bundled, so the
## game stays offline.

const MIX_RATE := 22050.0
const DrivetrainProfile := preload("res://scripts/player/drivetrain_profile.gd")
const EngineRecording := preload("res://scripts/player/engine_recording.gd")
## Thar defaults; configure() replaces them with the car's own engine.
const IDLE_RPM := 750.0
const REDLINE_RPM := 4200.0
const CRANK_RPM := 220.0
const CRANK_DURATION := 0.7
const CATCH_RPM := 1150.0
const CATCH_DURATION := 0.35
const FADE_TIME := 0.4
const HORN_FREQUENCIES := Vector2(415.0, 520.0)
## Per-sample decay of the injector clatter burst (~6 ms).
const CLATTER_DECAY := 0.993
const MAX_FRAMES_PER_UPDATE := 4096
## Recorded loops take over from the synthesised starter once the engine catches.
const RECORDING_FADE_TIME := 0.3
## The loops are free revs; coasting sounds quieter than pulling under load.
const RECORDING_COAST_DB := -5.0

var engine_running := false
var idle_rpm := IDLE_RPM
var redline_rpm := REDLINE_RPM
var _cylinders := 4
var _clatter_level := 0.55
var _turbo_level := 0.05
var rpm := 0.0
var gear := 1
var horn_pressed := false
var _target_rpm := 0.0
var _engine_rpm := 0.0
var _load := 0.0
var _boost := 0.0
var _speed := 0.0
var _slip := 0.0
var _crank_timer := 0.0
var _catch_timer := 0.0
var _gain := 0.0
var _horn_gain := 0.0
var _playback: AudioStreamGeneratorPlayback
var _fire_phase := 0.0
var _crank_phase := 0.0
var _turbo_phase := 0.0
var _squeal_phase := 0.0
var _vibrato_phase := 0.0
var _horn_phases := Vector2.ZERO
var _fire_amplitude := 1.0
var _clatter := 0.0
var _clatter_lowpass := 0.0
var _intake_lowpass := 0.0
var _exhaust_lowpass := 0.0
var _road_lowpass := 0.0
var _squeal_lowpass := 0.0
var _horn_lowpass := 0.0
var _recording: EngineRecording
var _layers: Array[AudioStreamPlayer3D] = []
var _start_player: AudioStreamPlayer3D
var _recording_mix := 0.0

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.15
	stream = generator
	unit_size = 10.0
	volume_db = -4.0

func configure(profile: DrivetrainProfile) -> void:
	idle_rpm = profile.idle_rpm
	redline_rpm = profile.redline_rpm
	_cylinders = profile.cylinders
	_clatter_level = profile.diesel_clatter
	_turbo_level = profile.turbo_whine
	_recording = profile.engine_recording as EngineRecording
	_build_layers()

func _build_layers() -> void:
	for layer in _layers:
		layer.queue_free()
	_layers.clear()
	if _start_player:
		_start_player.queue_free()
		_start_player = null
	if _recording == null:
		return
	if _recording.start_sound:
		_start_player = _make_player(_recording.start_sound)
	for loop in _recording.loops:
		var layer := _make_player(loop)
		layer.volume_db = -80.0
		_layers.append(layer)

func _make_player(sound: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = sound
	player.unit_size = unit_size
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	return player

func has_recording() -> bool:
	return not _layers.is_empty()

## Equal-power crossfade weights over loops recorded at `loop_rpms`, spaced by pitch ratio.
static func layer_weights(engine_rpm: float, loop_rpms: Array[float]) -> Array[float]:
	var weights: Array[float] = []
	weights.resize(loop_rpms.size())
	weights.fill(0.0)
	if engine_rpm <= loop_rpms[0]:
		weights[0] = 1.0
		return weights
	for index in loop_rpms.size() - 1:
		if engine_rpm <= loop_rpms[index + 1]:
			var t := log(engine_rpm / loop_rpms[index]) / log(loop_rpms[index + 1] / loop_rpms[index])
			weights[index] = cos(t * PI * 0.5)
			weights[index + 1] = sin(t * PI * 0.5)
			return weights
	weights[-1] = 1.0
	return weights

## Starts (with a starter crank) or shuts the engine down. Safe to call every frame.
func set_running(value: bool) -> void:
	if value == engine_running:
		return
	engine_running = value
	if value:
		_crank_timer = CRANK_DURATION
		_catch_timer = 0.0
		if _start_player:
			# The loops take over halfway through the recorded start-up.
			_crank_timer = _start_player.stream.get_length() * 0.5
			_start_player.play()
		gear = 1
		if not playing:
			rpm = 0.0
			_playback = null
			play()
	else:
		horn_pressed = false
		_slip = 0.0
		if _start_player:
			_start_player.stop()

## The car's gearbox reports the real engine speed and selected gear each physics step.
func set_engine_rpm(value: float, selected_gear: int) -> void:
	_engine_rpm = value
	gear = selected_gear

## Fed from the car's physics step.
func update_drive_state(speed: float, throttle: float, slip: float, horn: bool, delta: float) -> void:
	_speed = absf(speed)
	_slip = slip
	horn_pressed = horn
	var drive := maxf(throttle, 0.0) if speed >= -0.5 else absf(throttle)
	# Spinning tyres let the engine flare above what the converter alone allows.
	_target_rpm = clampf(_engine_rpm + slip * 600.0 * drive, idle_rpm, redline_rpm)
	_load = move_toward(_load, drive, 4.0 * delta)

func _process(delta: float) -> void:
	if not playing:
		return
	_update_engine_state(delta)
	_update_layers(delta)
	if not engine_running and _gain <= 0.0 and _horn_gain <= 0.0:
		stop()
		_playback = null
		return
	if _playback == null:
		if not has_stream_playback():
			return
		_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	var frames := mini(_playback.get_frames_available(), MAX_FRAMES_PER_UPDATE)
	if frames > 0:
		_playback.push_buffer(render(frames))

func _update_engine_state(delta: float) -> void:
	var target_gain := 0.0
	if engine_running:
		target_gain = 1.0
		if _crank_timer > 0.0:
			_crank_timer -= delta
			_target_rpm = CRANK_RPM
			if _crank_timer <= 0.0:
				_catch_timer = CATCH_DURATION
		elif _catch_timer > 0.0:
			_catch_timer -= delta
			_target_rpm = maxf(_target_rpm, CATCH_RPM)
	else:
		_target_rpm = 0.0
		_load = 0.0
	_gain = move_toward(_gain, target_gain, delta / FADE_TIME)
	var rise := 9000.0 if _crank_timer > 0.0 or _catch_timer > 0.0 else 5000.0
	rpm = move_toward(rpm, _target_rpm, (rise if rpm < _target_rpm else 3500.0) * delta)
	var rpm_ratio := clampf(rpm / redline_rpm, 0.0, 1.0)
	_boost = move_toward(_boost, _load * rpm_ratio, (1.2 if _load * rpm_ratio > _boost else 3.0) * delta)

func _update_layers(delta: float) -> void:
	if _layers.is_empty():
		return
	var caught := engine_running and _crank_timer <= 0.0
	_recording_mix = move_toward(_recording_mix, 1.0 if caught else 0.0, delta / RECORDING_FADE_TIME)
	var level := _gain * _recording_mix
	if level <= 0.0:
		for layer in _layers:
			if layer.playing:
				layer.stop()
		return
	var weights := layer_weights(maxf(rpm, 1.0), _recording.loop_rpms)
	var trim := volume_db + _recording.volume_db + lerpf(RECORDING_COAST_DB, 0.0, _load)
	for index in _layers.size():
		var layer := _layers[index]
		if not layer.playing:
			layer.play()
		layer.pitch_scale = clampf(rpm / _recording.loop_rpms[index], 0.25, 4.0)
		layer.volume_db = linear_to_db(maxf(weights[index] * level, 0.0001)) + trim

## Synthesises the next block of stereo frames from the current engine state.
func render(frame_count: int) -> PackedVector2Array:
	var buffer := PackedVector2Array()
	buffer.resize(frame_count)
	var rpm_ratio := clampf(rpm / redline_rpm, 0.0, 1.0)
	# A four-stroke fires half its cylinders every crank revolution.
	var crank_step := rpm / 60.0 / MIX_RATE
	var fire_step := crank_step * _cylinders * 0.5
	var exhaust_coefficient := 0.1 + 0.25 * _load + 0.15 * rpm_ratio
	# A recording replaces the synthesised engine once the starter has caught.
	var synth_level := 0.0 if _start_player else 1.0 - _recording_mix
	var exhaust_gain := (0.55 + 0.35 * _load + 0.3 * rpm_ratio) * _gain * synth_level
	var clatter_strength := _clatter_level * (1.0 - 0.6 * rpm_ratio) * (0.6 + 0.4 * _load)
	var turbo_step := (1800.0 + 2600.0 * _boost) / MIX_RATE
	var turbo_gain := _boost * _turbo_level * _gain
	var road_gain := clampf(_speed / 22.0, 0.0, 1.0) * 0.12
	var squeal_gain := _slip * clampf(_speed / 4.0, 0.0, 1.0) * 0.3
	var horn_target := 0.35 if horn_pressed and engine_running else 0.0
	var horn_step := 1.0 / (0.01 * MIX_RATE)
	# Petrol engines (no injector knock) fire evenly, ring with upper harmonics and
	# draw an induction roar at high rpm; the diesel path is unchanged when this is 0.
	var petrol := 1.0 - clampf(_clatter_level / 0.3, 0.0, 1.0)
	var jitter := lerpf(0.2, 0.05, petrol)
	exhaust_coefficient = minf(exhaust_coefficient + 0.3 * petrol, 0.9)
	var ring_gain := 0.3 * petrol
	var intake_gain := petrol * rpm_ratio * rpm_ratio * (0.3 + 0.7 * _load) * 0.18 * _gain
	for index in frame_count:
		_fire_phase += fire_step
		if _fire_phase >= 1.0:
			# Each cylinder fires a little differently: that unevenness is the diesel growl.
			_fire_phase -= 1.0
			_fire_amplitude = randf_range(1.0 - jitter, 1.0 + jitter)
			_clatter = clatter_strength * randf_range(0.7, 1.0)
		var decay := 1.0 - _fire_phase
		decay *= decay
		var thump := (decay * decay - 0.2) * _fire_amplitude
		_crank_phase = fmod(_crank_phase + crank_step, 1.0)
		var lope := sin(TAU * _crank_phase) * 0.35
		var white := randf() * 2.0 - 1.0
		_clatter_lowpass += (white - _clatter_lowpass) * 0.25
		var clatter := (white - _clatter_lowpass) * _clatter
		_clatter *= CLATTER_DECAY
		_exhaust_lowpass += (thump * 0.9 + lope * 0.5 + clatter * 0.6 - _exhaust_lowpass) * exhaust_coefficient
		var sample := _exhaust_lowpass * exhaust_gain
		if petrol > 0.0:
			var ring := sin(TAU * _fire_phase * 2.0) * 0.6 + sin(TAU * _fire_phase * 3.0) * 0.4
			sample += ring * decay * ring_gain * exhaust_gain
			_intake_lowpass += (white - _intake_lowpass) * 0.5
			sample += (white - _intake_lowpass) * intake_gain
		_turbo_phase = fmod(_turbo_phase + turbo_step, 1.0)
		sample += sin(TAU * _turbo_phase) * turbo_gain
		_road_lowpass += (white - _road_lowpass) * 0.04
		sample += _road_lowpass * road_gain
		if squeal_gain > 0.005:
			_vibrato_phase = fmod(_vibrato_phase + 6.0 / MIX_RATE, 1.0)
			_squeal_phase = fmod(_squeal_phase + (780.0 + 35.0 * sin(TAU * _vibrato_phase)) / MIX_RATE, 1.0)
			_squeal_lowpass += (white - _squeal_lowpass) * 0.3
			sample += (sin(TAU * _squeal_phase) * 0.6 + _squeal_lowpass * 0.4) * squeal_gain
		_horn_gain = move_toward(_horn_gain, horn_target, horn_step * 0.35)
		if _horn_gain > 0.0:
			_horn_phases.x = fmod(_horn_phases.x + HORN_FREQUENCIES.x / MIX_RATE, 1.0)
			_horn_phases.y = fmod(_horn_phases.y + HORN_FREQUENCIES.y / MIX_RATE, 1.0)
			var horn := (1.0 if _horn_phases.x < 0.5 else -1.0) + (1.0 if _horn_phases.y < 0.5 else -1.0)
			_horn_lowpass += (horn - _horn_lowpass) * 0.2
			sample += _horn_lowpass * 0.5 * _horn_gain
		sample = clampf(sample, -1.0, 1.0)
		buffer[index] = Vector2(sample, sample)
	return buffer
