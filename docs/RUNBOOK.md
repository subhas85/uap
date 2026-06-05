# UAP — full install runbook

> The phase-by-phase manual walkthrough behind UAP. The [README](../README.md) quick start (`bootstrap.sh` + wizard) is the fast path; this document is the source of truth for what each component does, the system-level steps `apply.sh` can't perform, and every known issue baked into the configs.

## Phase 1A — Hypervisor / VM (default path)

Create a VM on your hypervisor with at least:

- 4 vCPU, 8 GB RAM, 40 GB disk (see the Minimum specs table in the [README](../README.md#minimum-specs))
- One bridged or routed NIC
- Boot from `ubuntu-24.04.x-live-server-amd64.iso`

On Proxmox specifically: do NOT enable memory ballooning if you intend to set a fixed memory size — see Known Issues below.

## Phase 1B — Bare metal (alternative)

UAP is not VM-specific — nothing in the runbook depends on virtualization. To install on physical hardware:

- Burn `ubuntu-24.04.x-live-server-amd64.iso` to a USB stick (`dd`, Rufus, balenaEtcher).
- Boot the target machine, install Ubuntu Server normally, skip the snap server bundles.
- Make sure firmware for Wi-Fi / GPU / audio loads (server install usually handles this, but consumer hardware sometimes needs `apt install linux-firmware-extra` or vendor packages).
- For unattended AI-driven installs: build a custom autoinstall ISO (Ubuntu Server's `autoinstall.yaml` + `user-data`/`meta-data`), have the operator boot it once; the rest of this runbook resumes over SSH after first boot.

Skip Phase 1A entirely; the remaining phases are identical.

## Phase 2 — Install Ubuntu Server 24.04 LTS

Standard installation. When prompted:

- Profile: pick a username (this guide uses `<your-username>` as a placeholder — substitute your own)
- Install OpenSSH server: **yes**
- No featured server snaps (skip)

Reboot after install. Log in over SSH for the rest of the steps.

## Phase 3 — Network access (Tailscale)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Authenticate via the URL it prints. RDP from another Tailnet host will reach this VM by its Tailscale name.

## Phase 4 — Install all packages

```bash
sudo apt update && sudo apt full-upgrade -y

sudo apt install -y \
  xrdp xorgxrdp \
  i3 i3-wm i3status i3lock \
  alacritty rofi flameshot feh thunar \
  xdotool scrot \
  btop bat \
  vim \
  fonts-jetbrains-mono fonts-inconsolata \
  microsoft-edge-stable     # see note below if package not found

# Snap apps (browsers + glow markdown viewer)
sudo snap install chromium
sudo snap install firefox
sudo snap install glow
```

### WezTerm terminal

WezTerm is installed from the upstream GitHub `.deb` and configured by the `wezterm` component:

```bash
ver=20240203-110809-5046fc22
base="https://github.com/wez/wezterm/releases/download/$ver"
cd /tmp
curl -fLO "$base/wezterm-$ver.Ubuntu22.04.deb"
curl -fLO "$base/wezterm-$ver.Ubuntu22.04.deb.sha256"
sha256sum -c "wezterm-$ver.Ubuntu22.04.deb.sha256"
sudo apt install -y "./wezterm-$ver.Ubuntu22.04.deb"
~/uap/setup/apply.sh wezterm
```

If `microsoft-edge-stable` is not in the default repos:

```bash
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
echo "deb [signed-by=/usr/share/keyrings/microsoft.gpg arch=amd64] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list
sudo apt update && sudo apt install -y microsoft-edge-stable
```

### Google Chrome (used for AI browser automation)

```bash
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [signed-by=/usr/share/keyrings/google-chrome.gpg arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update && sudo apt install -y google-chrome-stable
```

### Typora (markdown editor)

```bash
curl -fsSL https://typora.io/linux/public-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/typora.gpg
echo "deb [signed-by=/usr/share/keyrings/typora.gpg] https://typora.io/linux ./" | sudo tee /etc/apt/sources.list.d/typora.list
sudo apt update && sudo apt install -y typora
```

`bat` is installed as `/usr/bin/batcat` on Ubuntu (binary name conflict). Optionally:

```bash
mkdir -p ~/.local/bin && ln -s /usr/bin/batcat ~/.local/bin/bat
```

### Microsoft 365 / Teams Phone admin tools

The `m365-admin-tools` component installs PowerShell from Microsoft's Ubuntu 24.04 apt repository and installs the `MicrosoftTeams` PowerShell module for the operator:

```bash
~/uap/setup/apply.sh m365-admin-tools
```

Keep elevated Azure CLI auth isolated from normal auth with a separate profile:

```bash
AZURE_CONFIG_DIR=~/.azure-elevated az login
AZURE_CONFIG_DIR=~/.azure-elevated az account show
```

Teams Phone inspection uses Teams PowerShell:

```powershell
Connect-MicrosoftTeams
Get-CsCallQueue
Get-CsAutoAttendant
Get-CsOnlineUser -Identity user@domain.com
```

## Phase 5 — JetBrainsMono Nerd Font

`fonts-jetbrains-mono` from apt provides the regular font, but the i3 / alacritty / rofi configs reference the **Nerd Font** patched variant. Install it:

```bash
mkdir -p ~/.local/share/fonts/JetBrainsMono
cd /tmp
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono/
fc-cache -fv
```

Verify: `fc-list | grep -i 'JetBrainsMono Nerd'` should print several entries.

## Phase 6 — Configure xrdp

Default xrdp puts you in a Xorg session. UAP wants it to launch i3 on connect, survive reconnects without stuck modifier keys, and tolerate non-US RDP locales. `setup/apply.sh` handles the file-deploy parts; a few system-level steps remain manual.

1. Render and install the xinitrc + xrdp components:
   ```bash
   ~/uap/setup/apply.sh xinitrc xrdp
   ```
   What this does (driven by `identity.xrdp.*` and `identity.locale.rdp_lcid`):
   - Renders `os/xinitrc/xinitrc.tmpl` → `~/.xinitrc` (mode 755) and symlinks `~/.xsession → ~/.xinitrc`. The X session execs i3 from here.
   - If `identity.xrdp.install_reconnectwm: true`, installs `os/xrdp/reconnectwm.sh` to `/etc/xrdp/reconnectwm.sh` (root-owned, 755). Releases stuck modifier keys after RDP KeyboardSync — see Known Issues B.
   - Sets `Policy=<identity.xrdp.sesman_policy>` in `/etc/xrdp/sesman.ini` (default `Default`: session per `<user, bpp>`, so the same user reattaches from any client size/resolution — the Windows-RDP single-session feel). NOTE: `UBD`'s "D" is **DisplaySize**, not depth — it spawns a *new* desktop per client resolution; don't use it unless you deliberately want per-resolution desktops. Pair `Default` with `max_bpp=24` in `xrdp.ini` to pin the only remaining variable (bpp) so it's effectively keyed on user alone.
   - Pins `max_bpp=<identity.xrdp.max_bpp>` (default `24`) in `/etc/xrdp/xrdp.ini` `[Globals]` (idempotent), so color depth — the one policy key that can't be disabled — stays constant and `Default` reattaches from any client.
   - If `identity.locale.rdp_lcid` is not `0x00000409` (US English) and `/etc/xrdp/km-<lcid>.ini` is missing, mirrors `/etc/xrdp/km-00000409.ini` to the right filename. Fixes `/`, `?`, `'`, `"` being mis-translated on English-Canada (`0x00001009`), English-UK (`0x00000809`), English-Australia (`0x00000c09`), etc. No xrdp restart needed; the next RDP connection picks it up.

2. Enable and start xrdp:
   ```bash
   sudo systemctl enable --now xrdp
   sudo systemctl restart xrdp-sesman   # picks up the Policy change; safe with users connected — running X sessions live in their own logind scopes (session-cN.scope) and survive the restart
   ```

3. Open the RDP port if a firewall is enabled:
   ```bash
   sudo ufw allow 3389/tcp || true
   ```

4. (Optional, security) Fix `/etc/xrdp/key.pem` permissions so xrdp can use TLS:
   ```bash
   sudo chmod 644 /etc/xrdp/key.pem
   ```

Diagnose locale/keymap issues via `sudo tail /var/log/xrdp.log` after a connect — look for `Cannot find keymap file /etc/xrdp/km-<LCID>.ini`.

## Phase 7 — Deploy i3 + app configs

Render and install the i3, alacritty, rofi, and typora-themes components in one go:

```bash
~/uap/setup/apply.sh i3 alacritty rofi typora-themes
```

What this does (templates are rendered using `identity.theme.*` and `identity.wm.*` — colors, mod key, font, workspace count):

- `os/i3/i3-config.tmpl` → `~/.config/i3/config` + `os/i3/i3status.conf.tmpl` → `~/.config/i3/i3status.conf`. `apply.sh` also sends `i3-msg reload` so the change applies to the running session.
- `os/alacritty/alacritty.toml.tmpl` → `~/.config/alacritty/alacritty.toml`.
- `os/rofi/tokyo-night.rasi.tmpl` → `~/.config/rofi/tokyo-night.rasi`.
- `os/typora-themes/*` (no `.tmpl` — copied verbatim) → `~/.config/Typora/themes/`.

Wallpaper: drop any 16:9 image at `~/.config/i3/background` (referenced by `feh --bg-fill` in `xinitrc`). If you don't, the line silently no-ops.

### Typora themes

Two installable themes ship in `os/typora-themes/`:

- **monospace** + **monospace-dark** — official Typora typewriter theme (uses Inconsolata for body text, PT Mono for code). The dark variant is the day-to-day default.
- **tokyo-night** + **tokyo-night+** — community Tokyo Night theme matching the rest of the desktop's color scheme (the `+` variant has richer syntax colors).

The monospace theme also needs **PT Mono**, which `apply.sh` does NOT install (PT Mono is not in apt — the apt-installed `fonts-inconsolata` covers Inconsolata):

```bash
mkdir -p ~/.local/share/fonts/PTMono
curl -fsSL "https://github.com/google/fonts/raw/main/ofl/ptmono/PTM55FT.ttf" \
  -o ~/.local/share/fonts/PTMono/PTM55FT.ttf
fc-cache -f
```

Then launch Typora once and select **Themes → Monospace Dark** (or **Tokyo Night** etc.). Typora stores the choice itself; no config edit needed.

For the typewriter feel, also enable **View → Typewriter Mode** (current line stays vertically centered as you type) and optionally **View → Focus Mode** (dims paragraphs other than the current one).

Sources: [typora/typora-monospace-theme](https://github.com/typora/typora-monospace-theme), [Aemiii91/typora-theme-tokyo-night](https://github.com/Aemiii91/typora-theme-tokyo-night).

## Phase 8 — Workspace-title daemon

The i3 config already references `~/.local/bin/i3-workspace-title`; this is what makes the focused window's title appear on the workspace button in the top bar.

```bash
~/uap/setup/apply.sh workspace-title-daemon
```

Installs `os/workspace-title-daemon/i3-workspace-title` (verbatim, mode 755) to `~/.local/bin/`. It auto-starts via `exec_always --no-startup-id flock -n /tmp/i3-workspace-title.lock ~/.local/bin/i3-workspace-title` in the rendered i3 config — `flock -n` makes it a singleton across i3 reloads.

## Phase 8.55 — Workspace hub (UAP standard)

UAP's standard for organizing user work is a single **workspace hub** at `~/workspace/` that holds symlinks to all real work folders, plus a top-level `CLAUDE.md` that acts as the ICM "Layer 0" routing the AI agent to the right subworkspace.

**Why a hub instead of `~/` directly:**
- `~/` contains `~/.ssh/`, `~/.config/`, browser profiles, `~/.claude.json`, etc. — none of which should be in an AI agent's casual scope, especially with `bypassPermissions` mode active.
- `~/workspace/` gives the agent a clean entry point that excludes dotfiles.
- It's git-trackable as a unit (the symlinks resolve naturally) — easy to replicate to a teammate or future VM.
- Symlinks (not folder moves) preserve all existing paths so nothing outside UAP breaks.

**Standard layout:**

```
~/workspace/
  CLAUDE.md          ← router (Layer 0): names each subworkspace and how to route tasks
  ops/      → ~/ops          team ops (meetings, tickets, runbooks)
  dev/      → ~/dev          code repos
    dev/dashboard/ → ~/dashboard   example: an in-house dashboard repo (lives under dev/ as a code repo)
  uap/      → ~/uap          this OS's runbook + configs
  <add more symlinks as new workspaces appear>
```

Sub-repos that are conceptually code (like `dashboard`) get symlinked under `~/dev/`, not at the top level of `~/workspace/`. Only top-level *workspaces* (ops, dev, uap) live at the hub root.

**Setup steps:**

The workspace hub is built from `identity.ai.workspace_hub_name` and `identity.ai.subworkspaces[]`:

```bash
~/uap/setup/apply.sh workspace-hub
```

This:
- Creates `~/<workspace_hub_name>/` (default `workspace`).
- For each entry in `identity.ai.subworkspaces[]`, symlinks `~/<name>` → `<hub>/<name>` (skipping any source dir that doesn't exist yet, with a warning).
- Renders `ai/workspace-hub/CLAUDE.md.tmpl` (the router / Layer 0) into the hub root. The template fills in `identity.os.name`, `identity.os.tagline`, and the subworkspaces list.

For code repos living elsewhere in `$HOME` that should appear under `~/dev/` (not at the hub root), add the symlink manually after `apply.sh`:

```bash
ln -sfn ~/dashboard ~/dev/dashboard
```

When a new top-level workspace appears later, add it to `identity.ai.subworkspaces[]` and re-run `apply.sh workspace-hub`. The "Out-of-scope" section in the rendered `CLAUDE.md` listing sensitive paths is intentionally template-baked — keep it as is.

## Phase 8.6 — Claude Code autostart

UAP is built around AI-collaborator workflows, so a Claude Code session opens automatically on every login (in remote-control mode and with permission prompts bypassed):

```
# In ~/.config/i3/config:
exec --no-startup-id alacritty --working-directory /home/<your-username>/workspace -e claude --permission-mode=bypassPermissions
```

Launching from `~/workspace/` (not `~/`) is the UAP standard so Claude loads the hub's `CLAUDE.md` (Layer 0) on startup and routes to subworkspaces from there.

Remote-control is enabled at startup via `~/.claude/settings.json`:

```json
{
  "remoteControlAtStartup": true,
  "skipDangerousModePermissionPrompt": true
}
```

Together these mean every login spawns an alacritty running `claude` that's:
- Bypassing tool-permission prompts (`--permission-mode=bypassPermissions`).
- Already exposing its session via remote-control — the URL appears in the Claude mobile app immediately and you can also reach it at `https://claude.ai/code/session_<id>`.

If you don't want the autostart on a specific login, kill it after start (`pkill -f 'claude --permission-mode'`) or remove the `exec` line.

**Manual launch:** two ways beyond the autostart.

1. **Keybinding `Mod1+c`** — same i3 config:
   ```
   bindsym $mod+c exec --no-startup-id alacritty --working-directory /home/<your-username>/workspace -e claude --permission-mode=bypassPermissions
   ```
2. **Rofi launcher (`Mod1+d` → "Claude (workspace)")** — a `.desktop` file under `~/.local/share/applications/` + the official Claude icon:
   ```bash
   ~/uap/setup/apply.sh desktop-entries
   ```
   This renders `ai/desktop-entries/claude-workspace.desktop.tmpl` (using `identity.operator.username`, `identity.ai.workspace_hub_name`, and `identity.ai.permission_mode`) into `~/.local/share/applications/`, copies `ai/desktop-entries/claude.png` to `~/.local/share/icons/claude/`, and runs `update-desktop-database`. It also pre-seeds the rofi drun cache (`~/.cache/rofi3.druncache`) so Claude appears first in the launcher immediately, before usage history accumulates. The rofi theme at `os/rofi/tokyo-night.rasi.tmpl` enables `sort: true` so frequency-based ordering takes over after that.

Both share the same command, so behavior is identical: alacritty in `~/workspace/`, Claude with `bypassPermissions` and remote-control on.

## Phase 8.65 — Hermes Agent (Telegram surface, recommended)

UAP's recommended way to reach the operator's assistant from a phone is [Hermes Agent](https://hermes-agent.nousresearch.com/) (Nous Research, MIT-licensed) running on Telegram. Hermes is treated as a second surface of the same assistant Claude Code presents in the terminal — not a separate persona. It runs as a systemd service, talks to a bot you create in @BotFather, and shares Claude Code's knowledge layer on this machine: identity in `~/.hermes/SOUL.md`, bounded operator profile + environment memory in `~/.hermes/memories/`, and the same project-context router (`~/workspace/CLAUDE.md`) discovered from the gateway's working directory. The result: you can switch between the terminal Claude session and the Telegram bot without re-explaining who you are, what UAP is, or what you're working on.

```bash
~/uap/ai/hermes-agent/  # install + configure narrative, drop-in, and source-of-truth copies of SOUL.md, USER.md, MEMORY.md
```

Install is currently manual (not yet wired into `apply.sh`); see `~/uap/ai/hermes-agent/README.md` for the step-by-step. The critical UAP-specific piece is the systemd drop-in at `/etc/systemd/system/hermes-gateway.service.d/uap-override.conf` that sets `WorkingDirectory=/home/<user>/workspace` — survives `hermes gateway install --system` regenerating the main unit and ensures every Telegram conversation auto-loads the workspace-hub `CLAUDE.md`.

## Phase 8.5 — System-wide dark mode (GTK + Qt)

i3 doesn't bring a desktop environment, so GTK and Qt apps default to light themes (you'll see white menu bars in Typora, Thunar, Edge, Chrome, flameshot, etc.). Make them all dark:

```bash
sudo apt install -y gnome-themes-extra qt5-style-plugins
~/uap/setup/apply.sh gtk-theme
```

`apply.sh gtk-theme` renders and installs `~/.config/gtk-{3.0,4.0}/settings.ini` from `os/gtk-theme/` templates (driven by `identity.theme.gtk_theme`), then runs `gsettings set ... color-scheme 'prefer-dark'` and `gsettings set ... gtk-theme <identity.theme.gtk_theme>` for GNOME-aware apps.

The `xinitrc` deployed in Phase 6 already sets these env vars so they propagate to all apps started from i3:

```sh
export GTK_THEME=Adwaita:dark            # GTK 2 / Electron menus
export QT_STYLE_OVERRIDE=Adwaita-Dark    # Qt apps (e.g. flameshot)
export QT_QPA_PLATFORMTHEME=gtk2         # Qt → follow GTK theme via qt5-gtk2-platformtheme
```

Apps already running before this change (most importantly Typora and Edge) need to be restarted to pick up the dark theme. `pkill typora` then relaunch — same for any open browsers.

## Phase 8.7 — Plymouth boot splash

Replace the default Ubuntu splash with the UAP logo on a Tokyo Night background. Only visible on the hypervisor console / bare-metal display during boot (you won't see it via RDP since RDP only connects after boot finishes), but it brands the OS for anyone who does see the console.

```bash
sudo apt install -y plymouth-label   # silences a label-pango warning during initramfs build
~/uap/setup/apply.sh plymouth
```

`apply.sh plymouth` renders `os/plymouth/uap.plymouth.tmpl` and `os/plymouth/uap.script.tmpl` (renamed to match `identity.os.name_lower` — e.g. `myos.plymouth` if you re-themed), installs them along with `logo.png` into `/usr/share/plymouth/themes/<name_lower>/`, runs `update-alternatives` to point `default.plymouth` at the new theme, then `update-initramfs -u` to bake it in.

To use a custom logo: drop a `logo.png` (transparent background recommended, ~800×300) into `~/uap.local/`, set `assets.logo: logo.png` in your `identity.yaml`, and re-run `apply.sh plymouth`.

## Phase 9 — First connect

From a remote machine on the same Tailnet, RDP to this VM (`mstsc`, Remmina, etc.). On login you should see:

- Tokyo Night-themed i3 with the bar at the top
- Workspaces labeled `1`, `2`, … with the active one prefixed by its window title
- `Mod1+Return` (Alt+Enter) opens alacritty
- `Mod1+d` opens rofi launcher (`drun`) — includes "Claude (workspace)" entry
- `Mod1+c` opens a fresh Claude Code session in `~/workspace/`
- `Mod1+n` opens thunar
- `Mod1+Shift+Return` opens firefox
- `Print` or `Mod1+Shift+s` opens flameshot
- `Mod1+1`..`9`,`0` switches workspaces; `Mod1+Shift+...` moves windows
- `Mod1+u` grows the active tiled window to ~75% in whichever split direction has a neighbor (one-shot resize; stays tiled)

If the bar is empty or the title doesn't update on focus change, check `~/.local/bin/i3-workspace-title` is running and that `i3 --get-socketpath` returns a path.

---

## Known issues & gotchas

These are all real things that have hit this setup. The fixes are baked into the rendered configs and `apply.sh`'s install hooks, but you'll re-encounter them if you deviate.

### A. Alt+Enter "could not be successfully run"

i3-nagbar fires when an `exec` command's child exits non-zero quickly. An earlier version of the config wrapped the terminal launch in `exec sh -c 'if [ -n "$X2GO_SESSION" ]; then xterm; else alacritty; fi'`. The same string ran fine when invoked directly from a shell, but i3's exec/SIGCHLD path tripped the nagbar. Fix: bind `Mod1+Return` to a plain command (`exec --no-startup-id alacritty`) or to an external shell script — never inline `sh -c` with conditionals in a `bindsym` line.

### B. Alt+number bindings stop working after RDP reconnect

Microsoft RDP sends KeyboardSync PDUs on reconnect. On this xrdp+i3 stack, that sometimes leaves `ISO_Level5_Shift` (mapped to Mod3) stuck in pressed state. With Mod3 held, `Alt+1` becomes `Alt+ISO_Level5_Shift+1` and i3 won't fire its binding. Symptoms: workspace switch shortcuts silently die after a reconnect; a fresh login works fine.

Fix: `/etc/xrdp/reconnectwm.sh` (deployed by `apply.sh xrdp` in Phase 6 when `identity.xrdp.install_reconnectwm: true`) calls `xdotool keyup` for all common modifiers on every reconnect. Diagnose with `xinput test-xi2 --root` and look for `modifiers: base 0x20`; or compare `xdotool key alt+1` (broken) against `xdotool key --clearmodifiers alt+1` (works) to confirm the stuck-modifier theory.

### C. Black screen on RDP reconnect (chansrv socket held by stale xrdp)

Symptom: new RDP connection shows black screen, xrdp logs show `xrdp_mm_chansrv_connect: connect failed trying again...`. Cause: a previous xrdp child (from an unclean disconnect — sleep, network swap) still holds `xrdp_chansrv_socket_<DISPLAY>`.

Fix: `sudo lsof -p <chansrv-pid> | grep chansrv_socket` to find the stale child, then `sudo kill <stale-xrdp-pid>` — kill ONLY that specific child PID, not the whole xrdp service. The chansrv socket returns to LISTEN and new connects succeed.

### D. xrdp keymap warning ("local keymap file ... doesn't match built in keymap")

Cosmetic. The `.km` file works; removing it breaks key translation. Leave it alone.

### E. Non-US English RDP clients can't type `/` and a few other punctuation keys

xrdp ships only a handful of keymap files (`/etc/xrdp/km-*.ini`). If the Windows RDP client reports a locale not in that set (e.g. English-Canada `0x00001009`), xrdp falls back to US English imperfectly and a few keys including `/` get mis-translated. Fix: copy `km-00000409.ini` to `km-<your-locale>.ini`. `apply.sh xrdp` does this automatically when `identity.locale.rdp_lcid` is set to a non-US locale. See Phase 6.

### F. Punctuation keys (`/`, `?`, `'`, `"`, etc.) arrive as wrong characters on Microsoft Remote Desktop clients

Symptom: typing `/` produces `#`, `'` produces something else, etc. over RDP from Microsoft Remote Desktop on Android (and possibly mstsc on Windows). xdotool injection of `/` directly on the X server works fine, proving the bug is xrdp-side, not X-side.

Root cause: the Microsoft RD client defaults to **scancode mode**, which sends raw key scan codes. xrdp 0.9.24 looks up these scancodes in `/etc/xrdp/km-<LCID>.ini`. When the client reports a non-US English locale (e.g. `0x00001009` English-Canada) and no exact keymap file exists, xrdp falls back to the US keymap — but the client's *physical key layout* expectations may not match US, so punctuation arrives garbled.

**Fix (client-side toggle, no server change needed):** in the Microsoft Remote Desktop app, turn OFF "Use scancode input when available". This makes the client send each character as a Unicode event, which xrdp 0.9.24 handles correctly regardless of LCID/keymap.

- **Android:** Tap **☰ menu → General → "Use scancode input when available" → OFF**
- **iOS / macOS / Windows mstsc:** equivalent setting in the app's general/keyboard preferences. Look for "scancode" or "keyboard mode".

The xrdp 0.10+ upgrade (with better keymap handling) would also fix the underlying issue but isn't in Ubuntu 24.04 repos; see [neutrinolabs/xrdp#3339](https://github.com/neutrinolabs/xrdp/discussions/3339).

### G. xrdp-sesman creates a new session instead of reattaching after `xrdp.service` restart

Symptom: reconnecting from a client whose window size (or color depth) differs from the running session lands you on a fresh blank `:11` Xorg desktop instead of reattaching to the `:10` session you had before. The old session keeps running headless, but its windows are stranded. Enough of these stack up and `MaxSessions` jams new logins.

Root cause: `Policy=UBD` keys a session on `<user, bpp, DisplaySize>` — the "D" is **DisplaySize (initial resolution)**, NOT depth. A differently-sized client can't match the existing session, so sesman allocates a new one. (Per `man 5 sesman.ini`: `Default` = `<user, bpp>`; `UBD` = `<user, bpp, DisplaySize>`. User and BitPerPixel can never be turned off.)

Fix: set `Policy=Default` in `/etc/xrdp/sesman.ini` (session per `<user, bpp>` — resolution-independent) and `systemctl restart xrdp-sesman`. Existing X sessions survive the restart (separate logind scopes). For true single-desktop-from-any-client, also pin `max_bpp=24` in `xrdp.ini [Globals]` so bpp can't vary either. `apply.sh xrdp` writes the policy in-place from `identity.xrdp.sesman_policy` (default `Default`). See Phase 6.

Recovery when it happens: any Claude Code sessions in the stranded `:10` are still reachable via the Claude mobile app (because of `remoteControlAtStartup`); other windows are lost unless you can SSH in and find another way to access them.

### H. Proxmox memory ballooning

On Proxmox, set the VM's memory ballooning *off* if you allocate a specific RAM size. With ballooning on, the displayed "memory" metric is the balloon size, which makes monitoring confusing and can squeeze the VM under host pressure.

### I. Focused-window border doesn't show on Alacritty / WezTerm

Symptom: the `client.focused` highlight (the colored border on the active window) paints correctly on browsers, Thunar, etc., but **not** on Alacritty or WezTerm — those windows show no border even when focused.

Root cause: both terminals request no decorations (Alacritty's `decorations = "none"`, WezTerm similarly), which sets the Motif `_MOTIF_WM_HINTS` "no decorations" flag. Modern i3 honors that hint by giving the window `border none` — so there is no border surface for the focus color to paint. Confirm with `i3-msg -t get_tree | grep -i border` (focused terminal shows `"border": "none"`).

Fix (baked into the rendered i3 config): force a real pixel border on those classes so the highlight has something to draw on —

```
for_window [class="Alacritty"] border pixel 3
for_window [class="org.wezfurlong.wezterm"] border pixel 3
```

`for_window` only fires on window *creation*, so it covers every terminal opened after the config loads (including all windows after a relogin). To fix terminals already open without relaunching: `i3-msg '[class="Alacritty"] border pixel 3'`.

---

## Known issues — RDP reconnect bugs (auto-fixed by watchdog)

xrdp 0.9.x has three reconnect bugs that affect users running stricter session-reattach policies (`Policy=U` or `Policy=UB`). UAP ships an optional `xrdp-watchdog` that auto-detects and remediates them. Defaults to **auto** — enabled when the policy is `U`/`UB`, disabled on the conservative `UBD` default.

### The bugs

1. **Black screen on reconnect** — a stale xrdp child from an unclean disconnect holds the chansrv socket; new connections see black until the stale child is killed.
2. **chansrv missing/defunct** — `xrdp-chansrv` dies mid-session without a parent respawn; clipboard/audio/drive redirection silently stop working.
3. **Clipboard desync (cliprdr)** — chansrv's cliprdr channel state corrupts on disconnect; new mstsc connect inherits broken state. Fixing requires chansrv restart **plus** the operator must disconnect + reconnect mstsc for the cliprdr handshake to redo.

### Identity toggles

```yaml
# ~/uap.local/identity.yaml
xrdp:
  install_watchdog: auto                  # true | false | auto
  watchdog_interval_seconds: 30
  watchdog_clipboard_active_probe: false  # opt-in active clipboard probe
  tcp_keepalive: true                     # patches xrdp.ini [Globals]
```

### Inspect / control

```bash
systemctl status xrdp-watchdog.timer
journalctl -u xrdp-watchdog -f
xrdp-watchdog --check       # dry-run diagnostics
xrdp-watchdog --explain     # dump current xrdp/chansrv/display state
```

### Disable

Set `install_watchdog: false` in `~/uap.local/identity.yaml` and rerun `~/uap/setup/apply.sh`. The watchdog and its timer will be cleanly removed.

### Design rationale

See `docs/specs/2026-05-23-xrdp-watchdogs-design.md`.

---

## Per-user state that is NOT in this folder

These are intentionally outside the runbook and need to be redone manually:

- Tailscale auth (one-time login URL)
- Microsoft Edge profile sync
- Snap auth (firefox / chromium login)
- SSH keys, dotfiles for shells, git config, etc.
- Any Claude Code / API tokens

---

## Verification checklist

After deploy, confirm in this order:

1. `systemctl is-active xrdp` → `active`
2. RDP from another host succeeds and lands on i3
3. `Mod1+Return` opens alacritty
4. Top bar shows workspace numbers; active one shows `N: <window title>`
5. `pgrep -f i3-workspace-title` returns one PID
6. `cat /etc/xrdp/reconnectwm.sh` matches `os/xrdp/reconnectwm.sh`
7. `sudo update-alternatives --display default.plymouth` shows the UAP theme as the active link
8. `systemctl is-active hermes-gateway` → `active` and `sudo readlink /proc/$(systemctl show -p MainPID --value hermes-gateway)/cwd` prints `/home/<user>/workspace`
