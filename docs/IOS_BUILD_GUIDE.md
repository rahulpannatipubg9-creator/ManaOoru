# MANA OORU — iOS / iPhone Build & Deployment Guide

This guide details the iOS export configuration, build pipeline, and deployment instructions for running **MANA OORU** on Apple iPhones and iPads.

---

## 1. Overview & Architecture

MANA OORU is configured to export native iOS Xcode projects directly from Godot 4:
- **Target Platform:** iOS 15.0+ (iPhone & iPad Universal, `TARGETED_DEVICE_FAMILY = "1,2"`).
- **Supported Architectures:** `arm64` (Physical iPhones & Apple Silicon Simulator), `x86_64` (Simulator fallback).
- **Graphics Pipeline:** OpenGL ES 3.0 / GL Compatibility via MoltenVK (Metal wrapper).
- **Display Orientation:** Sensor Landscape (`window/handheld/orientation=4`), enabling seamless 180° auto-rotation (`UIInterfaceOrientationLandscapeLeft` and `UIInterfaceOrientationLandscapeRight`) for comfortable gaming while charging.
- **Display Safe Area:** HUD and touch controls use `DisplayServer.get_display_safe_area()` in `scripts/mobile/claw_layout.gd`, automatically keeping controls away from the iPhone Notch, Dynamic Island, and Home Indicator bar.
- **Hardware Performance:** `DevicePerformanceManager` auto-detects `Apple GPU` and A15/A16/A17/A18/M-series chips, configuring Tier 3 (60-90 FPS, high fidelity) or Tier 4 (Pro tablet / desktop).

---

## 2. Automated Export Pipeline

An automated build tool is provided in `tools/build_ios.sh`:

```bash
./tools/build_ios.sh
```

### What this tool does:
1. Runs the mandatory regression gate (`tests/movement_regression.gd`) to ensure movement, collision, camera, and vehicle recovery stability.
2. Invokes Godot in headless export mode:
   ```bash
   godot --headless --export-debug "iOS" builds/ios/ManaOoru.ipa
   ```
3. Generates the complete Xcode workspace inside `builds/ios/`:
   - `builds/ios/ManaOoru.xcodeproj`: Native Xcode project.
   - `builds/ios/ManaOoru.pck`: Packed game assets, terrain, models, audio, and bytecode (approx. 436 MB).
   - `builds/ios/ManaOoru.xcframework`: Godot iOS engine framework.
   - `builds/ios/MoltenVK.xcframework`: Metal/Vulkan bridge.
   - `builds/ios/PrivacyInfo.xcprivacy`: Apple App Store privacy manifest.
   - `builds/ios/ManaOoru/Images.xcassets`: Pre-scaled app icons (1024x1024, 180x180, 120x120, etc.).

---

## 3. Running on an iPhone via Xcode

### Prerequisites:
- A Mac running macOS with **Xcode** installed from the Mac App Store (or developer.apple.com).
- An Apple ID (a free personal Apple ID works for installing on personal iPhones; paid Apple Developer Program required for TestFlight / App Store).

### Step-by-Step Instructions:

1. **Export the iOS Project:**
   ```bash
   ./tools/build_ios.sh
   ```

2. **Open the Project in Xcode:**
   ```bash
   open builds/ios/ManaOoru.xcodeproj
   ```

3. **Configure Code Signing:**
   - In Xcode's left navigator, select the top-level **ManaOoru** project node.
   - Go to the **Signing & Capabilities** tab.
   - Check **"Automatically manage signing"**.
   - In the **Team** dropdown, select your Apple ID or Team account.
   - Ensure Bundle Identifier is set (e.g. `com.manaooru.game` or your custom domain).

4. **Connect your iPhone:**
   - Connect your iPhone to your Mac via USB or Wi-Fi.
   - On your iPhone:
     - If prompted, tap **"Trust This Computer"**.
     - Enable **Developer Mode**: Go to **Settings > Privacy & Security > Developer Mode** and switch it ON (requires a quick reboot).
   - In the Xcode toolbar at the top, select your iPhone as the build target device.

5. **Build and Run (⌘R):**
   - Click the **Play** button (or press `Cmd + R`).
   - Xcode will compile dummy swift/cpp stubs, link the Godot and MoltenVK frameworks, embed `ManaOoru.pck`, sign the app, and install it on your iPhone.
   - Launch MANA OORU from your iPhone home screen!

---

## 4. Running on iOS Simulator

If you do not have a physical iPhone handy:
1. In Xcode's device selector at the top, choose any **iPhone Simulator** (e.g., *iPhone 16 Pro*, *iPhone 15*).
2. Press `Cmd + R` to run.
3. The iOS Simulator boots up, installs Mana Ooru, and runs the game.

---

## 5. Touch Controls & Notch / Dynamic Island Handling

- **Claw Layout:** Built specifically for landscape mobile gameplay (similar to BGMI/PUBG Mobile), featuring floating movement joystick on the left thumb, fire/aim/crouch/prone/jump on the right thumb, and vehicle interaction buttons.
- **Safe Area Insets:** The interface respects hardware cutouts:
  - When held with the Dynamic Island on the left: joystick moves inward away from the cutout.
  - When held with the Dynamic Island on the right: combat cluster moves inward away from the cutout.
  - Bottom edge margins ensure touch events are never swallowed by iOS Home Indicator gestures.
