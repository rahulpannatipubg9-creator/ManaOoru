#!/usr/bin/env bash
# Mana Ooru — iOS Build & Export Pipeline for iPhone & iPad
# Exports the Xcode project and game pack from Godot, with automated Xcode archiving support.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/builds/ios"
PROJECT_FILE="$BUILD_DIR/ManaOoru.xcodeproj"
IPA_PATH="$BUILD_DIR/ManaOoru.ipa"

echo "=========================================================="
echo "  MANA OORU — iOS / iPhone Build Pipeline"
echo "=========================================================="

# 1. Locate Godot
if which godot >/dev/null 2>&1; then
    GODOT_CMD="godot"
elif [ -f "/opt/homebrew/bin/godot" ]; then
    GODOT_CMD="/opt/homebrew/bin/godot"
elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT_CMD="/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "❌ Godot binary not found in PATH or standard locations."
    exit 1
fi

echo "🎮 Found Godot: $("$GODOT_CMD" --version)"

# 2. Regression check
echo "🧪 [1/3] Running movement regression gate..."
if "$GODOT_CMD" --headless --path . --script tests/movement_regression.gd; then
    echo "✅ Movement regression tests passed."
else
    echo "❌ Movement regression tests failed! Aborting export."
    exit 1
fi

# 3. Export iOS Xcode project & pack
echo "📦 [2/3] Exporting iOS project via Godot..."
mkdir -p "$BUILD_DIR"
"$GODOT_CMD" --headless --export-debug "iOS" "$IPA_PATH"

if [ ! -d "$PROJECT_FILE" ]; then
    echo "❌ Export failed: $PROJECT_FILE was not generated."
    exit 1
fi

echo "✅ iOS project successfully exported to:"
echo "   $BUILD_DIR/ManaOoru.xcodeproj"
echo "   $BUILD_DIR/ManaOoru.pck"

# 4. Xcode verification / IPA compilation
echo "📱 [3/3] Checking Xcode environment..."
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
    echo "🔨 Xcode detected: $(xcodebuild -version | head -n 1)"
    echo "   You can build the IPA directly or open the project in Xcode:"
    echo "   open \"$PROJECT_FILE\""
    
    if [ "$1" == "--archive" ]; then
        echo "🚀 Archiving Xcode project..."
        ARCHIVE_PATH="$BUILD_DIR/ManaOoru.xcarchive"
        xcodebuild -project "$PROJECT_FILE" \
                   -scheme "ManaOoru" \
                   -configuration Debug \
                   -destination "generic/platform=iOS" \
                   archive -archivePath "$ARCHIVE_PATH"
        echo "✅ Xcode archive created at: $ARCHIVE_PATH"
    fi
else
    echo "ℹ️  Full Xcode.app not active in xcode-select (Command Line Tools active)."
    echo "   The iOS project is 100% prepared and ready to open in Xcode!"
    echo "   To run on your iPhone:"
    echo "     1. Open the project in Xcode:"
    echo "        open \"$PROJECT_FILE\""
    echo "     2. Select your Apple Developer Team in Signing & Capabilities."
    echo "     3. Plug in your iPhone (or select an iPhone Simulator) and click Run (⌘R)."
fi

echo ""
echo "🎉 iOS / iPhone build ready!"
echo "=========================================================="
