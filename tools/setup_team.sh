#!/usr/bin/env bash
# Mana Ooru — Team Environment Setup
# Configures Git hooks and verifies Godot installation.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "⚙️  [Mana Ooru] Setting up team automation guardrails..."

# Configure Git hooks path
git config core.hooksPath .githooks
echo "✅ Git safety hooks enabled (.githooks/pre-commit & .githooks/pre-push)."

# Verify Godot
if which godot >/dev/null 2>&1 || [ -f "/opt/homebrew/bin/godot" ]; then
    echo "✅ Godot 4 installation detected."
else
    echo "⚠️  Godot 4 not found in PATH. Please install Godot 4.x from https://godotengine.org/download/"
fi

echo ""
echo "🎉 Setup complete! You are ready to collaborate."
echo "   - To get latest team updates: ./tools/sync.sh"
echo "   - To test and submit work:    ./tools/ship.sh \"your message\""
echo ""
