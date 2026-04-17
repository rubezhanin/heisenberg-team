# IMPROVEMENTS.md — План и реализация изменений

> Полный перечень всех улучшений проекта Heisenberg Team.
> Дата: 2026-04-17
> Раунды: 1-4

---

## Содержание

- [Раунд 1: Провайдеры и установка](#раунд-1-провайдеры-и-установка)
- [Раунд 2: Исправление ошибок](#раунд-2-исправление-ошибок)
- [Раунд 3: Универсальность развёртывания](#раунд-3-универсальность-развёртывания)
- [Раунд 4: Оркестрация](#раунд-4-оркестрация)

---

## Раунд 1: Провайдеры и установка

### Цель

Добавить поддержку OpenRouter, Ollama (эмбеддинги), Groq (голос), per-agent bot tokens. Исправить Linux-совместимость. Model placeholders для конституции.

### Изменённые файлы

| Файл | Что |
|------|-----|
| `.env.example` | +OpenRouter, +Groq, +Ollama embed, +per-agent bot tokens (8 шт), +OPENCLAW_VERSION |
| `scripts/setup-wizard.sh` | +пункт OpenRouter, +Ollama embeddings, +Groq voice, +model placeholders, +auto .env, +summary, +auto-bootstrap, +gateway auto-start, +language flag |
| `scripts/bootstrap-install.sh` | +dnf/yum/apk/pacman/zypper, +build-essential, npm prefix fix, nvm fallback, pre-flight, non-interactive |
| `scripts/transcribe.sh` | +Groq API fallback перед whisper.cpp, +auto-sourcing .env |
| `scripts/smoke-test.sh` | +placeholder check, +empty apiKeys, +.env validation, +API key format, +skills symlink health |
| `configs/*.openclaw.json.example` (8 шт) | +`"openrouter"` в apiKeys |
| `references/team-constitution.md` | Opus/Sonnet → placeholders |
| `agents/saul/IDENTITY.md` | `Opus` → `{{AGENT_MODEL_SHORT}}` |
| `agents/skyler/AGENTS.md` | Таблица цен → provider-aware |
| `SETUP.md` | +OpenRouter, +Ollama, +Voice, +install.sh |
| `docs/linux-setup.md` | +Fedora/RHEL/Alpine/Arch/SUSE |

### Новые .env переменные

```
OPENROUTER_API_KEY=sk-or-...
GROQ_API_KEY=gsk_...
GROQ_WHISPER_MODEL=whisper-large-v3-turbo
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
TELEGRAM_BOT_TOKEN_HEISENBERG=...  (и все остальные агенты)
OPENCLAW_VERSION=2026.4.12
TEAM_LANG=en
```

---

## Раунд 2: Исправление ошибок

### Цель

Убрать hardcoded model IDs из скриптов, docs, skills. Исправить Node.js версию.

### Изменённые файлы

| Файл | Что |
|------|-----|
| `scripts/obsidian-watcher.sh` | Hardcoded model → из .env |
| `scripts/file-hook-watcher.sh` | Hardcoded model → из .env через jq |
| `scripts/post-update-check.sh` | Anthropic-only fallback → provider-aware |
| `scripts/deploy-team.sh` | `set -e` → `set -euo pipefail` |
| `scripts/agent-health-check.sh` | +`set -euo pipefail` |
| `.nvmrc` | `18` → `20` |
| `docs/linux-setup.md` | "18+" → "20+" |
| `docs/deploy-agents.md` | "18+" → "20+", hardcoded → placeholders |
| `skills/swipe-file/SKILL.md` | Hardcoded → placeholder |
| `skills/skill-and-agent-creator/SKILL.md` | 3 hardcoded → placeholders |
| `skills/skill-and-agent-creator/references/checklist.md` | Hardcoded → placeholder |

---

## Раунд 3: Универсальность развёртывания

### Цель

Единая точка входа, non-interactive режим, shared skills, backup, gateway auto-start.

### Новые файлы

| Файл | Назначение |
|------|-----------|
| `install.sh` | Единая точка входа (4 шага в 1 скрипте) |
| `scripts/setup-skills.sh` | Shared skills: 1 копия + симлинки |
| `scripts/update-check.sh` | Diff перед git pull |
| `scripts/orchestration-audit.sh` | Полный аудит оркестрации |

### Изменённые файлы

| Файл | Что |
|------|-----|
| `install.sh` | +backup ~/.openclaw, +auto-clone при pipe, +non-interactive |
| `scripts/bootstrap-install.sh` | +apk/pacman/zypper, +nvm fallback, +npm prefix, +pre-flight, +version from .env |
| `scripts/setup-wizard.sh` | +auto-bootstrap, +gateway auto-start (systemd/launchd), +shared skills, +watchdog, +language |
| `scripts/setup.sh` | setup-skills.sh вместо cp |
| `scripts/deploy-team.sh` | Shared skills + симлинки |
| `scripts/smoke-test.sh` | +API key validation, +skills symlink health |
| `SETUP.md` | bash install.sh |
| `docs/linux-setup.md` | Новый flow |

### Поддерживаемые ОС

Ubuntu, Debian, Alpine, Fedora, RHEL, CentOS, Arch, openSUSE, macOS

### Команды установки

```bash
bash install.sh                         # Interactive
bash install.sh --yes                   # Non-interactive
bash install.sh --agents heisenberg,saul  # Частичная
```

---

## Раунд 4: Оркестрация

### Цель

Structured return format, timeout SLA, visibility policy, sessions_spawn, watchdog, облегчение main.

### Архитектура

```
ДО:  Все агенты → пишут пользователю напрямую
ПОСЛЕ:
  main (ingress/egress)
    ├── saul (VISIBLE) → walter (VISIBLE), jesse (VISIBLE)
    │                  → twins (SILENT), skyler (SILENT)
    ├── hank (SILENT)
    ├── gus (SILENT)
    └── watchdog (SILENT)
```

### Изменённые файлы

| Файл | Что |
|------|-----|
| `references/team-constitution.md` | +Orchestration Contract, +Timeout SLA, +Visibility Policy |
| `agents/heisenberg/AGENTS.md` | Облегчен (132→75 строк), +structured return, +timeout, +spawn |
| `agents/saul/AGENTS.md` | +sessions_spawn primary, +timeout SLA |
| `agents/walter/AGENTS.md` | VISIBLE SPECIALIST + structured return |
| `agents/jesse/AGENTS.md` | VISIBLE SPECIALIST + structured return |
| `agents/twins/AGENTS.md` | SILENT MODE |
| `agents/hank/AGENTS.md` | SILENT MODE |
| `agents/skyler/AGENTS.md` | SILENT MODE |
| `agents/gus/AGENTS.md` | SILENT MODE |
| `agents/jesse/HEARTBEAT.md` | Очищен |
| `agents/skyler/HEARTBEAT.md` | Очищен |
| `agents/twins/HEARTBEAT.md` | Очищен |
| `agents/hank/HEARTBEAT.md` | Упрощен, алерт через main |
| `configs/heisenberg.openclaw.json.example` | +queue, +retry, +maxConcurrent: 3 |
| `configs/saul.openclaw.json.example` | +queue |
| `configs/*.openclaw.json.example` (6 шт) | +maxConcurrent: 2 |

### Новый агент: Watchdog

```
agents/watchdog/
├── AGENTS.md     Silent supervisor
├── SOUL.md       "I watch. I report."
├── IDENTITY.md   Watchdog identity
├── TOOLS.md      Monitoring commands
├── MEMORY.md     Alert principles
├── BOOTSTRAP.md  Recovery
└── HEARTBEAT.md  2-min check cycle
```

### Visibility Policy

| Агент | Видимость |
|-------|-----------|
| Heisenberg | MAIN (всегда пишет) |
| Saul | VISIBLE |
| Walter | VISIBLE |
| Jesse | VISIBLE |
| Skyler | SILENT |
| Hank | SILENT |
| Gus | SILENT |
| Twins | SILENT |
| Watchdog | SILENT |

### Structured Return Format

```
STATUS: done | blocked | escalate
SUMMARY: [1-3 предложения]
EVIDENCE: [что проверено]
ARTIFACTS: [файлы]
NEXT_STEP: [что делать дальше]
```

### Timeout SLA

| Время | Действие |
|-------|----------|
| 30-45с | Checkpoint |
| 60с | Progress update |
| 90с | Сигнал "подвисает" |
| 120с | Hard decision: continue / steer / cancel+respawn / take over |

### Delegation Rules

| Задача | Метод |
|--------|-------|
| Простой вопрос | Ответить напрямую |
| Consult <20с | `sessions_send` |
| Work >20с | `sessions_spawn` |

### Конфигурация

```json
{
  "messages": {
    "queue": { "mode": "collect", "debounceMs": 1000, "cap": 20 }
  },
  "agents": {
    "defaults": { "maxConcurrent": 3 }
  }
}
```

---

## Итого

| Метрика | Значение |
|---------|----------|
| Файлов изменено | ~50 |
| Новых файлов | ~15 |
| Провайдеров | 7 |
| ОС | 7 |
| Агентов | 9 (8 + watchdog) |
| Silent | 5 |
| Visible | 4 |

---

## После установки

```bash
openclaw init
openclaw gateway start
bash scripts/orchestration-audit.sh
```
