# ТЕХНИЧЕСКОЕ ЗАДАНИЕ
# Автоматизация развёртывания мультиагентной команды на OpenClaw

**Версия ТЗ:** 2.0
**Дата:** 2026-04-21
**Репозиторий:** `rubezhanin/heisenberg-team`
**Статус:** Реализовано и задеплоено

---

## 1. ЦЕЛЬ

Создать one-click систему развёртывания мультиагентной команды (9 AI-агентов) на платформе OpenClaw. Одна команда — полностью рабочая защищённая инфраструктура.

### Критерии приёмки (все выполнены)

- `bash deploy-one-click.sh` — работает на чистой macOS/Ubuntu с curl за <10 минут
- `bash deploy-one-click.sh --yes` — non-interactive из `.env`
- Все smoke tests проходят
- Gateway привязан к `127.0.0.1` с 64-символьным токеном
- SOUL.md/IDENTITY.md — `chmod 444` (защита от перезаписи агентом)
- Pre-commit hook блокирует коммиты с API-ключами
- Обратная совместимость: старые скрипты работают через обёртки

---

## 2. АРХИТЕКТУРА ПРОЕКТА

### 2.1 Структура файлов (финальная)

```
heisenberg-team/
├── deploy-one-click.sh         # Главный скрипт (1571 строк, 10 фаз)
├── install.sh                  # Тонкая обёртка для curl | bash
├── .env.example                # Шаблон конфигурации (все настройки)
├── agents/                     # 9 агентов (heisenberg, saul, walter, jesse, skyler, hank, gus, twins, watchdog)
│   └── {agent}/
│       ├── SOUL.md             # Личность (chmod 444 после deploy)
│       ├── AGENTS.md           # Протоколы
│       ├── IDENTITY.md         # Идентификация (chmod 444)
│       ├── TOOLS.md            # Инструменты
│       ├── MEMORY.md           # Правила памяти
│       ├── BOOTSTRAP.md        # Восстановление
│       └── HEARTBEAT.md        # Периодические задачи
├── skills/                     # 34 shared skills
├── configs/                    # Шаблоны .openclaw.json (9 шт)
│   └── generated/              # Сгенерированные конфиги (.gitignore)
├── scripts/                    # Утилиты (49 файлов)
│   ├── openclaw-watchdog.sh    # Мониторинг gateway (здоровье, 401, telegram)
│   ├── self-heal.sh            # Автовосстановление (gateway, WAL, disk, docker, crons)
│   ├── smoke-test.sh           # standalone smoke test
│   ├── setup-wizard.sh         # Подробный визард (6 шагов)
│   ├── init-workspace.sh       # Создание workspace директорий
│   ├── setup.sh                # Обёртка → deploy-one-click.sh
│   ├── deploy-team.sh          # Обёртка → deploy-one-click.sh
│   ├── bootstrap-install.sh    # Обёртка → deploy-one-click.sh --attach-existing
│   └── ...                     # Остальные утилиты
├── references/                 # Конституция команды
├── docs/                       # Документация
├── README.md                   # English
├── README.ru.md                # Русский
├── SETUP.md                    # Подробная инструкция
└── SECURITY.md                 # Политика безопасности
```

### 2.2 deploy-one-click.sh — Пайплайн (10 фаз)

```
main()
│
├── phase_1_preflight()            ОС detection, curl/git/jq/Node.js 20+
│   ├── detect_os()                macOS / debian / fedora / rhel / arch / alpine / suse
│   ├── install_system_package()   Кроссплатформенная установка пакетов
│   ├── install_node()             nvm / brew / nodesource / pacman / apk
│   └── fix_npm_prefix()           Fix: npm global prefix без sudo
│
├── phase_2_install_openclaw()     npm install -g openclaw@{version}
│                                    + version_gte проверка >= MIN_OPENCLAW_VERSION
│                                    + openclaw init при первом запуске
│
├── phase_3_load_config()          .env → source или интерактивный визард
│   ├── run_wizard()               7 шагов: имя, провайдер, ключ, модель, агенты, telegram, язык, лимит
│   ├── validate_config()          Обязательные поля + regex-валидация ключей
│   └── save_env_file()            Запись .env с chmod 600
│
├── phase_4_backup()               cp -r ~/.openclaw/agents/ → backup/
│
├── phase_5_generate_configs()     Генерация .openclaw.json через jq
│                                    - apiKeys из .env
│                                    - gateway: host=127.0.0.1, token=64hex
│                                    - safety: maxCostPerDay, maxActionsPerHour
│                                    - telegram: per-agent bot token
│
├── phase_6_deploy_workspaces()    agents/ → ~/.openclaw/agents/$agent/
│                                    sed подстановка {{PLACEHOLDER}} из .env
│                                    + копирование openclaw.json
│
├── phase_7_deploy_skills()        skills/ → ~/.openclaw/shared-skills/
│                                    + симлинки для каждого агента
│                                    + CHECKSUMS.sha256
│
├── phase_8_security_hardening()
│   ├── chmod 444 SOUL.md, IDENTITY.md
│   ├── chmod 600 openclaw.json, .env
│   ├── install_precommit_hook()   Блок .env/.openclaw.json + regex API ключей
│   ├── integrity baseline         sha256 SOUL.md + IDENTITY.md
│   └── openclaw security audit
│
├── phase_9_start_gateway()        systemd unit / launchd plist / direct start
│                                    + health check (30s timeout)
│
└── phase_10_smoke_test()          13 проверок (мерж smoke-test.sh)
    ├── openclaw в PATH
    ├── openclaw doctor
    ├── Файлы агентов (AGENTS.md, SOUL.md, IDENTITY.md, TOOLS.md...)
    ├── Конфиги всех агентов
    ├── Плейсхолдеры в конфигах
    ├── Пустые API ключи в конфигах
    ├── Skills симлинки + broken symlink check
    ├── Gateway bind to localhost (не 0.0.0.0)
    ├── Нет API ключей в .md файлах
    ├── Плейсхолдеры в .md файлах агентов
    ├── Integrity baseline
    ├── .env permissions (chmod 600)
    ├── .env переменные + формат ключей
    └── Синтаксис всех скриптов
```

### 2.3 Режимы работы

| Режим | Команда | Описание |
|-------|---------|----------|
| Интерактивный | `bash deploy-one-click.sh` | Визард из 7 шагов |
| Non-interactive | `bash deploy-one-click.sh --yes` | Все значения из `.env` |
| Частичный | `bash deploy-one-click.sh --agents heisenberg,saul,walter` | Только указанные агенты |
| Attach | `bash deploy-one-click.sh --attach-existing` | Не устанавливать OpenClaw |
| Dry run | `bash deploy-one-click.sh --dry-run` | Только показать план |
| curl \| bash | `HEISENBERG_REPO=url bash <(curl -fsSL .../install.sh)` | Удалённая установка |

### 2.4 .env — Все настройки

```bash
# LLM
DEFAULT_PROVIDER=anthropic        # anthropic|openai|openrouter|google|deepseek|ollama
DEFAULT_MODEL=claude-sonnet-4-20250514
BOSS_MODEL=claude-sonnet-4-20250514
SPECIALIST_MODEL=claude-sonnet-4-20250514

# API Keys (заполнить хотя бы один)
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
OPENROUTER_API_KEY=
GOOGLE_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
GROQ_WHISPER_MODEL=whisper-large-v3-turbo

# Ollama (локальный)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text

# Telegram (по одному боту на агента)
OWNER_TELEGRAM_ID=
TELEGRAM_BOT_TOKEN_HEISENBERG=
TELEGRAM_BOT_TOKEN_SAUL=
# ... один токен на каждого агента

# Персонализация
OWNER_NAME=
TEAM_LANG=ru

# Безопасность
GATEWAY_HOST=127.0.0.1            # НИКОГДА 0.0.0.0
GATEWAY_PORT=18789
GATEWAY_TOKEN=                    # Генерируется автоматически (64 hex)

# OpenClaw
OPENCLAW_VERSION=2026.4.12        # Минимальная безопасная версия

# Лимиты
MAX_COST_PER_DAY=10.00
MAX_ACTIONS_PER_HOUR=100

# Watchdog / Self-Heal
HEALTH_URL=http://127.0.0.1:18789/health
HANK_BOT_TOKEN=
HANK_CHAT_ID=
HEALTH_CHECK_INTERVAL=120
SELF_HEAL_INTERVAL=1800

# Пути (автоопределение если пусто)
OPENCLAW_HOME=                    # default: $HOME/.openclaw
WORKSPACE_PATH=                   # default: $HOME/workspace

# Агенты
AGENTS=all                        # all | heisenberg,saul,walter
```

### 2.5 Поддерживаемые платформы

| ОС | Пакетный менеджер | Init | Статус |
|----|-------------------|------|--------|
| macOS 13+ | brew | launchd | ✅ |
| Ubuntu 22.04+ | apt | systemd | ✅ |
| Debian 12+ | apt | systemd | ✅ |
| Fedora 39+ | dnf | systemd | ✅ |
| RHEL/CentOS 9+ | yum | systemd | ✅ |
| Arch | pacman | systemd | ✅ |
| Alpine | apk | none | ⚠️ (без автозапуска) |
| openSUSE | zypper | systemd | ✅ |
| Windows 11 | WSL2 (apt) | systemd | ✅ |

---

## 3. БЕЗОПАСНОСТЬ

### Реализованные меры

| Мера | Где | Описание |
|------|-----|----------|
| Gateway binding | Фаза 5 | `host: "127.0.0.1"` в каждом конфиге |
| Token auth | Фаза 5 | 64-символьный hex токен генерируется автоматически |
| Version pinning | Фаза 2 | `version_gte` проверка `>= MIN_OPENCLAW_VERSION` |
| File protection | Фаза 8 | `chmod 444` SOUL.md, IDENTITY.md |
| Secret files | Фаза 8 | `chmod 600` openclaw.json, .env |
| Pre-commit hook | Фаза 8 | Блокирует .env, .openclaw.json, regex API ключей |
| Integrity baseline | Фаза 8 | sha256 хеши SOUL.md + IDENTITY.md |
| Cost limits | Фаза 5 | `maxCostPerDay`, `maxActionsPerHour` в каждом конфиге |
| Skills checksums | Фаза 7 | CHECKSUMS.sha256 для всех SKILL.md |
| API key validation | Фаза 3 | regex: `sk-ant-`, `sk-`, `sk-or-`, `gsk_` |
| No hardcoded secrets | watchdog/self-heal | Все токены из .env |
| No 0.0.0.0 binding | smoke test | Проверка на gateway host |

---

## 4. СКРИПТЫ-ОБЁРТКИ (обратная совместимость)

Старые скрипты сохранены как обёртки:

| Скрипт | Содержимое | Делегирует в |
|--------|-----------|--------------|
| `scripts/setup.sh` | 23 строки | `deploy-one-click.sh "$@"` |
| `scripts/deploy-team.sh` | 22 строки | `deploy-one-click.sh "$@"` |
| `scripts/bootstrap-install.sh` | 24 строки | `deploy-one-click.sh --attach-existing "$@"` |
| `install.sh` | 65 строк | Клонирует репо → `deploy-one-click.sh "$@"` |

---

## 5. МОНИТОРИНГ И САМОИСЦЕЛЕНИЕ

### openclaw-watchdog.sh
- Проверяет health endpoint каждые 2 минуты
- Обнаруживает 401 от Anthropic (连续 2 проверки → restart)
- Telegram-уведомления о падениях
- Все переменные из `.env` (нет хардкода)

### self-heal.sh
- Запускается кроном каждые 30 минут
- Проверяет: gateway, SQLite WAL, memory freshness, disk, docker, crons
- Авторемонт: gateway restart, WAL switch, docker start
- Telegram-отчёт при проблемах

---

## 6. ИНСТРУКЦИЯ ДЛЯ ИИ-РАЗРАБОТЧИКА

Этот раздел — гайд для воспроизведения аналогичного проекта с помощью ИИ.

### 6.1 Порядок работы

1. **Определить агентов и их роли** → создать `agents/{name}/` с SOUL.md, AGENTS.md, IDENTITY.md
2. **Написать .env.example** → ВСЕ настройки через переменные, ноль хардкода
3. **Написать deploy-one-click.sh** → фазы 1-10 последовательно
4. **Написать smoke tests** → отдельно + встроить в фазу 10
5. **Security hardening** → chmod, pre-commit hook, integrity baseline
6. **Wrapper scripts** → для обратной совместимости

### 6.2 Ключевые принципы

- **Ни одного хардкода** — все пути, токены, порты из .env
- **Обратная совместимость** — старые скрипты → обёртки, не удаление
- **Smoke test = финальная фаза** — не отдельный скрипт, а часть пайплайна
- **set -euo pipefail** — в каждом скрипте
- **chmod 600 на секреты** — .env, openclaw.json, auth.json
- **chmod 444 на identity** — SOUL.md, IDENTITY.md (агент не может перезаписать)
- **Кроссплатформенность через detect_os()** — case по uname + /etc/os-release

### 6.3 Антипаттерны (избегать)

- ❌ Отдельные скрипты для каждого шага (bootstrap, wizard, setup, deploy)
- ❌ AGENT_MAP с разными именами (heisenberg → main, saul → producer)
- ❌ Хардкод путей (`$HOME/.openclaw/scripts/hank-watchdog.env`)
- ❌ Плейсхолдеры в прод-скриптах (`{{YOUR_BRAND}}`, `{{OWNER_TELEGRAM_ID}}`)
- ❌ Разные визарды с разными полями (один визард, один источник правды)
- ❌ `curl | sudo bash` без проверки

### 6.4 Метрики проекта

| Метрика | Значение |
|---------|----------|
| deploy-one-click.sh | 1571 строк, 10 фаз |
| install.sh (wrapper) | 65 строк |
| .env.example | 79 строк, 30+ переменных |
| Smoke tests | 13 проверок |
| Обратная совместимость | 3 обёртки (setup, deploy-team, bootstrap) |
| Уязвимостей закрыто | 7 |
| Строка кода убрано (дубли) | ~633 (net) |
| Платформ | 8 Linux + macOS + WSL2 |

---

## 7. CHANGELOG

### v2.0 (2026-04-21) — Рефакторинг

**Безопасность:**
- watchdog: убран хардкод `source hank-watchdog.env`, все переменные из .env
- self-heal: убран `{{YOUR_BRAND}}` и `{{OWNER_TELEGRAM_ID}}` плейсхолдеры
- install.sh: убран хардкод GitHub URL
- SETUP.md: Node.js v18 → v20

**Архитектура:**
- setup.sh, deploy-team.sh, bootstrap-install.sh → обёртки (23-24 строки вместо 200+)
- install.sh → тонкая обёртка (65 строк вместо 193)
- smoke-test.sh мерж в фазу 10 deploy-one-click.sh (13 тестов вместо 8)
- .env расширен: HEALTH_URL, HANK_BOT_TOKEN, HANK_CHAT_ID, OPENCLAW_HOME, WORKSPACE_PATH

**Документация:**
- README.md + README.ru.md: Architecture диаграмма унифицирована
- Skills count: 34 (исправлено везде, было 34/35 хаос)
- SETUP.md: обновлён Quick Start, paths

### v1.0 (2026-04-17) — Первоначальная реализация

- deploy-one-click.sh: 10 фаз, полный пайплайн
- Security hardening: chmod, pre-commit hook, integrity baseline
- Cross-platform: 8 дистрибутивов Linux + macOS + WSL2
- Interactive wizard + non-interactive (.env) режимы
