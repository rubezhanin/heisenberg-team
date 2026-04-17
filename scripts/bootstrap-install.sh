#!/bin/bash
# bootstrap-install.sh - Universal dependency installer for Heisenberg Team
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Alpine (Docker), macOS
# Non-interactive mode: OPENCLAW_NONINTERACTIVE=1 or --yes
set -euo pipefail

# ─── Configuration ───
# Read from .env if it exists (user-configurable)
SCRIPT_DIR_BOOT="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR_BOOT="$(dirname "$SCRIPT_DIR_BOOT")"
if [ -f "$REPO_DIR_BOOT/.env" ]; then
  ENV_VER=$(grep '^OPENCLAW_VERSION=' "$REPO_DIR_BOOT/.env" 2>/dev/null | cut -d= -f2)
  [ -n "$ENV_VER" ] && OPENCLAW_VERSION="$ENV_VER"
fi
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.4.12}"
NODE_MAJOR="${NODE_MAJOR:-20}"
NONINTERACTIVE="${OPENCLAW_NONINTERACTIVE:-0}"

# Parse args
for arg in "$@"; do
  case "$arg" in
    --yes|-y) NONINTERACTIVE=1 ;;
    --version) echo "$OPENCLAW_VERSION"; exit 0 ;;
    --help|-h)
      cat <<'EOF'
Usage: bash scripts/bootstrap-install.sh [options]

Options:
  --yes, -y          Non-interactive mode (auto-install everything)
  --version          Show target OpenClaw version
  --help             Show this help

Environment:
  OPENCLAW_VERSION=X.Y.Z    Override OpenClaw version (default: 2026.4.12)
  NODE_MAJOR=N              Override Node.js major version (default: 20)
  OPENCLAW_NONINTERACTIVE=1 Same as --yes

Examples:
  bash scripts/bootstrap-install.sh              # Interactive
  bash scripts/bootstrap-install.sh --yes        # Non-interactive (CI/VPS)
  OPENCLAW_VERSION=2026.5.1 bash scripts/bootstrap-install.sh --yes
EOF
      exit 0
      ;;
  esac
done

# ─── Logging ───
log()   { echo "[bootstrap] $*"; }
warn()  { echo "[bootstrap] WARN: $*" >&2; }
error() { echo "[bootstrap] ERROR: $*" >&2; }

# ─── Sudo helper ───
need_sudo=false
if command -v sudo >/dev/null 2>&1; then
  need_sudo=true
fi

run_sudo() {
  if [ "$need_sudo" = true ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# ─── Version comparison ───
# Returns 0 if $1 >= $2
version_gte() {
  printf '%s\n%s' "$1" "$2" | sort -V -C
}

# ─── Interactive prompt ───
ask_install() {
  local what="$1"
  if [ "$NONINTERACTIVE" = "1" ]; then
    log "Auto-installing $what (non-interactive mode)"
    return 0
  fi
  read -p "[bootstrap] Install $what? [Y/n] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
}

# ─── Detect package manager ───
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v apk >/dev/null 2>&1; then
    echo "apk"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  else
    echo "unknown"
  fi
}

# ─── Pre-flight checks ───
preflight() {
  log "Running pre-flight checks..."
  local issues=0

  # Network connectivity
  if ! curl -s --connect-timeout 5 https://registry.npmjs.org/ >/dev/null 2>&1; then
    warn "Cannot reach npm registry. Check your internet connection."
    issues=$((issues + 1))
  fi

  # Disk space (need at least 500MB free)
  local free_kb
  if command -v df >/dev/null 2>&1; then
    free_kb=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -n "$free_kb" ] && [ "$free_kb" -lt 512000 ]; then
      warn "Low disk space: ${free_kb}KB free (need 500MB+)"
      issues=$((issues + 1))
    fi
  fi

  # Port check (OpenClaw gateway default: 18789)
  if command -v lsof >/dev/null 2>&1; then
    if lsof -i :18789 >/dev/null 2>&1; then
      warn "Port 18789 is already in use (OpenClaw gateway port)"
    fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -tlnp 2>/dev/null | grep -q ':18789 '; then
      warn "Port 18789 is already in use"
    fi
  fi

  if [ "$issues" -gt 0 ]; then
    if [ "$NONINTERACTIVE" = "0" ]; then
      read -p "[bootstrap] Continue despite warnings? [y/N] " -n 1 -r
      echo
      [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    else
      warn "Continuing despite $issues warning(s) (non-interactive mode)"
    fi
  fi
  log "Pre-flight checks passed"
}

# ─── Install system dependencies ───
install_system_deps() {
  local pkg_mgr="$1"
  log "Installing system dependencies via $pkg_mgr..."

  case "$pkg_mgr" in
    apt)
      run_sudo apt-get update -qq
      run_sudo apt-get install -y -qq git curl ca-certificates gnupg jq
      # build-essential is optional but recommended
      if ! dpkg -l build-essential >/dev/null 2>&1; then
        run_sudo apt-get install -y -qq build-essential || warn "build-essential install failed (non-critical)"
      fi
      ;;
    apk)
      run_sudo apk add --no-cache git curl ca-certificates jq build-base
      ;;
    dnf)
      run_sudo dnf install -y git curl @development-tools ca-certificates jq
      ;;
    yum)
      run_sudo yum install -y git curl @development-tools ca-certificates jq
      ;;
    pacman)
      run_sudo pacman -Sy --noconfirm git curl base-devel ca-certificates jq
      ;;
    zypper)
      run_sudo zypper install -y git curl patterns-devel-base-devel_basis ca-certificates jq
      ;;
    brew)
      brew install git jq
      ;;
    *)
      error "Unknown package manager: $pkg_mgr"
      log "Install manually: git, curl, jq, Node.js ${NODE_MAJOR}+"
      return 1
      ;;
  esac
}

# ─── Install Node.js ───
install_nodejs() {
  local pkg_mgr="$1"

  # Check if already installed with correct version
  if command -v node >/dev/null 2>&1; then
    local current_ver
    current_ver=$(node --version 2>/dev/null | sed 's/^v//')
    local current_major="${current_ver%%.*}"
    if [ "$current_major" -ge "$NODE_MAJOR" ]; then
      log "Node.js $current_ver already installed (>= ${NODE_MAJOR})"
      return 0
    else
      warn "Node.js $current_ver is too old (need ${NODE_MAJOR}+)"
    fi
  fi

  log "Installing Node.js ${NODE_MAJOR}.x..."

  case "$pkg_mgr" in
    apt)
      if curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" 2>/dev/null | run_sudo -E bash - 2>/dev/null; then
        run_sudo apt-get install -y -qq nodejs
      else
        warn "nodesource setup failed, trying nvm..."
        install_node_via_nvm
      fi
      ;;
    apk)
      run_sudo apk add --no-cache "nodejs" "npm"
      ;;
    dnf)
      if curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" 2>/dev/null | run_sudo -E bash - 2>/dev/null; then
        run_sudo dnf install -y nodejs
      else
        install_node_via_nvm
      fi
      ;;
    yum)
      if curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" 2>/dev/null | run_sudo -E bash - 2>/dev/null; then
        run_sudo yum install -y nodejs
      else
        install_node_via_nvm
      fi
      ;;
    pacman)
      run_sudo pacman -Sy --noconfirm nodejs npm
      ;;
    zypper)
      run_sudo zypper install -y nodejs npm
      ;;
    brew)
      brew install node
      ;;
    *)
      install_node_via_nvm
      ;;
  esac

  # Verify
  if command -v node >/dev/null 2>&1; then
    log "Node.js $(node --version) installed"
  else
    error "Node.js installation failed"
    return 1
  fi
}

# ─── Fallback: install Node via nvm ───
install_node_via_nvm() {
  log "Installing Node.js via nvm..."
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install "$NODE_MAJOR"
  nvm use "$NODE_MAJOR"
  nvm alias default "$NODE_MAJOR"
}

# ─── Setup npm global prefix (avoid sudo for npm -g) ───
setup_npm_prefix() {
  # If npm global installs require sudo, configure user-level prefix
  if [ "$(id -u)" -ne 0 ] && [ "$need_sudo" = true ]; then
    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
    # Check if we can write to the global prefix
    if [ ! -w "$npm_prefix" ] 2>/dev/null; then
      log "Configuring npm for user-level global installs..."
      mkdir -p "$HOME/.npm-global"
      npm config set prefix "$HOME/.npm-global"
      # Add to PATH if not already
      if ! echo "$PATH" | grep -q "$HOME/.npm-global/bin"; then
        export PATH="$HOME/.npm-global/bin:$PATH"
        # Add to shell profile
        for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
          if [ -f "$profile" ]; then
            if ! grep -q ".npm-global/bin" "$profile"; then
              echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$profile"
              log "Added npm-global to PATH in $profile"
            fi
          fi
        done
      fi
    fi
  fi
}

# ─── Install OpenClaw ───
install_openclaw() {
  # Ensure npm is available
  if ! command -v npm >/dev/null 2>&1; then
    error "npm not found. Node.js may not be properly installed."
    return 1
  fi

  if command -v openclaw >/dev/null 2>&1; then
    local installed_ver
    installed_ver=$(openclaw --version 2>/dev/null || echo "unknown")

    if [ "$installed_ver" = "$OPENCLAW_VERSION" ]; then
      log "OpenClaw $installed_ver already installed (matches target)"
      return 0
    elif version_gte "$installed_ver" "$OPENCLAW_VERSION"; then
      log "OpenClaw $installed_ver is newer than target $OPENCLAW_VERSION — keeping"
      return 0
    else
      log "OpenClaw $installed_ver is older than target $OPENCLAW_VERSION — upgrading..."
      npm install -g "openclaw@$OPENCLAW_VERSION" || {
        error "Failed to upgrade OpenClaw. Try manually: npm install -g openclaw@$OPENCLAW_VERSION"
        return 1
      }
    fi
  else
    log "Installing OpenClaw $OPENCLAW_VERSION..."
    npm install -g "openclaw@$OPENCLAW_VERSION" || {
      error "Failed to install OpenClaw. Check npm permissions."
      log "Fix: npm config set prefix ~/.npm-global && export PATH=~/.npm-global/bin:\$PATH"
      return 1
    }
  fi

  log "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed') ready"
}

# ─── Setup git hooks (pre-commit for secret protection) ───
setup_git_hooks() {
  # Only if we're in a git repo
  if [ -d ".git" ] || git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -d ".githooks" ]; then
      git config core.hooksPath .githooks 2>/dev/null && \
        log "Git hooks configured (.githooks)" || true
    fi
  fi
}

# ─── Optional: Ollama ───
install_ollama_optional() {
  if command -v ollama >/dev/null 2>&1; then
    log "Ollama already installed"
    return 0
  fi

  if ask_install "Ollama for local LLM/embeddings"; then
    log "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installed. Pull models: ollama pull llama3 && ollama pull nomic-embed-text"
  fi
}

# ─── Main ───
main() {
  log "=== Heisenberg Team Bootstrap ==="
  log "Target: OpenClaw $OPENCLAW_VERSION, Node.js ${NODE_MAJOR}+"
  [ "$NONINTERACTIVE" = "1" ] && log "Mode: non-interactive"
  echo ""

  # Pre-flight
  preflight

  # Detect OS and package manager
  local pkg_mgr
  if [[ "${OSTYPE:-}" == linux* ]]; then
    pkg_mgr=$(detect_pkg_manager)
    if [ "$pkg_mgr" = "unknown" ]; then
      error "Unsupported Linux distribution"
      log "Install manually: git, curl, Node.js ${NODE_MAJOR}+, jq"
      log "Supported: apt (Ubuntu/Debian), apk (Alpine), dnf (Fedora/RHEL), yum (CentOS), pacman (Arch), zypper (SUSE)"
      exit 1
    fi
    install_system_deps "$pkg_mgr"
    install_nodejs "$pkg_mgr"
  elif [[ "${OSTYPE:-}" == darwin* ]]; then
    pkg_mgr="brew"
    install_system_deps "$pkg_mgr"
    install_nodejs "$pkg_mgr"
  else
    error "Unsupported OS: ${OSTYPE:-unknown}"
    log "Supported: Linux (apt/apk/dnf/yum/pacman/zypper), macOS (brew)"
    exit 1
  fi

  echo ""

  # npm prefix setup
  setup_npm_prefix

  # OpenClaw
  install_openclaw

  echo ""

  # Optional: Ollama
  install_ollama_optional

  echo ""

  # Git hooks
  setup_git_hooks

  echo ""
  log "=== Bootstrap complete ==="
  log "Next: bash scripts/setup-wizard.sh"
}

main "$@"
