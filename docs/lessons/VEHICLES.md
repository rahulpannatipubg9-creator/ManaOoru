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
