# TOOLS.md — Watchdog 🔍

## Команды мониторинга

| Команда | Что |
|---------|-----|
| `openclaw status` | Общий статус |
| `openclaw gateway status` | Gateway health |
| `openclaw sessions --all-agents --active 300` | Stuck sessions |
| `openclaw tasks list --status error` | Failed tasks |

## Алерты

Только через main: `sessions_send(sessionKey="agent:main:main", ...)`

НЕ пишу пользователю. НЕ вмешиваюсь. Только наблюдаю и докладываю.
