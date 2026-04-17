# Аудит репозитория Heisenberg Team
## Анализ уязвимостей, неоптимальных настроек и план автоматизации развёртывания

**Дата:** 2026-04-17
**Репозиторий:** `rubezhanin/heisenberg-team` (форк `ai-operacionka/heisenberg-team`)
**Платформа:** OpenClaw (v2026.4.x)

---

## 1. ОБЩАЯ ОЦЕНКА ПРОЕКТА

Heisenberg Team — мультиагентная система из 9 AI-агентов (8 основных + watchdog), построенная на OpenClaw. Использует Board-First координацию, файловое хранение состояния, 34 навыка (skills). Архитектура: один главный агент (Heisenberg) принимает сообщения от пользователя и делегирует задачи специалистам через `sessions_send` / `sessions_spawn`.

**Сильные стороны:**
- Хорошо продуманная оркестрация (Visibility Policy, Timeout SLA, structured return format)
- Board-First протокол — состояние переживает краши
- Watchdog-агент для мониторинга
- Shared skills через симлинки (экономия диска)
- Поддержка 7 LLM-провайдеров и 7 ОС
- Non-interactive режим установки (`--yes`)

**Критическая проблема:** проект сложен для "развёртывания в один клик" — текущий пайплайн состоит из 4+ отдельных скриптов, не всё автоматизировано.

---

## 2. НАЙДЕННЫЕ УЯЗВИМОСТИ

### 2.1 КРИТИЧЕСКИЕ

#### U-01: Отсутствие hardening Gateway по умолчанию
**Проблема:** OpenClaw по умолчанию слушает на `0.0.0.0:18789` без аутентификации. В конфигах `.openclaw.json.example` нет явного указания `gateway.host: "127.0.0.1"` и обязательного gateway-токена. При текущей эпидемии CVE OpenClaw (138+ CVE за 63 дня, включая RCE CVE-2026-25253) это критически опасно.

**Риск:** Удалённое выполнение кода через WebSocket gateway. 42,000+ незащищённых инстансов обнаружены на Shodan.

**Рекомендация:**
```json
{
  "gateway": {
    "host": "127.0.0.1",
    "port": 18789,
    "token": "{{GATEWAY_TOKEN}}"
  }
}
```
Добавить генерацию 64-символьного токена в setup-wizard.sh.

#### U-02: Нет pinning версии OpenClaw
**Проблема:** `OPENCLAW_VERSION` задаётся в `.env.example`, но `bootstrap-install.sh` может ставить `latest` без проверки CVE-патчей. Между v2026.1 и v2026.4 было 138 CVE. Установка произвольной "свежей" версии без верификации опасна.

**Рекомендация:** Жёстко зафиксировать минимально безопасную версию (≥ v2026.4.12), добавить проверку `openclaw --version` после установки.

#### U-03: SOUL.md / MEMORY.md не защищены от модификации агентом
**Проблема:** OpenClaw-агент может перезаписывать свои SOUL.md и MEMORY.md. Это вектор "sticky" атак — внедрённая инструкция остаётся в памяти и активируется позже. В SECURITY.md упоминается `chmod 600`, но это не применяется автоматически.

**Рекомендация:** В deploy-team.sh после развёртывания сделать `chmod 444` на SOUL.md и IDENTITY.md, `chmod 644` на MEMORY.md. Добавить integrity check (хэш-сумму) в watchdog.

### 2.2 ВЫСОКИЕ

#### U-04: API-ключи в .env без валидации формата
**Проблема:** smoke-test.sh проверяет наличие ключей, но не валидирует формат (например, Anthropic ключ должен начинаться с `sk-ant-`, OpenAI с `sk-`). Ошибочный ключ приведёт к скрытым сбоям при работе агентов.

#### U-05: Нет rate-limiting на межагентные вызовы
**Проблема:** В конфигах `maxConcurrent: 3` для Heisenberg и `maxConcurrent: 2` для остальных, но нет `maxActionsPerHour` и `maxCostPerDay`. Зацикленные агенты могут генерировать неограниченные API-затраты.

**Рекомендация:** Добавить в конфиги:
```json
{
  "safety": {
    "maxActionsPerHour": 100,
    "maxCostPerDay": 10.00,
    "currency": "USD"
  }
}
```

#### U-06: ClawHub skills не проходят верификацию
**Проблема:** 824+ вредоносных skills обнаружены в ClawHub. Проект использует 34 skills, но нет механизма проверки их целостности (checksums, подписи). В skills/ нет CHECKSUMS файла.

#### U-07: Telegram bot tokens хранятся в .env
**Проблема:** При случайном коммите `.env` (несмотря на .gitignore) утекают все 8+ Telegram bot tokens. Нет механизма ротации токенов.

### 2.3 СРЕДНИЕ

#### U-08: depersonalize.sh не запускается автоматически перед коммитом
**Проблема:** Есть скрипт для удаления персональных данных, но нет git pre-commit hook для его автоматического запуска.

**Рекомендация:** Добавить `.github/hooks/pre-commit` или husky.

#### U-09: Нет TLS/шифрования для межагентной коммуникации
**Проблема:** sessions_send работает через локальный gateway без шифрования. При удалённом развёртывании данные передаются открытым текстом.

#### U-10: Node.js 18 всё ещё указан как минимум
**Проблема:** README указывает Node.js v18+ как минимальное требование, но .nvmrc исправлен на 20. Несогласованность. Node.js 18 EOL — апрель 2025.

---

## 3. НЕОПТИМАЛЬНЫЕ НАСТРОЙКИ

### N-01: Heisenberg использует Opus для всех задач
Heisenberg (boss) маршрутизирует через Opus. Для простых задач делегирования это избыточно — можно использовать Sonnet для маршрутизации и Opus только для сложных задач. Экономия до 70-80% стоимости.

### N-02: Нет hybrid routing (local + API)
OpenClaw поддерживает Ollama для бесплатного локального инференса. Конфиг в `.env.example` содержит `OLLAMA_BASE_URL`, но routing rules для автоматического переключения local↔API отсутствуют.

### N-03: queue.debounceMs = 1000 слишком мал для группового чата
При активном использовании в Telegram-группе debounce 1 секунда может привести к множественным ответам. Для группового чата рекомендуется 3000-5000 мс.

### N-04: Нет backup перед обновлением
update-check.sh делает diff перед git pull, но не создаёт автоматический backup ~/.openclaw/ перед применением изменений.

### N-05: Скрипты оптимизированы под macOS
README явно указывает: скрипты оптимизированы для macOS. Используются macOS-специфичные команды (например, `launchd` для автозапуска). Linux-пользователи получают вторичный опыт.

---

## 4. ПЛАН СКРИПТА АВТОМАТИЧЕСКОГО РАЗВЁРТЫВАНИЯ

### Цель: "Один клик" — от чистой системы до работающей команды агентов

### Архитектура решения

```
deploy-one-click.sh
├── [1] Проверка/установка зависимостей (Node.js 20+, npm, git, jq, curl)
├── [2] Проверка/установка OpenClaw (с pinning версии)
├── [3] openclaw init + security hardening
├── [4] Конфигурация из .env или интерактивный визард
├── [5] Генерация конфигов для выбранных агентов
├── [6] Развёртывание workspaces + shared skills (симлинки)
├── [7] Security hardening (chmod, gateway token, bind 127.0.0.1)
├── [8] Запуск gateway (systemd/launchd)
├── [9] Smoke test + orchestration audit
└── [10] Отчёт об успешном развёртывании
```

### Режимы работы

1. **Interactive (визард):** `bash deploy-one-click.sh` — пошаговые вопросы
2. **Non-interactive (.env):** `bash deploy-one-click.sh --yes` — всё из .env
3. **Частичный:** `bash deploy-one-click.sh --agents heisenberg,saul,walter`
4. **Attach:** `bash deploy-one-click.sh --attach-existing` — OpenClaw уже установлен

### Переменные .env (необходимые)

```bash
# === ОБЯЗАТЕЛЬНЫЕ ===
ANTHROPIC_API_KEY=sk-ant-...          # или другой провайдер
DEFAULT_PROVIDER=anthropic            # anthropic|openai|openrouter|google|deepseek|ollama
DEFAULT_MODEL=claude-sonnet-4-20250514

# === ОПЦИОНАЛЬНО ===
OPENAI_API_KEY=sk-...
OPENROUTER_API_KEY=sk-or-...
GOOGLE_API_KEY=...
DEEPSEEK_API_KEY=...
GROQ_API_KEY=gsk_...
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_EMBEDDING_MODEL=nomic-embed-text

# === TELEGRAM (опционально) ===
TELEGRAM_BOT_TOKEN_HEISENBERG=...
TELEGRAM_BOT_TOKEN_SAUL=...
TELEGRAM_BOT_TOKEN_WALTER=...
TELEGRAM_BOT_TOKEN_JESSE=...
TELEGRAM_BOT_TOKEN_SKYLER=...
TELEGRAM_BOT_TOKEN_HANK=...
TELEGRAM_BOT_TOKEN_GUS=...
TELEGRAM_BOT_TOKEN_TWINS=...
TELEGRAM_BOT_TOKEN_WATCHDOG=...

# === ПЕРСОНАЛИЗАЦИЯ ===
OWNER_NAME="Your Name"
OWNER_TELEGRAM_ID=123456789
TEAM_LANG=ru                          # ru|en

# === БЕЗОПАСНОСТЬ ===
GATEWAY_TOKEN=                        # автогенерируется если пусто
OPENCLAW_VERSION=2026.4.12            # минимальная безопасная версия

# === ОПЦИИ ===
AGENTS=all                            # all | heisenberg,saul,walter
BOSS_MODEL=claude-sonnet-4-20250514   # модель для Heisenberg
SPECIALIST_MODEL=claude-sonnet-4-20250514  # модель для специалистов
MAX_COST_PER_DAY=10.00                # USD лимит
```

---

## 5. РЕАЛИЗАЦИЯ: DEPLOY-ONE-CLICK.SH

Ниже приведена структура главного скрипта. Он объединяет функциональность `install.sh`, `bootstrap-install.sh`, `setup-wizard.sh`, `deploy-team.sh`, `setup-skills.sh` и добавляет security hardening.

### Ключевые функции скрипта

```bash
#!/usr/bin/env bash
set -euo pipefail

# === ФАЗЫ ===

phase_1_preflight()
# - Определение ОС (macOS/Ubuntu/Debian/Fedora/Arch/Alpine/RHEL/SUSE)
# - Проверка: curl, git, jq (установка если нет)
# - Проверка: Node.js >= 20 (установка через nvm если нет)
# - Проверка: npm global prefix (fix если нужно)

phase_2_install_openclaw()
# - Проверка: openclaw --version
# - Если нет: npm install -g openclaw@${OPENCLAW_VERSION}
# - Верификация версии >= минимально безопасной
# - openclaw init (если ~/.openclaw не существует)

phase_3_load_config()
# - Загрузка .env (если существует)
# - ИЛИ запуск интерактивного визарда
# - Генерация GATEWAY_TOKEN (openssl rand -hex 32)
# - Валидация API ключей (формат)

phase_4_generate_configs()
# - Для каждого агента: генерация .openclaw.json из шаблона
# - Подстановка: провайдер, модель, API ключи, gateway token
# - Подстановка: bot tokens (если указаны)
# - Файл → configs/generated/{agent}.openclaw.json

phase_5_deploy_workspaces()
# - Для каждого агента: mkdir -p ~/.openclaw/agents/{agent}
# - Копирование: SOUL.md, AGENTS.md, IDENTITY.md, TOOLS.md, etc.
# - Подстановка: {{PLACEHOLDER}} → реальные значения
# - Подстановка: {{AGENT_MODEL_SHORT}} → из конфига

phase_6_deploy_skills()
# - Создание shared каталога: ~/.openclaw/shared-skills/
# - Копирование skills/ → shared-skills/
# - Для каждого агента: симлинки skills → shared-skills
# - Проверка целостности симлинков

phase_7_security_hardening()
# - Gateway: bind 127.0.0.1, установка token
# - chmod 444 на SOUL.md, IDENTITY.md (immutable)
# - chmod 600 на .env, auth.json, configs с ключами
# - Проверка: openclaw security audit (если доступна)
# - Генерация CHECKSUMS.sha256 для skills/

phase_8_start_gateway()
# - Определение init-системы (systemd/launchd)
# - Создание unit-файла / plist
# - Запуск gateway
# - Ожидание готовности (health check endpoint)

phase_9_smoke_test()
# - openclaw doctor
# - openclaw gateway status
# - Проверка: каждый агент отвечает
# - Проверка: skills симлинки живые
# - Проверка: API connectivity

phase_10_report()
# - Сводка: установленные агенты, провайдер, статус
# - Предупреждения: незаполненные bot tokens, отсутствующие ключи
# - Ссылки: docs/first-task.md, FAQ
```

### Визард (интерактивный режим)

```
╔══════════════════════════════════════════════╗
║       🧪 Heisenberg Team — Setup Wizard      ║
╚══════════════════════════════════════════════╝

Шаг 1/7: Ваше имя
> _

Шаг 2/7: LLM-провайдер
  [1] Anthropic (Claude)
  [2] OpenAI
  [3] OpenRouter
  [4] Google (Gemini)
  [5] DeepSeek
  [6] Ollama (локальный)
> _

Шаг 3/7: API-ключ
> sk-ant-***

Шаг 4/7: Какие агенты развернуть?
  [1] Все 9 (рекомендуется)
  [2] Минимум (Heisenberg + Saul + Walter)
  [3] Выбрать вручную
> _

Шаг 5/7: Telegram (опционально)
  Telegram ID: _
  Bot token для Heisenberg: _
  (остальные можно добавить позже)

Шаг 6/7: Язык агентов
  [1] Русский
  [2] English
> _

Шаг 7/7: Лимит затрат в день (USD)
> 10.00

════════════════════════════════════════════════
✓ Конфигурация сохранена в .env
  Запуск развёртывания...
```

---

## 6. ДОПОЛНИТЕЛЬНЫЕ РЕКОМЕНДАЦИИ

### 6.1 Pre-commit hook для защиты от утечки секретов

```bash
# .github/hooks/pre-commit
#!/bin/bash
if git diff --cached --name-only | grep -qE '\.env$|auth\.json$'; then
  echo "❌ BLOCKED: Attempt to commit secrets (.env or auth.json)"
  exit 1
fi
bash scripts/depersonalize.sh --check-only
```

### 6.2 Integrity monitoring (watchdog расширение)

Добавить в watchdog/TOOLS.md:

```
## Integrity Check
Каждые 30 минут проверяй:
- sha256sum SOUL.md каждого агента == эталон из CHECKSUMS.sha256
- Нет новых файлов в skills/ за пределами симлинков
- Gateway token не изменился
- .env не стал readable для group/other
```

### 6.3 Model routing для экономии

```json
{
  "ai": {
    "routing": {
      "local_tasks": ["simple_questions", "calendar", "file_management"],
      "api_tasks": ["complex_reasoning", "code_generation", "long_document_analysis"],
      "default_provider": "ollama",
      "api_provider": "anthropic"
    }
  }
}
```

### 6.4 Rollback механизм

Перед каждым deploy создавать:
```bash
BACKUP_DIR=~/.openclaw/backups/$(date +%Y%m%d_%H%M%S)
cp -r ~/.openclaw/agents/ "$BACKUP_DIR/"
cp ~/.openclaw/config.json "$BACKUP_DIR/"
```

### 6.5 README.md обновления

Заменить в Quick Start:
```bash
# БЫЛО (4 шага):
bash scripts/bootstrap-install.sh
cp .env.example .env
bash scripts/setup-wizard.sh
openclaw init

# СТАЛО (1 шаг):
bash deploy-one-click.sh
```

---

## 7. МАТРИЦА ПРИОРИТЕТОВ

| # | Проблема | Приоритет | Сложность | Влияние |
|---|----------|-----------|-----------|---------|
| U-01 | Gateway без auth | 🔴 Критический | Низкая | Взлом всей системы |
| U-02 | Нет pinning версии | 🔴 Критический | Низкая | Установка уязвимой версии |
| U-03 | SOUL.md перезапись | 🔴 Критический | Средняя | Persistent backdoor |
| U-05 | Нет cost limits | 🟠 Высокий | Низкая | Финансовый ущерб |
| U-06 | Skills без checksums | 🟠 Высокий | Низкая | Вредоносный код |
| U-04 | API key validation | 🟠 Высокий | Низкая | Скрытые сбои |
| U-08 | Нет pre-commit hook | 🟡 Средний | Низкая | Утечка секретов |
| U-10 | Node.js 18 vs 20 | 🟡 Средний | Низкая | Несовместимость |
| N-01 | Opus для маршрутизации | 🟡 Средний | Средняя | Перерасход |
| N-05 | macOS-first скрипты | 🟡 Средний | Высокая | Linux UX |

---

## 8. ИТОГ

Проект Heisenberg Team имеет хорошую архитектуру оркестрации, но **недостаточно hardened для продакшн-использования**. Ключевые проблемы:

1. **Безопасность gateway** — самая критичная точка, требующая немедленного исправления
2. **Автоматизация развёртывания** — текущие 4 скрипта нужно объединить в один `deploy-one-click.sh`
3. **Cost controls** — отсутствуют лимиты затрат, что при 9 агентах может привести к серьёзным расходам
4. **Integrity monitoring** — watchdog существует, но не проверяет целостность критических файлов

Предложенный `deploy-one-click.sh` решает проблемы 1-2 и закладывает основу для 3-4. Реализация всех рекомендаций оценивается в 8-12 часов работы.
