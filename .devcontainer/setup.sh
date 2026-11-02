#!/usr/bin/env bash
set -e

echo "=== Setting up Mana Ooru Cloud Workstation (Godot 4, Android SDK & AI Agents) ==="

# 1. System packages
sudo apt-get update -y
sudo apt-get install -y wget unzip curl git python3 python3-pip openjdk-17-jdk

# 2. Android SDK Setup
export ANDROID_HOME="${HOME}/android-sdk"
if [ ! -d "${ANDROID_HOME}/cmdline-tools/latest" ]; then
    echo "Installing Android Command Line Tools..."
    mkdir -p "${ANDROID_HOME}/cmdline-tools"
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools"
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
    rm -f /tmp/cmdline-tools.zip

    # Accept licenses and install platform-tools and build-tools
    yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null 2>&1 || true
    "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "build-tools;34.0.0" "platforms;android-34" > /dev/null 2>&1 || true
fi

# 3. Download and install Godot 4.3 stable Linux headless binary
GODOT_VERSION="4.3"
GODOT_RELEASE="4.3-stable"
GODOT_DIR="/opt/godot"

if [ ! -f "/usr/local/bin/godot" ]; then
    echo "Downloading Godot ${GODOT_RELEASE} Linux binary..."
    sudo mkdir -p "${GODOT_DIR}"
    wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_linux.x86_64.zip" -O /tmp/godot.zip
    sudo unzip -q /tmp/godot.zip -d "${GODOT_DIR}"
    sudo mv "${GODOT_DIR}/Godot_v${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot
    sudo chmod +x /usr/local/bin/godot
    rm -f /tmp/godot.zip
fi

# 4. Download and install Godot 4.3 export templates
TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_RELEASE}"
if [ ! -f "${TEMPLATES_DIR}/android_debug.apk" ]; then
    mkdir -p "${TEMPLATES_DIR}"
    echo "Downloading Godot ${GODOT_RELEASE} Export Templates..."
    wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_export_templates.tpz" -O /tmp/templates.tpz
    unzip -q /tmp/templates.tpz -d /tmp/templates_extract
    mv /tmp/templates_extract/templates/* "${TEMPLATES_DIR}/"
    rm -rf /tmp/templates.tpz /tmp/templates_extract
fi

# 5. Configure Godot Editor Settings for Android Export
JAVA_17_PATH="/usr/lib/jvm/java-17-openjdk-amd64"
mkdir -p "${HOME}/.config/godot"
cat << EOF > "${HOME}/.config/godot/editor_settings-4.tres"
[gd_resource format=3]

[resource]
export/android/sdk_path = "${ANDROID_HOME}"
export/android/java_sdk_path = "${JAVA_17_PATH}"
EOF

# 6. Generate Keystores (Debug in ~/.android and Release in builds/)
mkdir -p "${HOME}/.android"
if [ ! -f "${HOME}/.android/debug.keystore" ]; then
    echo "Generating Android debug keystore..."
    keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "${HOME}/.android/debug.keystore" -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999
fi

mkdir -p builds
if [ ! -f "builds/manaooru-release.keystore" ]; then
    echo "Generating Mana Ooru release keystore..."
    keytool -genkeypair -v -keystore builds/manaooru-release.keystore -alias manaooru -keyalg RSA -keysize 2048 -validity 10000 -storepass manaooru2026 -keypass manaooru2026 -dname "CN=ManaOoru,OU=Dev,O=ManaOoru,L=Godavarikhani,ST=Telangana,C=IN"
fi

# 7. Add helpful terminal aliases for mobile & tablet coding
cat << 'EOF' >> "${HOME}/.bashrc"

# Mana Ooru Mobile Cloud Shortcuts
export ANDROID_HOME="${HOME}/android-sdk"
export PATH="${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"

alias test-movement="godot --headless --path . --script tests/movement_regression.gd"
alias test-perf="godot --headless --path . --script tests/device_performance_manager_regression.gd"
alias test-streaming="godot --headless --path . --script tests/high_speed_streaming_regression.gd"
alias test-all="godot --headless --path . --script tests/movement_regression.gd && godot --headless --path . --script tests/device_performance_manager_regression.gd && godot --headless --path . --script tests/high_speed_streaming_regression.gd"
alias build-apk="mkdir -p builds && godot --headless --export-debug 'Android' builds/ManaOoru-cloud.apk"

EOF

echo "=== Mana Ooru Cloud Setup Complete! Godot version: $(godot --version) ==="
