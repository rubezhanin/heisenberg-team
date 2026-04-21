#!/bin/bash
# scripts/self-heal.sh — Автоматическое восстановление системы
# Запускается кроном каждые 30 мин (или вручную)
# Проверяет и ЧИНИТ: gateway, токен, WAL, базу, диск
# v2: все переменные из .env, убраны плейсхолдеры
set -euo pipefail

# ── Загрузка .env (безопасно) ──
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
SCRIPT_DIR_ENV="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR_ENV="$(dirname "$SCRIPT_DIR_ENV")"

ENV_FILE=""
for candidate in "$REPO_DIR_ENV/.env" "$OPENCLAW_HOME/.env" "$HOME/.env"; do
  if [ -f "$candidate" ]; then ENV_FILE="$candidate"; break; fi
done

if [ -n "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE" 2>/dev/null || true; set +a
fi

# ── Конфигурация из .env с дефолтами ──
TG_BOT_TOKEN="${HANK_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN_HANK:-}}"
TG_CHAT_ID="${HANK_CHAT_ID:-${OWNER_TELEGRAM_ID:-}}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:${GATEWAY_PORT:-18789}/health}"
WORKSPACE="${WORKSPACE_PATH:-$HOME/workspace}"
LOG="$OPENCLAW_HOME/logs/self-heal.log"
DB="$OPENCLAW_HOME/memory/main.sqlite"
KAIZEN_DB="$OPENCLAW_HOME/memory/kaizen.sqlite"
FIXED=0
FAILED=0
ALERTS=""

# Cross-platform stat
if [[ "${OSTYPE:-}" == "darwin"* ]]; then
  file_mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }
  file_size() { stat -f %z "$1" 2>/dev/null || echo 0; }
else
  file_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
  file_size() { stat -c %s "$1" 2>/dev/null || echo 0; }
fi

# Cross-platform gateway restart
restart_gateway() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
  elif command -v systemctl &>/dev/null; then
    systemctl --user restart openclaw-gateway 2>/dev/null || \
    openclaw gateway restart
  else
    openclaw gateway restart
  fi
}

# Cross-platform service restart helper
restart_service() {
  local svc="$1"
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    launchctl kickstart "gui/$(id -u)/$svc" 2>/dev/null || true
  elif command -v systemctl &>/dev/null; then
    systemctl --user restart "$svc" 2>/dev/null || true
  fi
}

get_service_pid() {
  local svc="$1"
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    launchctl list "$svc" 2>/dev/null | grep '"PID"' | grep -o '[0-9]*' || echo ""
  elif command -v systemctl &>/dev/null; then
    systemctl --user show -p MainPID "$svc" 2>/dev/null | cut -d= -f2 || echo ""
  else
    echo ""
  fi
}

# md5sum fallback (macOS doesn't have md5sum)
md5sum() { python3 -c "import hashlib,sys; print(hashlib.md5(open(sys.argv[1],'rb').read()).hexdigest())" "$@"; }

mkdir -p "$(dirname "$LOG")"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }
alert() { ALERTS="${ALERTS}\n$1"; }

notify() {
  [ -z "$ALERTS" ] && return
  local msg="🔧 Self-Heal Report:\n${ALERTS}\n\n✅ Fixed: $FIXED | ❌ Failed: $FAILED"
  if [ -n "$TG_BOT_TOKEN" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TG_CHAT_ID" -d text="$(echo -e "$msg")" -d parse_mode="HTML" > /dev/null 2>&1 || true
  fi
  log "$(echo -e "$msg")"
}

# ============ 1. GATEWAY HEALTH ============
check_gateway() {
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
  if [ "$status" != "200" ]; then
    log "🔴 Gateway down (HTTP $status). Restarting..."
    restart_gateway
    sleep 15
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")
    if [ "$status" = "200" ]; then
      alert "🔄 Gateway был мёртв → перезапущен ✅"
      FIXED=$((FIXED+1))
    else
      alert "🚨 Gateway НЕ поднялся после рестарта!"
      FAILED=$((FAILED+1))
    fi
  fi
}

# ============ 2. SQLite WAL MODE ============
check_wal() {
  for db_file in "$DB" "$KAIZEN_DB"; do
    [ ! -f "$db_file" ] && continue
    local mode
    mode=$(sqlite3 "$db_file" "PRAGMA journal_mode;" 2>/dev/null || echo "error")
    if [ "$mode" != "wal" ]; then
      log "🔴 $db_file journal=$mode. Fixing to WAL..."
      sqlite3 "$db_file" "PRAGMA journal_mode=WAL;" 2>/dev/null || true
      local new_mode
      new_mode=$(sqlite3 "$db_file" "PRAGMA journal_mode;" 2>/dev/null || echo "error")
      if [ "$new_mode" = "wal" ]; then
        alert "🔐 $(basename "$db_file"): $mode → WAL ✅"
        FIXED=$((FIXED+1))
      else
        alert "🚨 $(basename "$db_file"): не удалось переключить на WAL!"
        FAILED=$((FAILED+1))
      fi
    fi
  done
}

# ============ 3. MEMORY FRESHNESS ============
check_memory() {
  [ ! -f "$DB" ] && return

  local last_update chunk_count
  chunk_count=$(sqlite3 "$DB" "SELECT count(*) FROM chunks;" 2>/dev/null || echo 0)
  if [ "$chunk_count" -eq 0 ]; then
    alert "🚨 База памяти пуста — 0 чанков! Индексация сломана."
    FAILED=$((FAILED+1))
    return
  fi

  last_update=$(sqlite3 "$DB" "SELECT MAX(updated_at) FROM chunks;" 2>/dev/null || echo 0)
  local now_ms diff_h
  now_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
  diff_h=$(( (now_ms - last_update) / 3600000 ))

  if [ "$diff_h" -gt 20 ]; then
    alert "⚠️ Последнее обновление чанков было ${diff_h}ч назад. Проверь memory-core плагин."
    FAILED=$((FAILED+1))
  fi

  local empty
  empty=$(sqlite3 "$DB" "SELECT count(*) FROM chunks WHERE embedding IS NULL OR length(embedding) = 0;" 2>/dev/null || echo 0)
  if [ "$empty" -gt 0 ]; then
    alert "⚠️ $empty чанков без embeddings! Индексация сломана."
    FAILED=$((FAILED+1))
  fi
}

# ============ 4. DISK SPACE ============
check_disk() {
  local pct
  pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
  if [ "$pct" -gt 90 ]; then
    alert "🚨 Диск заполнен на ${pct}%! Нужна очистка."
    FAILED=$((FAILED+1))
  elif [ "$pct" -gt 80 ]; then
    alert "⚠️ Диск ${pct}%. Скоро закончится место."
  fi
}

# ============ 5. DOCKER ============
check_docker() {
  command -v docker &>/dev/null || return 0
  local stopped
  stopped=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null | grep -E "searxng|n8n-local|n8n-postgres" || true)
  if [ -n "$stopped" ]; then
    for c in $stopped; do
      docker start "$c" 2>/dev/null || true
      if docker ps --filter "name=$c" --filter "status=running" -q 2>/dev/null | grep -q .; then
        alert "🐳 Docker $c был остановлен → запущен ✅"
        FIXED=$((FIXED+1))
      else
        alert "🚨 Docker $c не удалось запустить!"
        FAILED=$((FAILED+1))
      fi
    done
  fi
}

# ============ 6. CRON ERRORS + AUTO-RETRY ============
check_crons() {
  local cron_script="$WORKSPACE/scripts/cron-get-jobs.sh"
  [ -f "$cron_script" ] || return 0

  local jobs_json
  jobs_json=$(bash "$cron_script" 2>/dev/null) || {
    log "⚠️ check_crons: не удалось получить список кронов"
    return 0
  }

  local count names
  read -r count names < <(echo "$jobs_json" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    bad = [j.get('name', j['id']) for j in d.get('jobs',[])
           if j.get('enabled', True)
           and j.get('state',{}).get('consecutiveErrors',0) > 0
           and j.get('schedule',{}).get('kind') != 'at']
    print(len(bad), ','.join(bad[:5]))
except Exception:
    print(0, '')
" 2>/dev/null || echo "0 ")

  if [ "${count:-0}" -gt 0 ]; then
    log "⚠️ $count кронов в ошибке: $names — запускаю auto-retry"
    local retry_script="$WORKSPACE/scripts/cron-retry.sh"
    if [ -f "$retry_script" ]; then
      bash "$retry_script" >> "$LOG" 2>&1 &
    fi
    alert "🔄 Кроны в ошибке ($count) → auto-retry запущен в фоне"
    FIXED=$((FIXED+1))
  fi
}

# ============ 7. BACKUP GATEWAYS ============
check_agents() {
  # Проверяем только стандартные сервисы OpenClaw
  for svc in com.openclaw.gateway-backup com.openclaw.gateway; do
    local pid
    pid=$(get_service_pid "$svc")
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
      restart_service "$svc"
      sleep 3
      pid=$(get_service_pid "$svc")
      if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        alert "🤖 $svc был мёртв → запущен (PID $pid) ✅"
        FIXED=$((FIXED+1))
      fi
    fi
  done
}

# ============ RUN ALL ============
log "--- Self-heal started ---"
check_gateway
check_wal
check_memory
check_disk
check_docker
check_crons
check_agents

if [ "$FIXED" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
  notify
  log "Result: fixed=$FIXED failed=$FAILED"
else
  log "✅ All checks passed"
fi
