extends Resource

## Per-car engine, gearbox and engine-sound character. The defaults are the
## Mahindra Thar 2.2 mHawk diesel: 130 hp / 300 Nm through a 6-speed
## torque-converter automatic (Aisin AC60-family ratios).

@export_group("Gearbox")
@export var gear_ratios: Array[float] = [3.600, 2.090, 1.488, 1.000, 0.687, 0.580]
@export var reverse_ratio: float = 3.732
## Owners report ~1500 rpm at 90 km/h in 6th on 255/65 R18 tyres; this axle ratio matches.
@export var final_drive: float = 4.27
@export var driveline_efficiency: float = 0.88
## False for manual-only cars: they start in Manual and T does nothing.
@export var automatic_available: bool = true
## Seconds of reduced torque while a gear change completes.
@export var shift_time: float = 0.25

@export_group("Engine")
@export var idle_rpm: float = 750.0
@export var redline_rpm: float = 4200.0
## Torque (Nm) against rpm; Thar: flat 300 Nm from 1600 to 2800 rpm, 97 kW at 3750 rpm.
@export var torque_curve: Array[Vector2] = [
	Vector2(750.0, 150.0),
	Vector2(1250.0, 235.0),
	Vector2(1600.0, 300.0),
	Vector2(2800.0, 300.0),
	Vector2(3750.0, 247.0),
	Vector2(4200.0, 205.0),
]
## Engine speed while pulling away: converter stall for automatics, clutch slip for manuals.
@export var launch_rpm: float = 2100.0
## Torque multiplication at launch; 1.0 for a clutch or dual-clutch box.
@export var launch_torque_ratio: float = 1.6

@export_group("Sound")
@export var cylinders: int = 4
## Diesel injector knock; 0 for petrol engines.
@export var diesel_clatter: float = 0.55
## Turbo whistle level; 0 for naturally aspirated engines.
@export var turbo_whine: float = 0.05
## Real recorded engine loops (engine_recording.gd); empty keeps the synthesised engine.
@export var engine_recording: Resource
