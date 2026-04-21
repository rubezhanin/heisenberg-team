# Security Policy

## Overview

Heisenberg Team is a multi-agent AI system. Security is critical because agents can execute code, access APIs, and interact with external services.

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public GitHub issue
2. Contact the maintainers privately via email or GitHub Security Advisories
3. Include a description, steps to reproduce, and potential impact

## Security Architecture

### Agent Isolation

- Each agent runs in its own OpenClaw session
- Agents communicate via `sessions_send()` with timeout protection
- File-based board (`team-board.md`) is the primary state store

### Sensitive Data Protection

- `.gitignore` excludes all sensitive files (`.env`, `auth.json`, credentials)
- `scripts/depersonalize.sh` removes personal data before publishing
- `skills/quality-check/SKILL.md` includes PII scanning patterns
- Agent configs use `{{PLACEHOLDER}}` format for all personal values

### What to Watch For

- **API keys/tokens** — Never commit real tokens. Use `.env` files (gitignored)
- **Telegram bot tokens** — Store in OpenClaw config, not in agent files
- **Personal data** — Run `depersonalize.sh` before any public sharing
- **File permissions** — Sensitive configs should be `chmod 600`

### Production Safety

See `references/production-safety-standard.md` for the full checklist covering:
- Backup procedures before file operations
- PII protection in generated documents
- Cross-platform compatibility checks
- Rollback documentation

## Best Practices

1. Run `scripts/agent-health-check.sh` regularly
2. Review `scripts/system-health-monitor.sh` output
3. Keep agent session sizes manageable (use `scripts/trash-agent-session.sh` for cleanup)
4. Monitor cron jobs via `scripts/cron-watchdog.sh`

## Automated Security Hardening

`deploy-one-click.sh` автоматически применяет следующие меры:

### Gateway Protection
- Gateway привязан к `127.0.0.1` (никогда `0.0.0.0`)
- 64-символьный случайный gateway token
- Для удалённого доступа используйте Tailscale/VPN/SSH tunnel

### File Permissions
| Файл | Права | Причина |
|------|-------|---------|
| `.env` | `600` | API ключи и токены |
| `openclaw.json` | `600` | Конфигурация с ключами |
| `SOUL.md` | `444` | Защита от перезаписи агентом |
| `IDENTITY.md` | `444` | Защита личности агента |
| `.integrity-baseline.sha256` | `444` | Эталон целостности |

### Integrity Monitoring

```bash
bash scripts/integrity-check.sh            # Проверка
bash scripts/integrity-check.sh --fix      # Восстановление
bash scripts/integrity-check.sh --update   # Обновить baseline
```

### Security Checklist (перед production)
- [ ] Gateway: `host` = `127.0.0.1`, token задан
- [ ] Firewall: порт 18789 закрыт для внешнего доступа
- [ ] `.env`: `chmod 600`, не в git
- [ ] SOUL.md/IDENTITY.md: `chmod 444`
- [ ] Skills: CHECKSUMS.sha256 верифицирован
- [ ] Pre-commit hook установлен
- [ ] `openclaw security audit` пройден
- [ ] `bash scripts/integrity-check.sh` — OK
- [ ] Cost limits установлены
- [ ] Telegram bot tokens ротированы с момента тестирования

## Automated Security Hardening

`deploy-one-click.sh` automatically applies the following security measures during deployment. Each measure closes a specific attack vector documented in OpenClaw CVEs (138+ tracked as of April 2026).

### Gateway Protection

- Gateway binds to `127.0.0.1` (never `0.0.0.0`) — prevents external RCE via WebSocket
- 64-character random gateway token (generated via `openssl rand -hex 32`)
- For remote access use Tailscale, VPN, or SSH tunnel — never expose port 18789 publicly

Mitigated CVEs: CVE-2026-25253 (WebSocket RCE), CVE-2026-25157 (command injection)

### File Permissions

| File | Mode | Reason |
|------|------|--------|
| `.env` | `600` | API keys, Telegram tokens |
| `openclaw.json` | `600` | Provider credentials |
| `auth.json` | `600` | OAuth tokens |
| `SOUL.md` | `444` | Prevents agent self-modification ("sticky" injection) |
| `IDENTITY.md` | `444` | Protects public persona from tampering |
| `.integrity-baseline.sha256` | `444` | Tamper-evident integrity reference |

### Integrity Monitoring

SOUL.md and IDENTITY.md are write-protected after deployment. A SHA256 baseline is generated to detect tampering:

``````bash
# Check integrity (exits 2 on tampering)
bash scripts/integrity-check.sh

# Restore modified files from repository source
bash scripts/integrity-check.sh --fix

# Regenerate baseline after legitimate updates
bash scripts/integrity-check.sh --update
``````

Recommended: run `integrity-check.sh` from watchdog agent every 30 minutes or via cron.

### Pre-commit Hook

Prevents accidental secret leakage. Blocks commits containing:

- Files: `.env`, `auth.json`, `*.openclaw.json`, `configs/generated/*`
- API key patterns in diff: Anthropic (`sk-ant-api*`), OpenAI (`sk-*`), OpenRouter (`sk-or-v1-*`), Groq (`gsk_*`), Google (`AIzaSy*`)

Manual installation:

``````bash
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
``````

To bypass intentionally (use with caution): `git commit --no-verify`

### Cost Controls

Every generated `openclaw.json` includes hard limits in the `safety` block:

``````json
{
  "safety": {
    "maxCostPerDay": 10.00,
    "maxActionsPerHour": 100,
    "currency": "USD"
  }
}
``````

Configure via `.env`:
``````bash
MAX_COST_PER_DAY=10.00
MAX_ACTIONS_PER_HOUR=100
``````

### OpenClaw Version Pinning

`deploy-one-click.sh` enforces minimum safe version (`2026.4.12`). Older versions with known CVEs are rejected. Override via `.env`:

``````bash
OPENCLAW_VERSION=2026.4.12
``````

### Production Security Checklist

Before deploying to production, verify each item:

- [ ] Gateway `host` is `127.0.0.1`, `token` is set (check every `configs/generated/*.openclaw.json`)
- [ ] Firewall blocks port 18789 from external access
- [ ] `.env` has permissions `600` (`stat -c %a .env` returns `600`)
- [ ] `SOUL.md` and `IDENTITY.md` in every agent are `444`
- [ ] `bash scripts/integrity-check.sh` exits with code 0
- [ ] Pre-commit hook installed: `ls -la .git/hooks/pre-commit`
- [ ] `openclaw security audit` passes (if CLI version supports it)
- [ ] Cost limits set in every agent config
- [ ] Telegram bot tokens rotated after testing (old tokens may have leaked in logs)
- [ ] Skills directory verified against `CHECKSUMS.sha256` (see `shared-skills/`)
- [ ] `.integrity-baseline.sha256` exists and is `chmod 444`

### Incident Response

If integrity check fails or suspicious activity is detected:

1. **Stop gateway immediately**: `openclaw gateway stop`
2. **Check logs**: `tail -n 200 ~/.openclaw/logs/gateway.log`
3. **Compare with baseline**: `bash scripts/integrity-check.sh`
4. **Restore modified files**: `bash scripts/integrity-check.sh --fix`
5. **Rotate credentials**: regenerate all API keys and Telegram bot tokens in `.env`
6. **Restart deployment**: `bash deploy-one-click.sh --yes`
7. **Post-mortem**: review `~/.openclaw/backups/` to understand what changed

---

## Scope

This security policy covers the Heisenberg Team template and its configuration files. Security of the underlying OpenClaw platform is managed separately.
