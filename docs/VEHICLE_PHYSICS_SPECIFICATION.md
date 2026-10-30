# Vehicle Physics Specification

## First milestone contract

- Frame-rate-independent acceleration and braking.
- Forward throttle, braking, reverse, steering, traction, drag, and handbrake.
- Stable vehicle center and collision body.
- Wheel rolling and front-wheel steering visuals.
- Only the possessed vehicle may integrate movement.
- Parked vehicles retain their last world transform.

## Suspension and tyres (implemented)

- One downward ray per wheel feeds a spring-damper. Stiffness is derived from
  `vehicle_mass`, `suspension_frequency` (1.6 Hz) and the static ride height so
  the four springs carry exactly the car's weight at rest; damping comes from
  `suspension_damping_ratio` (0.45). A stiff bump stop limits compression.
- The root `CharacterBody3D` integrates heave only, keeping its collision box
  upright and raised so the wheels, not the box, meet the road. Pitch and roll
  are integrated from the spring moments plus inertial load transfer
  (`center_of_mass_height`) and applied to the visual `Chassis` node.
- Tyre grip = `tyre_friction` × the measured spring loads. Longitudinal and
  lateral forces share a friction circle; lateral slide decays at
  `tyre_cornering_stiffness` up to that limit. No load means no grip.
- Handbrake: rear lateral grip drops to `handbrake_rear_grip`, braking comes
  from the locked rear tyres only, and yaw is boosted by `handbrake_yaw_boost`.
- `tyre_slip` (0–1) drives tyre squeal.
- Covered by `tests/suspension_regression.gd`.

## Long-term dynamics target

The production vehicle model should use rigidbody dynamics with wheel contact,
suspension travel, tire grip, rolling resistance, collision response, and a
stable center of gravity. It must be fixed-timestep safe and tested on slopes,
bumps, braking, reversing, and recovery.

The current `CharacterBody3D` car is explicitly an interim arcade implementation;
its limitations are tracked rather than hidden.
