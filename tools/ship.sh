#!/usr/bin/env bash
# Mana Ooru — Team Auto-Ship Script
# Runs regression tests, creates safety branch if on main, commits, and pushes to GitHub.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

COMMIT_MSG="$1"

if [ -z "$COMMIT_MSG" ]; then
    echo "Usage: ./tools/ship.sh \"Description of your work\""
    echo "Example: ./tools/ship.sh \"Add tea stall interaction\""
    exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Guardrail: Never allow pushing directly to main
if [ "$CURRENT_BRANCH" = "main" ]; then
    SAFE_BRANCH="feature/dev-$(date +%Y%m%d-%H%M%S)"
    echo "⚠️  [Mana Ooru] Notice: Direct work on 'main' is restricted to prevent team conflicts."
    echo "   Automatically creating a safe feature branch: $SAFE_BRANCH"
    git checkout -b "$SAFE_BRANCH"
    CURRENT_BRANCH="$SAFE_BRANCH"
fi

echo "🧪 [Mana Ooru] Step 1/3: Running Godot automated regression tests..."
if which godot >/dev/null 2>&1; then
    GODOT_CMD="godot"
elif [ -f "/opt/homebrew/bin/godot" ]; then
    GODOT_CMD="/opt/homebrew/bin/godot"
else
    echo "⚠️  [Mana Ooru] Godot binary not found in PATH. Skipping local headless test."
    GODOT_CMD=""
fi

if [ -n "$GODOT_CMD" ]; then
    if ! "$GODOT_CMD" --headless --path . --script tests/movement_regression.gd; then
        echo ""
        echo "❌ [Mana Ooru] Quality Gate FAILED: Movement regression test did not pass!"
        echo "   Push has been blocked to protect the project from broken movement."
        echo "   Tell your AI: 'The movement regression test failed, please fix the errors before pushing.'"
        exit 1
    fi
    echo "✅ [Mana Ooru] Tests PASSED! (WASD movement, camera, vehicle recovery all stable)"
fi

echo "📦 [Mana Ooru] Step 2/3: Staging and committing changes..."
git add .

if git diff --cached --quiet; then
    echo "ℹ️  [Mana Ooru] No new changes to commit."
else
    git commit -m "$COMMIT_MSG"
fi

echo "🚀 [Mana Ooru] Step 3/3: Pushing '$CURRENT_BRANCH' to GitHub..."
git push -u origin "$CURRENT_BRANCH"

REPO_URL="https://github.com/rahulpannatipubg9-creator/ManaOoru"
PR_URL="$REPO_URL/pull/new/$CURRENT_BRANCH"

echo ""
echo "🎉 [Mana Ooru] SUCCESS! Your work is safely uploaded to GitHub."
echo "👉 Create your Pull Request here: $PR_URL"
echo "   Rahul can review and merge your feature with 1 click."
echo ""
