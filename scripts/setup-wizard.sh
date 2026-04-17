#!/bin/bash
# setup-wizard.sh — Interactive setup for Heisenberg Team
# Guides user through all configuration steps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Cross-platform sed: macOS uses -i '', Linux uses -i
if [[ "${OSTYPE:-}" == "darwin"* ]]; then
  SED_INPLACE="sed -i ''"
else
  SED_INPLACE="sed -i"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}🧪 Heisenberg Team — Setup Wizard${NC}"
echo "========================================"
echo ""
echo -e "${CYAN}This wizard will configure your multi-agent system.${NC}"
echo -e "${CYAN}It takes about 5 minutes. You can re-run it anytime.${NC}"
echo ""

# ─── Step 1: Check prerequisites ───
echo -e "${BOLD}Step 1/6: Checking prerequisites...${NC}"
echo ""

ERRORS=0

if command -v openclaw >/dev/null 2>&1; then
  echo -e "  ${GREEN}OK${NC} OpenClaw installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
else
  echo -e "  ${RED}MISSING${NC} OpenClaw not found"
  ERRORS=$((ERRORS + 1))
fi

if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version)
  NODE_MAJOR="${NODE_VER#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [ "$NODE_MAJOR" -ge 20 ] 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} Node.js $NODE_VER"
  else
    echo -e "  ${YELLOW}OLD${NC} Node.js $NODE_VER (need v20+)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo -e "  ${RED}MISSING${NC} Node.js not found"
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  SCRIPT_DIR_BOOT="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "$SCRIPT_DIR_BOOT/bootstrap-install.sh" ]; then
    echo -e "${YELLOW}Missing dependencies detected.${NC}"
    read -p "  Run bootstrap-install.sh to auto-install? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      echo ""
      bash "$SCRIPT_DIR_BOOT/bootstrap-install.sh"
      echo ""
      # Re-check after bootstrap
      ERRORS=0
      command -v openclaw >/dev/null 2>&1 || ERRORS=$((ERRORS + 1))
      if command -v node >/dev/null 2>&1; then
        NODE_MAJOR_CHECK=$(node --version | sed 's/^v//' | cut -d. -f1)
        [ "$NODE_MAJOR_CHECK" -lt 20 ] 2>/dev/null && ERRORS=$((ERRORS + 1))
      else
        ERRORS=$((ERRORS + 1))
      fi
      if [ "$ERRORS" -gt 0 ]; then
        echo -e "${RED}Bootstrap completed but dependencies still missing. Check errors above.${NC}"
        exit 1
      fi
      echo -e "${GREEN}Dependencies installed. Continuing setup...${NC}"
      echo ""
    else
      echo -e "${RED}Fix the issues above and re-run this script.${NC}"
      exit 1
    fi
  else
    echo -e "${RED}Fix the issues above and re-run this script.${NC}"
    echo -e "  Or run: ${BOLD}bash scripts/bootstrap-install.sh${NC}"
    exit 1
  fi
fi

echo ""

# ─── Step 2: Collect user data ───
echo -e "${BOLD}Step 2/6: Your information${NC}"
echo -e "${CYAN}This data replaces {{PLACEHOLDER}} values in agent configs.${NC}"
echo ""

# Helper: prompt with default
ask() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"
  local required="${4:-false}"

  if [ -n "$default" ]; then
    read -p "  $prompt [$default]: " value
    value="${value:-$default}"
  else
    if [ "$required" = "true" ]; then
      while true; do
        read -p "  $prompt: " value
        [ -n "$value" ] && break
        echo -e "  ${RED}This field is required.${NC}"
      done
    else
      read -p "  $prompt (skip with Enter): " value
    fi
  fi
  printf -v "$var_name" '%s' "$value"
}

echo -e "${YELLOW}── Required ──${NC}"
ask OWNER_NAME "Your first name" "" true
ask OWNER_USERNAME "Your GitHub/online username" "" true

echo ""
echo -e "${YELLOW}── Language ──${NC}"
echo "  Agent instruction language (technical files like AGENTS.md, TOOLS.md)"
echo "  Agent personality language is set per-character in SOUL.md"
echo ""
echo "  1) English (recommended — better LLM comprehension)"
echo "  2) Russian (default for this project)"
echo ""
read -p "  Choose [1]: " LANG_CHOICE
LANG_CHOICE="${LANG_CHOICE:-1}"
case "$LANG_CHOICE" in
  1) TEAM_LANG="en" ;;
  2) TEAM_LANG="ru" ;;
  *) TEAM_LANG="en" ;;
esac
echo -e "  ${GREEN}✓${NC} Team language: $TEAM_LANG"

echo ""
echo -e "${YELLOW}── Team layout ──${NC}"
echo "  Default agents: heisenberg, saul, walter, jesse, skyler, hank, gus, twins"
echo "  Default agents: heisenberg, saul, walter, jesse, skyler, hank, gus, twins, watchdog"
ask SELECTED_AGENTS "Agents to install (comma-separated)" "heisenberg,saul,walter,jesse,skyler,hank,gus,twins,watchdog" true
ask TEAM_DIRECTORY "Team root directory" "~/openclaw-agents" true
ask TEAM_DISPLAY_NAME "Team / system name" "Heisenberg Team" true

echo ""
echo -e "${YELLOW}── LLM Provider ──${NC}"
echo ""
echo "  Which LLM provider do you use?"
echo ""
echo "  1) Anthropic (Claude) - recommended"
echo "  2) OpenAI (GPT-4, GPT-4o)"
echo "  3) Google (Gemini)"
echo "  4) Ollama (local models)"
echo "  5) DeepSeek"
echo "  6) OpenRouter (access many models via one key)"
echo "  7) Other / I'll configure manually"
echo ""
read -p "  Choose [1]: " LLM_CHOICE
LLM_CHOICE="${LLM_CHOICE:-1}"

case "$LLM_CHOICE" in
  1)
    LLM_PROVIDER="anthropic"
    MAIN_MODEL="anthropic/claude-opus-4-5"
    AGENT_MODEL="anthropic/claude-sonnet-4-5"
    ask ANTHROPIC_API_KEY "Anthropic API key (or 'max' for Claude Max subscription)" "" true
    if [ "$ANTHROPIC_API_KEY" = "max" ]; then
      ANTHROPIC_API_KEY=""
      echo -e "  ${CYAN}Claude Max detected - no API key needed, uses built-in auth${NC}"
    fi
    ;;
  2)
    LLM_PROVIDER="openai"
    MAIN_MODEL="openai/gpt-4o"
    AGENT_MODEL="openai/gpt-4o"
    ask OPENAI_API_KEY "OpenAI API key" "" true
    ;;
  3)
    LLM_PROVIDER="google"
    MAIN_MODEL="google/gemini-2.5-pro"
    AGENT_MODEL="google/gemini-2.5-flash"
    ask GOOGLE_API_KEY "Google AI API key" "" true
    ;;
  4)
    LLM_PROVIDER="ollama"
    MAIN_MODEL="ollama/llama3"
    AGENT_MODEL="ollama/llama3"
    echo -e "  ${CYAN}Make sure Ollama is running: ollama serve${NC}"
    ask OLLAMA_BASE_URL "Ollama base URL" "http://localhost:11434" false
    ask OLLAMA_MODEL "Ollama model name" "llama3" false
    MAIN_MODEL="ollama/$OLLAMA_MODEL"
    AGENT_MODEL="ollama/$OLLAMA_MODEL"
    ;;
  5)
    LLM_PROVIDER="deepseek"
    MAIN_MODEL="deepseek/deepseek-chat"
    AGENT_MODEL="deepseek/deepseek-chat"
    ask DEEPSEEK_API_KEY "DeepSeek API key (from platform.deepseek.com)" "" true
    echo -e "  ${CYAN}Tip: deepseek-reasoner available for complex tasks${NC}"
    ;;
  6)
    LLM_PROVIDER="openrouter"
    echo ""
    echo -e "  ${CYAN}OpenRouter gives access to 100+ models via one API key.${NC}"
    echo -e "  ${CYAN}Get your key at: https://openrouter.ai/keys${NC}"
    echo ""
    ask OPENROUTER_API_KEY "OpenRouter API key (sk-or-...)" "" true
    echo ""
    echo "  Popular models on OpenRouter:"
    echo "    anthropic/claude-opus-4-5"
    echo "    anthropic/claude-sonnet-4-5"
    echo "    openai/gpt-4o"
    echo "    google/gemini-2.5-pro"
    echo "    deepseek/deepseek-chat-v3-0324"
    echo ""
    ask MAIN_MODEL "Main model (provider/model format)" "anthropic/claude-opus-4-5" true
    ask AGENT_MODEL "Agent model (provider/model format)" "anthropic/claude-sonnet-4-5" true
    ;;
  7)
    LLM_PROVIDER="custom"
    ask MAIN_MODEL "Main model (provider/model format)" "anthropic/claude-opus-4-5" true
    AGENT_MODEL="$MAIN_MODEL"
    ;;
esac

echo ""
echo -e "${YELLOW}── Embeddings ──${NC}"
echo "  Vector memory search needs an embedding provider."
echo ""
echo "  1) OpenAI text-embedding-3-small (recommended, needs OpenAI key)"
echo "  2) Ollama (local, free — needs running Ollama with embedding model)"
echo "  3) Skip (keyword-only memory search)"
echo ""
read -p "  Choose [1]: " EMBED_CHOICE
EMBED_CHOICE="${EMBED_CHOICE:-1}"

case "$EMBED_CHOICE" in
  1)
    if [ "$LLM_PROVIDER" = "openai" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
      EMBEDDING_PROVIDER="openai"
      EMBEDDING_MODEL="text-embedding-3-small"
      echo -e "  ${GREEN}✓${NC} Using OpenAI embeddings (same API key)"
    else
      read -p "  OpenAI API key for embeddings: " EMBED_KEY
      if [ -z "$EMBED_KEY" ]; then
        EMBEDDING_PROVIDER="none"
        EMBEDDING_MODEL=""
        echo -e "  ${YELLOW}⚠${NC} Embeddings skipped - memory search will be keyword-only"
      else
        OPENAI_API_KEY="${OPENAI_API_KEY:-$EMBED_KEY}"
        EMBEDDING_PROVIDER="openai"
        EMBEDDING_MODEL="text-embedding-3-small"
        echo -e "  ${GREEN}✓${NC} OpenAI embeddings configured"
      fi
    fi
    ;;
  2)
    EMBEDDING_PROVIDER="ollama"
    EMBEDDING_MODEL="${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text}"
    ask OLLAMA_BASE_URL "Ollama base URL" "${OLLAMA_BASE_URL:-http://localhost:11434}" false
    ask OLLAMA_EMBEDDING_MODEL "Ollama embedding model" "${EMBEDDING_MODEL}" false
    EMBEDDING_MODEL="$OLLAMA_EMBEDDING_MODEL"
    echo -e "  ${GREEN}✓${NC} Ollama embeddings configured ($EMBEDDING_MODEL)"
    echo -e "  ${CYAN}  Make sure model is pulled: ollama pull $EMBEDDING_MODEL${NC}"
    ;;
  3)
    EMBEDDING_PROVIDER="none"
    EMBEDDING_MODEL=""
    echo -e "  ${YELLOW}⚠${NC} Embeddings skipped - memory search will be keyword-only"
    ;;
  *)
    EMBEDDING_PROVIDER="none"
    EMBEDDING_MODEL=""
    echo -e "  ${YELLOW}⚠${NC} Unknown choice — embeddings skipped"
    ;;
esac

echo ""
echo -e "${YELLOW}── Voice Transcription ──${NC}"
echo "  Transcribe Telegram voice messages."
echo ""
echo "  1) Groq Whisper API (fast, cloud, needs Groq key)"
echo "  2) Local whisper.cpp (free, needs whisper.cpp installed)"
echo "  3) Skip (no voice transcription)"
echo ""
read -p "  Choose [1]: " VOICE_CHOICE
VOICE_CHOICE="${VOICE_CHOICE:-1}"

case "$VOICE_CHOICE" in
  1)
    VOICE_PROVIDER="groq"
    ask GROQ_API_KEY "Groq API key (gsk_...)" "" true
    ask GROQ_WHISPER_MODEL "Whisper model" "whisper-large-v3-turbo" false
    GROQ_WHISPER_MODEL="${GROQ_WHISPER_MODEL:-whisper-large-v3-turbo}"
    echo -e "  ${GREEN}✓${NC} Groq transcription configured ($GROQ_WHISPER_MODEL)"
    ;;
  2)
    VOICE_PROVIDER="local"
    WHISPER_DIR="$HOME/whisper.cpp"
    if [ -d "$WHISPER_DIR" ]; then
      echo -e "  ${GREEN}✓${NC} whisper.cpp found at $WHISPER_DIR"
    else
      echo -e "  ${YELLOW}⚠${NC} whisper.cpp not found at $WHISPER_DIR"
      echo -e "  ${CYAN}  Install: git clone https://github.com/ggerganov/whisper.cpp ~/whisper.cpp && cd ~/whisper.cpp && make${NC}"
    fi
    ;;
  3)
    VOICE_PROVIDER="none"
    echo -e "  ${YELLOW}⚠${NC} Voice transcription skipped"
    ;;
  *)
    VOICE_PROVIDER="none"
    echo -e "  ${YELLOW}⚠${NC} Unknown choice — voice transcription skipped"
    ;;
esac

echo ""
echo -e "${YELLOW}── Telegram (recommended) ──${NC}"
echo -e "  ${CYAN}Agents send you status updates via Telegram.${NC}"
echo -e "  ${CYAN}Get your ID from @userinfobot on Telegram.${NC}"
ask OWNER_TELEGRAM_ID "Your Telegram user ID (digits)"
ask TELEGRAM_CHANNEL "Your Telegram channel name (without @)"
ask BOT_USERNAME "Main bot username (e.g. @MyBot_bot)"

declare -A AGENT_MAP=(
  ["heisenberg"]="main"
  ["saul"]="producer"
  ["walter"]="teamlead"
  ["jesse"]="marketing-funnel"
  ["skyler"]="skyler"
  ["hank"]="hank"
  ["gus"]="kaizen"
  ["twins"]="researcher"
  ["watchdog"]="watchdog"
)

declare -A DEFAULT_DISPLAY_NAMES=(
  ["heisenberg"]="Heisenberg"
  ["saul"]="Saul"
  ["walter"]="Walter"
  ["jesse"]="Jesse"
  ["skyler"]="Skyler"
  ["hank"]="Hank"
  ["gus"]="Gus"
  ["twins"]="Twins"
  ["watchdog"]="Watchdog"
)

IFS=',' read -r -a SELECTED_AGENT_LIST <<< "$SELECTED_AGENTS"
echo ""
echo -e "${YELLOW}── Per-agent setup ──${NC}"
for i in "${!SELECTED_AGENT_LIST[@]}"; do
  agent="$(printf '%s' "${SELECTED_AGENT_LIST[$i]}" | xargs)"
  [ -z "$agent" ] && continue
  if [ -z "${AGENT_MAP[$agent]:-}" ]; then
    echo -e "  ${YELLOW}⚠${NC} Unknown built-in agent '$agent' - skipped in guided token setup"
    continue
  fi
  upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
  default_name="${DEFAULT_DISPLAY_NAMES[$agent]}"
  ask "DISPLAY_NAME_${upper}" "Display name for $agent" "$default_name" true
  ask "TELEGRAM_BOT_TOKEN_${upper}" "Telegram bot token for $agent" ""
  session_name="${AGENT_MAP[$agent]}"
  printf -v "CUSTOM_AGENT_NAME_${upper}" '%s' "$session_name"
done

echo ""
echo -e "${YELLOW}── Optional ──${NC}"
ask OWNER_SURNAME "Your last name"
ask COUNTRY "Your country"
ask CITY "Your city"
ask GITHUB_ORG "GitHub organization/username" "$OWNER_USERNAME"
ask WORKSPACE_PATH "Workspace path" "$TEAM_DIRECTORY/"

echo ""
# ─── Step 3: Replace placeholders ───
echo -e "${BOLD}Step 3/6: Applying configuration...${NC}"
echo ""

# Derive short model names for constitution
MAIN_MODEL_SHORT=$(echo "$MAIN_MODEL" | sed 's|.*/||')
AGENT_MODEL_SHORT=$(echo "$AGENT_MODEL" | sed 's|.*/||')

# Build replacement pairs
declare -A REPLACEMENTS=(
  ["{{OWNER_NAME}}"]="${OWNER_NAME}"
  ["{{TEAM_NAME}}"]="${TEAM_DISPLAY_NAME}"
  ["{{TEAM_LANG}}"]="${TEAM_LANG:-en}"
  ["{{OWNER_USERNAME}}"]="${OWNER_USERNAME}"
  ["{{OWNER_TELEGRAM_ID}}"]="${OWNER_TELEGRAM_ID:-YOUR_TELEGRAM_ID}"
  ["{{TELEGRAM_CHANNEL}}"]="${TELEGRAM_CHANNEL:-YOUR_CHANNEL}"
  ["{{BOT_USERNAME}}"]="${BOT_USERNAME:-@YourBot_bot}"
  ["{{OWNER_SURNAME}}"]="${OWNER_SURNAME:-Surname}"
  ["{{COUNTRY}}"]="${COUNTRY:-Country}"
  ["{{CITY}}"]="${CITY:-City}"
  ["{{GITHUB_ORG}}"]="${GITHUB_ORG:-$OWNER_USERNAME}"
  ["{{WORKSPACE_PATH}}"]="${WORKSPACE_PATH:-$TEAM_DIRECTORY/}"
  ["{{PROJECTS_PATH}}"]="${WORKSPACE_PATH:-$TEAM_DIRECTORY/}projects/"
  ["{{MAIN_MODEL}}"]="${MAIN_MODEL}"
  ["{{AGENT_MODEL}}"]="${AGENT_MODEL}"
  ["{{MAIN_MODEL_ID}}"]="${MAIN_MODEL}"
  ["{{AGENT_MODEL_ID}}"]="${AGENT_MODEL}"
  ["{{MAIN_MODEL_SHORT}}"]="${MAIN_MODEL_SHORT}"
  ["{{AGENT_MODEL_SHORT}}"]="${AGENT_MODEL_SHORT}"
  ["{{EMBEDDING_PROVIDER}}"]="${EMBEDDING_PROVIDER:-openai}"
  ["{{EMBEDDING_MODEL}}"]="${EMBEDDING_MODEL:-text-embedding-3-small}"
  ["{{ANTHROPIC_API_KEY}}"]="${ANTHROPIC_API_KEY:-your-anthropic-key}"
  ["{{OPENAI_API_KEY}}"]="${OPENAI_API_KEY:-your-openai-key}"
  ["{{GOOGLE_API_KEY}}"]="${GOOGLE_API_KEY:-your-google-key}"
  ["{{DEEPSEEK_API_KEY}}"]="${DEEPSEEK_API_KEY:-your-deepseek-key}"
  ["{{OPENROUTER_API_KEY}}"]="${OPENROUTER_API_KEY:-your-openrouter-key}"
  ["{{GROQ_API_KEY}}"]="${GROQ_API_KEY:-your-groq-key}"
  ["{{GROQ_WHISPER_MODEL}}"]="${GROQ_WHISPER_MODEL:-whisper-large-v3-turbo}"
  ["{{OLLAMA_BASE_URL}}"]="${OLLAMA_BASE_URL:-http://localhost:11434}"
  ["{{OLLAMA_EMBEDDING_MODEL}}"]="${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text}"
)


for agent in heisenberg saul walter jesse skyler hank gus twins watchdog; do
  upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
  display_var="DISPLAY_NAME_${upper}"
  token_var="TELEGRAM_BOT_TOKEN_${upper}"
  display_value="${!display_var:-${DEFAULT_DISPLAY_NAMES[$agent]}}"
  token_value="${!token_var:-{{TELEGRAM_BOT_TOKEN}}}"
  REPLACEMENTS["{{DISPLAY_NAME_${upper}}}"]="$display_value"
  REPLACEMENTS["{{TELEGRAM_BOT_TOKEN_${upper}}}"]="$token_value"
done

# Count files to process
FILE_COUNT=$(find "$REPO_DIR" -type f \( \
  -name "*.md" -o -name "*.sh" -o -name "*.txt" -o \
  -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o \
  -name "*.example" -o -name "*.py" -o -name "LICENSE" \
\) ! -path "*/setup-wizard.sh" ! -path "*/.git/*" | wc -l | tr -d ' ')

echo -e "  Processing $FILE_COUNT files..."
echo ""

REPLACED_TOTAL=0

for placeholder in "${!REPLACEMENTS[@]}"; do
  value="${REPLACEMENTS[$placeholder]}"
  # Escape special chars for sed
  escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\]/\\&/g')
  escaped_placeholder=$(printf '%s\n' "$placeholder" | sed 's/[&/\]/\\&/g')

  count=$(grep -rl "$placeholder" "$REPO_DIR" --include="*.md" --include="*.sh" --include="*.txt" --include="*.yaml" --include="*.yml" --include="*.json" --include="*.example" --include="*.py" --include="LICENSE" 2>/dev/null | grep -v setup-wizard.sh | grep -v depersonalize.sh | wc -l | tr -d ' ')

  if [ "$count" -gt 0 ]; then
    find "$REPO_DIR" -type f \( \
      -name "*.md" -o -name "*.sh" -o -name "*.txt" -o \
      -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o \
      -name "*.example" -o -name "*.py" -o -name "LICENSE" \
    \) ! -path "*/setup-wizard.sh" ! -path "*/depersonalize.sh" ! -path "*/.git/*" \
    -print0 2>/dev/null | while IFS= read -r -d '' file; do
      eval "$SED_INPLACE \"s|$escaped_placeholder|$escaped_value|g\" \"$file\"" 2>/dev/null || true
    done

    echo -e "  ${GREEN}✓${NC} $placeholder → $value ($count files)"
    REPLACED_TOTAL=$((REPLACED_TOTAL + count))
  fi
done

echo ""
echo -e "  Replaced in $REPLACED_TOTAL file locations."
echo ""

# ─── Step 4: Generate .env if not present ───
echo -e "${BOLD}Step 4/6: Environment file...${NC}"
echo ""

if [ ! -f "$REPO_DIR/.env" ]; then
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
  echo -e "  ${GREEN}✓${NC} Created .env from .env.example"
  echo -e "  ${CYAN}  Review and edit .env for any remaining values.${NC}"
else
  echo -e "  ${CYAN}ℹ${NC} .env already exists — not overwriting"
fi

# Write key values into .env
write_env_var() {
  local key="$1"
  local value="$2"
  if [ -n "$value" ] && [ "$value" != "your-anthropic-key" ] && [ "$value" != "your-openai-key" ] && [ "$value" != "your-google-key" ] && [ "$value" != "your-deepseek-key" ] && [ "$value" != "your-openrouter-key" ] && [ "$value" != "your-groq-key" ]; then
    if grep -q "^${key}=" "$REPO_DIR/.env" 2>/dev/null; then
      eval "$SED_INPLACE \"s|^${key}=.*|${key}=${value}|\" \"$REPO_DIR/.env\"" 2>/dev/null || true
    else
      echo "${key}=${value}" >> "$REPO_DIR/.env"
    fi
  fi
}

write_env_var "OWNER_NAME" "$OWNER_NAME"
write_env_var "OWNER_USERNAME" "$OWNER_USERNAME"
write_env_var "TEAM_LANG" "${TEAM_LANG:-en}"
write_env_var "OWNER_SURNAME" "${OWNER_SURNAME:-}"
write_env_var "MAIN_MODEL" "$MAIN_MODEL"
write_env_var "AGENT_MODEL" "$AGENT_MODEL"
write_env_var "EMBEDDING_PROVIDER" "$EMBEDDING_PROVIDER"
write_env_var "EMBEDDING_MODEL" "$EMBEDDING_MODEL"
write_env_var "OWNER_TELEGRAM_ID" "${OWNER_TELEGRAM_ID:-}"
write_env_var "ANTHROPIC_API_KEY" "${ANTHROPIC_API_KEY:-}"
write_env_var "OPENAI_API_KEY" "${OPENAI_API_KEY:-}"
write_env_var "GOOGLE_API_KEY" "${GOOGLE_API_KEY:-}"
write_env_var "DEEPSEEK_API_KEY" "${DEEPSEEK_API_KEY:-}"
write_env_var "OPENROUTER_API_KEY" "${OPENROUTER_API_KEY:-}"
write_env_var "GROQ_API_KEY" "${GROQ_API_KEY:-}"
write_env_var "GROQ_WHISPER_MODEL" "${GROQ_WHISPER_MODEL:-}"
write_env_var "OLLAMA_BASE_URL" "${OLLAMA_BASE_URL:-}"
write_env_var "OLLAMA_EMBEDDING_MODEL" "${OLLAMA_EMBEDDING_MODEL:-}"

for agent in heisenberg saul walter jesse skyler hank gus twins watchdog; do
  upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
  token_var="TELEGRAM_BOT_TOKEN_${upper}"
  token_value="${!token_var:-}"
  [ -n "$token_value" ] && write_env_var "TELEGRAM_BOT_TOKEN_${upper}" "$token_value"
done

echo ""

# ─── Step 5: Install agents and skills ───
echo -e "${BOLD}Step 5/6: Installing agents and skills...${NC}"
echo ""

OPENCLAW_DIR="$HOME/.openclaw/agents"
TEAM_ROOT_EXPANDED="${TEAM_DIRECTORY/#\~/$HOME}"
mkdir -p "$REPO_DIR/configs/generated" "$TEAM_ROOT_EXPANDED" "$TEAM_ROOT_EXPANDED/projects"

INSTALLED=0
for char_name in "${SELECTED_AGENT_LIST[@]}"; do
  char_name="$(printf "%s" "$char_name" | xargs)"
  [ -z "$char_name" ] && continue
  agent_name="${AGENT_MAP[$char_name]}"
  src="$REPO_DIR/agents/$char_name"
  dest="$OPENCLAW_DIR/$agent_name/agent"

  if [ -d "$src" ]; then
    mkdir -p "$dest" "$TEAM_ROOT_EXPANDED/$char_name"
    cp "$src"/*.md "$dest/"
    cp "$src"/*.md "$TEAM_ROOT_EXPANDED/$char_name/" 2>/dev/null || true
    if [ -f "$REPO_DIR/configs/$char_name.openclaw.json.example" ]; then
      cp "$REPO_DIR/configs/$char_name.openclaw.json.example" "$REPO_DIR/configs/generated/$char_name.openclaw.json"
    fi
    echo -e "  ${GREEN}✓${NC} $char_name → $agent_name"
    INSTALLED=$((INSTALLED + 1))
  else
    echo -e "  ${YELLOW}⚠${NC} $char_name not found, skipping"
  fi
done

echo ""

# Skills (shared directory + symlinks)
SCRIPT_DIR_WIZARD="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR_WIZARD/setup-skills.sh" ]; then
  bash "$SCRIPT_DIR_WIZARD/setup-skills.sh" --agents "$SELECTED_AGENTS"
else
  echo -e "  ${YELLOW}⚠${NC} setup-skills.sh not found, falling back to copy..."
  SKILLS_DEST="$OPENCLAW_DIR/producer/agent/skills"
  if [ -d "$REPO_DIR/skills" ]; then
    mkdir -p "$SKILLS_DEST"
    SKILL_ERRORS=0
    SKILL_OK=0
    for skill_dir in "$REPO_DIR/skills"/*/; do
      skill_name=$(basename "$skill_dir")
      if cp -r "$skill_dir" "$SKILLS_DEST/" 2>/dev/null; then
        SKILL_OK=$((SKILL_OK + 1))
      else
        echo -e "  ${YELLOW}⚠${NC} Failed to copy skill: $skill_name"
        SKILL_ERRORS=$((SKILL_ERRORS + 1))
      fi
    done
    echo -e "  ${GREEN}✓${NC} $SKILL_OK skills installed"
    if [ "$SKILL_ERRORS" -gt 0 ]; then
      echo -e "  ${YELLOW}⚠${NC} $SKILL_ERRORS skills failed to copy"
    fi
  else
    echo -e "  ${RED}✗${NC} Skills directory not found!"
  fi
fi

echo ""

# ─── Step 6: Verification ───
echo -e "${BOLD}Step 6/6: Verification...${NC}"
echo ""

# Check remaining placeholders
REMAINING=$(grep -rn '{{[A-Z_]*}}' "$REPO_DIR" \
  --include="*.md" --include="*.sh" --include="*.py" \
  2>/dev/null \
  | grep -v setup-wizard.sh \
  | grep -v depersonalize.sh \
  | grep -v ".env.example" \
  | grep -v "quality-check/SKILL.md" \
  | wc -l | tr -d ' ')

if [ "$REMAINING" -gt 0 ]; then
  echo -e "  ${YELLOW}⚠${NC} $REMAINING placeholder(s) still unfilled."
  echo -e "  ${CYAN}  These are optional fields. You can fill them later by editing the files directly.${NC}"
  echo -e "  ${CYAN}  Run: grep -rn '{{[A-Z_]*}}' . --include='*.md' | grep -v setup-wizard | head -20${NC}"
else
  echo -e "  ${GREEN}✓${NC} All placeholders replaced"
fi

# Check agents installed
AGENT_COUNT=$(ls "$OPENCLAW_DIR" 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${GREEN}✓${NC} $AGENT_COUNT agents installed in ~/.openclaw/agents/"
echo -e "  ${GREEN}✓${NC} Team directory prepared at $TEAM_ROOT_EXPANDED"

# Check skills
SKILL_COUNT=$(ls "$SKILLS_DEST" 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${GREEN}✓${NC} $SKILL_COUNT skills installed"

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo -e "Configuration summary:"
echo -e "  Provider:    ${BOLD}$LLM_PROVIDER${NC}"
echo -e "  Main model:  ${BOLD}$MAIN_MODEL${NC} (Heisenberg)"
echo -e "  Agent model: ${BOLD}$AGENT_MODEL${NC} (team)"
echo -e "  Embedding:   ${BOLD}$EMBEDDING_PROVIDER${NC}${EMBEDDING_MODEL:+ ($EMBEDDING_MODEL)}"
echo -e "  Voice:       ${BOLD}${VOICE_PROVIDER:-none}${NC}${GROQ_WHISPER_MODEL:+ ($GROQ_WHISPER_MODEL)}"
echo ""
echo -e "Next steps:"
echo -e "  1. Initialize OpenClaw (if first time):  ${BOLD}openclaw init${NC}"
echo -e "  2. Review generated configs:            ${BOLD}configs/generated/*.openclaw.json${NC}"
echo -e "  3. Start the system:                     ${BOLD}openclaw gateway start${NC}"
echo -e "  4. Check status:                         ${BOLD}openclaw status${NC}"
echo -e "  5. Send a message to your bot to test!"
echo ""
echo -e "Guides:"
echo -e "  First task:    ${BLUE}docs/first-task.md${NC}"
echo -e "  Architecture:  ${BLUE}docs/architecture.md${NC}"
echo -e "  FAQ:           ${BLUE}docs/faq.md${NC}"
echo ""

# Optional: configure gateway auto-start
echo -e "${YELLOW}── Gateway Auto-Start ──${NC}"
echo "  Configure OpenClaw gateway to start automatically on boot?"
if [[ "${OSTYPE:-}" == linux* ]]; then
  echo "  (Creates systemd user service)"
  read -p "  Enable auto-start? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || echo "openclaw")"
    cat > "$SYSTEMD_DIR/openclaw-gateway.service" << SYSEOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
ExecStart=$OPENCLAW_BIN gateway start --foreground
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
SYSEOF
    systemctl --user daemon-reload 2>/dev/null && \
    systemctl --user enable openclaw-gateway 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC} Systemd service installed and enabled" || \
    echo -e "  ${YELLOW}⚠${NC} Failed to enable systemd service (run manually)"
  fi
elif [[ "${OSTYPE:-}" == darwin* ]]; then
  echo "  (Creates launchd plist)"
  read -p "  Enable auto-start? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    PLIST_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"
    OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || echo "/usr/local/bin/openclaw")"
    cat > "$PLIST_DIR/com.openclaw.gateway.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.openclaw.gateway</string>
  <key>ProgramArguments</key>
  <array>
    <string>$OPENCLAW_BIN</string>
    <string>gateway</string>
    <string>start</string>
    <string>--foreground</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLISTEOF
    launchctl load "$PLIST_DIR/com.openclaw.gateway.plist" 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC} LaunchAgent installed and loaded" || \
    echo -e "  ${YELLOW}⚠${NC} Failed to load LaunchAgent (run manually)"
  fi
fi
echo -e "🧪 ${BOLD}Say my name.${NC}"
