#!/bin/bash
# scripts/bootstrap-install.sh — System dependencies installer (wrapper)
# Обёртка для обратной совместимости.
# Устанавливает только зависимости (curl, git, jq, Node.js, OpenClaw),
# без конфигурации агентов. Делегирует в deploy-one-click.sh фазы 1-2.
#
# Usage:
#   bash scripts/bootstrap-install.sh              # Interactive
#   bash scripts/bootstrap-install.sh --yes        # Non-interactive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENTRY_POINT="$REPO_DIR/deploy-one-click.sh"

if [ ! -f "$ENTRY_POINT" ]; then
  echo "ERROR: deploy-one-click.sh not found at $ENTRY_POINT"
  echo "Make sure you are running from the heisenberg-team repository."
  exit 1
fi

echo "ℹ️  bootstrap-install.sh → установка зависимостей через deploy-one-click.sh"
echo "    (использую --attach-existing чтобы не конфигурировать агентов)"
exec bash "$ENTRY_POINT" --attach-existing "$@"
