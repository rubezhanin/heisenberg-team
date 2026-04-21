#!/bin/bash
# smoke-test.sh — Quick verification that Heisenberg Team is correctly installed
# Синхронизирован с фазой 10 deploy-one-click.sh
# Standalone: можно запускать отдельно после deploy-one-click.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
SELECTED_AGENTS=""
ALL_AGENTS=(heisenberg saul walter jesse skyler hank gus twins watchdog)
TARGET_AGENTS=()

# ── Paths ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

usage() {
  cat <<'EOF'
Usage: bash scripts/smoke-test.sh [options]

Options:
  --agents a,b,c   Check only selected agents
  --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agents)
      SELECTED_AGENTS="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [ -n "$SELECTED_AGENTS" ]; then
  IFS=',' read -r -a TARGET_AGENTS <<< "$SELECTED_AGENTS"
  for i in "${!TARGET_AGENTS[@]}"; do
    TARGET_AGENTS[$i]="$(printf '%s' "${TARGET_AGENTS[$i]}" | xargs)"
  done
else
  TARGET_AGENTS=("${ALL_AGENTS[@]}")
fi

echo ""
echo -e "${BOLD}Heisenberg Team — Smoke Test${NC}"
echo "================================="
echo ""
echo "Agents under test: ${TARGET_AGENTS[*]}"
echo ""

# 1. Check critical files in repo
echo -e "${BOLD}📁 1. Critical repo files${NC}"
for f in AGENTS.md references/team-constitution.md references/team-board.md.example README.md LICENSE; do
  if [ -f "$REPO_DIR/$f" ]; then
    echo -e "  ${GREEN}OK${NC} $f"
  else
    echo -e "  ${RED}FAIL${NC} $f MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
echo ""

# 2. Check selected agents
echo -e "${BOLD}👤 2. Agent files${NC}"
REQUIRED_AGENT_FILES="AGENTS.md SOUL.md IDENTITY.md TOOLS.md MEMORY.md BOOTSTRAP.md HEARTBEAT.md"
for agent in "${TARGET_AGENTS[@]}"; do
  dir="$REPO_DIR/agents/$agent"
  if [ ! -d "$dir" ]; then
    echo -e "  ${RED}FAIL${NC} $agent — directory missing"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  agent_ok=true
  for f in $REQUIRED_AGENT_FILES; do
    if [ ! -f "$dir/$f" ]; then
      echo -e "  ${RED}FAIL${NC} $agent — missing $f"
      agent_ok=false
      ERRORS=$((ERRORS + 1))
    fi
  done
  if [ "$agent_ok" = true ]; then
    echo -e "  ${GREEN}OK${NC} $agent"
  fi
done
echo ""

# 3. Check for remaining placeholders
echo -e "${BOLD}🔍 3. Placeholders${NC}"
PLACEHOLDER_COUNT=0
for agent in "${TARGET_AGENTS[@]}"; do
  if [ -d "$REPO_DIR/agents/$agent" ]; then
    count=$(grep -r '{{[A-Z_]*}}' "$REPO_DIR/agents/$agent" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')
    PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + count))
  fi
done
if [ "$PLACEHOLDER_COUNT" -gt 0 ]; then
  echo -e "  ${YELLOW}WARN${NC} $PLACEHOLDER_COUNT unfilled placeholders in agent files"
  echo "    Run: grep -rn '{{' agents/ --include='*.md' | head -10"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "  ${GREEN}OK${NC} All agent placeholders filled"
fi

# Check generated configs for placeholders
if ls "$REPO_DIR/configs/generated/"*.json 1>/dev/null 2>&1; then
  GEN_PLACEHOLDERS=$(grep -rn '{{' "$REPO_DIR/configs/generated/" --include="*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${GEN_PLACEHOLDERS:-0}" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN${NC} $GEN_PLACEHOLDERS placeholders in generated configs"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "  ${GREEN}OK${NC} Generated configs clean"
  fi

  # Check empty API keys in generated configs
  for cfg in "$REPO_DIR/configs/generated/"*.json; do
    [ -f "$cfg" ] || continue
    empty_keys=$(grep -c '"[a-z]*": ""' "$cfg" 2>/dev/null || echo 0)
    if [ "${empty_keys:-0}" -gt 0 ]; then
      echo -e "  ${YELLOW}WARN${NC} $(basename "$cfg"): $empty_keys empty API key(s)"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
fi
echo ""

# 4. Check configs
echo -e "${BOLD}⚙️  4. Config templates${NC}"
if ls "$REPO_DIR/configs/"*.example 1>/dev/null 2>&1; then
  CONFIG_COUNT=$(ls "$REPO_DIR/configs/"*.example | wc -l | tr -d ' ')
  echo -e "  ${GREEN}OK${NC} $CONFIG_COUNT config templates found"
else
  echo -e "  ${RED}FAIL${NC} No config templates in configs/"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# 5. Check scripts syntax
echo -e "${BOLD}📜 5. Script syntax${NC}"
SCRIPT_ERRORS=0
for f in "$REPO_DIR/scripts/"*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC} Syntax error: $(basename "$f")"
    SCRIPT_ERRORS=$((SCRIPT_ERRORS + 1))
  fi
done
if [ "$SCRIPT_ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}OK${NC} All scripts pass syntax check"
else
  ERRORS=$((ERRORS + SCRIPT_ERRORS))
fi
echo ""

# 6. Check OpenClaw
echo -e "${BOLD}🔧 6. OpenClaw${NC}"
if command -v openclaw >/dev/null 2>&1; then
  echo -e "  ${GREEN}OK${NC} OpenClaw installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
else
  echo -e "  ${YELLOW}WARN${NC} OpenClaw not installed — install with: npm install -g openclaw"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 7. Check .env file
echo -e "${BOLD}🔐 7. Environment (.env)${NC}"
if [ -f "$REPO_DIR/.env" ]; then
  echo -e "  ${GREEN}OK${NC} .env exists"

  # Check permissions
  env_perms=$(stat -c '%a' "$REPO_DIR/.env" 2>/dev/null || stat -f '%Lp' "$REPO_DIR/.env" 2>/dev/null || echo "unknown")
  if [ "$env_perms" = "600" ]; then
    echo -e "  ${GREEN}OK${NC} .env permissions: 600"
  else
    echo -e "  ${YELLOW}WARN${NC} .env permissions: $env_perms (recommended: 600)"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Source safely
  set -a; . "$REPO_DIR/.env" 2>/dev/null || true; set +a

  # Check key env vars
  for var in DEFAULT_PROVIDER DEFAULT_MODEL; do
    val="${!var:-}"
    if [ -n "$val" ]; then
      echo -e "  ${GREEN}OK${NC} $var=$val"
    else
      echo -e "  ${YELLOW}WARN${NC} $var not set"
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  # Validate API key formats
  if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$ANTHROPIC_API_KEY" != "your-anthropic-key" ]; then
    if echo "$ANTHROPIC_API_KEY" | grep -qE '^sk-ant-'; then
      echo -e "  ${GREEN}OK${NC} Anthropic key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} Anthropic key format unexpected (expected sk-ant-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ -n "${OPENAI_API_KEY:-}" ] && [ "$OPENAI_API_KEY" != "your-openai-key" ]; then
    if echo "$OPENAI_API_KEY" | grep -qE '^sk-'; then
      echo -e "  ${GREEN}OK${NC} OpenAI key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} OpenAI key format unexpected (expected sk-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ -n "${OPENROUTER_API_KEY:-}" ] && [ "$OPENROUTER_API_KEY" != "your-openrouter-key" ]; then
    if echo "$OPENROUTER_API_KEY" | grep -qE '^sk-or-'; then
      echo -e "  ${GREEN}OK${NC} OpenRouter key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} OpenRouter key format unexpected (expected sk-or-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ -n "${GROQ_API_KEY:-}" ] && [ "$GROQ_API_KEY" != "your-groq-key" ]; then
    if echo "$GROQ_API_KEY" | grep -qE '^gsk_'; then
      echo -e "  ${GREEN}OK${NC} Groq key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} Groq key format unexpected (expected gsk_...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check for placeholder values
  PLACEHOLDER_KEYS=$(grep -E '^(ANTHROPIC|OPENAI|OPENROUTER|GOOGLE|DEEPSEEK|GROQ)_API_KEY=' "$REPO_DIR/.env" 2>/dev/null | grep -cE '=your-|=sk-your|gsk-your' || echo 0)
  if [ "${PLACEHOLDER_KEYS:-0}" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN${NC} $PLACEHOLDER_KEYS API key(s) still have placeholder values"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo -e "  ${YELLOW}WARN${NC} .env not found — run: cp .env.example .env"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 8. Check installed workspaces (if any)
echo -e "${BOLD}📂 8. Installed workspaces${NC}"
if [ -d "$OPENCLAW_HOME/agents" ]; then
  INSTALLED=$(ls "$OPENCLAW_HOME/agents/" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}OK${NC} $INSTALLED agents in $OPENCLAW_HOME/agents/"

  # Check configs exist
  for agent in "${TARGET_AGENTS[@]}"; do
    if [ -f "$OPENCLAW_HOME/agents/$agent/openclaw.json" ]; then
      echo -e "  ${GREEN}OK${NC} $agent config exists"
    else
      echo -e "  ${YELLOW}INFO${NC} $agent config not deployed yet"
    fi
  done

  # Check gateway binding
  for agent in "${TARGET_AGENTS[@]}"; do
    config="$OPENCLAW_HOME/agents/$agent/openclaw.json"
    [ -f "$config" ] || continue
    gw_host=$(jq -r '.gateway.host // "0.0.0.0"' "$config" 2>/dev/null)
    if [ "$gw_host" = "0.0.0.0" ]; then
      echo -e "  ${RED}FAIL${NC} $agent: gateway bound to 0.0.0.0 (SECURITY RISK!)"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo -e "  ${CYAN}INFO${NC} No workspaces deployed yet (run deploy-one-click.sh first)"
fi
echo ""

# 9. Check skills
echo -e "${BOLD}📚 9. Skills${NC}"
SHARED_SKILLS="$OPENCLAW_HOME/shared-skills"
if [ -d "$SHARED_SKILLS" ]; then
  SKILL_COUNT=$(ls "$SHARED_SKILLS/" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}OK${NC} Shared skills: $SKILL_COUNT ($SHARED_SKILLS)"

  # Check CHECKSUMS
  if [ -f "$SHARED_SKILLS/CHECKSUMS.sha256" ]; then
    echo -e "  ${GREEN}OK${NC} CHECKSUMS.sha256 exists"
  fi

  # Check symlinks
  BROKEN_SYMLINKS=0
  for agent in "${TARGET_AGENTS[@]}"; do
    skills_link="$OPENCLAW_HOME/agents/$agent/skills"
    if [ -L "$skills_link" ] && [ ! -e "$skills_link" ]; then
      BROKEN_SYMLINKS=$((BROKEN_SYMLINKS + 1))
      echo -e "  ${RED}FAIL${NC} Broken symlink: $agent/skills"
    fi
  done
  if [ "$BROKEN_SYMLINKS" -eq 0 ]; then
    echo -e "  ${GREEN}OK${NC} No broken symlinks"
  else
    ERRORS=$((ERRORS + BROKEN_SYMLINKS))
  fi
else
  echo -e "  ${CYAN}INFO${NC} Shared skills not deployed yet"
fi
echo ""

# 10. Integrity baseline
echo -e "${BOLD}🛡️  10. Security${NC}"
if [ -f "$OPENCLAW_HOME/.integrity-baseline.sha256" ]; then
  echo -e "  ${GREEN}OK${NC} Integrity baseline exists"
fi

# Check for API key leaks
LEAKED=$(grep -rlE '(sk-ant-|sk-or-|sk-[a-zA-Z0-9]{32,}|gsk_)' "$REPO_DIR/agents/" --include="*.md" 2>/dev/null || true)
if [ -n "$LEAKED" ]; then
  echo -e "  ${RED}FAIL${NC} API keys found in .md files!"
  echo "$LEAKED" | head -5
  ERRORS=$((ERRORS + 1))
else
  echo -e "  ${GREEN}OK${NC} No API key leaks in agent files"
fi
echo ""

# ── Summary ──
echo "================================="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed!${NC}"
  exit 0
elif [ "$ERRORS" -eq 0 ]; then
  echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$ERRORS error(s), $WARNINGS warning(s)${NC}"
  exit 1
fi
