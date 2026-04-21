#!/usr/bin/env bash
# ============================================================================
# deploy-one-click.sh — Heisenberg Team: полное развёртывание в один клик
# ============================================================================
# Использование:
#   bash deploy-one-click.sh                          # Интерактивный визард
#   bash deploy-one-click.sh --yes                    # Non-interactive (из .env)
#   bash deploy-one-click.sh --agents heisenberg,saul # Частичное развёртывание
#   bash deploy-one-click.sh --attach-existing        # OpenClaw уже установлен
#   bash deploy-one-click.sh --dry-run                # Только показать план
#   bash deploy-one-click.sh --help                   # Справка
# ============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Версия и константы ──────────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.0"
readonly MIN_NODE_VERSION="20"
readonly MIN_OPENCLAW_VERSION="2026.4.12"
readonly DEFAULT_GATEWAY_PORT="18789"

# OPENCLAW_HOME и WORKSPACE_PATH — НЕ readonly, т.к. перезаписываются из .env
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
WORKSPACE_PATH="${WORKSPACE_PATH:-$HOME/workspace}"
BACKUP_DIR="$OPENCLAW_HOME/backups"

# ── Цвета ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
  DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ── Все агенты ──────────────────────────────────────────────────────────────
ALL_AGENTS=(heisenberg saul walter jesse skyler hank gus twins watchdog)
VISIBLE_AGENTS=(heisenberg saul walter jesse)
SILENT_AGENTS=(skyler hank gus twins watchdog)
MINIMUM_AGENTS=(heisenberg saul walter)

# ── Состояние ───────────────────────────────────────────────────────────────
INTERACTIVE=true
DRY_RUN=false
ATTACH_EXISTING=false
SELECTED_AGENTS=("${ALL_AGENTS[@]}")
ERRORS=()
WARNINGS=()

# ── Базовый каталог скрипта ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# УТИЛИТЫ
# ============================================================================

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; WARNINGS+=("$*"); }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; ERRORS+=("$*"); }
log_fatal()   { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }
log_step()    { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }
log_substep() { echo -e "  ${DIM}→${NC} $*"; }

confirm() {
  if [[ "$INTERACTIVE" == false ]]; then return 0; fi
  local msg="${1:-Продолжить?}"
  read -rp "$(echo -e "${YELLOW}$msg [y/N]:${NC} ")" answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_value() {
  local varname="$1" prompt="$2" default="${3:-}"
  if [[ "$INTERACTIVE" == false ]]; then
    echo "${!varname:-$default}"
    return
  fi
  local display_default=""
  if [[ -n "$default" ]]; then display_default=" ${DIM}[$default]${NC}"; fi
  read -rp "$(echo -e "  ${prompt}${display_default}: ")" value
  echo "${value:-$default}"
}

prompt_secret() {
  local varname="$1" prompt="$2"
  if [[ "$INTERACTIVE" == false ]]; then
    echo "${!varname:-}"
    return
  fi
  read -srp "$(echo -e "  ${prompt}: ")" value
  echo
  echo "$value"
}

prompt_choice() {
  local prompt="$1"; shift
  local options=("$@")
  if [[ "$INTERACTIVE" == false ]]; then
    echo "1"
    return
  fi
  echo -e "  ${prompt}"
  for i in "${!options[@]}"; do
    echo -e "    ${BOLD}[$((i+1))]${NC} ${options[$i]}"
  done
  local choice
  read -rp "$(echo -e "  ${YELLOW}>>${NC} ")" choice
  echo "$choice"
}

version_gte() {
  # Возвращает 0 если $1 >= $2 (семантическое сравнение)
  local v1="$1" v2="$2"
  if [[ "$v1" == "$v2" ]]; then return 0; fi
  local IFS=.
  local i v1_parts=($v1) v2_parts=($v2)
  for ((i=0; i<${#v1_parts[@]}; i++)); do
    local p1="${v1_parts[$i]:-0}" p2="${v2_parts[$i]:-0}"
    # Убираем нецифровые суффиксы
    p1="${p1%%[!0-9]*}"; p2="${p2%%[!0-9]*}"
    p1="${p1:-0}"; p2="${p2:-0}"
    if ((p1 > p2)); then return 0; fi
    if ((p1 < p2)); then return 1; fi
  done
  return 0
}

generate_token() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  elif [[ -r /dev/urandom ]]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    # Fallback: date + PID + RANDOM
    echo "$(date +%s%N)$$${RANDOM}${RANDOM}" | sha256sum | cut -c1-64
  fi
}

sha256_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

# ============================================================================
# ПАРСИНГ АРГУМЕНТОВ
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)           INTERACTIVE=false ;;
      --dry-run)          DRY_RUN=true ;;
      --attach-existing)  ATTACH_EXISTING=true ;;
      --agents)
        shift
        IFS=',' read -ra SELECTED_AGENTS <<< "$1"
        ;;
      --agents=*)
        IFS=',' read -ra SELECTED_AGENTS <<< "${1#*=}"
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        log_fatal "Неизвестный аргумент: $1. Используйте --help."
        ;;
    esac
    shift
  done
}

show_help() {
  cat <<'HELP'
╔══════════════════════════════════════════════════════════╗
║         🧪 Heisenberg Team — Deploy One Click           ║
╚══════════════════════════════════════════════════════════╝

ИСПОЛЬЗОВАНИЕ:
  bash deploy-one-click.sh [ОПЦИИ]

ОПЦИИ:
  --yes, -y             Non-interactive режим (настройки из .env)
  --agents СПИСОК       Развернуть только указанных агентов
                        Пример: --agents heisenberg,saul,walter
  --attach-existing     Не устанавливать OpenClaw (уже есть)
  --dry-run             Показать план без выполнения
  --help, -h            Показать эту справку

ПРИМЕРЫ:
  bash deploy-one-click.sh                              # Визард
  bash deploy-one-click.sh --yes                        # Из .env
  bash deploy-one-click.sh --agents heisenberg,saul     # Минимум
  bash deploy-one-click.sh --attach-existing --yes      # Быстрый

ПЕРЕМЕННЫЕ .env:
  Скопируйте .env.example → .env и заполните перед --yes
HELP
}

# ============================================================================
# ФАЗА 1: ОПРЕДЕЛЕНИЕ ОС И УСТАНОВКА ЗАВИСИМОСТЕЙ
# ============================================================================

detect_os() {
  local os="" pkg_manager="" init_system=""

  case "$(uname -s)" in
    Darwin)
      os="macos"
      pkg_manager="brew"
      init_system="launchd"
      ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "$ID" in
          ubuntu|debian|pop|linuxmint)   os="debian";  pkg_manager="apt" ;;
          fedora)                        os="fedora";  pkg_manager="dnf" ;;
          rhel|centos|rocky|alma)        os="rhel";    pkg_manager="yum" ;;
          arch|manjaro|endeavouros)      os="arch";    pkg_manager="pacman" ;;
          alpine)                        os="alpine";  pkg_manager="apk" ;;
          opensuse*|sles)               os="suse";    pkg_manager="zypper" ;;
          *)                             os="linux";   pkg_manager="unknown" ;;
        esac
      else
        os="linux"; pkg_manager="unknown"
      fi
      if command -v systemctl &>/dev/null; then
        init_system="systemd"
      else
        init_system="none"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      log_fatal "Windows обнаружен. Используйте WSL2:\n  wsl --install\n  Затем запустите этот скрипт из WSL."
      ;;
    *)
      log_fatal "Неизвестная ОС: $(uname -s)"
      ;;
  esac

  export DETECTED_OS="$os"
  export PKG_MANAGER="$pkg_manager"
  export INIT_SYSTEM="$init_system"
}

install_system_package() {
  local pkg="$1"
  log_substep "Установка $pkg..."

  case "$PKG_MANAGER" in
    brew)    brew install "$pkg" ;;
    apt)     sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" ;;
    dnf)     sudo dnf install -y -q "$pkg" ;;
    yum)     sudo yum install -y -q "$pkg" ;;
    pacman)  sudo pacman -S --noconfirm --needed "$pkg" ;;
    apk)     sudo apk add --quiet "$pkg" ;;
    zypper)  sudo zypper install -y "$pkg" ;;
    *)       log_fatal "Не удалось установить $pkg: неизвестный пакетный менеджер" ;;
  esac
}

phase_1_preflight() {
  log_step "Фаза 1/10: Проверка системы"

  detect_os
  log_ok "ОС: ${DETECTED_OS} | Пакетный менеджер: ${PKG_MANAGER} | Init: ${INIT_SYSTEM}"

  # ── curl ──
  if ! command -v curl &>/dev/null; then
    log_info "curl не найден, устанавливаю..."
    install_system_package curl
  fi
  log_ok "curl: $(curl --version | head -1 | awk '{print $2}')"

  # ── git ──
  if ! command -v git &>/dev/null; then
    log_info "git не найден, устанавливаю..."
    install_system_package git
  fi
  log_ok "git: $(git --version | awk '{print $3}')"

  # ── jq ──
  if ! command -v jq &>/dev/null; then
    log_info "jq не найден, устанавливаю..."
    install_system_package jq
  fi
  log_ok "jq: $(jq --version 2>/dev/null || echo 'installed')"

  # ── Node.js ──
  if command -v node &>/dev/null; then
    local node_version
    node_version="$(node -v | sed 's/^v//')"
    local node_major="${node_version%%.*}"
    if (( node_major < MIN_NODE_VERSION )); then
      log_warn "Node.js $node_version слишком старый (нужен >= $MIN_NODE_VERSION)"
      install_node
    else
      log_ok "Node.js: v${node_version}"
    fi
  else
    log_info "Node.js не найден, устанавливаю..."
    install_node
  fi

  # ── npm global prefix fix ──
  fix_npm_prefix
}

install_node() {
  log_substep "Установка Node.js ${MIN_NODE_VERSION}.x..."

  if command -v nvm &>/dev/null; then
    nvm install "$MIN_NODE_VERSION"
    nvm use "$MIN_NODE_VERSION"
  elif [[ "$DETECTED_OS" == "macos" ]]; then
    brew install "node@${MIN_NODE_VERSION}"
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    curl -fsSL "https://deb.nodesource.com/setup_${MIN_NODE_VERSION}.x" | sudo -E bash -
    sudo apt-get install -y -qq nodejs
  elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
    curl -fsSL "https://rpm.nodesource.com/setup_${MIN_NODE_VERSION}.x" | sudo bash -
    sudo "$PKG_MANAGER" install -y nodejs
  elif [[ "$PKG_MANAGER" == "pacman" ]]; then
    sudo pacman -S --noconfirm nodejs npm
  elif [[ "$PKG_MANAGER" == "apk" ]]; then
    sudo apk add nodejs npm
  elif [[ "$PKG_MANAGER" == "zypper" ]]; then
    sudo zypper install -y nodejs20 npm20
  else
    # Fallback: nvm
    log_substep "Устанавливаю через nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install "$MIN_NODE_VERSION"
    nvm use "$MIN_NODE_VERSION"
  fi

  if ! command -v node &>/dev/null; then
    log_fatal "Не удалось установить Node.js. Установите вручную: https://nodejs.org/"
  fi
  log_ok "Node.js: $(node -v)"
}

fix_npm_prefix() {
  # На некоторых системах npm global prefix требует sudo
  local npm_prefix
  npm_prefix="$(npm prefix -g 2>/dev/null || echo "")"

  if [[ -n "$npm_prefix" && ! -w "$npm_prefix" ]]; then
    log_substep "Настраиваю npm global prefix для пользователя..."
    local user_prefix="$HOME/.npm-global"
    mkdir -p "$user_prefix"
    npm config set prefix "$user_prefix"

    # Добавляем в PATH если нет
    if [[ ":$PATH:" != *":$user_prefix/bin:"* ]]; then
      export PATH="$user_prefix/bin:$PATH"

      # Определяем shell RC файл
      local shell_rc=""
      if [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_rc="$HOME/.zshrc"
      elif [[ -n "${BASH_VERSION:-}" ]]; then
        shell_rc="$HOME/.bashrc"
      fi

      if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
        if ! grep -q '.npm-global/bin' "$shell_rc"; then
          echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$shell_rc"
          log_substep "Добавлен PATH в $shell_rc"
        fi
      fi
    fi
  fi
}

# ============================================================================
# ФАЗА 2: УСТАНОВКА OPENCLAW
# ============================================================================

phase_2_install_openclaw() {
  log_step "Фаза 2/10: OpenClaw"

  if [[ "$ATTACH_EXISTING" == true ]]; then
    if ! command -v openclaw &>/dev/null; then
      log_fatal "--attach-existing указан, но openclaw не найден в PATH"
    fi
    log_ok "Используем существующий OpenClaw: $(openclaw --version 2>/dev/null || echo 'unknown')"
    return
  fi

  local target_version="${OPENCLAW_VERSION:-$MIN_OPENCLAW_VERSION}"

  if command -v openclaw &>/dev/null; then
    local current_version
    current_version="$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"

    if version_gte "$current_version" "$target_version"; then
      log_ok "OpenClaw уже установлен: v${current_version}"
    else
      log_warn "OpenClaw v${current_version} устарел (нужен >= $target_version)"
      log_info "Обновляю OpenClaw..."
      npm install -g "openclaw@${target_version}"
    fi
  else
    log_info "Устанавливаю OpenClaw v${target_version}..."
    if [[ "$DRY_RUN" == true ]]; then
      log_substep "[DRY RUN] npm install -g openclaw@${target_version}"
    else
      npm install -g "openclaw@${target_version}"
    fi
  fi

  # Верификация
  if [[ "$DRY_RUN" == false ]]; then
    if ! command -v openclaw &>/dev/null; then
      log_fatal "openclaw не найден после установки. Проверьте PATH."
    fi
    log_ok "OpenClaw: $(openclaw --version 2>/dev/null || echo 'installed')"
  fi

  # Init если нет конфигурации
  if [[ ! -d "$OPENCLAW_HOME" ]]; then
    log_info "Инициализация OpenClaw..."
    if [[ "$DRY_RUN" == false ]]; then
      openclaw init 2>/dev/null || true
    fi
    log_ok "OpenClaw инициализирован: $OPENCLAW_HOME"
  fi
}

# ============================================================================
# ФАЗА 3: ЗАГРУЗКА / СБОР КОНФИГУРАЦИИ
# ============================================================================

phase_3_load_config() {
  log_step "Фаза 3/10: Конфигурация"

  # Загрузка .env если существует
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log_info "Загружаю .env..."
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
    set +a
    log_ok ".env загружен"
  elif [[ "$INTERACTIVE" == false ]]; then
    log_fatal "Режим --yes требует файл .env. Скопируйте:\n  cp .env.example .env"
  fi

  # ── Интерактивный визард ──
  if [[ "$INTERACTIVE" == true ]]; then
    run_wizard
  fi

  # ── Валидация обязательных переменных ──
  validate_config

  # ── Генерация GATEWAY_TOKEN если пусто ──
  if [[ -z "${GATEWAY_TOKEN:-}" ]]; then
    GATEWAY_TOKEN="$(generate_token)"
    log_ok "Gateway token сгенерирован (64 символа)"
  fi

  # ── Сохранение .env если визард ──
  if [[ "$INTERACTIVE" == true ]]; then
    save_env_file
  fi
}

run_wizard() {
  echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       🧪 Heisenberg Team — Setup Wizard           ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}\n"

  # Шаг 1: Имя
  OWNER_NAME="$(prompt_value OWNER_NAME "Шаг 1/7 — Ваше имя" "${OWNER_NAME:-}")"

  # Шаг 2: Провайдер
  echo ""
  local provider_choice
  provider_choice="$(prompt_choice "Шаг 2/7 — LLM-провайдер:" \
    "Anthropic (Claude) — рекомендуется" \
    "OpenAI (GPT)" \
    "OpenRouter (мульти-провайдер)" \
    "Google (Gemini)" \
    "DeepSeek" \
    "Ollama (локальный, бесплатно)")"

  case "$provider_choice" in
    1) DEFAULT_PROVIDER="anthropic" ;;
    2) DEFAULT_PROVIDER="openai" ;;
    3) DEFAULT_PROVIDER="openrouter" ;;
    4) DEFAULT_PROVIDER="google" ;;
    5) DEFAULT_PROVIDER="deepseek" ;;
    6) DEFAULT_PROVIDER="ollama" ;;
    *) DEFAULT_PROVIDER="anthropic" ;;
  esac

  # Шаг 3: API ключ
  echo ""
  if [[ "$DEFAULT_PROVIDER" != "ollama" ]]; then
    local key_var_name
    case "$DEFAULT_PROVIDER" in
      anthropic)  key_var_name="ANTHROPIC_API_KEY" ;;
      openai)     key_var_name="OPENAI_API_KEY" ;;
      openrouter) key_var_name="OPENROUTER_API_KEY" ;;
      google)     key_var_name="GOOGLE_API_KEY" ;;
      deepseek)   key_var_name="DEEPSEEK_API_KEY" ;;
    esac
    local api_key
    api_key="$(prompt_secret "$key_var_name" "Шаг 3/7 — API-ключ ($DEFAULT_PROVIDER)")"
    export "$key_var_name=$api_key"
  else
    OLLAMA_BASE_URL="$(prompt_value OLLAMA_BASE_URL "Шаг 3/7 — Ollama URL" "http://localhost:11434")"
  fi

  # Шаг 4: Модель
  echo ""
  local default_model
  case "$DEFAULT_PROVIDER" in
    anthropic)  default_model="claude-sonnet-4-20250514" ;;
    openai)     default_model="gpt-4o" ;;
    openrouter) default_model="anthropic/claude-sonnet-4-20250514" ;;
    google)     default_model="gemini-2.5-pro" ;;
    deepseek)   default_model="deepseek-chat" ;;
    ollama)     default_model="qwen2.5:32b" ;;
  esac
  DEFAULT_MODEL="$(prompt_value DEFAULT_MODEL "Шаг 3.5/7 — Модель" "$default_model")"
  BOSS_MODEL="${BOSS_MODEL:-$DEFAULT_MODEL}"
  SPECIALIST_MODEL="${SPECIALIST_MODEL:-$DEFAULT_MODEL}"

  # Шаг 5: Агенты
  echo ""
  local agents_choice
  agents_choice="$(prompt_choice "Шаг 4/7 — Какие агенты развернуть:" \
    "Все 9 (рекомендуется)" \
    "Минимум 3 (Heisenberg + Saul + Walter)" \
    "Выбрать вручную")"

  case "$agents_choice" in
    1) SELECTED_AGENTS=("${ALL_AGENTS[@]}") ;;
    2) SELECTED_AGENTS=("${MINIMUM_AGENTS[@]}") ;;
    3)
      echo -e "  Введите имена через запятую:"
      echo -e "  Доступные: ${ALL_AGENTS[*]}"
      local custom_agents
      read -rp "  >> " custom_agents
      IFS=',' read -ra SELECTED_AGENTS <<< "$custom_agents"
      ;;
    *) SELECTED_AGENTS=("${ALL_AGENTS[@]}") ;;
  esac

  # Шаг 6: Telegram
  echo ""
  OWNER_TELEGRAM_ID="$(prompt_value OWNER_TELEGRAM_ID "Шаг 5/7 — Telegram ID (опционально, Enter чтобы пропустить)" "")"
  if [[ -n "$OWNER_TELEGRAM_ID" ]]; then
    TELEGRAM_BOT_TOKEN_HEISENBERG="$(prompt_secret TELEGRAM_BOT_TOKEN_HEISENBERG "  Bot token для Heisenberg (Enter чтобы пропустить)")"
  fi

  # Шаг 7: Язык
  echo ""
  local lang_choice
  lang_choice="$(prompt_choice "Шаг 6/7 — Язык агентов:" "Русский" "English")"
  case "$lang_choice" in
    1) TEAM_LANG="ru" ;;
    2) TEAM_LANG="en" ;;
    *) TEAM_LANG="ru" ;;
  esac

  # Шаг 8: Лимит затрат
  echo ""
  MAX_COST_PER_DAY="$(prompt_value MAX_COST_PER_DAY "Шаг 7/7 — Лимит затрат в день, USD" "${MAX_COST_PER_DAY:-10.00}")"

  echo -e "\n${GREEN}✓ Конфигурация собрана${NC}"
}

validate_config() {
  log_substep "Валидация конфигурации..."

  # Провайдер
  DEFAULT_PROVIDER="${DEFAULT_PROVIDER:-anthropic}"

  # API ключ
  if [[ "$DEFAULT_PROVIDER" != "ollama" ]]; then
    local key_value=""
    case "$DEFAULT_PROVIDER" in
      anthropic)  key_value="${ANTHROPIC_API_KEY:-}" ;;
      openai)     key_value="${OPENAI_API_KEY:-}" ;;
      openrouter) key_value="${OPENROUTER_API_KEY:-}" ;;
      google)     key_value="${GOOGLE_API_KEY:-}" ;;
      deepseek)   key_value="${DEEPSEEK_API_KEY:-}" ;;
    esac

    if [[ -z "$key_value" ]]; then
      log_fatal "API ключ для $DEFAULT_PROVIDER не задан. Заполните .env."
    fi

    # Валидация формата ключа
    case "$DEFAULT_PROVIDER" in
      anthropic)
        if [[ ! "$key_value" =~ ^sk-ant- ]]; then
          log_warn "Anthropic API key обычно начинается с 'sk-ant-'. Проверьте ключ."
        fi
        ;;
      openai)
        if [[ ! "$key_value" =~ ^sk- ]]; then
          log_warn "OpenAI API key обычно начинается с 'sk-'. Проверьте ключ."
        fi
        ;;
      openrouter)
        if [[ ! "$key_value" =~ ^sk-or- ]]; then
          log_warn "OpenRouter API key обычно начинается с 'sk-or-'. Проверьте ключ."
        fi
        ;;
    esac
  fi

  # Модель
  DEFAULT_MODEL="${DEFAULT_MODEL:-claude-sonnet-4-20250514}"
  BOSS_MODEL="${BOSS_MODEL:-$DEFAULT_MODEL}"
  SPECIALIST_MODEL="${SPECIALIST_MODEL:-$DEFAULT_MODEL}"

  # Агенты — валидация имён
  for agent in "${SELECTED_AGENTS[@]}"; do
    local valid=false
    for known in "${ALL_AGENTS[@]}"; do
      if [[ "$agent" == "$known" ]]; then valid=true; break; fi
    done
    if [[ "$valid" == false ]]; then
      log_fatal "Неизвестный агент: $agent. Доступные: ${ALL_AGENTS[*]}"
    fi
  done

  # Heisenberg обязателен
  local has_heisenberg=false
  for agent in "${SELECTED_AGENTS[@]}"; do
    if [[ "$agent" == "heisenberg" ]]; then has_heisenberg=true; break; fi
  done
  if [[ "$has_heisenberg" == false ]]; then
    log_warn "Heisenberg не в списке агентов. Добавляю автоматически."
    SELECTED_AGENTS=("heisenberg" "${SELECTED_AGENTS[@]}")
  fi

  # Defaults
  OWNER_NAME="${OWNER_NAME:-User}"
  TEAM_LANG="${TEAM_LANG:-ru}"
  MAX_COST_PER_DAY="${MAX_COST_PER_DAY:-10.00}"
  GATEWAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
  GATEWAY_PORT="${GATEWAY_PORT:-$DEFAULT_GATEWAY_PORT}"

  # Пересчитываем BACKUP_DIR т.к. OPENCLAW_HOME мог измениться из .env
  BACKUP_DIR="$OPENCLAW_HOME/backups"

  log_ok "Конфигурация валидна"
  log_substep "Провайдер: $DEFAULT_PROVIDER | Модель: $DEFAULT_MODEL"
  log_substep "Агенты: ${SELECTED_AGENTS[*]}"
}

save_env_file() {
  local env_file="$SCRIPT_DIR/.env"

  cat > "$env_file" <<ENVFILE
# ============================================================================
# Heisenberg Team — Конфигурация
# Сгенерировано: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ============================================================================

# === LLM Провайдер ===
DEFAULT_PROVIDER=${DEFAULT_PROVIDER}
DEFAULT_MODEL=${DEFAULT_MODEL}
BOSS_MODEL=${BOSS_MODEL}
SPECIALIST_MODEL=${SPECIALIST_MODEL}

# === API Ключи ===
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}

# === Ollama ===
OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-http://localhost:11434}
OLLAMA_EMBEDDING_MODEL=${OLLAMA_EMBEDDING_MODEL:-nomic-embed-text}

# === Telegram ===
OWNER_TELEGRAM_ID=${OWNER_TELEGRAM_ID:-}
TELEGRAM_BOT_TOKEN_HEISENBERG=${TELEGRAM_BOT_TOKEN_HEISENBERG:-}
TELEGRAM_BOT_TOKEN_SAUL=${TELEGRAM_BOT_TOKEN_SAUL:-}
TELEGRAM_BOT_TOKEN_WALTER=${TELEGRAM_BOT_TOKEN_WALTER:-}
TELEGRAM_BOT_TOKEN_JESSE=${TELEGRAM_BOT_TOKEN_JESSE:-}
TELEGRAM_BOT_TOKEN_SKYLER=${TELEGRAM_BOT_TOKEN_SKYLER:-}
TELEGRAM_BOT_TOKEN_HANK=${TELEGRAM_BOT_TOKEN_HANK:-}
TELEGRAM_BOT_TOKEN_GUS=${TELEGRAM_BOT_TOKEN_GUS:-}
TELEGRAM_BOT_TOKEN_TWINS=${TELEGRAM_BOT_TOKEN_TWINS:-}
TELEGRAM_BOT_TOKEN_WATCHDOG=${TELEGRAM_BOT_TOKEN_WATCHDOG:-}

# === Персонализация ===
OWNER_NAME=${OWNER_NAME}
TEAM_LANG=${TEAM_LANG}

# === Безопасность ===
GATEWAY_TOKEN=${GATEWAY_TOKEN}
GATEWAY_HOST=${GATEWAY_HOST}
GATEWAY_PORT=${GATEWAY_PORT}
OPENCLAW_VERSION=${OPENCLAW_VERSION:-$MIN_OPENCLAW_VERSION}

# === Watchdog / Self-Heal ===
HEALTH_URL=http://${GATEWAY_HOST}:${GATEWAY_PORT}/health
HANK_BOT_TOKEN=${HANK_BOT_TOKEN:-}
HANK_CHAT_ID=${HANK_CHAT_ID:-${OWNER_TELEGRAM_ID:-}}
HEALTH_CHECK_INTERVAL=120
SELF_HEAL_INTERVAL=1800

# === Пути ===
OPENCLAW_HOME=${OPENCLAW_HOME}
WORKSPACE_PATH=${WORKSPACE_PATH:-$HOME/workspace}

# === Опции ===
AGENTS=$(IFS=,; echo "${SELECTED_AGENTS[*]}")
MAX_COST_PER_DAY=${MAX_COST_PER_DAY}
ENVFILE

  chmod 600 "$env_file"
  log_ok ".env сохранён (chmod 600)"
}

# ============================================================================
# ФАЗА 4: BACKUP
# ============================================================================

phase_4_backup() {
  log_step "Фаза 4/10: Backup"

  if [[ ! -d "$OPENCLAW_HOME/agents" ]]; then
    log_info "Первое развёртывание, backup не требуется"
    return
  fi

  local backup_path="$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_path"

  if [[ "$DRY_RUN" == true ]]; then
    log_substep "[DRY RUN] Backup → $backup_path"
    return
  fi

  # Backup агентов
  if [[ -d "$OPENCLAW_HOME/agents" ]]; then
    cp -r "$OPENCLAW_HOME/agents" "$backup_path/agents"
  fi

  # Backup конфига
  for f in "$OPENCLAW_HOME"/*.json; do
    [[ -f "$f" ]] && cp "$f" "$backup_path/" || true
  done

  log_ok "Backup создан: $backup_path"
}

# ============================================================================
# ФАЗА 5: ГЕНЕРАЦИЯ КОНФИГОВ АГЕНТОВ
# ============================================================================

phase_5_generate_configs() {
  log_step "Фаза 5/10: Генерация конфигов"

  local generated_dir="$SCRIPT_DIR/configs/generated"
  mkdir -p "$generated_dir"

  for agent in "${SELECTED_AGENTS[@]}"; do
    local config_file="$generated_dir/${agent}.openclaw.json"
    local model="$SPECIALIST_MODEL"
    local max_concurrent=2

    if [[ "$agent" == "heisenberg" ]]; then
      model="$BOSS_MODEL"
      max_concurrent=3
    fi

    # Собираем apiKeys
    local api_keys_json="{}"
    [[ -n "${ANTHROPIC_API_KEY:-}" ]]  && api_keys_json="$(echo "$api_keys_json" | jq --arg k "$ANTHROPIC_API_KEY" '. + {anthropic: $k}')"
    [[ -n "${OPENAI_API_KEY:-}" ]]     && api_keys_json="$(echo "$api_keys_json" | jq --arg k "$OPENAI_API_KEY" '. + {openai: $k}')"
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && api_keys_json="$(echo "$api_keys_json" | jq --arg k "$OPENROUTER_API_KEY" '. + {openrouter: $k}')"
    [[ -n "${GOOGLE_API_KEY:-}" ]]     && api_keys_json="$(echo "$api_keys_json" | jq --arg k "$GOOGLE_API_KEY" '. + {google: $k}')"
    [[ -n "${DEEPSEEK_API_KEY:-}" ]]   && api_keys_json="$(echo "$api_keys_json" | jq --arg k "$DEEPSEEK_API_KEY" '. + {deepseek: $k}')"

    # Telegram token для конкретного агента
    local bot_token_var="TELEGRAM_BOT_TOKEN_$(echo "$agent" | tr '[:lower:]' '[:upper:]')"
    local bot_token="${!bot_token_var:-}"

    # Telegram конфиг
    local telegram_json="null"
    if [[ -n "$bot_token" ]]; then
      telegram_json="$(jq -n --arg token "$bot_token" '{enabled: true, botToken: $token}')"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      log_substep "[DRY RUN] Генерация: $config_file"
      continue
    fi

    # Генерация JSON
    jq -n \
      --arg name "$agent" \
      --arg provider "$DEFAULT_PROVIDER" \
      --arg model "$model" \
      --arg gw_host "$GATEWAY_HOST" \
      --arg gw_port "$GATEWAY_PORT" \
      --arg gw_token "$GATEWAY_TOKEN" \
      --argjson api_keys "$api_keys_json" \
      --argjson max_concurrent "$max_concurrent" \
      --argjson max_cost "${MAX_COST_PER_DAY}" \
      --argjson telegram "$telegram_json" \
      '{
        name: $name,
        ai: {
          defaultProvider: $provider,
          defaultModel: $model,
          apiKeys: $api_keys
        },
        gateway: {
          host: $gw_host,
          port: ($gw_port | tonumber),
          token: $gw_token
        },
        messages: {
          queue: {
            mode: "collect",
            debounceMs: 2000,
            cap: 20
          }
        },
        agents: {
          defaults: {
            maxConcurrent: $max_concurrent
          }
        },
        safety: {
          maxCostPerDay: $max_cost,
          maxActionsPerHour: 100,
          currency: "USD"
        }
      }
      | if $telegram != null then . + {telegram: $telegram} else . end
      ' > "$config_file"

    chmod 600 "$config_file"
    log_ok "Конфиг: $agent (модель: $model)"
  done

  log_ok "Сгенерировано конфигов: ${#SELECTED_AGENTS[@]}"
}

# ============================================================================
# ФАЗА 6: РАЗВЁРТЫВАНИЕ WORKSPACES
# ============================================================================

phase_6_deploy_workspaces() {
  log_step "Фаза 6/10: Развёртывание рабочих пространств"

  local agents_src="$SCRIPT_DIR/agents"
  if [[ ! -d "$agents_src" ]]; then
    log_fatal "Каталог agents/ не найден. Запустите скрипт из корня heisenberg-team."
  fi

  for agent in "${SELECTED_AGENTS[@]}"; do
    local src="$agents_src/$agent"
    local dest="$OPENCLAW_HOME/agents/$agent"

    if [[ ! -d "$src" ]]; then
      log_warn "Каталог $src не найден, пропускаю агента $agent"
      continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
      log_substep "[DRY RUN] Копирование: $src → $dest"
      continue
    fi

    mkdir -p "$dest"

    # Копируем все .md файлы
    for md_file in "$src"/*.md; do
      [[ -f "$md_file" ]] || continue
      local filename
      filename="$(basename "$md_file")"
      local dest_file="$dest/$filename"

      # Копируем и подставляем плейсхолдеры
      sed \
        -e "s|{{OWNER_NAME}}|${OWNER_NAME}|g" \
        -e "s|{{OWNER_TELEGRAM_ID}}|${OWNER_TELEGRAM_ID:-}|g" \
        -e "s|{{DEFAULT_PROVIDER}}|${DEFAULT_PROVIDER}|g" \
        -e "s|{{DEFAULT_MODEL}}|${DEFAULT_MODEL}|g" \
        -e "s|{{BOSS_MODEL}}|${BOSS_MODEL}|g" \
        -e "s|{{SPECIALIST_MODEL}}|${SPECIALIST_MODEL}|g" \
        -e "s|{{AGENT_MODEL_SHORT}}|$(echo "$SPECIALIST_MODEL" | sed 's/.*\///' | cut -d'-' -f1-2)|g" \
        -e "s|{{TEAM_LANG}}|${TEAM_LANG}|g" \
        -e "s|{{GATEWAY_HOST}}|${GATEWAY_HOST}|g" \
        -e "s|{{GATEWAY_PORT}}|${GATEWAY_PORT}|g" \
        "$md_file" > "$dest_file"
    done

    # Копируем конфиг OpenClaw
    local config_src="$SCRIPT_DIR/configs/generated/${agent}.openclaw.json"
    if [[ -f "$config_src" ]]; then
      cp "$config_src" "$dest/openclaw.json"
      chmod 600 "$dest/openclaw.json"
    fi

    log_ok "Workspace: $agent → $dest"
  done
}

# ============================================================================
# ФАЗА 7: SHARED SKILLS (СИМЛИНКИ)
# ============================================================================

phase_7_deploy_skills() {
  log_step "Фаза 7/10: Skills (shared)"

  local skills_src="$SCRIPT_DIR/skills"
  if [[ ! -d "$skills_src" ]]; then
    log_warn "Каталог skills/ не найден, пропускаю"
    return
  fi

  local shared_dir="$OPENCLAW_HOME/shared-skills"

  if [[ "$DRY_RUN" == true ]]; then
    log_substep "[DRY RUN] skills/ → $shared_dir + симлинки"
    return
  fi

  # Копируем skills в shared
  mkdir -p "$shared_dir"
  rsync -a --delete "$skills_src/" "$shared_dir/" 2>/dev/null || cp -r "$skills_src/"* "$shared_dir/"
  log_ok "Skills скопированы: $shared_dir"

  # Создаём симлинки для каждого агента
  for agent in "${SELECTED_AGENTS[@]}"; do
    local agent_skills="$OPENCLAW_HOME/agents/$agent/skills"

    # Удаляем старые skills если не симлинк
    if [[ -d "$agent_skills" && ! -L "$agent_skills" ]]; then
      rm -rf "$agent_skills"
    fi

    ln -sfn "$shared_dir" "$agent_skills"
    log_substep "Симлинк: $agent/skills → shared-skills"
  done

  # Генерация CHECKSUMS
  local checksums_file="$shared_dir/CHECKSUMS.sha256"
  find "$shared_dir" -name "SKILL.md" -type f | sort | while read -r skill_file; do
    echo "$(sha256_file "$skill_file")  ${skill_file#"$shared_dir/"}"
  done > "$checksums_file"
  log_ok "CHECKSUMS.sha256 сгенерирован ($(wc -l < "$checksums_file") skills)"
}

# ============================================================================
# ФАЗА 8: SECURITY HARDENING
# ============================================================================

phase_8_security_hardening() {
  log_step "Фаза 8/10: Security Hardening"

  if [[ "$DRY_RUN" == true ]]; then
    log_substep "[DRY RUN] chmod, integrity checks"
    return
  fi

  local hardening_count=0

  # ── Права на файлы ──
  log_substep "Начинаю обработку прав на файлы для агентов: ${SELECTED_AGENTS[*]}"
  for agent in "${SELECTED_AGENTS[@]}"; do
    log_substep "Обрабатываю агента: $agent"
    local agent_dir="$OPENCLAW_HOME/agents/$agent"
    [[ -d "$agent_dir" ]] || { log_warn "Директория агента не найдена: $agent_dir"; continue; }

    # SOUL.md и IDENTITY.md — только чтение (защита от перезаписи агентом)
    for protected_file in SOUL.md IDENTITY.md; do
      local file_path="$agent_dir/$protected_file"
      if [[ -f "$file_path" ]]; then
        log_substep "Устанавливаю chmod 444 для $file_path"
        chmod 444 "$file_path"
        ((hardening_count++))
      else
        log_substep "Файл не найден: $file_path"
      fi
    done

    # Конфиги с ключами — только владелец
    for secret_file in openclaw.json auth.json; do
      local file_path="$agent_dir/$secret_file"
      if [[ -f "$file_path" ]]; then
        log_substep "Устанавливаю chmod 600 для $file_path"
        chmod 600 "$file_path"
        ((hardening_count++))
      else
        log_substep "Файл не найден: $file_path"
      fi
    done
  done
  log_ok "Права на файлы: $hardening_count файлов защищено"

  # ── .env ──
  log_substep "Проверяю наличие .env"
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log_substep "Устанавливаю chmod 600 для .env"
    chmod 600 "$SCRIPT_DIR/.env"
    log_ok ".env: chmod 600"
  else
    log_warn ".env не найден"
  fi

  # ── Pre-commit hook ──
  log_substep "Проверяю наличие .git директории"
  local hooks_dir="$SCRIPT_DIR/.git/hooks"
  if [[ -d "$SCRIPT_DIR/.git" ]]; then
    log_substep "Создаю директорию хуков: $hooks_dir"
    mkdir -p "$hooks_dir"
    log_substep "Устанавливаю pre-commit hook"
    install_precommit_hook "$hooks_dir"
    log_ok "Pre-commit hook установлен"
  else
    log_warn "Git репозиторий не найден, пропускаю pre-commit hook"
  fi

  # ── Integrity baseline ──
  log_substep "Создаю файл целостности"
  local integrity_file="$OPENCLAW_HOME/.integrity-baseline.sha256"
  {
    log_substep "Собираю хеши для файлов целостности"
    for agent in "${SELECTED_AGENTS[@]}"; do
      local agent_dir="$OPENCLAW_HOME/agents/$agent"
      [[ -d "$agent_dir" ]] || continue
      for check_file in SOUL.md IDENTITY.md; do
        local file_path="$agent_dir/$check_file"
        if [[ -f "$file_path" ]]; then
          log_substep "Вычисляю хеш для $file_path"
          echo "$(sha256_file "$agent_dir/$check_file")  agents/$agent/$check_file"
        else
          log_substep "Файл для хеширования не найден: $file_path"
        fi
      done
    done
  } > "$integrity_file"
  log_substep "Устанавливаю права на файл целостности"
  chmod 444 "$integrity_file"
  log_ok "Integrity baseline: $(wc -l < "$integrity_file") файлов"

  # ── openclaw security audit (если доступна, с таймаутом) ──
  log_substep "Проверяю наличие openclaw команды"
  if command -v openclaw &>/dev/null; then
    log_substep "Запускаю openclaw security audit..."
    if command -v timeout &>/dev/null; then
      log_substep "Запускаю с таймаутом 10 секунд и перенаправлением stdin/stdout/stderr"
      timeout 10 openclaw security audit </dev/null &>/dev/null || log_warn "openclaw security audit недоступен или таймаут"
    else
      log_warn "timeout не найден, пропускаю security audit"
    fi
  else
    log_warn "openclaw не найден в PATH, пропускаю security audit"
  fi
  log_substep "Фаза 8 завершена"
}

install_precommit_hook() {
  local hooks_dir="$1"
  cat > "$hooks_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Heisenberg Team: защита от утечки секретов

# Проверка на коммит .env и auth.json
BLOCKED_FILES=$(git diff --cached --name-only | grep -E '\.env$|auth\.json$|\.openclaw\.json$' || true)
if [[ -n "$BLOCKED_FILES" ]]; then
  echo "❌ BLOCKED: Попытка закоммитить секреты:"
  echo "$BLOCKED_FILES"
  echo ""
  echo "Если это намеренно, используйте: git commit --no-verify"
  exit 1
fi

# Проверка на API ключи в коде
LEAKED=$(git diff --cached -U0 | grep -E '(sk-ant-|sk-or-|sk-[a-zA-Z0-9]{20,}|gsk_[a-zA-Z0-9]+)' || true)
if [[ -n "$LEAKED" ]]; then
  echo "❌ BLOCKED: Обнаружен API ключ в изменениях!"
  echo "Удалите ключ и используйте .env вместо этого."
  exit 1
fi

exit 0
HOOK
  chmod +x "$hooks_dir/pre-commit"
}

# ============================================================================
# ФАЗА 9: ЗАПУСК GATEWAY
# ============================================================================

phase_9_start_gateway() {
  log_step "Фаза 9/10: Запуск Gateway"

  if [[ "$DRY_RUN" == true ]]; then
    log_substep "[DRY RUN] openclaw gateway start"
    return
  fi

  # Проверяем, не запущен ли уже
  if openclaw gateway status &>/dev/null 2>&1; then
    log_ok "Gateway уже работает"
    return
  fi

  # ── Создание service файла ──
  case "$INIT_SYSTEM" in
    systemd)
      install_systemd_service
      ;;
    launchd)
      install_launchd_plist
      ;;
    *)
      log_info "Init-система не обнаружена, запускаю gateway напрямую..."
      ;;
  esac

  # Запуск
  log_info "Запускаю OpenClaw Gateway..."
  openclaw gateway start &>/dev/null &
  local gw_pid=$!

  # Ожидание готовности (до 30 секунд)
  local max_wait=30
  local waited=0
  while (( waited < max_wait )); do
    if openclaw gateway status &>/dev/null 2>&1; then
      log_ok "Gateway запущен (PID: $gw_pid)"
      return
    fi
    sleep 1
    ((waited++))
  done

  log_warn "Gateway не ответил за ${max_wait}с. Проверьте: openclaw gateway status"
}

install_systemd_service() {
  local service_file="/etc/systemd/system/openclaw-gateway.service"

  if [[ -f "$service_file" ]]; then
    log_substep "Systemd unit уже существует"
    return
  fi

  local node_path
  node_path="$(which node)"
  local openclaw_path
  openclaw_path="$(which openclaw)"
  local user
  user="$(whoami)"

  sudo tee "$service_file" > /dev/null <<SERVICE
[Unit]
Description=OpenClaw Gateway — Heisenberg Team
After=network.target

[Service]
Type=simple
User=$user
WorkingDirectory=$OPENCLAW_HOME
ExecStart=$openclaw_path gateway start
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production
Environment=PATH=$PATH

[Install]
WantedBy=multi-user.target
SERVICE

  sudo systemctl daemon-reload
  sudo systemctl enable openclaw-gateway.service
  log_ok "Systemd service создан и включён"
}

install_launchd_plist() {
  local plist_file="$HOME/Library/LaunchAgents/com.openclaw.gateway.plist"

  if [[ -f "$plist_file" ]]; then
    log_substep "LaunchAgent уже существует"
    return
  fi

  local openclaw_path
  openclaw_path="$(which openclaw)"

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.openclaw.gateway</string>
  <key>ProgramArguments</key>
  <array>
    <string>$openclaw_path</string>
    <string>gateway</string>
    <string>start</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$OPENCLAW_HOME</string>
  <key>StandardOutPath</key>
  <string>$OPENCLAW_HOME/logs/gateway.log</string>
  <key>StandardErrorPath</key>
  <string>$OPENCLAW_HOME/logs/gateway-error.log</string>
</dict>
</plist>
PLIST

  mkdir -p "$OPENCLAW_HOME/logs"
  log_ok "LaunchAgent создан: $plist_file"
}

# ============================================================================
# ФАЗА 10: SMOKE TEST + ОТЧЁТ (мерж smoke-test.sh)
# ============================================================================

phase_10_smoke_test() {
  log_step "Фаза 10/10: Smoke Test"

  if [[ "$DRY_RUN" == true ]]; then
    log_substep "[DRY RUN] Все проверки пропущены"
    print_report
    return
  fi

  local tests_passed=0
  local tests_failed=0
  local tests_warn=0

  # ── Test 1: openclaw в PATH ──
  if command -v openclaw &>/dev/null; then
    log_ok "✓ openclaw в PATH"
    ((tests_passed++))
  else
    log_error "✗ openclaw не найден в PATH"
    ((tests_failed++))
  fi

  # ── Test 2: openclaw doctor ──
  if openclaw doctor &>/dev/null 2>&1; then
    log_ok "✓ openclaw doctor — OK"
    ((tests_passed++))
  else
    log_warn "⚠ openclaw doctor — есть замечания"
    ((tests_warn++))
  fi

  # ── Test 3: Файлы агентов существуют ──
  local required_files="AGENTS.md SOUL.md IDENTITY.md TOOLS.md MEMORY.md BOOTSTRAP.md HEARTBEAT.md"
  local agent_files_ok=true
  for agent in "${SELECTED_AGENTS[@]}"; do
    local agent_dir="$SCRIPT_DIR/agents/$agent"
    if [[ ! -d "$agent_dir" ]]; then
      log_error "✗ Каталог агента отсутствует: $agent"
      agent_files_ok=false
      ((tests_failed++))
      continue
    fi
    for f in $required_files; do
      if [[ ! -f "$agent_dir/$f" ]]; then
        log_error "✗ $agent: отсутствует $f"
        agent_files_ok=false
        ((tests_failed++))
      fi
    done
  done
  if [[ "$agent_files_ok" == true ]]; then
    log_ok "✓ Файлы всех агентов на месте"
    ((tests_passed++))
  fi

  # ── Test 4: Конфиги существуют ──
  local configs_ok=true
  for agent in "${SELECTED_AGENTS[@]}"; do
    local config="$OPENCLAW_HOME/agents/$agent/openclaw.json"
    if [[ ! -f "$config" ]]; then
      log_error "✗ Конфиг отсутствует: $agent"
      configs_ok=false
      ((tests_failed++))
    fi
  done
  if [[ "$configs_ok" == true ]]; then
    log_ok "✓ Конфиги всех агентов на месте (${#SELECTED_AGENTS[@]})"
    ((tests_passed++))
  fi

  # ── Test 5: Плейсхолдеры в конфигах ──
  if ls "$SCRIPT_DIR/configs/generated/"*.json &>/dev/null 2>&1; then
    local gen_placeholders
    gen_placeholders="$(grep -rn '{{' "$SCRIPT_DIR/configs/generated/" --include="*.json" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${gen_placeholders:-0}" -gt 0 ]]; then
      log_warn "⚠ $gen_placeholders плейсхолдеров в сгенерированных конфигах"
      ((tests_warn++))
    else
      log_ok "✓ Сгенерированные конфиги чисты"
      ((tests_passed++))
    fi

    # Проверка пустых API ключей в конфигах
    for cfg in "$SCRIPT_DIR/configs/generated/"*.json; do
      [[ -f "$cfg" ]] || continue
      local empty_keys
      empty_keys="$(grep -c '"[a-z]*": ""' "$cfg" 2>/dev/null || echo 0)"
      if [[ "${empty_keys:-0}" -gt 0 ]]; then
        log_warn "⚠ $(basename "$cfg"): $empty_keys пустых API ключей"
        ((tests_warn++))
      fi
    done
  fi

  # ── Test 6: Skills симлинки ──
  local skills_ok=true
  for agent in "${SELECTED_AGENTS[@]}"; do
    local skills_link="$OPENCLAW_HOME/agents/$agent/skills"
    if [[ -L "$skills_link" ]]; then
      local target
      target="$(readlink "$skills_link")"
      if [[ ! -d "$target" ]]; then
        log_error "✗ Битый симлинк: $agent/skills → $target"
        skills_ok=false
        ((tests_failed++))
      fi
    elif [[ -d "$skills_link" ]]; then
      log_warn "⚠ $agent/skills — не симлинк (устаревший подход)"
      ((tests_warn++))
    fi
  done

  # Проверка shared skills
  local shared_skills_dir="$OPENCLAW_HOME/shared-skills"
  if [[ -d "$shared_skills_dir" ]]; then
    local skill_count
    skill_count="$(ls "$shared_skills_dir/" 2>/dev/null | wc -l | tr -d ' ')"
    log_ok "✓ Shared skills: $skill_count ($shared_skills_dir)"
    ((tests_passed++))
  elif [[ "$skills_ok" == true ]]; then
    log_ok "✓ Skills симлинки — OK"
    ((tests_passed++))
  fi

  # ── Test 7: Security — gateway привязан к localhost ──
  local gw_all_ok=true
  for agent in "${SELECTED_AGENTS[@]}"; do
    local config="$OPENCLAW_HOME/agents/$agent/openclaw.json"
    if [[ -f "$config" ]]; then
      local gw_host
      gw_host="$(jq -r '.gateway.host // "0.0.0.0"' "$config" 2>/dev/null)"
      if [[ "$gw_host" == "0.0.0.0" ]]; then
        log_error "✗ ОПАСНО: $agent gateway привязан к 0.0.0.0!"
        gw_all_ok=false
        ((tests_failed++))
      fi
    fi
  done
  if [[ "$gw_all_ok" == true ]]; then
    log_ok "✓ Gateway привязан к $GATEWAY_HOST"
    ((tests_passed++))
  fi

  # ── Test 8: Нет API ключей в .md файлах ──
  local leaked_keys
  leaked_keys="$(grep -rlE '(sk-ant-|sk-or-|sk-[a-zA-Z0-9]{32,}|gsk_)' "$OPENCLAW_HOME/agents/" --include="*.md" 2>/dev/null || true)"
  if [[ -n "$leaked_keys" ]]; then
    log_error "✗ API ключи обнаружены в .md файлах!"
    echo "$leaked_keys" | head -5
    ((tests_failed++))
  else
    log_ok "✓ Нет утечек API ключей в workspace файлах"
    ((tests_passed++))
  fi

  # ── Test 9: Плейсхолдеры в .md файлах агентов ──
  local placeholder_count=0
  for agent in "${SELECTED_AGENTS[@]}"; do
    local agent_dir="$SCRIPT_DIR/agents/$agent"
    if [[ -d "$agent_dir" ]]; then
      local count
      count="$(grep -r '{{[A-Z_]*}}' "$agent_dir" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')"
      placeholder_count=$((placeholder_count + count))
    fi
  done
  if [[ "$placeholder_count" -gt 0 ]]; then
    log_warn "⚠ $placeholder_count незаполненных плейсхолдеров в агентах"
    ((tests_warn++))
  else
    log_ok "✓ Все плейсхолдеры заполнены"
    ((tests_passed++))
  fi

  # ── Test 10: Integrity baseline ──
  if [[ -f "$OPENCLAW_HOME/.integrity-baseline.sha256" ]]; then
    log_ok "✓ Integrity baseline создан"
    ((tests_passed++))
  fi

  # ── Test 11: .env защищён ──
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    local env_perms
    env_perms="$(stat -c '%a' "$SCRIPT_DIR/.env" 2>/dev/null || stat -f '%Lp' "$SCRIPT_DIR/.env" 2>/dev/null || echo "unknown")"
    if [[ "$env_perms" == "600" ]]; then
      log_ok "✓ .env — chmod 600"
      ((tests_passed++))
    else
      log_warn "⚠ .env имеет права $env_perms (рекомендуется 600)"
      ((tests_warn++))
    fi
  fi

  # ── Test 12: .env переменные ──
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; . "$SCRIPT_DIR/.env" 2>/dev/null || true; set +a
    for var in DEFAULT_PROVIDER DEFAULT_MODEL; do
      if [[ -z "${!var:-}" ]]; then
        log_warn "⚠ .env: $var не задана"
        ((tests_warn++))
      fi
    done

    # Валидация формата ключей
    if [[ -n "${ANTHROPIC_API_KEY:-}" && "$ANTHROPIC_API_KEY" != "your-anthropic-key" ]]; then
      if [[ ! "$ANTHROPIC_API_KEY" =~ ^sk-ant- ]]; then
        log_warn "⚠ Anthropic key: необычный формат (ожидается sk-ant-...)"
        ((tests_warn++))
      fi
    fi
    if [[ -n "${OPENAI_API_KEY:-}" && "$OPENAI_API_KEY" != "your-openai-key" ]]; then
      if [[ ! "$OPENAI_API_KEY" =~ ^sk- ]]; then
        log_warn "⚠ OpenAI key: необычный формат (ожидается sk-...)"
        ((tests_warn++))
      fi
    fi
    if [[ -n "${OPENROUTER_API_KEY:-}" && "$OPENROUTER_API_KEY" != "your-openrouter-key" ]]; then
      if [[ ! "$OPENROUTER_API_KEY" =~ ^sk-or- ]]; then
        log_warn "⚠ OpenRouter key: необычный формат (ожидается sk-or-...)"
        ((tests_warn++))
      fi
    fi
    if [[ -n "${GROQ_API_KEY:-}" && "$GROQ_API_KEY" != "your-groq-key" ]]; then
      if [[ ! "$GROQ_API_KEY" =~ ^gsk_ ]]; then
        log_warn "⚠ Groq key: необычный формат (ожидается gsk_...)"
        ((tests_warn++))
      fi
    fi

    # Проверка плейсхолдерных значений
    local placeholder_keys
    placeholder_keys="$(grep -E '^(ANTHROPIC|OPENAI|OPENROUTER|GOOGLE|DEEPSEEK|GROQ)_API_KEY=' "$SCRIPT_DIR/.env" 2>/dev/null | grep -cE '=your-|=sk-your|gsk-your' || echo 0)"
    if [[ "${placeholder_keys:-0}" -gt 0 ]]; then
      log_warn "⚠ $placeholder_keys API ключей с placeholder-значениями"
      ((tests_warn++))
    fi
  fi

  # ── Test 13: Синтаксис скриптов ──
  local script_errors=0
  for f in "$SCRIPT_DIR/scripts/"*.sh; do
    [[ -f "$f" ]] || continue
    if ! bash -n "$f" 2>/dev/null; then
      log_error "✗ Синтаксическая ошибка: $(basename "$f")"
      ((script_errors++))
    fi
  done
  if [[ "$script_errors" -eq 0 ]]; then
    log_ok "✓ Все скрипты прошли синтаксическую проверку"
    ((tests_passed++))
  else
    ((tests_failed += script_errors))
  fi

  echo ""
  echo -e "  Результат: ${GREEN}${tests_passed} passed${NC}, ${YELLOW}${tests_warn} warnings${NC}, ${RED}${tests_failed} failed${NC}"

  print_report
}

print_report() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║            🧪 Heisenberg Team — Отчёт                    ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}Режим: DRY RUN (ничего не было изменено)${NC}"
    echo ""
  fi

  echo -e "  ${BOLD}Провайдер:${NC}     $DEFAULT_PROVIDER"
  echo -e "  ${BOLD}Boss модель:${NC}   $BOSS_MODEL"
  echo -e "  ${BOLD}Specialist:${NC}    $SPECIALIST_MODEL"
  echo -e "  ${BOLD}Gateway:${NC}       ${GATEWAY_HOST}:${GATEWAY_PORT}"
  echo -e "  ${BOLD}Лимит:${NC}         \$${MAX_COST_PER_DAY}/день"
  echo ""
  echo -e "  ${BOLD}Агенты (${#SELECTED_AGENTS[@]}):${NC}"

  for agent in "${SELECTED_AGENTS[@]}"; do
    local visibility="VISIBLE"
    for s in "${SILENT_AGENTS[@]}"; do
      if [[ "$agent" == "$s" ]]; then visibility="SILENT"; break; fi
    done
    if [[ "$agent" == "heisenberg" ]]; then visibility="MAIN"; fi

    local icon="🔇"
    if [[ "$visibility" == "VISIBLE" ]]; then icon="👁 "; fi
    if [[ "$visibility" == "MAIN" ]]; then icon="🧪"; fi

    echo -e "    $icon  $agent ($visibility)"
  done

  # Предупреждения
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}⚠ Предупреждения:${NC}"
    for w in "${WARNINGS[@]}"; do
      echo -e "    - $w"
    done
  fi

  # Ошибки
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}❌ Ошибки:${NC}"
    for e in "${ERRORS[@]}"; do
      echo -e "    - $e"
    done
  fi

  echo ""
  echo -e "  ${BOLD}Следующие шаги:${NC}"
  echo -e "    1. Проверьте статус:    ${CYAN}openclaw gateway status${NC}"
  echo -e "    2. Первая задача:       ${CYAN}cat docs/first-task.md${NC}"
  echo -e "    3. Аудит оркестрации:   ${CYAN}bash scripts/orchestration-audit.sh${NC}"
  echo -e "    4. Health check:        ${CYAN}bash scripts/agent-health-check.sh${NC}"

  if [[ -z "${TELEGRAM_BOT_TOKEN_HEISENBERG:-}" ]]; then
    echo ""
    echo -e "  ${DIM}Telegram не настроен. Добавьте bot token в .env позже.${NC}"
  fi

  echo ""
  echo -e "${DIM}  Версия скрипта: $SCRIPT_VERSION | $(date)${NC}"
  echo ""
}

# ============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================================================

main() {
  echo -e "\n${BOLD}🧪 Heisenberg Team — One-Click Deploy v${SCRIPT_VERSION}${NC}\n"

  parse_args "$@"

  # Проверяем, что мы в корне проекта
  if [[ ! -f "$SCRIPT_DIR/AGENTS.md" && ! -d "$SCRIPT_DIR/agents" ]]; then
    # Может мы не в корне — ищем
    if [[ -f "./AGENTS.md" && -d "./agents" ]]; then
      SCRIPT_DIR="$(pwd)"
    else
      log_fatal "Запустите из корня проекта heisenberg-team\n  cd heisenberg-team && bash deploy-one-click.sh"
    fi
  fi

  phase_1_preflight
  phase_2_install_openclaw
  phase_3_load_config
  phase_4_backup
  phase_5_generate_configs
  phase_6_deploy_workspaces
  phase_7_deploy_skills
  phase_8_security_hardening
  phase_9_start_gateway
  phase_10_smoke_test

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
