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

## Scope

This security policy covers the Heisenberg Team template and its configuration files. Security of the underlying OpenClaw platform is managed separately.
