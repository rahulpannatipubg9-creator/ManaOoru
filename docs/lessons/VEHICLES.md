# Vehicles: lessons

Code: `scripts/vehicle/` (`vehicle_entry.gd` for getting in and out and the seat), `scripts/main.gd`
(who controls what), vehicle scenes in `scenes/vehicles/`. Physics background: `docs/PHYSICS_OVERHAUL.md`.

## Adding a new vehicle

1. Measure the driver's **hip point on the seat cushion** and the **heel point at the pedals** in the car's own
   space (raycast the body mesh) and add them to `SEATS` in `vehicle_entry.gd`, or give the car `seat_hip` /
   `pedal_point`. Note which side the wheel is on (the Thar is right-hand drive, x −0.36; the Porsche is
   left-hand drive, x +0.32).
2. If the car has a modelled wheel, give it `left_hand_grip` / `right_hand_grip`; otherwise the hands go to a
   default wheel 0.40 m above and 0.42 m ahead of the hips.
3. Get in and render the driver from both sides and the front (see [TESTING_AND_TOOLS.md](TESTING_AND_TOOLS.md)):
   nothing may poke through the roof, doors or floor.
4. Run `vehicle_entry_regression` and `movement_regression`.

## Entries

### A helicopter parked in mid-air stayed in the sky (2026-10-30)
- **Symptom:** dying in flight, or a match starting in flight, left the helicopter frozen in the air, out of reach.
- **Cause:** `helicopter.gd set_driving_enabled(false)` always freezes the body where it is.
- **Rule:** parking a craft with no ground under its skids sends it to `_safe_landing`.
- **Check:** `save_and_feedback_regression`.

### A wrecked helicopter kept a stale exit prompt (2026-10-30)
- **Symptom:** after a wreck the prompt stayed on "LAND TO EXIT" even on the ground, and a wreck falling out of the
  world was never recovered.
- **Cause:** `helicopter.gd _physics_process` returned on `condition <= 0.0` before the fall check and before
  updating `_grounded`.
- **Rule:** an early return in a vehicle's physics step must not skip the state the HUD reads.
- **Check:** `save_and_feedback_regression`.

### Driver hanging out of the Porsche window (2026-10-29)
- **Symptom:** body half outside the car, an arm out of the window, legs through the floor.
- **Cause:** the character's fixed-angle driving pose, not the seat numbers: the seat put the hips exactly on
  the cushion. Details in [CHARACTERS.md](CHARACTERS.md).
- **Rule:** when a driver looks wrong, first probe where the hips, hands and feet are in the car's space
  against `seat_points()`; that tells you whether the seat or the pose is at fault.
- **Check:** `vehicle_entry_regression` plus side and front renders in every car type.

### Cars behave like walls when they hit each other (before 2026-10-29)
- **Cause:** kinematic `CharacterBody3D` cars and `move_and_slide()` exchange no momentum; parked cars had
  physics switched off, and entering a car lifted it to at least 1.2 m (teleporting cars on low ground).
- **Rule:** never write a car's height or rotation directly to "fix" it; use the rigid car and its suspension.
  See `docs/PHYSICS_OVERHAUL.md`.

### All parked cars moved with the player's input (early prototype)
- **Cause:** every car read the same input.
- **Rule:** exactly one thing has input authority at a time; `main.gd` assigns it and parked cars keep their
  stored transforms.

### Parked vehicle suspension draining mobile CPU (2026-10-30)
- **Symptom:** Running 4 suspension raycasts and Pacejka tyre friction calculations per car on every parked Thar, Tuk Tuk, and Porsche drained CPU on mobile.
- **Rule:** Parked vehicles sleep on their simple box collider with zero raycasts running. Full suspension, drivetrain and tyre calculations wake up only when `driving_enabled` is handed to the car by `main.gd`. Tire raycasts strictly query Layer 1 (Roads/Terrain), ignoring buildings, pedestrians and props. Engine audio is strictly voice-capped: only the active driven vehicle plays engine audio, while parked cars are completely muted.
- **Check:** `movement_regression.gd`, verify parked cars sleep at rest, zero audio playback when parked, and wake up smoothly on entry.
