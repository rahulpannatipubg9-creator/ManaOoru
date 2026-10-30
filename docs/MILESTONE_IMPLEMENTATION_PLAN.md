# Milestone Implementation Plan

## M0 - Audit and baseline

Acceptance: engine, input, scene architecture, platform state, risks, and
unavailable evidence are documented. No gameplay claim is made without a test.

## M1 - First playable possession loop

Acceptance:

- Person walks, sprints, jumps, and looks around.
- Person approaches a parked car and receives an ENTER prompt.
- F/ENTER enters the nearest car.
- Only the selected car drives.
- All other cars remain stationary.
- F/EXIT places the person safely beside the car.
- The loop repeats.
- Desktop and existing Android UI paths parse and smoke-test.

## M2 - Input and camera completeness

Add controller actions, crouch presentation, shoulder/reverse camera, map
placeholder, pause/settings, safe-area layout, pinch zoom, and focus-loss
cleanup. Acceptance requires action-level tests and desktop verification.

## M3 - Vehicle and motorcycle foundation

Add a reusable vehicle interface, a motorcycle scene, and a physics evaluation
against the current arcade car. Do not replace the current car until handling,
collision, recovery, and performance tests pass.

## M4 - City quality and streaming

Verify geographic references, modularize landmarks, add original local props,
introduce chunk streaming/LOD, and profile each device tier.

## M5 - Release hardening

Physical Android phone/tablet tests, Windows test, soak tests, save/load,
settings, packaging, and release checklist completion.
