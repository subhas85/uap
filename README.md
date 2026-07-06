# UAP — an AI-collaborator workstation framework

> *out of this world*

![UAP — a dark, keyboard-driven Ubuntu workstation you RDP into, with an AI agent in the session: i3 tiling desktop showing system-monitor graphs and AI coding-assistant terminals in the Tokyo Night theme](branding/hero2.png)

UAP turns a fresh Ubuntu Server install into a quiet, dark, keyboard-driven workstation you log into remotely — and that has an AI agent in the session with you from the first keystroke. Open source, MIT-licensed, parameterized so any operator can fork it and stand up an identical machine in minutes.

**What you actually get:**

- Ubuntu Server 24.04 LTS + i3 + xrdp (you RDP in from your laptop or phone, you don't sit at the box)
- Tokyo Night theme across the whole stack (i3 bar, WezTerm, alacritty, rofi, Typora, GTK apps, the boot splash)
- [Herdr](https://herdr.dev/) as the main terminal/agent window: a persistent tmux-like workspace you can reach from RDP, SSH, or the physical/adminbox screen, with an Alt+d launcher entry for the shared session
- Claude Code installed and auto-starting in a `~/workspace/` hub, with an Alt+d launcher entry for a fresh Claude Code session and four built-in permission tiers (`personal-lab`, `engineer`, `staff`, `production-admin`)
- Optional second surface for the same assistant on Telegram via [Hermes Agent](https://hermes-agent.nousresearch.com/) (recommended), sharing the workspace-hub knowledge layer with Claude Code and Herdr so you can jump between terminal and phone without re-explaining context
- Optional Agent Reach layer for read/search access to webpages, YouTube transcripts, GitHub, RSS/Atom, Exa, V2EX, and basic Bilibili — with cookie-backed social channels kept off by default
- The toolchain a dev needs out of the box: Edge, Chrome, btop, bat, glow, Typora, git, build essentials

**What's different about it:**

- **AI-collaborator first.** Terminal autostart, workspace hub, permission-tier `~/.claude/settings.json`s are designed around having a Claude session in the room with you — not bolted on after the fact.
- **Identity-driven & reproducible.** Everything that makes a machine *yours* (hostname, theme, `components_enabled`, operator email) lives in `~/uap.local/identity.yaml`, not in this repo. Fork → set identity → `apply.sh`. Same identity on another machine = the same workstation.
- **Unopinionated about what work you bring.** UAP wires the box for AI-collaborator use; what you put in `~/workspace/` is up to you. If you want a folder-as-workflow methodology, [`setup/references.md`](setup/references.md) links to one approach (ICM), but it's optional.

Working today. PRs and issues welcome. See [`setup/DESIGN.md`](setup/DESIGN.md) for architecture, [`CONTRIBUTING.md`](CONTRIBUTING.md) to contribute.

## How UAP is meant to be used

UAP is an **always-on machine you reach remotely** — not a daily-driver laptop OS. Run it in a VM or on a dedicated box that stays powered on, put Ubuntu Server on it, and RDP/SSH in from whatever you're holding. Installing it on bare-metal hardware you carry around defeats the point: the whole model assumes the box is sitting somewhere reliable while you come and go.

It's also **deliberately minimal**. There's no app dock or hand-holding — i3 is keyboard-driven, and you learn the shortcuts to drive it. That's the trade: a few hours of muscle memory buys a machine that then gets out of your way.

**Herdr is the main terminal surface.** UAP treats Herdr as the persistent window into terminals and agents: one Herdr session can be viewed over RDP, from an SSH terminal, or at the adminbox itself, and panes keep running while clients disconnect. Launch it from Alt+d as **Herdr (terminal workspace)**; it attaches in `~/workspace/` so fresh panes inherit the same shared context.

**Claude Code is the main driver.** You don't open an editor and *then* maybe ask an AI for help — you start a Claude session and work through it: kicking off sessions, doing the serious work, steering from the terminal. Sessions autostart with remote control on, so you can pick up exactly where you left off after a disconnect, and monitor or redirect a long-running task from your phone as you step away from the machine.

**Hermes is your second surface and second agent.** It's the same assistant reached over a chat app — configurable for Telegram, Microsoft Teams, Discord, or wherever your team already lives. In day-to-day use it's mostly for checking Herdr/agent status, launching a fresh terminal, diagnosing the machine, or just having a lightweight second agent on the system for an extra pair of hands while the main session is busy.

**Other ways people run it:**

- **A homelab / infrastructure command center** — an always-reachable box that already knows your environment, for running diagnostics, restarting services, and poking at the network.
- **A long-task runner** — kick off a build, migration, or research run, walk away, and watch or redirect it from your phone.
- **On-call / incident triage** — Hermes on Teams or Discord as the front door: pull logs, check service health, or open a terminal the moment an alert lands.
- **A shared, persistent workspace** — runbooks, notes, and project context that both Claude Code and Hermes read, so nothing has to be re-explained between sessions or across surfaces.
- **Scheduled agent routines** — recurring overnight jobs (reports, housekeeping, health checks) that only make sense on a machine that's always up.

## Quick Start

You have a fresh **Ubuntu Server 24.04 LTS** install (VM or bare metal) reachable over SSH or local console. UAP turns it into your AI-collaborator workstation.

**One-liner from the public repo:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/subhas85/uap/main/bootstrap.sh)
```

**Or, clone first** (recommended — lets you inspect what you're about to run, and the repo ends up at `~/uap` where the rest of the framework expects it):

```bash
git clone https://github.com/subhas85/uap.git ~/uap
bash ~/uap/bootstrap.sh
```

**Pointing an AI agent at it:** Once you've SSHed into the box, install Claude Code (`curl -fsSL https://claude.ai/install.sh | bash`), launch Claude from your home directory, and tell it: *"This is a fresh Ubuntu Server 24.04. Clone github.com/subhas85/uap into ~/uap, run bootstrap.sh, and help me through the wizard it launches."* The agent prepares the box and hands you off to the wizard, where it can continue helping you answer questions.

What `bootstrap.sh` does:

1. Sanity-checks the OS, refuses root.
2. Installs minimal apt prereqs (`git`, `curl`, `ca-certificates`).
3. Installs the Claude Code CLI (`curl https://claude.ai/install.sh | bash`) and persists `~/.local/bin` on `PATH` for future shells.
4. Ensures the UAP repo is at `~/uap/` (clones from `REPO_URL` if not).
5. Launches `claude` in `~/uap/setup/` — at which point the **deployment wizard** takes over.

The wizard offers two paths:

- **Simple** (recommended for first-timers) — one question: which of four built-in profiles to install (`personal-lab`, `engineer`, `staff`, `production-admin`). The wizard auto-detects your username and hostname, asks for your email, copies the chosen profile to `~/uap.local/identity.yaml`, and runs `apply.sh`. ~30 seconds. To customize anything after install, edit `~/uap.local/identity.yaml` and rerun `apply.sh`.
- **Advanced** — walks the full `setup/QUESTIONNAIRE.md` so you can pick each piece (browsers, modifier key, workspace count, theme, etc.). Use this when you want to deviate from defaults during install rather than after.

Once the wizard finishes, RDP to the box from your laptop or phone over your tailnet and you should be on the UAP desktop.



## Minimum specs

| Tier | CPU | RAM | Disk | Real-world feel |
|---|---|---|---|---|
| Absolute min | 2 vCPU | 2 GB | 25 GB | Boots and RDP works; browsers swap heavily |
| Comfortable | 2 vCPU | 4 GB | 30 GB | Single browser, terminal, Typora — fine for sysadmin work |
| **Recommended** | 4 vCPU | 8 GB | 40 GB | Edge + Chrome both running, multiple terminals, Claude Code happy |
| Reference build | 4–8 vCPU | 16 GB | 60 GB+ | Headroom for AI tooling, containers, many tabs |

Browsers (especially Chrome with AI browser-automation extensions) are the dominant RAM consumer; if you'll use UAP as an AI-collaborator workstation, plan for 8 GB minimum.

## How AI-driven installs work

UAP's automation starts once Ubuntu Server is running and reachable. **Provisioning the VM (or burning the ISO for bare-metal) is the operator's job today** — install Ubuntu Server 24.04 LTS via your hypervisor's normal flow or a USB stick, get network access, then point an AI agent at this repo. From that moment forward the agent drives everything: clones the repo, runs `bootstrap.sh`, walks you through the wizard, and applies the result.

Future work — fully hands-off provisioning from a hypervisor API (e.g., Proxmox `pvesh` + cloud-init autoinstall) is on the roadmap but not in this release. If you want to contribute that piece, see `CONTRIBUTING.md`.

## What you get

- Ubuntu Server 24.04 LTS as the base
- xrdp + xorgxrdp for RDP access (Tailscale-friendly)
- i3 window manager (Tokyo Night theme, JetBrainsMono Nerd Font)
- [Herdr](https://herdr.dev/) terminal workspace manager: persistent panes/agents across RDP and SSH, with an Alt+d launcher entry for `Herdr (terminal workspace)`
- WezTerm + Alacritty terminals, rofi launcher, flameshot screenshots, feh wallpaper, thunar file manager
- Browsers: Microsoft Edge, Google Chrome, Chromium (snap), Firefox (snap)
- Markdown editor: Typora (with Tokyo Night theme installed)
- Terminal tools: btop, bat, glow (markdown viewer)
- A small daemon that puts the active window title next to the workspace number on the i3 top bar
- System-wide dark mode (Adwaita-dark for GTK apps; Qt apps follow GTK)
- Custom Plymouth boot splash (UAP logo on Tokyo Night background — visible on hypervisor console / bare-metal display)
- **Optional Telegram surface:** [Hermes Agent](https://hermes-agent.nousresearch.com/) (Nous Research, MIT) is the recommended way to reach the same assistant from your phone. Hermes runs as a systemd service, shares `~/workspace/CLAUDE.md` and `~/.hermes/SOUL.md` + memories with Claude Code, and is documented as a UAP component at `ai/hermes-agent/`.
- **Optional agent reach layer:** [Agent Reach](https://github.com/Panniantong/Agent-Reach) adds read/search access to external content sources (web pages, YouTube subtitles, GitHub, RSS, Exa search, V2EX, basic Bilibili) for Hermes/Claude workflows. UAP documents the core install and safety posture at `ai/agent-reach/`; cookie-backed social channels are not enabled by default.
- Optional admin-tooling components you can swap for your own — the bundled example, `m365-admin-tools`, installs PowerShell + the `MicrosoftTeams` module for operators who manage a Microsoft 365 tenant; drop it if you don't.

## Layout of this folder

```
bootstrap.sh                    # kickstart entry point — installs Claude, launches wizard
setup/                          # deployment engine
  QUESTIONNAIRE.md              # source-of-truth list of questions for a new operator
  apply.sh                      # renders templates from identity.yaml and installs each component
  answers.example.yaml          # shape of the identity file (~/uap.local/identity.yaml)
  DESIGN.md                     # design notes for the deployment system
  references.md                 # links to ICM paper, upstream docs, known issues
profiles/                       # pre-canned identity.yaml files (skip the wizard if one fits)
  personal-lab.yaml             # bypass allowed; isolated experiments
  engineer.yaml                 # prompt before tool use; daily work with some sensitive context
  staff.yaml                    # prompts on, no concierge / remote-control; non-technical users
  production-admin.yaml         # prompts on, no autostart; high-stakes access (servers, cloud tenants, client data)
os/                             # system chrome — what Ubuntu looks like
  i3/, alacritty/, wezterm/, rofi/, xinitrc/, typora-themes/
  gtk-theme/, plymouth/, xrdp/, workspace-title-daemon/
  m365-admin-tools/             # PowerShell + Teams Phone admin module
ai/                             # AI-assistant-facing pieces
  herdr/                        # Persistent terminal/agent workspace manager
  workspace-hub/                # ~/workspace/CLAUDE.md router template (ICM Layer 0)
  desktop-entries/              # rofi launcher + icons for Herdr and "Claude (workspace)"
  hermes-agent/                 # Optional Telegram surface — install + SOUL.md / USER.md / MEMORY.md / systemd drop-in
  agent-reach/                  # Optional read/search capability layer for external content sources
workflows/                      # reusable workflow patterns (each with its own CLAUDE.md)
  dev/, helpdesk/, incidents/, requirements/
```

Files ending in `.tmpl` under `os/`, `ai/`, and `workflows/` are envsubst templates rendered by `setup/apply.sh` from `~/uap.local/identity.yaml`. Files without `.tmpl` are copied verbatim. See `setup/DESIGN.md` for the deployment contract.

## How it works, in one minute

```
fork → set identity.yaml → apply.sh → RDP in
```

1. **One identity file.** Everything that makes a machine yours — hostname, theme, which components to install, operator email — lives in `~/uap.local/identity.yaml`, outside this repo. Pick a profile or answer the wizard.
2. **`apply.sh` renders + installs components.** Each piece of the desktop (`i3`, `wezterm`, `rofi`, `xrdp`, `gtk-theme`, `herdr`, `workspace-hub`, …) is a self-contained component. `apply.sh` renders its templates from your identity and installs it. Run all of them, or one at a time.
3. **RDP in.** From your laptop or phone over your tailnet, you land on the Tokyo Night desktop with a Claude Code session already open in `~/workspace/`.

Same `identity.yaml` on another box = the same workstation. That reproducibility — not the apt list — is the point.

## Full install runbook

The quick start above is the fast path. If you want to understand or run the install **phase by phase** — provisioning, package install, xrdp tuning, each component, and every known issue baked into the configs — see **[`docs/RUNBOOK.md`](docs/RUNBOOK.md)**.

- Architecture & the `identity.yaml` schema → [`setup/DESIGN.md`](setup/DESIGN.md)
- Contributing → [`CONTRIBUTING.md`](CONTRIBUTING.md)
- ICM (the optional folder-as-workflow methodology) & upstream docs → [`setup/references.md`](setup/references.md)

## The name

"UAP" — and the UFO motif running through the branding — is a nod to Eddy Fasthouse.

