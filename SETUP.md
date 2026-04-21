# Setup Guide

> ⚠️ **Before you start:** Replace `YOUR_USERNAME` with your GitHub username in clone commands below.

## Prerequisites

- [Node.js](https://nodejs.org/) v20+
- [OpenClaw](https://github.com/openclaw/openclaw) installed (`npm install -g openclaw`)
- API key for at least one LLM provider (Anthropic, OpenAI, Google, etc.)
- Telegram bot token (recommended for notifications — create via [@BotFather](https://t.me/BotFather))

## Supported LLM Providers

| Provider | Main Model | Agent Model | Notes |
|----------|-----------|-------------|-------|
| Anthropic | claude-opus-4-5 | claude-sonnet-4-5 | Recommended. Best multi-agent coordination |
| OpenAI | gpt-4o | gpt-4o | Full support |
| Google | gemini-2.5-pro | gemini-2.5-flash | Full support |
| DeepSeek | deepseek-chat | deepseek-chat | Budget-friendly. Good reasoning with deepseek-reasoner |
| OpenRouter | any model | any model | Access 100+ models via one API key |
| Ollama | llama3 (or custom) | same | Local, free. Limited tool-use capability |

### Claude Max Users
If you have a Claude Max subscription ($100-200/month), you don't need a separate API key. The subscription includes API access through the Claude app. Enter 'max' when the wizard asks for your Anthropic API key.

### Embeddings
Vector memory search requires an embedding provider:
- **OpenAI** text-embedding-3-small ($0.02/1M tokens - practically free). Needs OpenAI API key.
- **Ollama** local embeddings (free). Needs running Ollama with an embedding model (e.g., `nomic-embed-text`).
- **Skip** - memory search will use keyword matching (BM25) only - still works, just less smart.

### Voice Transcription
Telegram voice messages can be transcribed via:
- **Groq Whisper API** (fast, cloud, needs Groq API key)
- **Local whisper.cpp** (free, needs whisper.cpp installed)
- **Skip** - no voice transcription

## Quick Start (Recommended)

One command installs everything — dependencies, OpenClaw, agents, configs:

```bash
git clone https://github.com/YOUR_USERNAME/heisenberg-team.git
cd heisenberg-team
bash deploy-one-click.sh
```

For non-interactive/VPS deployment:

```bash
cp .env.example .env
# Fill in .env with your values
bash deploy-one-click.sh --yes
```

For selected agents only:

```bash
bash deploy-one-click.sh --agents heisenberg,saul,walter
```

### curl | bash (one-liner)

```bash
HEISENBERG_REPO=https://github.com/YOU/heisenberg-team.git bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOU/heisenberg-team/main/install.sh)"
```

## Common Deployment Modes

### 1) Full team (interactive wizard)

```bash
bash deploy-one-click.sh
```

### 2) Non-interactive (from .env)

```bash
cp .env.example .env
# Edit .env
bash deploy-one-click.sh --yes
```

### 3) Selected agents only

```bash
bash deploy-one-click.sh --agents heisenberg,saul,walter
```

### 4) Attach to an existing OpenClaw install

Use this when you already have `~/.openclaw` and want to add Heisenberg Team agents:

```bash
bash deploy-one-click.sh --attach-existing --agents heisenberg,walter
```

### 5) Dry run (preview only)

```bash
bash deploy-one-click.sh --dry-run
```

### 6) Legacy scripts (still supported)

All legacy scripts (`scripts/setup.sh`, `scripts/deploy-team.sh`, `scripts/bootstrap-install.sh`) are now wrappers that delegate to `deploy-one-click.sh`:

```bash
bash scripts/setup.sh             # → deploy-one-click.sh
bash scripts/deploy-team.sh       # → deploy-one-click.sh
bash scripts/bootstrap-install.sh # → deploy-one-click.sh --attach-existing
```

```bash
bash scripts/init-workspace.sh  # Create directories for all agents
openclaw init                   # First time only — set LLM provider and API key
openclaw gateway start          # Start the system
openclaw status                 # Verify all 9 agents are active
```

Send a message to your Telegram bot to test. See [docs/first-task.md](docs/first-task.md) for a walkthrough.

## Manual Setup

If you prefer manual configuration:

### Step 1: Clone and Configure

```bash
git clone https://github.com/YOUR_USERNAME/heisenberg-team.git
cd heisenberg-team
cp .env.example .env
# Edit .env with your values
```

### Step 2: Initialize OpenClaw

```bash
openclaw init
```

Follow the prompts to set your LLM provider, API key, and messaging channel.

### Step 3: Replace Placeholders

Agent configs contain `{{PLACEHOLDER}}` values that must be replaced with your data. The most common ones:

| Placeholder | What to set | Where used |
|-------------|-------------|------------|
| `{{OWNER_NAME}}` | Your first name | All agent configs |
| `{{OWNER_USERNAME}}` | Your GitHub username | Agent identities |
| `{{OWNER_TELEGRAM_ID}}` | Your Telegram user ID | Notifications |
| `{{TELEGRAM_CHANNEL}}` | Your Telegram channel | Marketing agent |
| `{{BOT_USERNAME}}` | Your bot's username (legacy; see per-agent placeholders below) | Agent identities |
| `{{WORKSPACE_PATH}}` | Working directory | File operations |

You can use the setup wizard for this step or replace manually:
```bash
# Example: replace OWNER_NAME in all files
# macOS:
find . -type f -name "*.md" -exec sed -i '' 's/{{OWNER_NAME}}/YourName/g' {} \;
# Linux:
# find . -type f -name "*.md" -exec sed -i 's/{{OWNER_NAME}}/YourName/g' {} \;
```

### Additional Placeholders (per-agent)

These placeholders appear in individual agent files and are optional:

| Placeholder | Description | Where Used |
|------------|-------------|------------|
| `{{TOPIC_WALTER}}` | Telegram topic ID for Walter | walter/IDENTITY.md |
| `{{TOPIC_JESSE}}` | Telegram topic ID for Jesse | jesse/IDENTITY.md |
| `{{CLIENT_NAME}}` | Example client/project name | jesse/IDENTITY.md |
| `{{PAID_CHANNEL_ID}}` | Paid channel Telegram ID | walter/IDENTITY.md |
| `{{BOT_HEISENBERG}}` | Heisenberg bot username | team-constitution.md |
| `{{BOT_SAUL}}` | Saul bot username | team-constitution.md |
| `{{BOT_TEAMLEAD}}` | Walter bot username | team-constitution.md |
| `{{BOT_HANK}}` | Hank bot username | hank/MEMORY.md |
| `{{BOT_SKYLER}}` | Skyler bot username | team-constitution.md |
| `{{TTS_VOICE_NAME}}` | Text-to-speech voice name | jesse/TOOLS.md |

> 💡 The `setup-wizard.sh` handles the core placeholders automatically. These additional ones can be set manually as needed.

### Step 4: Deploy

```bash
# One-click (рекомендуется — делает шаги 1-4 автоматически):
bash deploy-one-click.sh

# Или вручную через обёртку:
bash scripts/setup.sh
```

### Step 5: Start and Verify

```bash
openclaw gateway start
openclaw status
bash scripts/smoke-test.sh
```

For partial installs:

```bash
bash scripts/smoke-test.sh --agents heisenberg,saul,walter
```

You should see 9 agents:

| Agent Name | Character | Role |
|-----------|-----------|------|
| main | Heisenberg | Boss (user-facing) |
| producer | Saul | Coordinator |
| teamlead | Walter | Code & production |
| marketing-funnel | Jesse | Marketing |
| skyler | Skyler | Finance & admin |
| hank | Hank | Security & QA |
| kaizen | Gus | Optimization |
| researcher | Twins | Research |

## Language Note

Agent personalities and team protocols are written in **Russian**. The agents communicate with you in Russian by default. If you need English:
- Edit `SOUL.md` in each agent to change the language and personality
- Edit `AGENTS.md` to change instructions language
- The architecture and system logic work in any language

## Customization

### Change Agent Personalities
Edit `agents/<name>/SOUL.md` and `IDENTITY.md`.

### Add/Remove Skills
Skills are in `skills/`. See the [skills index](skills/README.md) for the full list with dependencies.

### Modify Team Structure
Edit `references/team-constitution.md` to change delegation rules and workflows.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Setup wizard fails | Check Node.js v20+ and OpenClaw installed |
| Agent not responding | Check `openclaw status`, verify `~/.openclaw/agents/<name>/openclaw.json`, then inspect logs. Restart the shared gateway from your shell only if needed. |
| Skills not loading | Check `ls ~/.openclaw/shared-skills/` or `ls ~/.openclaw/agents/<name>/skills/` |
| Telegram not working | Verify `OWNER_TELEGRAM_ID` is set (digits only) |
| Remaining `{{PLACEHOLDER}}` | Run `grep -rn '{{' . --include='*.md'` to find them |
| No response after message | Check gateway logs, verify bot token is correct |

## Next Steps

- [Your First Task](docs/first-task.md) — step-by-step walkthrough
- [Architecture](docs/architecture.md) — how agents communicate
- [FAQ](docs/faq.md) — common questions
- [Add an Agent](examples/add-new-agent.md) — extend the team

---

## Multi-Agent Deployment

This repository contains a full team of 9 AI agents. To deploy the complete team:

1. Run `bash deploy-one-click.sh` (one-click, all 9 agents)
2. Config examples are in `configs/`
3. See [Deploy Agents Guide](docs/deploy-agents.md) for detailed instructions

> 💡 **Start small:** `bash deploy-one-click.sh --agents heisenberg,saul,walter` for 3 agents.
