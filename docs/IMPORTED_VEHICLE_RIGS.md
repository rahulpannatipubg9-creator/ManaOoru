# Imported road vehicle rigs

31 imported four-wheel road vehicles now use the same RigidVehicle suspension, tyre force, collision, control-authority and entry systems as the Thar, Porsche 911 and Jeep Compass. Each has its own scene, original body and rotating wheel meshes, mass, gearing, torque curve, steering, suspension, seats, camera and audio configuration.

## Status and limits

- Driving conversion: implemented for all 31 four-wheel road vehicles in the table. This does not convert the decorative helicopters or watercraft. The pre-existing Bullet scene is separate.
- Full 31-vehicle physics test passed before the final pivot/material/seat refinements; final checks are recorded below after execution.
- These are game handling profiles, not certified vehicle simulations. Published engine targets are distinguished from estimated curves, spring/damper tuning, drag, tyre grip and driver fits in the JSON catalog. Several source filenames do not prove an exact model year or trim.
- The i8 uses a combined hybrid torque approximation; it does not simulate two independent power sources. The electric cars use a single reduction, no combustion idle/start sound, and an inverter/motor sound.
- The Scania has independently spinning extra wheels; the tractor and trailer remain one physics body, without a fifth-wheel joint.
- Original source meshes contain UV, coplanar-overlap and disconnected-detail findings. Geometry QA is not a production-ready pass. New wheel assemblies retain original models; source defects must not be described as fully fixed.

## Vehicles

| Asset | Selected variant / assumption | Mass kg | Nm target | Gears | Drive | Wheels | Triangles |
|---|---|---:|---:|---:|---|---:|---:|
| lamborghini_aventador_svj | 2019 Aventador SVJ | 1575 | 720 | 7 | AWD | 4 | 48990 |
| bmw_i8 | 2015 i8 hybrid (combined game torque approximation) | 1535 | 500 | 6 | AWD | 4 | 48994 |
| porsche_boxster | 981 Boxster S PDK | 1350 | 360 | 7 | RWD | 4 | 48994 |
| tesla_model_x | Model X dual motor (representative 90D) | 2440 | 660 | 1 | AWD | 4 | 48992 |
| toyota_supra_gr | GR Supra 3.0 340 PS | 1570 | 500 | 8 | RWD | 4 | 48972 |
| bmw_x5 | 2014 X5 xDrive35i | 2070 | 400 | 8 | AWD | 4 | 48995 |
| bmw_x6 | X6 xDrive50i F16 | 2245 | 650 | 8 | AWD | 4 | 48924 |
| mini_cooper_s | 2015 Cooper S 3-door automatic | 1250 | 280 | 6 | FWD | 4 | 48995 |
| mazda_cx5 | 2017 CX-5 2.5 AWD | 1655 | 251 | 6 | AWD | 4 | 48995 |
| volvo_xc40 | 2018 XC40 T5 AWD | 1684 | 350 | 8 | AWD | 4 | 38385 |
| audi_q8 | Q8 55 TFSI quattro | 2175 | 500 | 8 | AWD | 4 | 49849 |
| audi_q8_custom | Q8 55 TFSI quattro | 2175 | 500 | 8 | AWD | 4 | 48993 |
| volkswagen_id | 2016 I.D. concept 125 kW (estimated mass and reduction) | 1700 | 290 | 1 | RWD | 4 | 50000 |
| mercedes_sedan | Mercedes S-Class W221 representative S500; source pack variant unspecified | 1955 | 530 | 7 | RWD | 4 | 48906 |
| scania_haul_truck | Scania R-series tractor and trailer; representative R500 | 18000 | 2550 | 12 | RWD | 8 | 48991 |
| ford_transit_camion | Transit 350 box-body 2.2 diesel (estimated laden mass) | 3200 | 350 | 6 | RWD | 4 | 48866 |
| can_am_maverick | Maverick X3 Turbo representative | 718 | 150 | 1 | AWD | 4 | 49816 |
| mercedes_amg_gla35 | 2021 AMG GLA 35 4MATIC | 1680 | 400 | 8 | AWD | 4 | 48996 |
| range_rover_classic | Range Rover L322 4.4 V8 (source pack generation estimate) | 2570 | 440 | 6 | AWD | 4 | 40979 |
| ford_mustang_mach_40 | Mach 40 custom mid-engine Mustang; estimated road tune | 1588 | 850 | 6 | RWD | 4 | 48984 |
| ford_f150_lightning | 2022 F-150 Lightning extended range | 2980 | 1050 | 1 | AWD | 4 | 48996 |
| ford_f150_raptor_2021 | 2021 F-150 Raptor 3.5 EcoBoost | 2600 | 691 | 10 | AWD | 4 | 48895 |
| indian_tgsrtc_bus | TGSRTC bus; representative 12m diesel service bus | 11500 | 1100 | 6 | RWD | 4 | 49374 |
| dodge_charger_f8 | 1969 Charger 440 R/T (model inferred) | 1700 | 651 | 3 | RWD | 4 | 48477 |
| ferrari_250_testa_rossa | 1957 Ferrari 250 Testa Rossa | 800 | 275 | 4 | RWD | 4 | 49870 |
| alfa_romeo_155_v6 | 155 V6 TI DTM (race car, estimated sequential ratios) | 1050 | 294 | 6 | AWD | 4 | 49909 |
| lamborghini_diablo_sv | 1997 Diablo SV | 1530 | 580 | 5 | RWD | 4 | 49982 |
| roush_mustang_96 | 1996 Roush Mustang Stage 3 (representative modified tune) | 1500 | 440 | 5 | RWD | 4 | 49983 |
| shelby_patrol_13 | 2013 Shelby GT500 patrol | 1750 | 856 | 6 | RWD | 4 | 48994 |
| shelby_cobra_68 | 1967 Shelby GT500 (file is Mustang, not Cobra roadster) | 1530 | 569 | 4 | RWD | 4 | 36978 |
| city_transit_bus | RoAZ 5236 city bus representative diesel | 11200 | 1100 | 6 | RWD | 4 | 5562 |

## References

Manufacturer reference links are stored per vehicle in `data/vehicles/imported_vehicle_profiles.json`. Blank source links mean the selected trim has not been independently verified in this change. Masses may use representative curb values rather than the dry weights advertised for supercars.

## Integration

- `scripts/world/custom_asset_placements.gd` loads `drivable_scene` as a physics vehicle and omits decorative static colliders.
- District placements are retained with `placement_spawn`; original roadside vehicles use their own spawn index.
- `scripts/vehicle/imported_vehicle.gd` attaches the measured body/wheel assemblies before the shared controller initializes. Its door interaction follows the actual seat station, including long buses and trucks.
- FWD/RWD/AWD torque shares preserve existing scene defaults. Optional road-speed governors only affect new scenes.
- Parked vehicles retain sleeping physics and muted audio; only the occupied vehicle has input authority.

## Rebuild

Run Blender with `--background --factory-startup --python tools/vehicle_rigging/build_rigs.py`, optionally appending `-- <asset_id>`. Outputs go to `work/vehicle_rigs`, leaving source GLBs intact. Review geometry/material/steering renders before copying approved GLBs into `assets/models/vehicles/<id>/`. `generate_scenes.py` stages scene changes under `work/vehicle_scene_staging`; it does not overwrite live scenes.

## Validation

- PASS: final imported-vehicle regression, 31 vehicles, zero failures (ground contacts, stable ride height, acceleration, steering, wheel spin, redline and parked audio).
- PASS: full-world imported roster, 31 vehicles, zero failures before streaming safeguard (entry registration, district positions, parked controls and no static colliders).
- PASS: existing vehicle-entry regression.
- PASS: movement regression after streaming safeguard; stale seven-vehicle assertion now counts the configured imported roster.
- Rendered: all 31 vehicles with seated player, with a contact sheet in outputs/vehicle_rigs.
- Geometry audit: 159 chassis/wheel assemblies checked across 31 rigs. Only 34 assemblies passed the geometry checker; original overlap, disconnected-detail and UV-area issues remain. This is not a clean asset-QA sign-off. UV-overlap rasterization was stopped because source UV ranges stalled the audit; exact UV-area counts are included instead.
- Existing full-world tests emit renderer/ObjectDB resource-leak messages on shutdown; the same messages existed in the movement baseline.
- Imported vehicles outside 100m are held until the player's streamed district provides ground. Activation checks all wheel support and chassis clearance, searching up to 28m around the district parking position. The original vehicle physics and spawn roster are preserved.
