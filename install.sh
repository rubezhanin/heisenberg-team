#!/bin/bash
# install.sh — Universal installer for Heisenberg Team
# Single command to install everything on a clean machine
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/USER/heisenberg-team/main/install.sh | bash
#   bash install.sh                    # Interactive
#   bash install.sh --yes              # Non-interactive
#   bash install.sh --agents heisenberg,saul   # Selected agents only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If running from pipe (curl | bash), SCRIPT_DIR is useless — clone the repo
if [ ! -f "$SCRIPT_DIR/scripts/bootstrap-install.sh" ]; then
  # Try to find the repo or clone it
  CLONE_DIR="${HEISENBERG_DIR:-$HOME/heisenberg-team}"
  if [ -d "$CLONE_DIR/scripts" ]; then
    SCRIPT_DIR="$CLONE_DIR"
  else
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
    REPO_URL="${HEISENBERG_REPO:-https://github.com/USER/heisenberg-team.git}"
    git clone "$REPO_URL" "$CLONE_DIR" || {
      echo "ERROR: Failed to clone. Set HEISENBERG_REPO to your fork URL:"
      echo "  HEISENBERG_REPO=https://github.com/YOU/heisenberg-team.git bash install.sh"
      exit 1
    }
    cd "$CLONE_DIR"
    SCRIPT_DIR="$CLONE_DIR"
  fi
fi

# ─── Configuration ───
NONINTERACTIVE="${OPENCLAW_NONINTERACTIVE:-0}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.4.12}"
SELECTED_AGENTS=""

# ─── Parse args ───
for arg in "$@"; do
  case "$arg" in
    --yes|-y) NONINTERACTIVE=1; export OPENCLAW_NONINTERACTIVE=1 ;;
    --agents) SELECTED_AGENTS="${2:-}"; shift ;;
    --version) echo "$OPENCLAW_VERSION"; exit 0 ;;
    --help|-h)
      cat <<'EOF'
Heisenberg Team — Universal Installer

Usage:
  bash install.sh [options]

Options:
  --yes, -y              Non-interactive mode (auto-install everything)
  --agents a,b,c         Install only selected agents
  --version              Show target OpenClaw version
  --help                 Show this help

Environment:
  OPENCLAW_VERSION=X.Y.Z       Override OpenClaw version
  OPENCLAW_NONINTERACTIVE=1    Same as --yes

What this script does:
  1. Installs system dependencies (git, Node.js, jq)
  2. Installs OpenClaw (specific version)
  3. Runs interactive setup wizard (configures providers, models, API keys)
  4. Installs agents and skills
  5. Runs smoke test to verify

After installation:
  openclaw init              # First time: configure LLM provider
  openclaw gateway start     # Start the system
  openclaw status            # Verify agents are running

One-liner (from GitHub):
  curl -fsSL https://raw.githubusercontent.com/USER/heisenberg-team/main/install.sh | bash
  # Or with your fork:
  HEISENBERG_REPO=https://github.com/YOU/heisenberg-team.git bash -c "$(curl -fsSL https://raw.githubusercontent.com/USER/heisenberg-team/main/install.sh)"
EOF
      exit 0
      ;;
  esac
done

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}🧪 Heisenberg Team — Universal Installer${NC}"
echo "=============================================="
echo ""

# ─── Backup existing installation ───
OPENCLAW_BASE="${OPENCLAW_DIR:-$HOME/.openclaw}"
if [ -d "$OPENCLAW_BASE/agents" ]; then
  BACKUP_DIR="$OPENCLAW_BASE/agents.backup.$(date +%Y%m%d%H%M%S)"
  echo -e "${YELLOW}Existing installation detected at $OPENCLAW_BASE/agents/${NC}"
  echo -e "Creating backup: ${CYAN}$BACKUP_DIR${NC}"
  cp -r "$OPENCLAW_BASE/agents" "$BACKUP_DIR"
  echo -e "${GREEN}Backup created.${NC}"
  echo ""
fi

# ─── Step 1: Bootstrap (system deps + Node.js + OpenClaw) ───
echo -e "${BOLD}Step 1/4: Installing dependencies...${NC}"
echo ""

if [ -f "$SCRIPT_DIR/scripts/bootstrap-install.sh" ]; then
  BOOTSTRAP_ARGS=""
  [ "$NONINTERACTIVE" = "1" ] && BOOTSTRAP_ARGS="--yes"
  bash "$SCRIPT_DIR/scripts/bootstrap-install.sh" $BOOTSTRAP_ARGS
else
  echo -e "${RED}ERROR: scripts/bootstrap-install.sh not found${NC}"
  echo "Make sure you cloned the repository correctly."
  exit 1
fi

echo ""

# ─── Step 2: Setup wizard (config + placeholders) ───
echo -e "${BOLD}Step 2/4: Running setup wizard...${NC}"
echo ""

if [ -f "$SCRIPT_DIR/scripts/setup-wizard.sh" ]; then
  if [ "$NONINTERACTIVE" = "1" ]; then
    echo -e "${YELLOW}Non-interactive mode: skipping wizard.${NC}"
    echo "Run manually later: bash scripts/setup-wizard.sh"
    # Create .env from example if not exists
    if [ ! -f "$SCRIPT_DIR/.env" ] && [ -f "$SCRIPT_DIR/.env.example" ]; then
      cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
      echo -e "${CYAN}Created .env from .env.example — edit with your values before starting.${NC}"
    fi
  else
    bash "$SCRIPT_DIR/scripts/setup-wizard.sh"
  fi
else
  echo -e "${YELLOW}WARNING: scripts/setup-wizard.sh not found${NC}"
  echo "You may need to configure manually."
fi

echo ""

# ─── Step 3: Initialize workspace ───
echo -e "${BOLD}Step 3/4: Initializing workspace...${NC}"
echo ""

if [ -f "$SCRIPT_DIR/scripts/init-workspace.sh" ]; then
  bash "$SCRIPT_DIR/scripts/init-workspace.sh"
else
  echo -e "${YELLOW}WARNING: scripts/init-workspace.sh not found${NC}"
fi

echo ""

# ─── Step 4: Smoke test ───
echo -e "${BOLD}Step 4/4: Running smoke test...${NC}"
echo ""

if [ -f "$SCRIPT_DIR/scripts/smoke-test.sh" ]; then
  AGENT_ARGS=""
  [ -n "$SELECTED_AGENTS" ] && AGENT_ARGS="--agents $SELECTED_AGENTS"
  bash "$SCRIPT_DIR/scripts/smoke-test.sh" $AGENT_ARGS || true
else
  echo -e "${YELLOW}WARNING: scripts/smoke-test.sh not found${NC}"
fi

# ─── Done ───
echo ""
echo "=============================================="
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. ${BOLD}openclaw init${NC}               — configure LLM provider (first time)"
echo -e "  2. ${BOLD}openclaw gateway start${NC}      — start the system"
echo -e "  3. ${BOLD}openclaw status${NC}             — verify agents"
echo -e "  4. Send a message to your Telegram bot"
echo ""
echo -e "Docs: ${CYAN}docs/first-task.md${NC} | ${CYAN}docs/architecture.md${NC} | ${CYAN}docs/faq.md${NC}"
echo ""
echo -e "🧪 ${BOLD}Say my name.${NC}"
