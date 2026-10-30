# Movement, controls and flight implementation report

## Project and root causes

The project is Godot 4, running natively on macOS with the compatibility renderer.
World coordinates use metres, +X east and -Z north. The character and cars face +Z;
the supplied helicopter nose faces -Z after its existing import rotation. The
native application was exercised; a browser export was not tested.

The former helicopter coupled forward input to climb, read Shift as both climb
and descent, used total 3D velocity as speed, and checked landed exit against the
original spawn height. Its lift/tilt controls and drag did not provide a predictable
cruise target. Camera chase and minimap headings assumed every model faced +Z.
Car handling, character stepping and road navigation already had working systems.

Controllers had local authority flags but no common UI/focus gate. Cameras could
all consume look events, C was already look-back while the requested crouch key
was C, and car-specific mobile gear controls remained visible for the helicopter.
The generic visible seated pilot appeared above the helicopter rotor in a rendered
flight check. A stale camera capture flag could also suppress mouse look after pause.

## Files changed

| File | Purpose |
|---|---|
| scripts/player/gameplay_controls.gd | Shared movement reading, active-controller authority, pause/UI modes and held-key clearing |
| scripts/player/person_controller.gd | C crouch toggle, input gate, grounded recovery checks |
| scripts/vehicle/rigid_vehicle.gd | Shared input gate; collision validation before recovery; existing tyre/suspension handling retained |
| scripts/vehicle/helicopter.gd | Assisted arcade flight, independent vertical input, actual landing checks, horizontal speed, safe recovery and audio lifecycle |
| scripts/main.gd | Focus/UI handling, exclusive control handover, grounded exits, camera blending, flight HUD/pilot presentation |
| scripts/camera/camera_controller.gd | Active-camera input only, correct helicopter chase/first-person heading, pause-safe mouse look |
| scripts/map/map_canvas.gd | Helicopter marker follows its actual nose direction |
| scripts/ui/hud.gd | Accurate helicopter hints, relative-altitude readout, touch ascend/descend, hidden car gear buttons during flight |
| project.godot | C crouch; B look-back without a key conflict |
| tests/arcade_flight_regression.gd | Actual rigid-body flight, speed, hover, yaw, descent and physical landing on two elevations |
| tests/exploration_flow_regression.gd | Actual city scene with UI/focus checks, helicopter possession/flight/exit and switching to a car; optional rendered capture |
| tests/engine_sound_regression.gd | Exercise helicopter audio separately from car EngineAudio nodes |
| tests/camera_regression.gd | Report the new B look-back mapping |

Roads, buildings, shop data, signage, landmarks and save formats were not modified.

## Controls

| Context | Inputs |
|---|---|
| On foot | Camera-relative WASD; Shift sprint; Space jump; C toggle crouch; Ctrl hold crouch remains supported; E interact/enter; R safe recovery |
| Car/auto | W accelerate; S brake then reverse; A/D steer; Space handbrake; F exit; R safe recovery |
| Helicopter | W/S forward/back; A/D strafe with visual bank; Space ascend; Shift descend; Q/E yaw; Ctrl fast flight; F landed exit; R safe recovery |
| Camera | Mouse/trackpad look; V first/third person; B look back; wheel camera distance |
| Exploration | M full map; map zoom/pan and road waypoints retained; Esc pause/release pointer, Esc resume; click to recapture when needed |

E is interaction on foot and yaw while flying, never an airborne exit key.
Only the occupied controller receives movement. Held keys/touch are cleared at
focus loss, pause, pointer release and possession changes. Text fields suspend
movement without disabling gravity or assisted hover. Motorcycle mode is reserved
in the control-state vocabulary; no new motorcycle controller was added.

## Handling and camera values

Helicopter: mass 2200 kg; normal horizontal target 25 m/s (90 km/h); fast target
42 m/s (151.2 km/h); acceleration limit 8 m/s²; hover braking 12 m/s²; vertical
target ±6 m/s; vertical acceleration limit 7 m/s²; yaw target 1.05 rad/s; visual
pitch/bank up to 0.16 rad (~9 degrees). The force controller integrates through
Godot physics, retaining rigid-body collisions. Normal project damping yields
measured cruise about 86.5 km/h and fast flight about 145.2 km/h.

Neutral input brakes horizontal drift and holds the release altitude. Forward
flight does not implicitly climb. The rigid collision body stabilizes upright;
the fuselage supplies restrained visual pitch/bank. Recovery reuses landed safe
poses and refuses an obstructed destination. Landing/exit probes the surface
under the craft rather than comparing its height with its original pad.

Character movement keeps existing 4.2 m/s walking/jogging and 7 m/s sprint tuning,
7 m/s jump velocity, 18 m/s² project gravity, slope and stair handling. Existing
speed-sensitive car steering, tyre friction, reverse and parking brake remain.
Car and character recovery now check candidate occupancy before teleporting.

Entry/exit camera handover blends for 0.4 seconds. Existing spring-arm clipping,
pitch limits, chase lag and restrained speed FOV remain. Helicopter cameras and
map markers use its -Z nose. The pilot is hidden during flight because the asset
does not have a verified cockpit seating layout. Relative altitude is explicitly
labelled Δ ALT; it is height above the last safe landing pose, not terrain AGL.

## Verification

Passed actual physics tests:

- Arcade flight at 30, 60 and 120 physics ticks/second, with equal simulated
  durations: vertical takeoff, forward/reverse-axis handling, cruise/fast target,
  hover, altitude stability, strafe/bank, Q/E yaw, Shift descent and physical
  landings at ground level and on an elevated platform.
- Exploration flow in the generated city: text focus and simulated window blur,
  entering helicopter, taking off, crossing a city block, airborne-exit rejection,
  recovery/landed exit, restoring character authority, switching to and driving a car.
- Movement regression: keyboard/touch translation, normalized axes, parked vehicles,
  car possession, driving, recovery and exit.
- Character physics: slopes, stairs, grounding, crouch/headroom, jump/landing,
  fall reactions and car impacts.
- Handling: straight-line stability, cornering, handbrake, countersteer and self-centering.
- Vehicle entry: walk to door, seat follow, pedals and driver-side exit.
- Camera and chase camera: V, rear view, stable WASD, FOV, mouse-look hold and return.
- Navigation: projection, road routing, one-way rules, minimap/full-map interaction,
  GPS progress/reroute and walk/drive handover.
- Engine sound: car layers, gear RPM, horn, possession/exit and parked helicopter silence.
- Scene: camera collision/distance and existing town components.

The native rendered flight capture checks city framing, HUD/minimap and pilot
visibility. Its capture fixture supplies synthetic focus because an automated
window may be behind the user's application. Full flow is independently exercised
by the headless city test. Real macOS focus/trackpad feel remains a human check.
An earlier native continuation was interrupted by focus loss; it is not counted
as a successful manual end-to-end session.

Existing ObjectDB/resource exit warnings remain in several legacy tests. Passing
assertions do not establish that those existing leaks are repaired.

## Manual acceptance checklist and limits

1. Walk with WASD, sprint with Shift, jump, then toggle C twice. Stop on a slope
   and climb a kerb. Verify B look-back does not alter WASD direction.
2. Move the mouse/trackpad without holding a button. Pause/resume with Esc, click
   to recapture if released, and switch apps while holding W; confirm no stuck input.
3. E-enter a car. Accelerate, brake with S, reverse, turn at low/high speed and
   use Space handbrake. Stop and F-exit; repeat. Check R refuses an obstructed recovery.
4. E-enter the helicopter. Space climbs; release holds altitude. W/S move forward
   and backward, A/D strafe, Q/E yaw. Confirm E does not exit. Ctrl+W enables fast
   flight. Verify speed and relative-altitude displays.
5. Release controls, then Shift-descend onto a clear surface. F must reject an
   airborne exit and allow a stopped landing. Exit/re-enter and switch to a car.
6. Check V/cockpit view, aerial chase framing, audible rotor/engine balance and
   map/waypoints in dense streets and near landmarks.

Human driving feel, rotor sound quality, real trackpad hardware, Android touch
ergonomics and browser pointer-lock/performance have not been manually certified.
No browser build or benchmark was run. Helicopter materials, cockpit geometry and
authored character animations remain asset limitations. No new missions, motorcycle
physics or custom cockpit interior are claimed by this upgrade.
