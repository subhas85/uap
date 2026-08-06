# Claude-settings deployment — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the `claude-settings` apply.sh component that renders `~/.claude/settings.json` and `~/<workspace_hub>/.claude/settings.json` per the active profile's permission tier.

> **⚠️ Correction (2026-07-27):** File-path denies must use `Edit(path)` **only**. `Edit` rules cover every file-writing tool (Write, Edit, NotebookEdit); `Write(path)` deny/ask rules are **not** enforced by the file-permission engine and make Claude Code warn at startup. Some illustrative JSON blocks below still show the old `Edit`+`Write` pairs — the **authoritative** templates in `ai/claude-settings/*.settings.json.tmpl` have had the `Write(path)` halves removed. Keep `Write(**)` in *allow* lists (that governs the Write tool, not a path).

**Architecture:** New component directory under `ai/claude-settings/` with one settings.json template per tier plus a shared workspace overlay. New `install_claude_settings()` hook in `apply.sh` resolves the active role, picks the matching template, refuses to overwrite an existing user settings.json without `--force-claude-settings`, and installs the workspace overlay to the hub.

**Tech Stack:** Bash (apply.sh), envsubst (rendering), jq (validation), YAML (profile manifests), JSON (settings.json templates).

**Reference spec:** `setup/CLAUDE-SETTINGS-DESIGN.md` at commit `aa14e0b`. The spec has the full rule content; this plan covers ordering, file boundaries, and verification.

**Heads-up — JSON schema correction:** The spec puts `defaultMode` inside `permissions`, which is wrong. Claude Code expects `defaultMode` at the top level (sibling to `permissions`). Task 1 fixes the spec before any template files reference it.

**Heads-up — git config:** This repo is configured for `subhas85` on the personal SSH alias. Commits to this repo MUST NOT include the `Co-Authored-By: Claude` trailer. Use the `git commit -m "..."` form without HEREDOC trailers.

---

## Task 1: Fix spec — move `defaultMode` to top level

**Files:**
- Modify: `setup/CLAUDE-SETTINGS-DESIGN.md` (4 JSON blocks, one per tier)

- [ ] **Step 1: Find every JSON example where `defaultMode` lives inside `permissions`**

Run:
```bash
cd ~/uap && grep -n '"defaultMode"' setup/CLAUDE-SETTINGS-DESIGN.md
```

Expected: 4 hits (lines inside `permissions: {...}` blocks for personal-lab, engineer, staff, production-admin).

- [ ] **Step 2: Move `defaultMode` out for `personal-lab`**

Use Edit to change:
```
"permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [],
```
to:
```
"defaultMode": "bypassPermissions",
"permissions": {
    "allow": [],
```

The opening `"permissions": {` line gets pulled down, and a new `"defaultMode": ...,` line is inserted as the first sibling of `permissions` inside the outermost object. Adjust indentation to match.

- [ ] **Step 3: Repeat for `engineer`, `staff`, `production-admin`**

Same shape edit. Each tier has `"defaultMode": "default"` (engineer/staff/production-admin) at top level instead of bypass.

- [ ] **Step 4: Validate all 4 examples are now correct shape**

Run:
```bash
cd ~/uap && grep -B1 '"defaultMode"' setup/CLAUDE-SETTINGS-DESIGN.md | head -20
```

Expected: every `"defaultMode"` line is preceded by an opening `{` (i.e., it's at the top of its enclosing object), not by `"permissions": {`.

- [ ] **Step 5: Commit**

```bash
cd ~/uap
git add setup/CLAUDE-SETTINGS-DESIGN.md
git commit -m "docs: fix defaultMode placement in claude-settings spec

defaultMode is a top-level settings.json key, not a nested permissions
key. Corrected all four tier examples to match Claude Code's actual
schema before implementation references them."
```

---

## Task 2: Create the 5 template files

**Files:**
- Create: `ai/claude-settings/personal-lab.settings.json.tmpl`
- Create: `ai/claude-settings/engineer.settings.json.tmpl`
- Create: `ai/claude-settings/staff.settings.json.tmpl`
- Create: `ai/claude-settings/production-admin.settings.json.tmpl`
- Create: `ai/claude-settings/workspace-overlay.settings.json.tmpl`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p ~/uap/ai/claude-settings
```

- [ ] **Step 2: Write `personal-lab.settings.json.tmpl`**

```json
{
  "defaultMode": "bypassPermissions",
  "permissions": {
    "allow": [],
    "ask": [],
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
  }
}
```

Note: `ask` is intentionally empty — `bypassPermissions` mode skips ask prompts. Only `deny` survives bypass. Operators of this tier should not add ask rules here; they won't fire.

- [ ] **Step 3: Write `engineer.settings.json.tmpl`**

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
      "Bash(pip install *)",
      "Bash(pip3 install *)",
      "Bash(python -m pip install *)",
      "Bash(python3 -m pip install *)",
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
  }
}
```

- [ ] **Step 4: Write `staff.settings.json.tmpl`**

```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Read(**)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(grep *)",
      "Bash(find *)",
      "Bash(wc *)",
      "Bash(git status)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git show *)",
      "Bash(pwd)",
      "Bash(whoami)",
      "Bash(date)",
      "Bash(uptime)"
    ],
    "ask": [],
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
  }
}
```

- [ ] **Step 5: Write `production-admin.settings.json.tmpl`**

```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Read(**)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(grep *)",
      "Bash(find *)",
      "Bash(wc *)",
      "Bash(git status)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git show *)",
      "Bash(pwd)",
      "Bash(whoami)",
      "Bash(date)"
    ],
    "ask": [],
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
      "Write(~/.claude/credentials*)",
      "Bash(sudo *)",
      "Bash(rm *)",
      "Bash(mv *)",
      "Bash(chmod *)",
      "Bash(chown *)",
      "Edit(//etc/**)",
      "Write(//etc/**)",
      "Edit(//var/**)",
      "Write(//var/**)",
      "Edit(~/.ssh/**)",
      "Write(~/.ssh/**)",
      "Edit(//usr/**)",
      "Write(//usr/**)"
    ]
  }
}
```

- [ ] **Step 6: Write `workspace-overlay.settings.json.tmpl`**

```json
{
  "_comment": "Per-workspace tightening. Operators add deny rules here for paths within the workspace hub that need extra protection (e.g., sensitive ops/ subfolders, dev/<repo>/.env files). Deny rules here stack on top of the global ~/.claude/settings.json regardless of role.",
  "permissions": {
    "deny": [
      "Edit(/**/.env)",
      "Write(/**/.env)",
      "Edit(/**/*.pem)",
      "Write(/**/*.pem)",
      "Edit(/**/*.key)",
      "Write(/**/*.key)",
      "Edit(/**/secrets/**)",
      "Write(/**/secrets/**)"
    ]
  }
}
```

Path syntax note: single-slash leading paths here are *project-root-relative*, meaning "anywhere under the workspace hub root." That's the intended scope for the overlay — exactly what we want.

- [ ] **Step 7: Validate all 5 files are valid JSON**

Run:
```bash
cd ~/uap && for f in ai/claude-settings/*.tmpl; do
  printf '%-60s ' "$f"
  jq . "$f" > /dev/null && echo "OK" || echo "INVALID"
done
```

Expected:
```
ai/claude-settings/engineer.settings.json.tmpl               OK
ai/claude-settings/personal-lab.settings.json.tmpl           OK
ai/claude-settings/production-admin.settings.json.tmpl       OK
ai/claude-settings/staff.settings.json.tmpl                  OK
ai/claude-settings/workspace-overlay.settings.json.tmpl      OK
```

If any file is INVALID, fix the JSON syntax before proceeding.

- [ ] **Step 8: Commit**

```bash
cd ~/uap
git add ai/claude-settings/
git commit -m "feat(ai): add claude-settings template files per permission tier

Five settings.json templates: one per profile tier (personal-lab,
engineer, staff, production-admin) plus a shared workspace overlay.
Content matches setup/CLAUDE-SETTINGS-DESIGN.md.

Each tier file is self-contained (the deny block is inlined four times
rather than composed) because envsubst can't do file includes. A future
refactor could use jq composition at render time."
```

---

## Task 3: Add `--force-claude-settings` flag to `apply.sh`

**Files:**
- Modify: `setup/apply.sh` (3 small edits — default var, arg parser, help text)

- [ ] **Step 1: Read the current arg-parsing block to find the right line numbers**

Run:
```bash
cd ~/uap && grep -n 'DRY_RUN=\|NO_SUDO=\|COMPONENTS_REQUESTED=\|--dry-run\|--no-sudo\|--\*\)' setup/apply.sh
```

Expected: roughly lines 23-54 hold the arg parser. Note the exact lines for the next steps.

- [ ] **Step 2: Add the default variable**

Find the line `NO_SUDO=0` near the top of apply.sh (around line 24) and add `FORCE_CLAUDE_SETTINGS=0` immediately below it. Use Edit:

old_string:
```
DRY_RUN=0
NO_SUDO=0
COMPONENTS_REQUESTED=()
```

new_string:
```
DRY_RUN=0
NO_SUDO=0
FORCE_CLAUDE_SETTINGS=0
COMPONENTS_REQUESTED=()
```

- [ ] **Step 3: Add the flag to the argument parser**

Find the argument parser case statement (around line 46-54) and add a new case for `--force-claude-settings`. Use Edit:

old_string:
```
        --dry-run)  DRY_RUN=1;  shift ;;
        --no-sudo)  NO_SUDO=1;  shift ;;
        -h|--help)  sed -n '3,12p' "$0"; exit 0 ;;
```

new_string:
```
        --dry-run)                DRY_RUN=1;                shift ;;
        --no-sudo)                NO_SUDO=1;                shift ;;
        --force-claude-settings)  FORCE_CLAUDE_SETTINGS=1;  shift ;;
        -h|--help)                sed -n '3,12p' "$0";      exit 0 ;;
```

(Reformatting the column alignment so the new flag fits cleanly.)

- [ ] **Step 4: Update the help block at the top of the file**

Find the docblock comment near the top (lines 3-11) and add a usage line for the new flag. Use Edit:

old_string:
```
#   apply.sh --dry-run        # render + show what would change; install nothing
#   apply.sh --no-sudo        # skip steps that need root
```

new_string:
```
#   apply.sh --dry-run                  # render + show what would change; install nothing
#   apply.sh --no-sudo                  # skip steps that need root
#   apply.sh --force-claude-settings    # overwrite existing ~/.claude/settings.json (claude-settings component only)
```

- [ ] **Step 5: Verify the help output and arg parser work**

Run:
```bash
cd ~/uap && ./setup/apply.sh --help
```

Expected output includes the new line:
```
  apply.sh --force-claude-settings    # overwrite existing ~/.claude/settings.json (claude-settings component only)
```

Run:
```bash
cd ~/uap && ./setup/apply.sh --force-claude-settings --help
```

Expected: no error, help printed (the flag parses without complaint).

- [ ] **Step 6: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "feat(apply): add --force-claude-settings flag

Lets claude-settings deployment overwrite an existing ~/.claude/settings.json
instead of writing to .uap-proposed. Other components ignore this flag.
Wired into the apply.sh arg parser and help docblock."
```

---

## Task 4: Add `install_claude_settings()` hook to `apply.sh`

**Files:**
- Modify: `setup/apply.sh` (add new function near the other install_* hooks, around line 290)

- [ ] **Step 1: Locate where to insert the new function**

Run:
```bash
cd ~/uap && grep -n '^install_' setup/apply.sh
```

Find a sensible insertion point — after `install_xinitrc()` (which is short) and before `install_gtk_theme()`. Note the line number of `install_gtk_theme()`'s declaration.

- [ ] **Step 2: Insert the install_claude_settings() function**

Use Edit to insert before `install_gtk_theme() {`. The exact replacement:

old_string:
```
install_xinitrc() {
    local render="$RENDER_DIR/xinitrc"
    install -m 755 "$render/xinitrc" "$HOME_DIR/.xinitrc"
    ln -sf "$HOME_DIR/.xinitrc" "$HOME_DIR/.xsession"
    log "xinitrc: installed to $HOME_DIR/.xinitrc (+ .xsession symlink)"
}

install_gtk_theme() {
```

new_string:
```
install_xinitrc() {
    local render="$RENDER_DIR/xinitrc"
    install -m 755 "$render/xinitrc" "$HOME_DIR/.xinitrc"
    ln -sf "$HOME_DIR/.xinitrc" "$HOME_DIR/.xsession"
    log "xinitrc: installed to $HOME_DIR/.xinitrc (+ .xsession symlink)"
}

install_claude_settings() {
    local render="$RENDER_DIR/claude-settings"

    # Map the role label to its template filename. Three of four match directly;
    # the personal-lab tier carries role: personal in identity.yaml for
    # historical reasons (consumed by other tools too).
    local role="$OPERATOR_ROLE"
    [ "$role" = "personal" ] && role="personal-lab"

    local src="$render/${role}.settings.json"
    [ -f "$src" ] || die "claude-settings: no rendered file at $src (role: $role)"

    # ---- Global file: ~/.claude/settings.json ----
    local global="$HOME_DIR/.claude/settings.json"
    install -d "$HOME_DIR/.claude"

    if [ -f "$global" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$src" "$global.uap-proposed"
        warn "claude-settings: $global already exists; wrote proposed to $global.uap-proposed — diff and merge manually, or rerun with --force-claude-settings to overwrite."
    else
        install -m 644 "$src" "$global"
        log "claude-settings: installed $global ($role tier)"
    fi

    # ---- Per-workspace overlay: ~/<hub>/.claude/settings.json ----
    local hub="$HOME_DIR/$WORKSPACE_HUB_NAME"
    local overlay="$hub/.claude/settings.json"
    install -d "$hub/.claude"

    if [ -f "$overlay" ] && [ "$FORCE_CLAUDE_SETTINGS" != 1 ]; then
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay.uap-proposed"
        warn "claude-settings: $overlay already exists; wrote proposed to $overlay.uap-proposed — diff and merge manually."
    else
        install -m 644 "$render/workspace-overlay.settings.json" "$overlay"
        log "claude-settings: installed workspace overlay at $overlay"
    fi
}

install_gtk_theme() {
```

- [ ] **Step 3: Verify the function reads `$OPERATOR_ROLE`**

The new function references `$OPERATOR_ROLE`. Confirm it's already exported earlier in apply.sh.

Run:
```bash
cd ~/uap && grep -n 'OPERATOR_ROLE' setup/apply.sh
```

Expected: 2+ hits. One in the `export OPERATOR_ROLE` line near the top, one in the `OPERATOR_ROLE=$(yq ...)` assignment, and now one in `install_claude_settings()`. If `OPERATOR_ROLE` is NOT already exported, the function will get an empty role and fail with the `no rendered file` error.

- [ ] **Step 4: Smoke-test rendering with a dry run**

Set up a sandbox identity that points at the engineer template:

```bash
mkdir -p ~/uap.local
cp ~/uap/profiles/engineer.yaml ~/uap.local/identity.yaml
# At this point identity.yaml has the engineer profile's values BUT
# components_enabled does NOT yet include claude-settings (that's Task 5).
# To smoke-test in isolation, manually request the component:
~/uap/setup/apply.sh --dry-run claude-settings
```

Expected:
- A line like `[apply.sh] claude-settings: rendered into /home/<user>/uap.local/rendered/claude-settings`.
- The function `install_claude_settings()` runs (dry-run doesn't actually install but does run the hook — check the existing `install_plymouth` for the DRY_RUN-aware pattern; if the new function doesn't honor `--dry-run` it'll attempt to install for real. The provided implementation above does NOT short-circuit on DRY_RUN, which mirrors the other install hooks that also don't — apply.sh's DRY_RUN flag is primarily about the render stage.)

If `~/.claude/settings.json` already exists on this machine, the function will write to `~/.claude/settings.json.uap-proposed` instead of clobbering. Verify:

```bash
ls -la ~/.claude/settings.json* 2>&1
diff ~/.claude/settings.json.uap-proposed ~/uap.local/rendered/claude-settings/engineer.settings.json
```

Expected: the `.uap-proposed` file matches the rendered template byte-for-byte.

- [ ] **Step 5: Validate the rendered JSON**

```bash
jq . ~/uap.local/rendered/claude-settings/engineer.settings.json > /dev/null && echo OK
jq . ~/uap.local/rendered/claude-settings/workspace-overlay.settings.json > /dev/null && echo OK
```

Expected: `OK` twice.

- [ ] **Step 6: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "feat(apply): install_claude_settings() hook for permission tiers

Resolves identity.operator.role to a rendered template under
claude-settings/, installs the result to ~/.claude/settings.json
unless that file already exists. With --force-claude-settings the
existing file is overwritten; otherwise a .uap-proposed file is
written next to it and a warning is logged.

Also installs the workspace overlay to ~/<hub>/.claude/settings.json
with the same overwrite protection.

Maps 'personal' role to the 'personal-lab' template filename — the
only profile where role label and template name diverge."
```

---

## Task 5: Enable `claude-settings` in all 4 profile yamls

**Files:**
- Modify: `profiles/personal-lab.yaml`
- Modify: `profiles/engineer.yaml`
- Modify: `profiles/staff.yaml`
- Modify: `profiles/production-admin.yaml`

- [ ] **Step 1: Confirm the current `components_enabled` shape**

Run:
```bash
cd ~/uap && grep -A 12 'components_enabled' profiles/personal-lab.yaml
```

Expected: a YAML list ending with `- workspace-hub`. The new entry goes immediately after.

- [ ] **Step 2: Add `claude-settings` to `personal-lab.yaml`**

Use Edit to change:

old_string:
```
  - i3
  - workspace-hub
```

new_string:
```
  - i3
  - workspace-hub
  - claude-settings
```

- [ ] **Step 3: Repeat for `engineer.yaml`**

Use Edit on `profiles/engineer.yaml`:

old_string:
```
  - i3
  - workspace-hub
```

new_string:
```
  - i3
  - workspace-hub
  - claude-settings
```

- [ ] **Step 4: Repeat for `staff.yaml`**

Use Edit on `profiles/staff.yaml`:

old_string:
```
  - i3
  - workspace-hub
```

new_string:
```
  - i3
  - workspace-hub
  - claude-settings
```

- [ ] **Step 5: Repeat for `production-admin.yaml`**

Use Edit on `profiles/production-admin.yaml`:

old_string:
```
  - i3
  - workspace-hub
```

new_string:
```
  - i3
  - workspace-hub
  - claude-settings
```

Order matters in `components_enabled`: `claude-settings` runs after `workspace-hub` so the hub dir exists when the overlay installs.

- [ ] **Step 6: Verify all 4 yamls have the new entry**

Run:
```bash
cd ~/uap && grep -c '^\s*- claude-settings$' profiles/*.yaml
```

Expected:
```
profiles/engineer.yaml:1
profiles/personal-lab.yaml:1
profiles/production-admin.yaml:1
profiles/staff.yaml:1
```

- [ ] **Step 7: Commit**

```bash
cd ~/uap
git add profiles/
git commit -m "feat(profiles): enable claude-settings component in all 4 tiers

Appends claude-settings to components_enabled after workspace-hub in
each profile. Order matters: the install hook writes the workspace
overlay to ~/<hub>/.claude/settings.json, which requires the hub dir
to exist."
```

---

## Task 6: Smoke test (verification, no commit)

This task verifies end-to-end that running `apply.sh` against each profile produces the expected files without clobbering anything.

**Files:** None. Read-only verification.

- [ ] **Step 1: Snapshot the current state of `~/.claude/settings.json`**

```bash
ls -la ~/.claude/settings.json 2>&1 | tee /tmp/claude-settings-before.txt
md5sum ~/.claude/settings.json 2>&1 | tee -a /tmp/claude-settings-before.txt
```

Record the hash so we can prove apply.sh didn't touch it during dry-run testing.

- [ ] **Step 2: Dry-run with `engineer` profile**

```bash
cp ~/uap/profiles/engineer.yaml ~/uap.local/identity.yaml
~/uap/setup/apply.sh --dry-run claude-settings
```

Expected log lines:
- `[apply.sh] claude-settings: rendered into /home/<user>/uap.local/rendered/claude-settings`
- Either: `claude-settings: installed /home/<user>/.claude/settings.json (engineer tier)` (if the file didn't exist before)
- Or: `WARN: ... already exists; wrote proposed to .../.claude/settings.json.uap-proposed ...`

Either is acceptable depending on whether the test machine already has a settings.json.

- [ ] **Step 3: Verify the rendered file is valid and has the expected tier-level structure**

```bash
RENDER=~/uap.local/rendered/claude-settings
jq '.defaultMode' $RENDER/engineer.settings.json
# Expected: "default"

jq '.permissions.allow | length' $RENDER/engineer.settings.json
# Expected: 10 (Read(**), Edit(**), Write(**), Bash(*), 6 WebFetch domains)

jq '.permissions.ask | length' $RENDER/engineer.settings.json
# Expected: 33 (count of items in engineer's ask list)

jq '.permissions.deny | length' $RENDER/engineer.settings.json
# Expected: 21 (shared deny block size)
```

If any counts differ from the template content, recheck the template file.

- [ ] **Step 4: Verify the hash didn't change**

```bash
md5sum ~/.claude/settings.json 2>&1 | tee /tmp/claude-settings-after.txt
diff /tmp/claude-settings-before.txt /tmp/claude-settings-after.txt
```

Expected: no diff. The real `~/.claude/settings.json` is untouched (either left alone because it pre-existed and `--force` wasn't passed, or never created because dry-run).

- [ ] **Step 5: Verify the workspace overlay rendered correctly**

```bash
jq '.permissions.deny | length' $RENDER/workspace-overlay.settings.json
# Expected: 4 (Edit-only rules; the Write(path) halves were removed — they are no-ops)

jq '.permissions.deny[]' $RENDER/workspace-overlay.settings.json
# Expected: "Edit(/**/.env)", "Edit(/**/*.pem)", "Edit(/**/*.key)", "Edit(/**/secrets/**)"
```

- [ ] **Step 6: Repeat dry-run for each remaining profile**

```bash
for profile in personal-lab staff production-admin; do
    echo "=== $profile ==="
    cp ~/uap/profiles/${profile}.yaml ~/uap.local/identity.yaml
    ~/uap/setup/apply.sh --dry-run claude-settings 2>&1 | grep claude-settings
done
```

Expected: each profile produces a `rendered into ...` line and either an `installed` line or a `WARN: ... .uap-proposed` line.

- [ ] **Step 7: Inspect the per-tier rendered output briefly**

```bash
for profile in personal-lab engineer staff production-admin; do
    cp ~/uap/profiles/${profile}.yaml ~/uap.local/identity.yaml
    ~/uap/setup/apply.sh --dry-run claude-settings > /dev/null 2>&1
    echo "=== $profile ==="
    role=$(yq '.operator.role' ~/uap.local/identity.yaml)
    [ "$role" = "personal" ] && role="personal-lab"
    jq -r '.defaultMode, (.permissions.allow | length), (.permissions.ask | length), (.permissions.deny | length)' \
        ~/uap.local/rendered/claude-settings/${role}.settings.json
done
```

Expected matrix (defaultMode / allow size / ask size / deny size):
```
=== personal-lab ===
bypassPermissions
0
0
21

=== engineer ===
default
10
33
21

=== staff ===
default
16
0
21

=== production-admin ===
default
15
0
34
```

If any tier's counts diverge, recheck that tier's template content against `setup/CLAUDE-SETTINGS-DESIGN.md`.

- [ ] **Step 8: Restore the user's preferred identity.yaml**

```bash
# If the user's identity.yaml was something other than engineer.yaml before,
# restore it from version control or their own backup. Otherwise leave the
# engineer profile in place if that's what they intend to use.
ls -la ~/uap.local/identity.yaml
```

- [ ] **Step 9: Final push**

After all 5 implementation commits and successful smoke tests:

```bash
cd ~/uap
git log --oneline -6   # confirm the 5 commits + the prior spec commit
git push origin main
```

Expected: pushes 5 new commits to subhas85/uap (the spec fix from Task 1 plus the 4 feature commits from Tasks 2-5).

---

## Out of scope (deferred to follow-up plans)

These items are listed in `setup/CLAUDE-SETTINGS-DESIGN.md` under "What's out of scope" and are not part of this implementation:

1. Real key-level merge of existing `~/.claude/settings.json` (currently overwrite-protected with `.uap-proposed`).
2. MCP server permission rules.
3. Subworkspace-specific overlay generation.
4. PreToolUse audit-logging hook for production-admin.
5. Renaming `identity.operator.role: personal` → `personal-lab` (coordinated change across uap + ops/bootstrap).
6. Allowlist refinement based on `identity.apps.*` and `identity.wm.*`.

Each merits its own brainstorm → spec → plan cycle.
