# Input Action Specification

## On foot

| Action | Desktop | Touch |
|---|---|---|
| Move | W/A/S/D | Left virtual joystick |
| Sprint | Hold Left Shift | RUN control |
| Jump | Space | JUMP control |
| Crouch | Hold Left Ctrl | Future touch action |
| Enter vehicle | E | ENTER control |
| Exit vehicle | F | EXIT control |
| Interact | E | Future interaction control |
| Camera look | Mouse movement | Right-side swipe |
| First/third person (`vehicle_camera`) | V | CAMERA control (while driving) |
| Look behind (`camera_look_behind`) | Hold C | Future touch action |
| Zoom | Mouse wheel | Future pinch |
| Map | M | Future map button |
| Quick info | Tab | Future info button |
| Pause | Esc | Android lifecycle/menu |

## Driving

| Action | Desktop | Touch |
|---|---|---|
| Accelerate | W | Throttle joystick/control |
| Brake/reverse | S | Brake/reverse control |
| Steer | A/D | Steering joystick |
| Handbrake | Space | Future handbrake control |
| Exit | F | EXIT control |
| Recover | R | RESET control |
| Horn (`vehicle_horn`) | H | Future touch action |
| Camera | Mouse movement | Right-side swipe |
| First/third person (`vehicle_camera`) | V | CAMERA control |
| Look behind (`camera_look_behind`) | Hold C | Future touch action |

All gameplay input must use named actions in `project.godot`. Controllers must
not independently decide which body owns input; `main.gd` assigns authority.
Touch cancellation and focus-loss cleanup must clear held actions.
