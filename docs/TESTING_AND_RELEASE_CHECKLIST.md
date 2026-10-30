# Testing and Release Checklist

## Current automated checks

- [x] Godot editor parse check.
- [x] Movement regression.
- [x] Scene/camera regression.
- [x] Headless world smoke test.
- [x] Android APK export completed previously.
- [x] Exclusive person/vehicle movement regression.

## Required before a milestone is released

- [ ] Desktop golden path: walk, enter, drive, exit, repeat.
- [ ] Verify every parked vehicle remains still while walking.
- [ ] Verify only the selected vehicle moves while driving.
- [ ] Verify collision and safe exit placement.
- [ ] Verify keyboard held input and mouse camera independently.
- [ ] Verify Android phone and tablet touch controls on physical devices.
- [ ] Verify pause/resume and focus-loss input cleanup.
- [ ] Verify stuck-vehicle recovery.
- [ ] Run a 30-minute soak test and inspect memory.
- [ ] Capture profiler evidence for FPS, physics, draw calls, and memory.
- [ ] Confirm asset licenses and export package.

Unavailable device checks must remain marked as not tested.
