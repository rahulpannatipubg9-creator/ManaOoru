# Godavarikhani Open World - Technical Design Document

## Engine decision

Continue with Godot 4.7.2 and GDScript. The existing project already has
procedural scenes, Android export configuration, offline OSM-derived data, and
working desktop/mobile paths. Migration would delay the first playable milestone
without solving a current product requirement.

## Runtime architecture

- `main.gd`: game state, possession, vehicle discovery, camera target, and HUD
  mode.
- `person_controller.gd`: on-foot movement and collision.
- `player_controller.gd`: current car movement and vehicle visuals/audio.
- `camera_controller.gd`: orbit camera, touch look, shoulder switching, and zoom.
- `hud.gd`: touch controls, interaction state, and status display.
- `world_generator.gd`: bounded procedural world and offline map conversion.

Person and vehicles are sibling nodes in `main.tscn`; neither is a child of the
other. Vehicle authority is exclusive and must be enforced by the game state,
not inferred from input alone.

## Physics decision

The current vehicle is a `CharacterBody3D` arcade controller. It is suitable for
the first playable milestone but does not yet satisfy the long-term requirement
for wheel suspension and rigidbody tire dynamics. A future vehicle physics
milestone must introduce `RigidBody3D`/wheel components behind the same
possession interface and compare handling against regression tests before
replacing the current controller.

## Known current limitations

- No world streaming or LOD system.
- No motorcycle scene.
- No controller mapping.
- No save/load.
- No full map or pause/settings UI.
- No physical Android device evidence in this environment.
- No profiler measurements proving FPS, memory, draw-call, or thermal targets.
