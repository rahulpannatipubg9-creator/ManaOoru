extends Resource

## A set of real engine recordings, each a seamless loop held at one rpm.
## The engine sound crossfades between the two loops nearest the current rpm
## and pitches them to match, like the sample-based engines in racing games.

## Loops in ascending rpm order; each must import with Forward loop mode.
@export var loops: Array[AudioStream] = []
## Engine speed each loop was recorded at, same order as `loops`.
@export var loop_rpms: Array[float] = []
## Level trim for the whole set, in dB.
@export var volume_db: float = 0.0
## Optional recorded start-up; replaces the synthesised starter crank.
@export var start_sound: AudioStream
