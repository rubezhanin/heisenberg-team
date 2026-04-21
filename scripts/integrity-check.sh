#!/usr/bin/env bash
# ============================================================================
# integrity-check.sh — Проверка целостности критических файлов
# ============================================================================
# Использование:
#   bash scripts/integrity-check.sh          # Проверка
#   bash scripts/integrity-check.sh --fix    # Восстановление из baseline
#   bash scripts/integrity-check.sh --update # Обновить baseline
# ============================================================================
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
BASELINE_FILE="$OPENCLAW_HOME/.integrity-baseline.sha256"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

sha256_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

check_integrity() {
  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Baseline не найден: $BASELINE_FILE"
    echo "Запустите: bash scripts/integrity-check.sh --update"
    exit 1
  fi

  local violations=0
  local checked=0

  while IFS='  ' read -r expected_hash rel_path; do
    local full_path="$OPENCLAW_HOME/$rel_path"
    if [[ ! -f "$full_path" ]]; then
      echo -e "${RED}[MISSING]${NC} $rel_path"
      ((violations++))
      continue
    fi

    local actual_hash
    actual_hash="$(sha256_file "$full_path")"

    if [[ "$actual_hash" != "$expected_hash" ]]; then
      echo -e "${RED}[MODIFIED]${NC} $rel_path"
      echo "  Ожидался: $expected_hash"
      echo "  Получен:  $actual_hash"
      ((violations++))
    else
      echo -e "${GREEN}[OK]${NC} $rel_path"
    fi
    ((checked++))
  done < "$BASELINE_FILE"

  echo ""
  echo "Проверено: $checked | Нарушений: $violations"

  if (( violations > 0 )); then
    echo -e "${RED}❌ ВНИМАНИЕ: Обнаружены изменения в защищённых файлах!${NC}"
    echo "Для восстановления: bash scripts/integrity-check.sh --fix"
    exit 2
  else
    echo -e "${GREEN}✓ Все файлы в порядке${NC}"
  fi
}

update_baseline() {
  echo "Обновление baseline..."
  > "$BASELINE_FILE"

  for agent_dir in "$OPENCLAW_HOME"/agents/*/; do
    [[ -d "$agent_dir" ]] || continue
    local agent
    agent="$(basename "$agent_dir")"

    for check_file in SOUL.md IDENTITY.md; do
      if [[ -f "$agent_dir/$check_file" ]]; then
        echo "$(sha256_file "$agent_dir/$check_file")  agents/$agent/$check_file" >> "$BASELINE_FILE"
      fi
    done
  done

  chmod 444 "$BASELINE_FILE"
  echo -e "${GREEN}✓ Baseline обновлён: $(wc -l < "$BASELINE_FILE") файлов${NC}"
}

fix_from_source() {
  if [[ ! -d "$SCRIPT_DIR/agents" ]]; then
    echo -e "${RED}Каталог agents/ не найден. Запустите из корня heisenberg-team.${NC}"
    exit 1
  fi

  local fixed=0
  while IFS='  ' read -r expected_hash rel_path; do
    local full_path="$OPENCLAW_HOME/$rel_path"
    local actual_hash=""
    if [[ -f "$full_path" ]]; then
      actual_hash="$(sha256_file "$full_path")"
    fi

    if [[ "$actual_hash" != "$expected_hash" ]]; then
      # Ищем оригинал в репозитории
      local src_path="$SCRIPT_DIR/$rel_path"
      if [[ -f "$src_path" ]]; then
        cp "$src_path" "$full_path"
        chmod 444 "$full_path"
        echo -e "${GREEN}[RESTORED]${NC} $rel_path"
        ((fixed++))
      else
        echo -e "${YELLOW}[SKIP]${NC} Оригинал не найден: $src_path"
      fi
    fi
  done < "$BASELINE_FILE"

  echo ""
  echo -e "Восстановлено: $fixed файлов"
}

# ── Main ──
case "${1:-}" in
  --update) update_baseline ;;
  --fix)    fix_from_source ;;
  *)        check_integrity ;;
esac
