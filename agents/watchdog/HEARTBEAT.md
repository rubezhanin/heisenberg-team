# HEARTBEAT.md — Watchdog 🔍

Каждый heartbeat (2 мин):
1. `openclaw status` — gateway alive?
2. `openclaw sessions --all-agents --active 300` — stuck sessions?
3. `openclaw tasks list --status error 2>/dev/null` — failed tasks?

Если проблема → alert main. Если всё ок → HEARTBEAT_OK.
