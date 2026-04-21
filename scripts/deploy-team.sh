#!/bin/bash
# scripts/deploy-team.sh — Deploy the Heisenberg Team (wrapper)
# Обёртка для обратной совместимости. Делегирует в deploy-one-click.sh.
#
# Usage (все аргументы передаются в deploy-one-click.sh):
#   bash scripts/deploy-team.sh                       # Интерактивный визард
#   bash scripts/deploy-team.sh --yes                 # Non-interactive (из .env)
#   bash scripts/deploy-team.sh --agents heisenberg   # Частичное развёртывание
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENTRY_POINT="$REPO_DIR/deploy-one-click.sh"

if [ ! -f "$ENTRY_POINT" ]; then
  echo "ERROR: deploy-one-click.sh not found at $ENTRY_POINT"
  echo "Make sure you are running from the heisenberg-team repository."
  exit 1
fi

echo "ℹ️  deploy-team.sh → делегирую в deploy-one-click.sh"
exec bash "$ENTRY_POINT" "$@"
