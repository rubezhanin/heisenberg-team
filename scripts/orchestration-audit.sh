#!/bin/bash
# orchestration-audit.sh — Full audit of OpenClaw orchestration health
# Run this to get a complete picture of the installation
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ISSUES=0

header() { echo -e "\n${BOLD}=== $1 ===${NC}"; }
ok()     { echo -e "  ${GREEN}OK${NC} $1"; }
warn()   { echo -e "  ${YELLOW}WARN${NC} $1"; }
fail()   { echo -e "  ${RED}FAIL${NC} $1"; ISSUES=$((ISSUES + 1)); }
info()   { echo -e "  ${CYAN}INFO${NC} $1"; }

echo ""
echo -e "${BOLD}Heisenberg Team — Orchestration Audit${NC}"
echo "==========================================="

# ─── 1. OpenClaw Version ───
header "OpenClaw"
if command -v openclaw >/dev/null 2>&1; then
  ok "OpenClaw $(openclaw --version 2>/dev/null || echo 'unknown')"
else
  fail "OpenClaw not installed"
fi

# ─── 2. Gateway Status ───
header "Gateway"
if command -v openclaw >/dev/null 2>&1; then
  GW_STATUS=$(openclaw gateway status 2>/dev/null || echo "error")
  if echo "$GW_STATUS" | grep -qi "running\|ok\|active"; then
    ok "Gateway running"
  else
    fail "Gateway not running or error: $GW_STATUS"
  fi
fi

# ─── 3. Node.js ───
header "Node.js"
if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version)
  NODE_MAJOR="${NODE_VER#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [ "$NODE_MAJOR" -ge 20 ] 2>/dev/null; then
    ok "Node.js $NODE_VER"
  else
    warn "Node.js $NODE_VER (need 20+)"
  fi
else
  fail "Node.js not installed"
fi

# ─── 4. Agent Health ───
header "Agents"
OPENCLAW_DIR="$HOME/.openclaw/agents"
if [ -d "$OPENCLAW_DIR" ]; then
  AGENT_COUNT=$(ls -d "$OPENCLAW_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
  ok "$AGENT_COUNT agents installed"

  for agent_dir in "$OPENCLAW_DIR"/*/; do
    agent_name=$(basename "$agent_dir")
    if [ -f "$agent_dir/agent/AGENTS.md" ]; then
      # Check if agent is silent or visible
      if grep -q "SILENT MODE" "$agent_dir/agent/AGENTS.md" 2>/dev/null; then
        info "$agent_name: silent"
      elif grep -q "VISIBLE SPECIALIST" "$agent_dir/agent/AGENTS.md" 2>/dev/null; then
        info "$agent_name: visible"
      else
        info "$agent_name: default"
      fi

      # Check for old-style notification blocks
      if grep -q "ОБЯЗАТЕЛЬНО: Уведомляй пользователя" "$agent_dir/agent/AGENTS.md" 2>/dev/null; then
        warn "$agent_name: still has old notification block (should be silent or visible-specialist)"
      fi
    else
      warn "$agent_name: no AGENTS.md"
    fi
  done
else
  fail "No agents directory at $OPENCLAW_DIR"
fi

# ─── 5. Skills ───
header "Skills"
if [ -d "$HOME/.openclaw/skills" ]; then
  SKILL_COUNT=$(ls "$HOME/.openclaw/skills/" 2>/dev/null | wc -l | tr -d ' ')
  ok "Shared skills: $SKILL_COUNT (single copy)"
elif [ -d "$OPENCLAW_DIR/producer/agent/skills" ]; then
  SKILL_COUNT=$(ls "$OPENCLAW_DIR/producer/agent/skills/" 2>/dev/null | wc -l | tr -d ' ')
  warn "Old-style skills in producer/: $SKILL_COUNT (consider migrating to shared)"
else
  warn "No skills found"
fi

# Check symlinks
if [ -d "$OPENCLAW_DIR" ]; then
  BROKEN=0
  for link in "$OPENCLAW_DIR"/*/agent/skills; do
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      BROKEN=$((BROKEN + 1))
    fi
  done
  if [ "$BROKEN" -gt 0 ]; then
    fail "$BROKEN broken skill symlinks"
  fi
fi

# ─── 6. Config Quality ───
header "Config Quality"
if [ -d "$OPENCLAW_DIR" ]; then
  for cfg in "$OPENCLAW_DIR"/*/openclaw.json; do
    [ -f "$cfg" ] || continue
    agent_name=$(basename "$(dirname "$cfg")")

    # Check for queue config
    if grep -q '"queue"' "$cfg" 2>/dev/null; then
      ok "$agent_name: queue configured"
    else
      warn "$agent_name: no queue config (default behavior)"
    fi

    # Check for empty API keys
    EMPTY=$(grep -c '"[a-z]*": ""' "$cfg" 2>/dev/null || echo 0)
    if [ "$EMPTY" -gt 0 ]; then
      warn "$agent_name: $EMPTY empty API key(s)"
    fi
  done
fi

# ─── 7. .env ───
header "Environment (.env)"
if [ -f ".env" ]; then
  ok ".env exists"
  set -a; . .env 2>/dev/null || true; set +a

  [ -n "${MAIN_MODEL:-}" ] && ok "MAIN_MODEL=$MAIN_MODEL" || warn "MAIN_MODEL not set"
  [ -n "${AGENT_MODEL:-}" ] && ok "AGENT_MODEL=$AGENT_MODEL" || warn "AGENT_MODEL not set"
  [ -n "${TEAM_LANG:-}" ] && ok "TEAM_LANG=$TEAM_LANG" || info "TEAM_LANG not set (default: en)"
  [ -n "${OPENCLAW_VERSION:-}" ] && ok "OPENCLAW_VERSION=$OPENCLAW_VERSION" || info "OPENCLAW_VERSION not pinned"
else
  warn ".env not found"
fi

# ─── 8. Constitution ───
header "Constitution"
if [ -f "references/team-constitution.md" ]; then
  if grep -q "Orchestration Contract" "references/team-constitution.md" 2>/dev/null; then
    ok "Structured return format defined"
  else
    warn "No orchestration contract in constitution"
  fi
  if grep -q "Timeout SLA" "references/team-constitution.md" 2>/dev/null; then
    ok "Timeout SLA defined"
  else
    warn "No timeout SLA in constitution"
  fi
  if grep -q "Visibility Policy" "references/team-constitution.md" 2>/dev/null; then
    ok "Visibility policy defined"
  else
    warn "No visibility policy in constitution"
  fi
else
  fail "team-constitution.md not found"
fi

# ─── Summary ───
echo ""
echo "==========================================="
if [ "$ISSUES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Audit passed — no issues found${NC}"
else
  echo -e "${RED}${BOLD}Audit found $ISSUES issue(s)${NC}"
fi
echo ""
echo "For deeper diagnostics, run:"
echo "  openclaw status"
echo "  openclaw gateway status --json"
echo "  openclaw doctor"
echo "  openclaw sessions --all-agents --active 180"
echo "  openclaw tasks list --json"
echo "  openclaw logs --follow"
