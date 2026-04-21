#!/bin/bash
# scripts/setup.sh — Heisenberg Team Setup (wrapper)
# Обёртка для обратной совместимости. Делегирует в deploy-one-click.sh.
#
# Usage (все аргументы передаются в deploy-one-click.sh):
#   bash scripts/setup.sh                         # Интерактивный визард
#   bash scripts/setup.sh --yes                   # Non-interactive (из .env)
#   bash scripts/setup.sh --agents heisenberg,saul # Частичное развёртывание
#   bash scripts/setup.sh --attach-existing       # OpenClaw уже установлен
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENTRY_POINT="$REPO_DIR/deploy-one-click.sh"

if [ ! -f "$ENTRY_POINT" ]; then
  echo "ERROR: deploy-one-click.sh not found at $ENTRY_POINT"
  echo "Make sure you are running from the heisenberg-team repository."
  exit 1
fi

echo "ℹ️  setup.sh → делегирую в deploy-one-click.sh"
exec bash "$ENTRY_POINT" "$@"
