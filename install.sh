#!/bin/bash
# install.sh — Thin wrapper for Heisenberg Team installation
# Supports: curl | bash pattern + local execution
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/heisenberg-team/main/install.sh | bash
#   HEISENBERG_REPO=https://github.com/YOU/heisenberg-team.git bash install.sh
#   bash install.sh                    # Interactive (from cloned repo)
#   bash install.sh --yes              # Non-interactive
#   bash install.sh --agents heisenberg,saul
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# ── Find or clone the repo ──
if [ -f "$SCRIPT_DIR/deploy-one-click.sh" ]; then
  REPO_DIR="$SCRIPT_DIR"
else
  CLONE_DIR="${HEISENBERG_DIR:-$HOME/heisenberg-team}"
  if [ -d "$CLONE_DIR/deploy-one-click.sh" ] || [ -f "$CLONE_DIR/deploy-one-click.sh" ]; then
    REPO_DIR="$CLONE_DIR"
  else
    REPO_URL="${HEISENBERG_REPO:-}"
    if [ -z "$REPO_URL" ]; then
      echo ""
      echo "Heisenberg Team — Installer"
      echo "============================"
      echo ""
      echo "ERROR: REPO URL not set. Use one of:"
      echo "  1. Clone first: git clone <YOUR_REPO_URL> && cd heisenberg-team && bash install.sh"
      echo "  2. Set env:     HEISENBERG_REPO=https://github.com/YOU/heisenberg-team.git bash install.sh"
      echo ""
      exit 1
    fi

    echo ""
    echo "Heisenberg Team — Installer"
    echo "============================"
    echo ""
    echo "Cloning repository to $CLONE_DIR ..."

    if ! command -v git >/dev/null 2>&1; then
      echo "ERROR: git is required. Install it first:"
      echo "  Ubuntu/Debian: sudo apt-get install -y git"
      echo "  macOS: brew install git"
      exit 1
    fi

    git clone "$REPO_URL" "$CLONE_DIR" || {
      echo "ERROR: Failed to clone from $REPO_URL"
      echo "Check the URL and your network connection."
      exit 1
    }
    REPO_DIR="$CLONE_DIR"
  fi
fi

# ── Delegate to deploy-one-click.sh ──
if [ -f "$REPO_DIR/deploy-one-click.sh" ]; then
  exec bash "$REPO_DIR/deploy-one-click.sh" "$@"
else
  echo "ERROR: deploy-one-click.sh not found in $REPO_DIR"
  echo "The repository may be corrupted. Try re-cloning."
  exit 1
fi
