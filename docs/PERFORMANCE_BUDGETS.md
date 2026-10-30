# Performance Budgets

These are acceptance targets, not current measurements.

| Budget | Target |
|---|---|
| Budget Android frame time | 33.3 ms (30 FPS) |
| Desktop frame time | 16.7 ms target (60 FPS) |
| Physics frame time | 4 ms target on budget Android |
| Loaded dynamic pedestrians/vehicles | Bounded and documented per district |
| World generation | One-time generation or streamed chunks; no unbounded loops |
| Texture memory | Profiled per device tier before release |
| Draw calls | Profiled per device tier before release |
| Memory growth | No growth during a 30-minute exploration soak |

The current world is bounded procedurally, but these budgets have not yet been
measured with Godot's profiler on representative devices.
