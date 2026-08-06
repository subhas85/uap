# Herdr

[Herdr](https://herdr.dev/) is UAP's preferred terminal/agent workspace manager: a tmux-like background server with workspaces, tabs, panes, agent-state detection, SSH/RDP-friendly reconnects, and a CLI/socket API that Hermes can inspect from Telegram.

## Install

Herdr is a first-class `apply.sh` component. One command installs and configures the whole surface:

```bash
~/uap/setup/apply.sh herdr
```

That does four things:

| Step | Result | Idempotent? |
|---|---|---|
| Binary | `~/.local/bin/herdr` from the upstream manifest, if not already present | yes — never re-downloads or updates an existing install |
| `config.toml` | this dir's `config.toml` → `~/.config/herdr/config.toml` | yes — identical file is a no-op |
| Plugins | `install-plugins.sh` installs the pinned set from `plugins.list` | yes — cached re-installs |
| sysmeter | `sysmeter.sh` → `~/.local/bin/herdr-sysmeter` + `herdr-sysmeter.service` enabled as a user unit | yes |

**The component never silently overwrites your `config.toml`.** Herdr rewrites parts of that file itself (onboarding state, plugin registry), so if the deployed file differs from the tracked one, `apply.sh` writes `~/.config/herdr/config.toml.uap-proposed` and warns instead. Diff and merge by hand, or force it:

```bash
~/uap/setup/apply.sh --force-herdr-config herdr   # keeps a .uap-bak of the old file
```

Everything below the binary step is **skipped with a warning if the installed Herdr is older than 0.7.4** (`HERDR_MIN_VERSION` in `apply.sh`) — the tracked config assumes the 0.7.4 "popup" pane type. Update Herdr first, then rerun.

After applying against a running server, pick up the config with `herdr server reload-config`.

### Binary only

The underlying install is just the upstream manifest, if you want it without the config layer:

```bash
curl -fsSL https://herdr.dev/install.sh | sh
```

The installer downloads the latest stable binary for the current Linux architecture from `https://herdr.dev/latest.json`. Future updates are managed by Herdr itself:

```bash
herdr update
herdr channel show
herdr channel set stable   # or preview
```

### Updating without losing panes/agents

`herdr update` **refuses to run from inside a Herdr pane** (`run herdr update outside herdr after detaching from the session`). Because the whole box lives inside one persistent session, detach first, or run the updater in a detached process with the `HERDR_*` env stripped:

```bash
setsid env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_SOCKET_PATH \
  bash -lc 'herdr update --handoff' >~/.config/herdr/update-handoff.log 2>&1 < /dev/null &
```

`--handoff` performs a **live handoff**: pane PTYs (and the agents running in them) survive the server swap when the protocol version is unchanged. Verify with `herdr --version` and `herdr workspace list`.

Gotcha observed 2026-07-21 (0.7.3 → 0.7.4): the handoff replaced the server's **plugin registry**, so plugins installed on the old binary stopped showing in `herdr plugin list`. The files stay on disk under `~/.config/herdr/plugins/github/`; just re-run `herdr plugin install <owner>/<repo>` (cached, instant) to re-register them on the new server. `install-plugins.sh` does this idempotently.

### Known upgrade hazards past 0.7.4

Two upstream changes make a jump from 0.7.4 more than a routine update — plan for both before running the handoff:

- **0.7.5 moves plugin state from per-session to global-per-user.** Installed/linked plugins and their enabled state are no longer isolated by Herdr session. Anything installed *inside a named session* on ≤0.7.4 must be installed or linked again afterwards. Re-running `apply.sh herdr` covers the pinned set.
- **0.8.0 bumps the wire protocol to 19.** A live `--handoff` only preserves pane PTYs when the protocol version is unchanged, so crossing this boundary means panes and the agents in them will not survive. Drain or checkpoint long-running agent sessions first.

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

See [`example-layout.md`](example-layout.md) for the workspace→project organization pattern and an example tab snapshot.

## Why UAP uses it

- Same persistent terminal/agent surface from RDP, SSH, and the physical/adminbox screen.
- Panes keep running when the RDP client disconnects.
- Agent state (`working`, `blocked`, `done`, `idle`) is visible in one sidebar.
- Hermes can read panes, summarize status, and send approved input through Herdr's CLI/socket API.

## Plugins

Herdr plugins are discovered from the GitHub topic `herdr-plugin` and installed with `herdr plugin install <owner>/<repo>`. The marketplace is **not reviewed by Herdr** — only install source-visible or checksum-verified plugins, and pin what we run here.

The plugin set is managed declaratively by **herdr-lazy** (see *Declarative management* below): `plugins.list` (intent) + `plugins.lock` (pinned commits) are the source of truth, both tracked in this dir. `install-plugins.sh` remains as a lazy-free fallback.

The UAP default set (requires Herdr ≥ 0.7.4). **Deliberately kept minimal** — the keybinding-launched panes (File Viewer, PR Tracker, Phin Board) were trialled and dropped; only the two passive **sidebar meters** earned their keep, plus the manager.

| Plugin | Repo | What it does | How to open |
|---|---|---|---|
| Claude Usage | `alejodelosrios/herdr-claude-usage` | Live Session % / Week % Claude quota, rendered in its own top **"Claude"** spaces entry (needs the `[ui.sidebar.spaces]` `$claude_usage` row). | Passive — daemon auto-armed via events. |
| Agent Usage | `senna-lang/herdr-agent-usage` (`usagebar`) | Per-agent **context %** + provider **rate-limit** rows in the **Agents** sidebar, plus toasts. | Passive — rows render from events. |
| herdr-lazy | `natori-hrj/herdr-lazy` | Declarative plugin manager + lockfile (manages the rows above). | `ctrl+b shift+l` (`herdr-lazy.manage`) |

Config (`[ui.sidebar.*]` rows + `[ui.toast]` + the one keybinding) lives in `~/.config/herdr/config.toml`; the tracked reference is **`uap/ai/herdr/config.toml`**. Apply changes live with `herdr server reload-config`.

**Removed 2026-07-21 (pane-only, unused):** `smarzban/herdr-file-viewer`, `Matovidlo/herdr-pr-tracker`, `phin-tech/herdr-phin-board`. **Also removed:** `aorumbayev/herdr-ctx` (needed Bun, absent; duplicated usagebar's `$context`). To bring any back: `herdr-lazy add <owner/repo> && herdr-lazy sync`, then re-add its keybinding.

**The top "Claude" space is intentional, not a stray.** `claude-usage` maintains a dedicated mini-space labelled *Claude*, pinned to the top of the spaces list, and reports its `$claude_usage` token *only* there (so the usage line renders once, not per-workspace). Do **not** close it — the daemon just recreates it via its `ensure` events. It renders **only** if `[ui.sidebar.spaces]` includes a `["$claude_usage"]` row (see `config.toml`); without that row the space exists but shows nothing. `herdr plugin action invoke stop --plugin unit1.claude-usage` removes the space and clears the row.

Remote/mobile plugins (`herdr-remote`, `collie`, etc.) are **redundant with Hermes/Telegram** — skip unless replacing Hermes.

## Declarative management (herdr-lazy)

herdr-lazy drives the herdr CLI to converge the machine to a declared plugin list. Its binary lives in the plugin dir; find config with `herdr plugin config-dir herdr-lazy`. The two files (both mirrored here as `plugins.list` / `plugins.lock`):

- `plugins.list` — desired set, one `owner/repo` per line (unpinned = tracks default branch).
- `plugins.lock` — commit each entry resolved to at last `sync` (from herdr's `source.resolved_commit`). This is the reproducible pin.

Run the binary directly (via `herdr plugin config-dir`/`HERDR_BIN_PATH`) so it does **not** spawn a stray "Claude" workspace the way `herdr plugin action invoke` does:

```bash
LZ="$(ls -d ~/.config/herdr/plugins/github/herdr-lazy-*)/target/release/herdr-lazy"
export HERDR_BIN_PATH="$(command -v herdr)"
"$LZ" list                 # show desired set
"$LZ" sync                 # install missing, rewrite lock from installed commits
"$LZ" sync --prune         # also uninstall anything not listed
"$LZ" update <owner/repo>  # move an unpinned entry to latest commit, then re-lock
```

Or drive it interactively from the manage pane: **`ctrl+b shift+l`** (`i`/`u`/`x`/`r` per row like lazy.nvim; `/` searches the marketplace; `a` adopts an already-installed plugin into the list).

**Reproduce on a rebuilt/new box** — copy the tracked lock in, then converge to it:

```bash
cp uap/ai/herdr/plugins.lock "$(herdr plugin config-dir herdr-lazy)/"
"$LZ" restore              # converge to the LOCK (exact commits), not the list
```

Caveat: herdr-lazy manages install/uninstall only — it does **not** track enable/disable state. `herdr-ctx` is in the list (so `--prune` won't remove it) but stays **disabled**; re-disable it by hand after a fresh `restore` if needed. Also: its README marks Linux install as unverified upstream, but `probe`/`list`/`sync` are confirmed working on this box (2026-07-21).

## CPU/RAM sidebar meter (sysmeter)

`sysmeter.sh` publishes a host **CPU% · RAM%** line into the sidebar, rendered on the claude-usage "Claude" mini-space right under the `Session/Week` usage line (added 2026-08-04).

- **Reporter:** `sysmeter.sh` — a ~5s loop reading `/proc/stat` + `/proc/meminfo`, pushing a `sys` token to the "Claude" space via `herdr workspace report-metadata --token sys=... --ttl-ms 15000`. It looks up the space by label each cycle, so it survives herdr restarts; the TTL clears the row if the reporter dies. Not polled by herdr — herdr tokens must be pushed, hence the loop. Tunable via `SYSMETER_INTERVAL` / `SYSMETER_TTL_MS`.
- **Render:** the `["$sys"]` row in `[ui.sidebar.spaces]` (see `config.toml`). Rows with no token are skipped, so it appears only on the "Claude" space. Depends on claude-usage being active (that plugin owns the space).
- **Autostart:** i3 runs it single-instance via `flock`, mirroring the `i3-workspace-title` daemon pattern:
  `exec_always --no-startup-id flock -n /tmp/sysmeter.lock bash ${HOME_DIR}/uap/ai/herdr/sysmeter.sh`
  (live `~/.config/i3/config` + template `os/i3/i3-config.tmpl`). Start by hand with the same `flock` line; the lock prevents duplicate reporters.
