# Hermes Agent — Telegram companion to Claude Code

Hermes is the Telegram-surface twin of the Claude Code session that runs on UAP. The two share an identity, a knowledge base, and a set of universal rules so the operator can jump between surfaces without re-explaining context.

This folder is the UAP runbook entry: how Hermes is installed on UAP, what files shape its behaviour, and how to reproduce the setup on a fresh deploy.

## What this component does on UAP

- Installs Hermes Agent (Nous Research, v0.13.x at time of writing) into `~/.hermes/hermes-agent` with its venv under `~/.hermes/hermes-agent/venv` and the launcher symlinked at `~/.local/bin/hermes`.
- Configures Telegram messaging with a long-polling gateway.
- Runs the gateway as a systemd **system** service (`hermes-gateway.service`) so the bot survives reboots and starts before user login.
- Drops a UAP override file so the gateway's `WorkingDirectory` is `~/workspace/`, making `~/workspace/CLAUDE.md` auto-load as Hermes's project-context file on every conversation.
- Seeds `~/.hermes/SOUL.md` with the durable Hermes identity (same assistant as Claude Code, universal rules, pointer to shared memory).
- Seeds `~/.hermes/memories/USER.md` and `~/.hermes/memories/MEMORY.md` with curated facts within their bounded char limits (1,375 / 2,200).

## Files in this folder

| File | Purpose | Live location |
|---|---|---|
| `SOUL.md` | Hermes identity + universal rules | `~/.hermes/SOUL.md` |
| `USER.md` | Bounded operator profile (≤1,375 chars) | `~/.hermes/memories/USER.md` |
| `MEMORY.md` | Bounded environment facts (≤2,200 chars) | `~/.hermes/memories/MEMORY.md` |
| `systemd-uap-override.conf.tmpl` | Drop-in setting `WorkingDirectory=${HOME_DIR}/workspace` (rendered per-operator) | `/etc/systemd/system/hermes-gateway.service.d/uap-override.conf` |

## Install (manual, no apply.sh integration yet)

```bash
# 1. Install Hermes from upstream (per https://hermes-agent.nousresearch.com/)
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# 2. Configure a Telegram bot (do this interactively in a real terminal, not a
#    Claude/Hermes session — the wizard reads /dev/tty):
#      - Get a bot token from @BotFather
#      - Get your numeric Telegram user ID from @userinfobot
hermes gateway setup
#    Verify ~/.hermes/.env has TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS (numeric),
#    and TELEGRAM_HOME_CHANNEL (numeric — same as user ID for DM delivery).

# 3. Wire in the UAP knowledge layer
install -m 0644 SOUL.md   ~/.hermes/SOUL.md
install -m 0644 USER.md   ~/.hermes/memories/USER.md
install -m 0644 MEMORY.md ~/.hermes/memories/MEMORY.md

# 4. Install the gateway as a systemd system service
sudo hermes gateway install --system
sudo hermes gateway start --system

# 5. Apply the UAP drop-in so the gateway runs from ~/workspace/.
#    Render the template first (HOME_DIR=/home/<your-username>):
HOME_DIR="$HOME" envsubst '${HOME_DIR}' < systemd-uap-override.conf.tmpl \
    > /tmp/uap-override.conf
sudo install -m 0644 -D /tmp/uap-override.conf \
    /etc/systemd/system/hermes-gateway.service.d/uap-override.conf
sudo systemctl daemon-reload
sudo systemctl restart hermes-gateway
```

## Verify

```bash
# Service running, drop-in detected
sudo systemctl status hermes-gateway

# Gateway CWD is the workspace hub
PID=$(systemctl show -p MainPID --value hermes-gateway)
sudo readlink /proc/$PID/cwd       # should print /home/<user>/workspace

# Gateway logs
tail -20 ~/.hermes/logs/gateway.log

# End-to-end: message the bot from your allowed Telegram account.
# A first turn should reflect knowledge of UAP, your role, and the universal rules
# without re-introduction.
```

## Why the drop-in pattern

`hermes gateway install --system` regenerates `/etc/systemd/system/hermes-gateway.service` from a template. Any direct edit to that file is lost the next time the unit is regenerated. The drop-in at `/etc/systemd/system/hermes-gateway.service.d/uap-override.conf` augments the unit without touching the generated file, so it survives reinstalls.

## What is NOT in this folder (intentionally)

- **The bot token.** Lives only in `~/.hermes/.env` on the live machine. Do not commit.
- **The operator's numeric Telegram user ID.** Per-operator; populated by `hermes gateway setup`, not by templates.
- **LLM provider keys** (OpenRouter, Anthropic, etc.). Same as above — `.env` only.

## Notes / known gaps

- This component is **not yet wired into `apply.sh`** as a UAP component. The install above is manual. A future iteration can add `install_hermes_agent()` and templates that read `identity.yaml` (operator username, allowed Telegram user IDs, preferred model provider).
- `ffmpeg` is not installed by default; voice-message transcription via TTS won't work until `sudo apt install ffmpeg`. Not critical for normal text use.
- The Hermes prompt-injection scanner rejects context files that match patterns like "ignore previous instructions", HTML comments, or `cat .env`. Keep SOUL/USER/MEMORY content free of those phrases.
