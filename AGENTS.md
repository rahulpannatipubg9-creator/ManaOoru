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

## Multi-Agent & Team Collaboration Rules (Prompt-First Workflow)
- **Always sync before working:** Run `git pull origin main` before starting any new task.
- **Never push directly to `main` for experimental features:** Always work on a descriptive branch (`git checkout -b feature/<name>` or `dev/<name>`).
- **Prevent Godot Scene Conflicts:** Avoid modifying monolithic shared scenes (like `scenes/main.tscn`) simultaneously. Build modular sub-scenes in `scenes/<feature>/` and instantiate them via code or separate scene components.
- **Pre-Push Validation:** Never push broken code. Run `godot --headless --path . --script tests/movement_regression.gd` to confirm regression tests pass before pushing.
- **Safe Push Protocol:** Push feature branches (`git push origin <branch-name>`) and open a Pull Request so teammates can review and merge cleanly. Never use force-push (`git push -f`).
