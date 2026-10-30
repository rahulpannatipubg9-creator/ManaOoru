# Contributing to MANA OORU

Welcome to the **MANA OORU** project! We are building an open-world exploration game set in a recreation of **Godavarikhani, Telangana, India**, built using **Godot 4.7+**.

Whether you are a developer, 3D artist, or using an AI coding assistant (like Antigravity, Cursor, or Claude Code), please follow these guidelines to keep the codebase stable and high-performance.

---

## 🤖 The Prompt-First AI Workflow

Our team uses an automated, prompt-first workflow. You do not need deep Git knowledge—our automated scripts handle syncing, headless physics testing, and shipping:

### 1. Setup Your Machine (First Time Only)
Run the one-step setup script:
```bash
./tools/setup_team.sh
```
This enables our local quality gates (`.githooks/pre-push` and `.githooks/pre-commit`) and verifies your Godot engine installation.

### 2. Before Starting Any Work (Always Sync)
Run the auto-sync script:
```bash
./tools/sync.sh
```
This safely stashes any uncommitted local work, fetches the newest commits from `main`, and rebases your workspace cleanly.

### 3. Build in Modular Sub-Scenes
To prevent merge conflicts with other teammates:
* **Never edit monolithic shared scenes** like `scenes/main.tscn` directly.
* Build your feature inside a dedicated sub-scene (e.g. `scenes/props/bus_stop.tscn` or `scripts/vehicles/rickshaw.gd`).
* Keep scenes self-contained with their own collision shapes and materials.

### 4. Ship Your Work (Auto-Test & Push)
When your feature is complete and verified in Godot, run:
```bash
./tools/ship.sh "add tea stall near bus stop"
```
The script will:
1. Run automated headless Godot movement and physics regression tests (`tests/movement_regression.gd`).
2. If tests pass, create a clean feature branch (`feature/<name>`).
3. Push to GitHub and provide a Pull Request link.

---

## 🛡️ Engineering & Quality Rules

All contributions must follow the core engineering principles documented in [`AGENTS.md`](./AGENTS.md):

1. **Preserve Camera-Relative WASD Movement**: Never introduce continuous unintended rotation.
2. **Offline Compliance**: The game must run 100% offline without remote server calls, analytics, or external trackers.
3. **Automated Testing**: Headless movement regression tests (`godot --headless --path . --script tests/movement_regression.gd`) must pass before code is merged.
4. **Performance Targets**:
   - Target hardware: Apple Silicon M1 (8GB RAM) and mid-range mobile devices.
   - Maintain 60 FPS in dense urban areas.
   - Keep 3D asset file sizes under 50 MB.

---

## 🎨 Asset & Legal Policy

We respect intellectual property and maintain strict licensing standards:
* **Zero Copyright Infringement**: Never import ripped assets from GTA, commercial games, or unverified 3D sources.
* **Document Every Asset**: Any imported model, texture, or audio track must be added to [`ASSET_LICENSES.md`](./ASSET_LICENSES.md) with author, URL, and license terms.
* **Format Standards**:
  * 3D Models: GLTF/GLB (`.glb` preferred) with PBR textures.
  * Audio: `.wav` for sound effects, `.ogg` for streaming background music/ambience.

---

## 🔀 Pull Request Process

1. Open a Pull Request using our automated PR template.
2. Ensure automated regression tests pass.
3. The repository maintainer (@rahulpannatipubg9-creator) will review the sub-scene integration and approve the merge into `main`.
