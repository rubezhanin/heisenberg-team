# HEARTBEAT.md — Хэнк Шрейдер 🔫

## Checks (every 30 min, silent — alert main only)

1. **Token exposure** — `grep -r "sk-ant-\|sk-proj-\|sk-or-" ~/.openclaw/ --include="*.json" -l 2>/dev/null | grep -v ".env"` — tokens outside .env?
2. **Permissions** — `stat -f "%Lp" ~/.openclaw/openclaw.json ~/.openclaw/.env` — should be 600
3. **Open ports** — `lsof -i -P | grep LISTEN` — gateway on 127.0.0.1 only?

## On failure

Alert main ONLY (silent mode):
```
sessions_send(sessionKey="agent:main:main", message="HEARTBEAT ALERT [Хэнк]: [what failed]", timeoutSeconds=120)
```

All OK → HEARTBEAT_OK
