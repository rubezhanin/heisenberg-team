#!/bin/bash
# setup-skills.sh — Install shared skills for Heisenberg Team
# Skills are stored ONCE in ~/.openclaw/skills/ and symlinked to each agent
# This replaces the old approach of copying skills per-agent
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OPENCLAW_BASE="${OPENCLAW_DIR:-$HOME/.openclaw}"
SHARED_SKILLS="$OPENCLAW_BASE/skills"
REPO_SKILLS="$REPO_DIR/skills"
SELECTED_AGENTS=""
FORCE=false

usage() {
  cat <<'EOF'
Usage: bash scripts/setup-skills.sh [options]

Options:
  --agents a,b,c    Only link skills for selected agents
  --force           Recreate symlinks even if they exist
  --help            Show this help

What this does:
  1. Copies skills from repo to ~/.openclaw/skills/ (shared, single copy)
  2. Creates symlinks: ~/.openclaw/agents/<agent>/agent/skills → ../../skills/
  3. All agents share the same skills directory
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agents) SELECTED_AGENTS="${2:-}"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done

# Agent mapping
declare -A AGENT_MAP=(
  ["heisenberg"]="main"
  ["saul"]="producer"
  ["walter"]="teamlead"
  ["jesse"]="marketing-funnel"
  ["skyler"]="skyler"
  ["hank"]="hank"
  ["gus"]="kaizen"
  ["twins"]="researcher"
)

ALL_AGENTS=(heisenberg saul walter jesse skyler hank gus twins)
TARGET_AGENTS=()

if [ -n "$SELECTED_AGENTS" ]; then
  IFS=',' read -r -a INPUT_AGENTS <<< "$SELECTED_AGENTS"
  for a in "${INPUT_AGENTS[@]}"; do
    a="$(printf '%s' "$a" | xargs)"
    [ -z "$a" ] && continue
    TARGET_AGENTS+=("$a")
  done
else
  TARGET_AGENTS=("${ALL_AGENTS[@]}")
fi

echo "Skills Setup (Shared Directory)"
echo "================================"
echo ""

# Step 1: Copy skills to shared directory
if [ ! -d "$REPO_SKILLS" ]; then
  echo "ERROR: Skills directory not found at $REPO_SKILLS"
  exit 1
fi

echo "Installing shared skills to $SHARED_SKILLS..."
mkdir -p "$SHARED_SKILLS"

SKILL_OK=0
SKILL_FAIL=0
for skill_dir in "$REPO_SKILLS"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if cp -r "$skill_dir" "$SHARED_SKILLS/" 2>/dev/null; then
    SKILL_OK=$((SKILL_OK + 1))
  else
    echo "  WARN: Failed to copy $skill_name"
    SKILL_FAIL=$((SKILL_FAIL + 1))
  fi
done
echo "  OK: $SKILL_OK skills installed"
[ "$SKILL_FAIL" -gt 0 ] && echo "  WARN: $SKILL_FAIL skills failed"

# Step 2: Create symlinks for each agent
echo ""
echo "Creating symlinks for agents..."

for char_name in "${TARGET_AGENTS[@]}"; do
  agent_name="${AGENT_MAP[$char_name]:-$char_name}"
  agent_dir="$OPENCLAW_BASE/agents/$agent_name/agent"

  if [ ! -d "$agent_dir" ]; then
    echo "  WARN: Agent directory not found: $agent_dir"
    continue
  fi

  skills_link="$agent_dir/skills"

  # Remove existing (file, dir, or symlink)
  if [ -e "$skills_link" ] || [ -L "$skills_link" ]; then
    if [ "$FORCE" = true ]; then
      rm -rf "$skills_link"
    elif [ -L "$skills_link" ]; then
      # Check if symlink points to correct location
      existing_target="$(readlink "$skills_link" 2>/dev/null || echo "")"
      if [ "$existing_target" = "$SHARED_SKILLS" ]; then
        echo "  OK: $agent_name — symlink already correct"
        continue
      else
        rm -f "$skills_link"
      fi
    else
      # It's a real directory (old-style copy) — remove and replace with symlink
      echo "  INFO: $agent_name — replacing old copied skills with symlink"
      rm -rf "$skills_link"
    fi
  fi

  # Create relative symlink
  # From: ~/.openclaw/agents/<agent>/agent/skills
  # To:   ~/.openclaw/skills/
  ln -s "$SHARED_SKILLS" "$skills_link"
  echo "  OK: $agent_name — skills linked"
done

echo ""
echo "================================"
echo "Done. All agents share: $SHARED_SKILLS"
echo ""
echo "Skills available:"
ls "$SHARED_SKILLS/" 2>/dev/null | head -10
echo "... ($(ls "$SHARED_SKILLS/" 2>/dev/null | wc -l | tr -d ' ') total)"
