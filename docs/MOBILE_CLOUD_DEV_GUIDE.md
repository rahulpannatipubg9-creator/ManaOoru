# Mana Ooru — Mobile & Tablet Cloud Development Guide

This guide enables you to build, test, modify, and deploy **Mana Ooru** directly from your mobile device (e.g., **Xiaomi Pad 7**, Android phone, or tablet) using **GitHub Cloud**, **GitHub Codespaces**, **GitHub Actions**, and AI Agents (**Codex** and **Gemini Antigravity**).

---

## 1. Cloud Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │          Xiaomi Pad 7 / Mobile         │
                      │  (Chrome / Edge / GitHub App / Web)    │
                      └──────────────────┬─────────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
   ┌───────────────────────────┐                   ┌───────────────────────────┐
   │     GitHub Codespaces     │                   │       GitHub Actions      │
   │      (Cloud Dev IDE)      │                   │     (Cloud CI/CD & APK)   │
   ├───────────────────────────┤                   ├───────────────────────────┤
   │ • Full VS Code Web        │                   │ • Automated Ubuntu runner │
   │ • Godot 4.3 Headless CLI  │  git push / PR    │ • Headless regression gate│
   │ • Android SDK & Keystores │ ────────────────► │ • Auto-signs Android APK  │
   │ • GitHub Copilot / Codex  │                   │ • 1-Tap Artifact Download │
   │ • Gemini Antigravity      │                   │   directly onto tablet    │
   └───────────────────────────┘                   └───────────────────────────┘
```

---

## 2. Launching GitHub Codespaces on Mobile / Tablet

You do not need a PC or Mac to code. A web browser on your tablet is sufficient.

### Step-by-Step:
1. Open **Google Chrome**, **Microsoft Edge**, or **Brave** on your tablet/phone.
2. Navigate to your repository: `https://github.com/rahulpannati/ManaOoru`.
3. Tap the green **`<> Code`** button.
4. Select the **Codespaces** tab.
5. Tap **`Create codespace on main`** (or select a feature branch).
6. **Recommended (Full-Screen App Mode):**
   - In Chrome: Tap the browser menu `⋮` (top right) -> tap **`Add to Home Screen`** or **`Install app`**.
   - An icon will appear on your tablet home screen. Tapping it opens Codespaces full-screen without address bars or tabs!

### What's Pre-Configured in the Cloud Container:
- **Godot 4.3 Stable** headless engine (`/usr/local/bin/godot`).
- **Godot 4.3 Android Export Templates** pre-installed in `~/.local/share/godot/`.
- **OpenJDK 17** & **Android Command Line Tools** (`sdkmanager`, `apksigner`, `zipalign`).
- **Android Debug Keystore** (`~/.android/debug.keystore`) & **Release Keystore** (`builds/manaooru-release.keystore`).
- **VS Code Extensions**: GDScript Tools (`geequlim.godot-tools`), Python, GitHub Copilot, Copilot Chat.

---

## 3. Working with AI Agents on Mobile

### Option A: GitHub Copilot / Codex
1. Tap the **Copilot Chat** icon on the left vertical activity bar.
2. Ask questions or request changes using touch keyboard or voice-to-text:
   - *"Add an auto-rickshaw parking zone near the bus station."*
   - *"Audit building sign placements and fix overlapping meshes."*
3. Review changes and tap **Apply in Editor**.

### Option B: Gemini Antigravity (`agy` / Gemini Agent)
1. Open the Codespaces terminal:
   - Tap Hamburger Menu `≡` (top-left) -> **Terminal** -> **New Terminal** (or keyboard shortcut `` Ctrl + ` ``).
2. Run your Gemini / Antigravity workflows or custom Python automation scripts in `tools/`:
   ```bash
   python3 tools/collect_latest_places.py
   python3 tools/asset_pipeline/pipeline.py --input ~/Downloads/model.glb
   ```

---

## 4. Mobile Quick-Action Terminal Aliases

Typing long terminal commands on a touch screen is tedious. The container comes with pre-configured mobile aliases:

| Alias | Command | Purpose |
|---|---|---|
| `test-movement` | `godot --headless --path . --script tests/movement_regression.gd` | Tests WASD, touch rotation, vehicle recovery. |
| `test-perf` | `godot --headless --path . --script tests/device_performance_manager_regression.gd` | Tests 4-tier mobile/tablet classification. |
| `test-streaming` | `godot --headless --path . --script tests/high_speed_streaming_regression.gd` | Tests 130 km/h chunk streaming lookahead. |
| `test-all` | Runs all 3 regressions sequentially | **Quality gate before pushing.** |
| `build-apk` | `godot --headless --export-debug 'Android' builds/ManaOoru-cloud.apk` | Builds a fresh Android APK inside Codespace. |

---

## 5. Automated Cloud APK Delivery (No PC / No Cable Needed)

Every time code is pushed to `main` or a Pull Request is opened, GitHub Actions automatically verifies regressions and compiles the Android APK.

### How to Install the Cloud APK onto your Tablet:
1. Open `https://github.com/rahulpannati/ManaOoru` on your tablet.
2. Tap the **Actions** tab at the top.
3. Tap the latest workflow run named **`Build & Test Android Cloud APK`**.
4. Scroll down to the **Artifacts** section at the bottom.
5. Tap **`ManaOoru-Android-APK`** to download `ManaOoru-Android-APK.zip`.
6. Open your tablet's **Files** app, extract the `.zip`, and tap **`ManaOoru-debug.apk`**.
7. Tap **Install** (or **Update**). The latest game build is now running on your tablet!

### Manual Cloud Build on Demand:
If you want to trigger a build manually from your phone:
1. Go to **Actions** -> **Build & Test Android Cloud APK**.
2. Tap **Run workflow**.
3. Select branch and export type (`debug`, `release`, or `all`).
4. Tap **Run workflow**. In 3-5 minutes, your signed APK is ready to download.

---

## 6. Safe Mobile Collaboration Workflow (AGENTS.md Rules)

To protect the game from regressions when developing from mobile:
1. **Never commit directly to `main`**:
   ```bash
   git checkout -b feature/my-mobile-feature
   ```
2. **Always verify tests before shipping**:
   ```bash
   test-all
   ```
3. **Use the auto-ship tool**:
   ```bash
   ./tools/ship.sh "Add tea stall landmark"
   ```
   `ship.sh` runs the movement quality gate, checks branch guards, commits, and pushes safely.
4. **Open and merge Pull Request**:
   - Create PR on GitHub mobile or run `gh pr create --fill`.
   - Once CI passes, merge into `main` (`gh pr merge --merge`).
