#!/usr/bin/env bash
# Mana Ooru — Team Auto-Sync Script
# Safely pulls the latest changes from GitHub without losing local work.

set -e

# Change to repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🔄 [Mana Ooru] Checking for latest team updates from GitHub..."

# Ensure remote is reachable
if ! git fetch origin main --quiet; then
    echo "⚠️  [Mana Ooru] Warning: Could not fetch from GitHub. Please check your internet connection."
    exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HAS_LOCAL_CHANGES="$(git status --porcelain)"

STASHED=false
if [ -n "$HAS_LOCAL_CHANGES" ]; then
    echo "💾 [Mana Ooru] Stashing uncommitted local work safely..."
    git stash push -u -m "mana_ooru_sync_$(date +%s)" --quiet
    STASHED=true
fi

if [ "$CURRENT_BRANCH" = "main" ]; then
    echo "📥 [Mana Ooru] Updating 'main' branch..."
    git pull --rebase origin main
else
    echo "📥 [Mana Ooru] Rebasing current branch '$CURRENT_BRANCH' on top of latest 'origin/main'..."
    git pull --rebase origin main || {
        echo "⚠️  [Mana Ooru] Conflict detected during rebase!"
        echo "    Don't panic! Your work is safe."
        echo "    Tell your AI: 'There is a git rebase conflict in Mana Ooru, please help me resolve it.'"
        exit 1
    }
fi

if [ "$STASHED" = true ]; then
    echo "📦 [Mana Ooru] Restoring your local uncommitted work..."
    git stash pop --quiet || {
        echo "⚠️  [Mana Ooru] Notice: Restored changes have conflicts with incoming team updates."
        echo "    Tell your AI: 'Help me resolve stash conflicts in Mana Ooru.'"
        exit 0
    }
fi

echo ""
echo "✅ [Mana Ooru] Up to date! Your project has all the latest team changes."
echo "   Current branch: $CURRENT_BRANCH"
echo "   Latest commit:  $(git log -1 --pretty=format:'%h - %s (%cr)')"
echo ""
