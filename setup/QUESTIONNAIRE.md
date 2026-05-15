# UAP Deployment Questionnaire

This is the source-of-truth list of questions to walk a new user/operator through when deploying UAP on a new VM or machine. The facilitator agent (see `CLAUDE.md` in this folder) asks each question conversationally and records answers in `answers.yaml`.

Defaults reflect UAP's reference build. They're the recommended starting point; the wizard should lead with them.

---

## Section 1 — Identity & branding

### Q1.1 Name of this OS
Default: **UAP**
Alternatives: any short, distinctive word.
Customizes: Plymouth splash title, README, suggested hostname.

### Q1.2 Tagline
Default: **out of this world**
Alternatives: any 2–5 word phrase.
Customizes: Plymouth subtitle, README intro.

### Q1.3 Logo source
Options:
- (a) Official Claude logomark (orange asterisk) — UAP default, fits the "AI-first OS" angle.
- (b) Upload a PNG — user provides path/file (square, transparent background recommended, 800×800 ideal).
- (c) Generate a text logo — facilitator renders the OS name in JetBrainsMono Nerd Font on the chosen background.
Customizes: `os/plymouth/logo.png`, `ai/desktop-entries/claude.png`, Claude `.desktop` entry icon.

### Q1.4 Color palette
Default: **Tokyo Night** (`#1a1b26` bg, `#7aa2f7` accent — already configured for i3, alacritty, rofi, Typora, GTK).
Alternatives: Dracula, Nord, Catppuccin, Gruvbox, custom hex.
Customizes: i3 config color block, alacritty `[colors]`, rofi theme, Typora theme selection, Plymouth background, GTK theme (Adwaita-dark by default; user can swap to a Catppuccin GTK theme etc.).

### Q1.5 Primary monospace font
Default: **JetBrainsMono Nerd Font**
Alternatives: FiraCode Nerd Font, CascadiaCode Nerd Font, IosevkaNF.
Customizes: alacritty, i3bar, rofi, Typora.

---

## Section 2 — Target machine

UAP installs in-place on whatever Linux box you're running the wizard on. Provisioning (creating a VM, running the Ubuntu installer, configuring the hypervisor) is the operator's job — by the time the wizard is asking these questions, the box already exists and `bootstrap.sh` has just run on it.

### Q2.1 Confirm: install UAP on this machine?
Default: **yes** — `bootstrap.sh` is running here, so this is the target.
Alternative: no — pause the wizard; UAP doesn't provision remote machines yet (see `setup/DESIGN-FOLLOWUPS.md`).
At wizard-start, detect this machine's specs (`nproc`, `free -h`, `df -h /`) and warn if below the recommended tier (4 vCPU / 8 GB / 40 GB — see `../README.md` Minimum specs). Don't ask for resource tier — observe.

---

## Section 3 — Network & remote access

### Q3.1 Primary remote-access path
Options:
- (a) **Tailscale** — recommended; works through NAT, encrypted, simple. Default.
- (b) WireGuard — self-hosted VPN.
- (c) ZeroTier.
- (d) Direct internet (port-forward + firewall) — only for hardened deployments.
Customizes: Phase 3 of runbook, firewall rules, `/etc/xrdp/xrdp.ini` listening interface.

### Q3.2 RDP listen scope
Default: **bind to Tailscale interface only** (recommended; xrdp only accepts connections from your tailnet).
Alternative: listen on all interfaces (less safe, only acceptable behind another firewall).
Customizes: xrdp `Address=` in `xrdp.ini`, ufw rules.

---

## Section 4 — User account

### Q4.1 Primary username
Default: **operator chooses**.
Customizes: created Linux user, all `/home/<user>/...` paths in the runbook get substituted.

### Q4.2 Multi-user or single-user?
Default: **single-user**.
Alternative: multi-user with shared/distinct workspaces — wizard will create per-user `~/workspace/` hubs.
Customizes: sesman policy, `/etc/skel/` templates.

### Q4.3 Auto-login on boot?
Default: **no** (require password). Recommended for security.
Alternative: yes — convenient for personal-only VMs behind Tailscale.
Customizes: `/etc/gdm3/custom.conf` or equivalent.

---

## Section 5 — Applications

### Q5.1 Browsers (multi-select)
Defaults: **Microsoft Edge** (work) + **Google Chrome** (AI browser automation).
Optional: Chromium (snap), Firefox (snap), Brave.
Customizes: Phase 4 install steps + sources.

### Q5.2 Markdown editor
Default: **Typora** (Tokyo Night theme + monospace-dark, both archived in `../os/typora-themes/`).
Alternatives: Obsidian, MarkText, VS Code with markdown extensions, none.
Customizes: Phase 4 install, theme deployment.

### Q5.3 Terminal-side tools (multi-select)
Defaults: **btop**, **bat**, **glow**.
Optional: htop, ripgrep, fd-find, tmux, fzf, jq, yq, neovim.
Customizes: Phase 4 apt install line.

### Q5.4 File manager
Default: **thunar** (lightweight, no extra DE deps).
Alternatives: nautilus (GNOME), dolphin (KDE), none.
Customizes: Phase 4 install, `$mod+n` keybinding target.

### Q5.5 Screenshot tool
Default: **flameshot** (already bound to `$mod+Shift+s` and `Print`).
Alternatives: scrot only, gnome-screenshot.
Customizes: i3 keybindings.

---

## Section 6 — Window manager preset

UAP is built around i3. Rather than five atomic config questions, pick one opinionated preset and tweak post-install if needed.

### Q6.1 i3 preset
Options:
- (a) **Standard UAP** (recommended). Mod1 (Alt), 10 workspaces, active-window title in the top bar, borderless windows (2px pixel border only). Default.
- (b) **macOS-flavor**. Mod4 (Super / Cmd) instead of Mod1 — leaves Alt free for in-app shortcuts. Otherwise identical to Standard.
- (c) **Minimalist**. Mod1, 4 workspaces, plain workspace numbers (no active-title daemon), borderless. Lower clutter and lower resource usage; good for older hardware or operators who want fewer moving parts.
Customizes: every variable in `os/i3/i3-config.tmpl` plus `wm.workspace_title_daemon` and `wm.workspace_count` in identity.yaml.

Post-install, individual settings (modifier key, workspace count, borders, daemon) can be changed by editing `~/uap.local/identity.yaml` and rerunning `apply.sh i3 workspace-title-daemon`. Operators who want a different window manager (sway, bspwm, awesome) should fork — the rest of UAP assumes i3.

---

## Section 7 — AI integration

### Q7.1 Install Claude Code?
Default: **yes** (the whole point of UAP).
Customizes: Claude Code install (separate from this runbook today — assumed already installed by operator).

### Q7.2 Autostart Claude on login?
Default: **yes** — fresh alacritty in `~/workspace/` running `claude --permission-mode=bypassPermissions` on every i3 startup.
Alternative: no — operator launches manually via `Mod1+c` or rofi entry.
Customizes: i3 `exec` line.

### Q7.3 Permission mode for the autostarted Claude
Default: **bypassPermissions** (matches the rest of UAP's AI-collaborator stance).
Alternative: default prompts. Recommended only for shared/multi-user deployments.
Customizes: Claude command-line flag.

### Q7.4 Enable remote-control at startup?
Default: **yes** — every Claude session is reachable from the mobile app immediately. Set via `~/.claude/settings.json: { "remoteControlAtStartup": true }`.
Customizes: Claude settings.

### Q7.5 Workspace hub folder name
Default: **`workspace`** (UAP convention).
Alternatives: `hub`, `work`, custom.
Customizes: directory name, i3 autostart `--working-directory`, all references.

### Q7.6 Subworkspaces inside the hub
Default: **create fresh subdirectories under `~/workspace/`** — name the project areas you want (e.g., `dev`, `ops`, `notes`, `clients`, whatever fits). The wizard creates the directories empty; the operator decides what goes in each. The `~/uap` framework repo is always symlinked in as `~/workspace/uap` since that's the only top-level folder UAP owns.
Alternative: **symlink existing top-level folders** (`~/ops/`, `~/dev/`, etc.) into `~/workspace/` — for operators migrating an existing layout where those folders already live at `~/`.

UAP is intentionally unopinionated about what *goes inside* each subworkspace — every operator works differently. If you want a folder-as-workflow pattern, see `references.md` for a link to one approach (ICM), but it's optional.

---

## Section 8 — Boot & theming

### Q8.1 Custom boot splash?
Default: **yes** — UAP logo on dark background (Plymouth script-theme).
Alternative: keep stock Ubuntu splash.
Customizes: Plymouth theme install.

### Q8.2 Wallpaper
Default: **a single Tokyo Night image** at `~/.config/i3/background`.
Alternative: solid color, slideshow (feh `--randomize`), user-supplied image.
Customizes: feh exec line in xinitrc.

### Q8.3 System-wide dark mode (GTK + Qt)?
Default: **yes** — Adwaita-dark for GTK, qt5gtk2 for Qt. So Typora/Edge/Chrome/thunar/flameshot menus are all dark.
Customizes: Phase 8.5 install + xinitrc env vars.

---

## Section 9 — Keyboard & locale

### Q9.1 Keyboard layout
Default: **us** (US English).
Alternatives: en-CA, en-GB, fr-CA, de, etc.
Customizes: `setxkbmap`, optional `/etc/xrdp/km-<LCID>.ini` for non-US RDP clients.

### Q9.2 RDP client setting reminder
The wizard should remind the operator: if RDP clients are Microsoft Remote Desktop (Android / iOS / Windows), toggle **"Use scancode input when available" → OFF** in the client to avoid punctuation mistranslation (see Known Issue F in the README).

---

## Section 10 — Operator profile

The answers here shape *how* the wizard facilitates the rest of the conversation — handholding level, whether to install learning aids, whether to warn about keyboard-driven defaults. They don't seed any folders or pipelines — UAP is intentionally unopinionated about what work the operator brings to the box.

### Q10.1 Linux terminal comfort
Options:
- (a) New — mostly used GUI Linux; the terminal is intimidating.
- (b) Some — knows `cd`, `ls`, edits config files with vim/nano occasionally.
- (c) Comfortable — daily terminal user, can troubleshoot.
- (d) Expert — sysadmin or dev professional.

If (a) or (b), the wizard installs **learning aids**: `tldr` (short manpages) and a curated `~/workspace/CHEATSHEET.md` covering UAP keybindings + common terminal commands. Skipped for (c)/(d) — they don't need the noise.

### Q10.2 Keyboard-driven workflow comfort
Options:
- (a) Prefer mouse / GUI — tiling WMs feel hostile.
- (b) Mixed — keyboard for code, mouse for navigation.
- (c) Comfortable — vim-style keybindings, curious about tiling WMs.
- (d) Power user — already using i3/sway/tmux.

If (a), the wizard flags a warning: UAP is keyboard-first; an operator who hates that may prefer GNOME/KDE atop the same Ubuntu base. The wizard can offer to install GNOME alongside i3 (or instead of it) and skip the keyboard-heavy parts of the desktop config if so.

---

## Section 11 — Deployment metadata (recorded automatically)

### Q11.1 Operator name / email
For the deployment record in `answers.yaml`.

### Q11.2 Deployment date
Recorded automatically.

### Q11.3 Notes
Free-form: anything specific about this deployment the operator wants to record.

---

## After the wizard

The facilitator agent should:

1. Save `answers.yaml` in this folder.
2. Apply customizations by walking `../README.md` phase by phase, substituting answers.
3. Mirror any newly-generated artifacts (custom logo, alternative themes, custom keybindings) back into the appropriate scope folder (`../os/`, `../ai/`, `../workflows/`) so the runbook reflects this deployment's choices, not just the framework defaults. This satisfies the standing rule that every system tweak is documented in `~/uap/`.
4. Commit the changes if the user has initialized `~/uap/` as a git repo.
