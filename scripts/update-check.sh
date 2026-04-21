#!/bin/bash
# update-check.sh — Check for config changes before updating
# Run before git pull to see what will change
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "Heisenberg Team — Update Check"
echo "==============================="
echo ""

# Check if we're in a git repo
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Not a git repository. Cannot check for updates."
  exit 1
fi

cd "$REPO_DIR"

# Fetch latest
echo "Fetching latest changes..."
git fetch origin 2>/dev/null || {
  echo "ERROR: Failed to fetch from origin"
  exit 1
}

# Check if update available
LOCAL=$(git rev-parse HEAD 2>/dev/null)
REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "Already up to date."
  exit 0
fi

echo ""
echo "Update available!"
echo "  Local:  $LOCAL"
echo "  Remote: $REMOTE"
echo ""

# Show what changed
echo "Files that will change:"
echo "----------------------"
git diff --stat HEAD origin/main 2>/dev/null || git diff --stat HEAD origin/master 2>/dev/null || true

echo ""

# Check if any custom files will be overwritten
CUSTOM_FILES=(".env" "configs/generated/" "agents/*/MEMORY.md" "agents/*/memory/")
CONFLICTS=0

for pattern in "${CUSTOM_FILES[@]}"; do
  # Check if git would overwrite these
  changed_files=$(git diff --name-only HEAD origin/main 2>/dev/null | grep -E "$pattern" 2>/dev/null || true)
  if [ -n "$changed_files" ]; then
    echo "WARNING: Update will change: $changed_files"
    CONFLICTS=$((CONFLICTS + 1))
  fi
done

if [ "$CONFLICTS" -gt 0 ]; then
  echo ""
  echo "Some custom files may be overwritten."
  echo "Recommend: backup first, then merge manually."
  echo ""
  read -p "Continue with update? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 1
  fi
fi

echo ""
echo "To update, run:"
echo "  git pull origin main"
echo ""
echo "After update, re-run:"
echo "  bash scripts/setup-skills.sh    # Update skill symlinks"
echo "  bash deploy-one-click.sh --attach-existing --dry-run  # Verify everything"
