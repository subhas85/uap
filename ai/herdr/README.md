# Herdr

[Herdr](https://herdr.dev/) is UAP's preferred terminal/agent workspace manager: a tmux-like background server with workspaces, tabs, panes, agent-state detection, SSH/RDP-friendly reconnects, and a CLI/socket API that Hermes can inspect from Telegram.

## Install

UAP installs Herdr to `~/.local/bin/herdr` using the upstream release manifest:

```bash
curl -fsSL https://herdr.dev/install.sh | sh
```

The installer downloads the latest stable binary for the current Linux architecture from `https://herdr.dev/latest.json`. Future updates are managed by Herdr itself:

```bash
herdr update
herdr channel show
herdr channel set stable   # or preview
```

## UAP launcher

The `desktop-entries` component installs a rofi/Alt+d launcher entry:

```text
Herdr (terminal workspace)
```

It starts Alacritty in `~/workspace` and attaches to the persistent Herdr session:

```bash
alacritty --working-directory ~/workspace -e herdr
```

Herdr does not require a special current directory to attach to an existing session. The launch cwd only matters when Herdr creates a new workspace/root shell; UAP uses `~/workspace` so new panes inherit the shared workspace hub.

## Why UAP uses it

- Same persistent terminal/agent surface from RDP, SSH, and the physical/adminbox screen.
- Panes keep running when the RDP client disconnects.
- Agent state (`working`, `blocked`, `done`, `idle`) is visible in one sidebar.
- Hermes can read panes, summarize status, and send approved input through Herdr's CLI/socket API.
