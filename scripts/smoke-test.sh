#!/bin/bash
# smoke-test.sh — Quick verification that Heisenberg Team is correctly installed
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
SELECTED_AGENTS=""
ALL_AGENTS=(heisenberg saul walter jesse skyler hank gus twins)
TARGET_AGENTS=()

usage() {
  cat <<'EOF'
Usage: bash scripts/smoke-test.sh [options]

Options:
  --agents a,b,c   Check only selected character directories
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
echo "Heisenberg Team - Smoke Test"
echo "================================="
echo ""
echo "Agents under test: ${TARGET_AGENTS[*]}"
echo ""

# 1. Check critical files
echo "Checking critical files..."
for f in agents/heisenberg/AGENTS.md agents/heisenberg/SOUL.md agents/heisenberg/IDENTITY.md \
         references/team-constitution.md references/team-board.md.example \
         README.md LICENSE SETUP.md; do
  if [ -f "$f" ]; then
    echo -e "  ${GREEN}OK${NC} $f"
  else
    echo -e "  ${RED}FAIL${NC} $f MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# 2. Check selected agents
echo "Checking agents..."
for agent in "${TARGET_AGENTS[@]}"; do
  dir="agents/$agent"
  if [ -d "$dir" ] && [ -f "$dir/AGENTS.md" ] && [ -f "$dir/SOUL.md" ]; then
    echo -e "  ${GREEN}OK${NC} $agent"
  else
    echo -e "  ${RED}FAIL${NC} $agent - missing files"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# 3. Check for remaining placeholders
echo "Checking for unfilled placeholders..."
PLACEHOLDER_COUNT=0
for agent in "${TARGET_AGENTS[@]}"; do
  if [ -d "agents/$agent" ]; then
    count=$(grep -r '{{' "agents/$agent" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')
    PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + count))
  fi
done
REFERENCE_PLACEHOLDERS=$(grep -r '{{' references/ --include="*.md" 2>/dev/null | grep -v '.example' | wc -l | tr -d ' ')
PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + REFERENCE_PLACEHOLDERS))
if [ "$PLACEHOLDER_COUNT" -gt 0 ]; then
  echo -e "  ${YELLOW}WARN${NC} $PLACEHOLDER_COUNT unfilled placeholders found"
  echo "    Run: grep -rn '{{' agents/ references/ --include='*.md' | head -10"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "  ${GREEN}OK${NC} All placeholders filled"
fi

echo ""

# 4. Check configs
echo "Checking configs..."
if ls configs/*.example 1>/dev/null 2>&1; then
  CONFIG_COUNT=$(ls configs/*.example | wc -l | tr -d ' ')
  echo -e "  ${GREEN}OK${NC} $CONFIG_COUNT config templates found"
else
  echo -e "  ${RED}FAIL${NC} No config templates in configs/"
  ERRORS=$((ERRORS + 1))
fi

# 4b. Check generated configs for remaining placeholders
if ls configs/generated/*.json 1>/dev/null 2>&1; then
  GEN_PLACEHOLDERS=$(grep -rn '{{' configs/generated/ --include="*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$GEN_PLACEHOLDERS" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN${NC} $GEN_PLACEHOLDERS placeholders in generated configs"
    echo "    Run: grep -rn '{{' configs/generated/ --include='*.json' | head -10"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "  ${GREEN}OK${NC} Generated configs clean"
  fi
fi

# 4c. Check generated configs have non-empty apiKeys
if ls configs/generated/*.json 1>/dev/null 2>&1; then
  for cfg in configs/generated/*.json; do
    empty_keys=$(grep -c '"[a-z]*": ""' "$cfg" 2>/dev/null || echo 0)
    if [ "$empty_keys" -gt 0 ]; then
      echo -e "  ${YELLOW}WARN${NC} $(basename "$cfg"): $empty_keys empty API key(s)"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
fi

echo ""

# 5. Check scripts
echo "Checking scripts..."
SCRIPT_ERRORS=0
for f in scripts/*.sh; do
  if ! bash -n "$f" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC} Syntax error: $f"
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
echo "Checking OpenClaw..."
if command -v openclaw >/dev/null 2>&1; then
  echo -e "  ${GREEN}OK${NC} OpenClaw installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
else
  echo -e "  ${YELLOW}WARN${NC} OpenClaw not installed - install with: npm install -g openclaw"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 7. Check .env file
echo "Checking .env..."
if [ -f ".env" ]; then
  echo -e "  ${GREEN}OK${NC} .env exists"
  # Check for model configuration
  if grep -q "^MAIN_MODEL=" .env 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} MAIN_MODEL configured: $(grep '^MAIN_MODEL=' .env | cut -d= -f2)"
  else
    echo -e "  ${YELLOW}WARN${NC} MAIN_MODEL not set in .env"
    WARNINGS=$((WARNINGS + 1))
  fi
  if grep -q "^AGENT_MODEL=" .env 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} AGENT_MODEL configured: $(grep '^AGENT_MODEL=' .env | cut -d= -f2)"
  else
    echo -e "  ${YELLOW}WARN${NC} AGENT_MODEL not set in .env"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo -e "  ${YELLOW}WARN${NC} .env not found - run setup wizard or copy from .env.example"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 8. Check voice transcription setup
echo "Checking voice transcription..."
if [ -f ".env" ] && grep -q "^GROQ_API_KEY=" .env 2>/dev/null; then
  GROQ_KEY=$(grep '^GROQ_API_KEY=' .env | cut -d= -f2)
  if [ -n "$GROQ_KEY" ] && [ "$GROQ_KEY" != "your-groq-key" ]; then
    echo -e "  ${GREEN}OK${NC} Groq API configured"
  else
    echo -e "  ${YELLOW}INFO${NC} Groq API key placeholder (not configured)"
  fi
elif [ -f "$HOME/whisper.cpp/build/bin/whisper-cli" ]; then
  echo -e "  ${GREEN}OK${NC} Local whisper.cpp found"
else
  echo -e "  ${YELLOW}INFO${NC} No voice transcription configured (Groq or whisper.cpp)"
fi

echo ""

# 9. Validate API keys format
echo "Validating API keys..."
if [ -f ".env" ]; then
  # Source .env safely
  set -a; . .env 2>/dev/null || true; set +a

  # Check Anthropic key format
  if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "$ANTHROPIC_API_KEY" != "your-anthropic-key" ]; then
    if echo "$ANTHROPIC_API_KEY" | grep -qE '^sk-ant-'; then
      echo -e "  ${GREEN}OK${NC} Anthropic key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} Anthropic key format unexpected (expected sk-ant-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check OpenAI key format
  if [ -n "${OPENAI_API_KEY:-}" ] && [ "$OPENAI_API_KEY" != "your-openai-key" ]; then
    if echo "$OPENAI_API_KEY" | grep -qE '^sk-'; then
      echo -e "  ${GREEN}OK${NC} OpenAI key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} OpenAI key format unexpected (expected sk-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check OpenRouter key format
  if [ -n "${OPENROUTER_API_KEY:-}" ] && [ "$OPENROUTER_API_KEY" != "your-openrouter-key" ]; then
    if echo "$OPENROUTER_API_KEY" | grep -qE '^sk-or-'; then
      echo -e "  ${GREEN}OK${NC} OpenRouter key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} OpenRouter key format unexpected (expected sk-or-...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check Groq key format
  if [ -n "${GROQ_API_KEY:-}" ] && [ "$GROQ_API_KEY" != "your-groq-key" ]; then
    if echo "$GROQ_API_KEY" | grep -qE '^gsk_'; then
      echo -e "  ${GREEN}OK${NC} Groq key format valid"
    else
      echo -e "  ${YELLOW}WARN${NC} Groq key format unexpected (expected gsk_...)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Check for placeholder values still present
  PLACEHOLDER_KEYS=$(grep -E '^(ANTHROPIC|OPENAI|OPENROUTER|GOOGLE|DEEPSEEK|GROQ)_API_KEY=' .env 2>/dev/null | grep -cE '=your-|=sk-your|gsk-your' || echo 0)
  if [ "$PLACEHOLDER_KEYS" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN${NC} $PLACEHOLDER_KEYS API key(s) still have placeholder values"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo -e "  ${YELLOW}SKIP${NC} No .env file to validate"
fi

echo ""

# 10. Check skills symlink health
echo "Checking skills installation..."
OPENCLAW_BASE="${OPENCLAW_DIR:-$HOME/.openclaw}"
if [ -d "$OPENCLAW_BASE/skills" ]; then
  SKILL_COUNT_SHARED=$(ls "$OPENCLAW_BASE/skills/" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${GREEN}OK${NC} Shared skills directory: $SKILL_COUNT_SHARED skills"

  # Check symlinks
  BROKEN_SYMLINKS=0
  for agent_dir in "$OPENCLAW_BASE/agents"/*/agent/skills; do
    if [ -L "$agent_dir" ] && [ ! -e "$agent_dir" ]; then
      BROKEN_SYMLINKS=$((BROKEN_SYMLINKS + 1))
    fi
  done
  if [ "$BROKEN_SYMLINKS" -gt 0 ]; then
    echo -e "  ${RED}FAIL${NC} $BROKEN_SYMLINKS broken skill symlinks"
    ERRORS=$((ERRORS + 1))
  fi
elif [ -d "$OPENCLAW_BASE/agents/producer/agent/skills" ]; then
  SKILL_COUNT_PROD=$(ls "$OPENCLAW_BASE/agents/producer/agent/skills/" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  ${YELLOW}INFO${NC} Old-style skills in producer/: $SKILL_COUNT_PROD"
  echo -e "    Consider running: bash scripts/setup-skills.sh"
else
  echo -e "  ${YELLOW}WARN${NC} No skills directory found"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "================================="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed!${NC}"
elif [ "$ERRORS" -eq 0 ]; then
  echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
else
  echo -e "${RED}$ERRORS error(s), $WARNINGS warning(s)${NC}"
  exit 1
fi
