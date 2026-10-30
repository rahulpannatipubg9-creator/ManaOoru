# MANA OORU Engineering Rules

- Inspect the existing architecture before modifying gameplay.
- Preserve camera-relative WASD movement and never introduce continuous unintended rotation.
- Keep player movement, camera rotation, and touch input responsibilities separate.
- Run `godot --headless --path . --script tests/movement_regression.gd` after gameplay changes.
- Test diagonal normalization, idle stability, collision, and camera clipping regressions.
- Keep the project fully offline and use only free or properly licensed resources.
- Avoid unnecessary dependencies and preserve modular map integration.
- Maintain performance on the Apple M1 with 8 GB RAM and mobile devices.
- Report only tests actually performed; mark unavailable checks as not tested.
- Before changing characters, vehicles, weapons, buildings, props, imported models or multiplayer, read the
  matching file in `docs/lessons/` (index: `docs/lessons/README.md`). When you fix a mistake, add an entry
  there in the same change; a fix without its lesson is not done.
