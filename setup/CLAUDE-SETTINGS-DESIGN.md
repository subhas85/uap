# Claude Code settings deployment — design

Sibling to `DESIGN.md`. Covers how UAP deploys Claude Code permission settings (`~/.claude/settings.json` + a per-workspace overlay) keyed off the active profile's permission tier.

> **⚠️ Correction (2026-07-27):** File-path denies must use `Edit(path)` **only**. `Edit` rules cover every file-writing tool (Write, Edit, NotebookEdit); `Write(path)` deny/ask rules are **not** enforced by the file-permission engine and make Claude Code warn at startup. The JSON blocks below still show the old `Edit`+`Write` pairs for illustration — the **authoritative** templates in `ai/claude-settings/*.settings.json.tmpl` have had the `Write(path)` halves removed. `Write(**)` in *allow* lists is fine (it governs the Write tool, not a path).

## Why

Today the four UAP profiles (`personal-lab`, `engineer`, `staff`, `production-admin`) differ on five fields under `ai.*` of `identity.yaml` — autostart, permission mode, remote control, concierge. That covers the **runtime mode** of Claude Code but does nothing about **what tools Claude is allowed to call** once a session is running. Without a permission settings layer:

- `engineer` users get prompted on every routine `git status`, even though "default mode" is fine for that tier in spirit.
- `production-admin` users have no actual restrictions beyond the operator's discipline.
- `personal-lab` runs in `bypassPermissions`, but the **deny** rules that survive bypass (private-key writes, pipe-to-shell from internet) are unused.

This design adds a `claude-settings` component that renders and installs the right `settings.json` for the active profile.

## Architecture

### New component: `ai/claude-settings/`

```
ai/claude-settings/
  personal-lab.settings.json.tmpl
  engineer.settings.json.tmpl
  staff.settings.json.tmpl
  production-admin.settings.json.tmpl
  workspace-overlay.settings.json.tmpl    # per-workspace tightening (same for all roles)
```

Each `<role>.settings.json.tmpl` is a complete `settings.json` (defaultMode + permissions.{allow,ask,deny}). The workspace overlay is just `permissions.deny` additions that stack on top.

### New apply.sh install hook: `install_claude_settings()`

1. Read `identity.operator.role` from identity.yaml. Map `personal` → `personal-lab` (the role label stays short but the file name is unambiguous).
2. Pick the template file: `ai/claude-settings/<role>.settings.json.tmpl`.
3. Render that template via envsubst with the standard variable allow-list (the role file is mostly literal JSON — envsubst lets us substitute `${HOME_DIR}` if needed for paths).
4. Install rendered output to **`~/.claude/settings.json`** (mode 644).
5. Render `workspace-overlay.settings.json.tmpl` and install to **`~/<workspace_hub_name>/.claude/settings.json`** (mode 644).
6. **Safety check**: if `~/.claude/settings.json` already exists at install time and `--force-claude-settings` is not passed, refuse to overwrite — emit a warning and the rendered file at `~/.claude/settings.json.uap-proposed` instead. Operators can diff and manually merge. This prevents clobbering keys the operator has set themselves (theme, statusLine, custom keybindings, etc.) that UAP currently doesn't manage.

### Profile yaml change

Each `profiles/<tier>.yaml` adds `claude-settings` to `components_enabled`, placed right after `workspace-hub`. Order matters: claude-settings should run after workspace-hub so the workspace dir exists for the overlay.

## Permission rule content

### Shared `deny` block

Applied to all four tiers, including `personal-lab` (deny survives `bypassPermissions`).

```json
"deny": [
  "Bash(rm -rf /*)",
  "Bash(rm -rf /)",
  "Bash(curl * | bash)",
  "Bash(curl * | sh)",
  "Bash(wget * | bash)",
  "Bash(wget * | sh)",
  "Bash(dd if=* of=/dev/sd*)",

  "Edit(~/.ssh/id_*)",
  "Write(~/.ssh/id_*)",
  "Edit(~/.ssh/*_rsa)",
  "Write(~/.ssh/*_rsa)",
  "Edit(~/.ssh/*_ed25519)",
  "Write(~/.ssh/*_ed25519)",

  "Edit(~/.gnupg/private-keys-v1.d/**)",
  "Write(~/.gnupg/private-keys-v1.d/**)",

  "Edit(~/.aws/credentials)",
  "Write(~/.aws/credentials)",

  "Edit(~/.claude.json)",
  "Write(~/.claude.json)",
  "Edit(~/.claude/credentials*)",
  "Write(~/.claude/credentials*)"
]
```

These are absolute floors: pipe-to-shell from the internet, dd to a block device, writes to private keys or stored credentials. Never legitimate.

### `personal-lab`

```json
{
  "defaultMode": "bypassPermissions",
  "permissions": {
    "allow": [],
    "ask": [],
    "deny": [ /* shared deny block */ ]
  }
}
```

`bypassPermissions` skips all prompts but `deny` still applies. `ask` is empty because ask rules don't fire under bypass.

### `engineer`

```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Read(**)",
      "Edit(**)",
      "Write(**)",
      "Bash(*)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:raw.githubusercontent.com)",
      "WebFetch(domain:registry.npmjs.org)",
      "WebFetch(domain:pypi.org)",
      "WebFetch(domain:docs.anthropic.com)",
      "WebFetch(domain:claude.ai)"
    ],
    "ask": [
      "Bash(sudo *)",
      "Bash(apt *)",
      "Bash(apt-get *)",
      "Bash(snap install *)",
      "Bash(snap refresh *)",
      "Bash(snap remove *)",
      "Bash(*pip install *)",
      "Bash(*pip3 install *)",
      "Bash(npm install *)",
      "Bash(npm i *)",
      "Bash(pnpm add *)",
      "Bash(yarn add *)",
      "Bash(cargo install *)",
      "Bash(go install *)",
      "Bash(gem install *)",
      "Bash(systemctl *)",
      "Bash(service *)",
      "Bash(ufw *)",
      "Bash(iptables *)",
      "Bash(chmod *777*)",
      "Bash(chmod +s *)",
      "Bash(chown *)",
      "Bash(mkfs* *)",
      "Bash(mount *)",
      "Bash(umount *)",
      "Edit(//etc/**)",
      "Write(//etc/**)",
      "Edit(~/.ssh/config)",
      "Write(~/.ssh/config)",
      "Edit(~/.claude/settings.json)",
      "Write(~/.claude/settings.json)"
    ],
    "deny": [ /* shared deny block */ ]
  }
}
```

Logic: `Bash(*)` and broad `Read/Edit/Write(**)` mean routine work flows without prompts. The `ask` list claws back package installs, sudo, service management, firewall changes, perm escalations, system mounts, writes to `/etc/`, and modifications to security-adjacent dotfiles (`~/.ssh/config`, the Claude Code settings file itself). The shared deny is the floor.

`WebFetch` is constrained to a small allow-list of known good hosts; everything else prompts (default mode behavior, no `ask` needed since there's no allow for "any domain").

### `staff`

```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Read(**)",
      "Bash(ls *)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(grep *)", "Bash(find *)", "Bash(wc *)",
      "Bash(git status)", "Bash(git log *)", "Bash(git diff *)", "Bash(git show *)",
      "Bash(pwd)", "Bash(whoami)", "Bash(date)", "Bash(uptime)"
    ],
    "ask": [],
    "deny": [ /* shared deny block */ ]
  }
}
```

`allow` is restricted to read-only file/git inspection plus a few harmless utilities. Everything else falls through to default-mode prompts. `ask` is empty because the narrow allow + default mode already enforces "prompt for most things." All `Edit`/`Write` operations prompt because they're not allowlisted.

### `production-admin`

```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Read(**)",
      "Bash(ls *)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(grep *)", "Bash(find *)", "Bash(wc *)",
      "Bash(git status)", "Bash(git log *)", "Bash(git diff *)", "Bash(git show *)",
      "Bash(pwd)", "Bash(whoami)", "Bash(date)"
    ],
    "ask": [],
    "deny": [
      /* shared deny block */
      "Bash(sudo *)",
      "Bash(rm *)",
      "Bash(mv *)",
      "Bash(chmod *)",
      "Bash(chown *)",
      "Edit(//etc/**)", "Write(//etc/**)",
      "Edit(//var/**)", "Write(//var/**)",
      "Edit(~/.ssh/**)", "Write(~/.ssh/**)",
      "Edit(//usr/**)", "Write(//usr/**)"
    ]
  }
}
```

Same allow as `staff` (read-only inspection), but with an expanded `deny`: `sudo`, destructive bash commands (`rm`, `mv`, `chmod`, `chown`), and writes to `/etc`, `/var`, `/usr`, `~/.ssh` are hard-blocked, not prompted.

If a `production-admin` operator legitimately needs Claude to run a denied command on a specific repo, they edit `<repo>/.claude/settings.local.json` (project-local, git-ignored) — a deliberate per-incident decision.

### Workspace overlay

```json
{
  "_comment": "Per-workspace tightening. Operators add deny rules here for paths within ~/workspace/ that need extra protection (e.g., sensitive ops/ subfolders, dev/<repo>/.env files). Deny rules here stack on top of the global ~/.claude/settings.json regardless of role.",
  "permissions": {
    "deny": [
      "Edit(/**/.env)",
      "Write(/**/.env)",
      "Edit(/**/*.pem)", "Write(/**/*.pem)",
      "Edit(/**/*.key)", "Write(/**/*.key)",
      "Edit(/**/secrets/**)", "Write(/**/secrets/**)"
    ]
  }
}
```

Generic patterns that should never be written under any subworkspace. Operators add machine-specific entries (e.g., `Edit(/ops/private/**)`) after deploy. This file lives at `~/<workspace_hub_name>/.claude/settings.json` and applies to any Claude Code session launched with cwd inside the hub.

## How Claude Code combines these

Per Claude Code's documented settings hierarchy:
- Managed settings (org-pushed) — highest.
- Command-line args.
- Project-local `<cwd>/.claude/settings.local.json` (operator-only, gitignored).
- Project-shared `<cwd>/.claude/settings.json` (the workspace overlay).
- User-global `~/.claude/settings.json` (the role file).

Rule evaluation order: **deny → ask → allow. First match wins.** Any deny from any scope blocks. So the workspace overlay's deny stacks on top of the role file without any explicit merge step — Claude Code does that on read.

## Edge cases

### Existing `~/.claude/settings.json`

Operators may already have a settings.json with theme, statusLine, custom keybindings, `remoteControlAtStartup`, or `skipDangerousModePermissionPrompt`. UAP doesn't currently manage that file. The install hook refuses to overwrite without `--force-claude-settings` and instead writes the rendered file to `~/.claude/settings.json.uap-proposed` so the operator can diff and merge.

Future v2 work: do a real key-level merge (using `jq -s '.[0] * .[1]'` or yq) that preserves unrelated top-level keys and only writes `permissions` and `defaultMode`. Out of scope for v1 to keep the install path simple.

### `bypassPermissions` caveat (personal-lab)

`ask` rules don't fire under `bypassPermissions`. The personal-lab file documents this in a top-of-file comment so future operators don't add `ask` rules and wonder why they don't trigger. Only `deny` is meaningful for this tier; the rest is permissive.

### Path syntax (single slash vs double slash)

Per Claude Code's documented path glob anchors:

- `Edit(//etc/**)` — **double slash**, absolute filesystem path.
- `Edit(/etc/**)` — single slash, relative to **project root** (the cwd at session start). NOT what we want for system paths.
- `Edit(~/path)` — home-directory anchored.
- `Edit(./path)` or `Edit(path)` — cwd-relative.

All system-path rules in this design use double-slash (`//etc/**`, `//usr/**`, etc.) because we want filesystem-absolute matching regardless of where Claude was launched. The workspace overlay deliberately uses single slash (`/**/.env`) because there it means "any .env under the workspace hub root" — exactly the scope we want.

### Compound bash commands

Claude Code parses `cmd1 && cmd2 || cmd3` and validates each subcommand independently. A rule like `Bash(sudo *)` in `ask` will fire on `git status && sudo apt update` even though `git status` is allowed — exactly the behavior we want. No special handling needed in the rules.

### Wrapper commands (`timeout`, `nohup`, etc.)

Claude Code strips known wrappers (`timeout`, `nohup`, `time`, `nice`, `stdbuf`) before matching, so `timeout 30 git fetch` matches `Bash(git *)`. Rules don't need to enumerate wrapper variants.

### MCP tools

Not yet covered. The `mcp__<server>__<tool>` rule pattern works but no MCP servers are deployed by UAP today. When that changes, add a per-tier section to this design. Deferred.

## Apply.sh implementation sketch

```bash
install_claude_settings() {
    local render="$RENDER_DIR/claude-settings"

    # Map the role label to its template filename. Three of four match directly;
    # the personal-lab tier carries role: personal in identity.yaml for
    # historical reasons (consumed by other tools too).
    local role="$OPERATOR_ROLE"
    [ "$role" = "personal" ] && role="personal-lab"

    local src="$render/${role}.settings.json"
    [ -f "$src" ] || die "claude-settings: no rendered file at $src (role: $role)"

    local global="$HOME_DIR/.claude/settings.json"
    local hub="$HOME_DIR/$WORKSPACE_HUB_NAME"
    local overlay="$hub/.claude/settings.json"

    # DRY_RUN guard — describe what would happen and exit before touching the FS.
    if [ "$DRY_RUN" = 1 ]; then
        log "claude-settings: DRY-RUN — would install $src to $global ($role tier)"
        log "claude-settings: DRY-RUN — would install workspace overlay to $overlay"
        return 0
    fi

    # ---- Global file: ~/.claude/settings.json ----
    install -d "$HOME_DIR/.claude"

    if [ -f "$global" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$src" "$global.uap-proposed"
        warn "claude-settings: $global already exists; wrote proposed to $global.uap-proposed — diff and merge manually, or rerun with --force-claude-settings to overwrite."
    else
        install -m 644 "$src" "$global"
        log "claude-settings: installed $global ($role tier)"
    fi

    # ---- Per-workspace overlay: ~/<hub>/.claude/settings.json ----
    # Same overwrite-protection as the global file — operators are expected to
    # customize the workspace overlay post-deploy with their specific deny rules.
    install -d "$hub/.claude"

    if [ -f "$overlay" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay.uap-proposed"
        warn "claude-settings: $overlay already exists; wrote proposed to $overlay.uap-proposed — diff and merge manually."
    else
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay"
        log "claude-settings: installed workspace overlay at $overlay"
    fi
}
```

Argument parser additions:
- New flag: `--force-claude-settings` — sets `FORCE_CLAUDE_SETTINGS=1` and is consumed only by `install_claude_settings()`.

Component resolver: the existing `component_source_dir()` searches `os/ → ai/ → workflows/`, so `ai/claude-settings/` is found automatically with no new code.

## What's out of scope (follow-up work)

1. **Real merge for existing settings.json** (v2 — yq/jq deep merge instead of overwrite-with-warning).
2. **MCP server permission rules** (deferred until UAP deploys MCP servers).
3. **Subworkspace-specific overlay generation** (e.g. a different overlay for `~/workspace/ops/` than for `~/workspace/dev/`). Today the operator hand-edits each subworkspace's local `.claude/settings.json` after deploy.
4. **Audit logging hook** (PreToolUse hook that records every tool call) — useful for `production-admin` tier. Pre-existing Claude Code hooks feature; UAP can add a `.claude/settings.json` `hooks` block in a future revision.
5. **Role naming wart**: `identity.operator.role` uses `personal` for the personal-lab tier (the other three role values match their template filename). The install hook does a one-line special-case mapping. Cleaner option for v2: rename the role value to `personal-lab` everywhere — but the `role` field is also consumed by ops/bootstrap (per `setup/DESIGN.md` line 116) so it'd need coordinated review across both repos.

6. **Per-component allow-list refinement based on `apps.*` and `wm.*` from identity.yaml** — e.g., only allow `Bash(typora *)` if `apps.markdown_editor: typora`. Adds complexity; defer until there's a real user reporting friction.
