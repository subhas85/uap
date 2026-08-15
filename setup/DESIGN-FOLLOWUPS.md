# UAP design follow-ups

Open design questions surfaced during real wizard runs. Each one is too big for a surgical edit — they need a brainstorm pass before changing code or wizard text.

Add items here when you encounter a "we should think about X" moment, with: what's confusing, what observation triggered it, what's blocked or hand-waved today.

---

## ops/ vs workspace/ — what does each one mean?

**Confusion observed:** During the first wizard test (2026-05-14), Q7.7 asks the operator to name subworkspaces to put under `~/workspace/`. One of the suggested defaults is `ops`. But UAP also seeds a separate `~/ops/` folder via Section 10 ("operator profile") with pipelines, TEAM.md, CONTEXT.md, ICM-shaped stage folders. Operators reasonably ask: are `~/workspace/ops/` and `~/ops/` the same thing? Is one a symlink to the other? Why are there two locations?

**What's true today (this author's adminbox):** `~/ops/` is a real private repo with team operations content. `~/workspace/ops` is a symlink to `~/ops/`. The split exists because the workspace hub was added on top of a pre-existing `~/` layout.

**Why that doesn't generalize to a fresh UAP install:** new operators have no pre-existing `~/ops/` to preserve. The symlink pattern is just compatibility scaffolding for one machine. A fresh deployment should have ONE canonical home for team ops, not two.

**The unresolved question:** which one is canonical?
- Option A — `~/workspace/ops/` is canonical; nothing under `~/ops/` exists. Everything operational lives inside the hub.
- Option B — `~/ops/` is canonical; the hub contains a `~/workspace/ops` symlink for AI convenience. Matches today's adminbox.
- Option C — kill the distinction. The hub *is* the operations folder. No separate `ops` concept.

Each option has implications for `setup/CLAUDE.md` Section 10 seeding (which paths get created), the QUESTIONNAIRE wording, the `workspace-hub` install hook in `apply.sh`, and the public README.

**Status: DECIDED 2026-08-15 — Option A.** Everything lives inside `~/workspace/`: `ops`, `dev`, and any other subworkspace are real directories under the hub, not symlinks to `~/`. The single exception is `uap/`, which stays a symlink to `~/uap` because the framework repo is the only top-level folder UAP owns and it must be clonable/updatable on its own.

**Rationale (user, 2026-08-15):** "on all new boxes going forward it makes more sense for everything to live inside the ~/workspace folder … ops folder should also live in workspace." One canonical home per machine; the two-location split was only ever compatibility scaffolding for a pre-existing `~/` layout.

**Implemented 2026-08-15:** new `identity.ai.subworkspace_mode` (`create` | `symlink`, default `create`).
- `apply.sh` `install_workspace_hub` creates real dirs in `create` mode; `symlink` mode keeps the old behaviour for migrating operators. `uap` is force-symlinked in both.
- In `create` mode the hook refuses to clobber an existing symlink left by a prior `symlink`-mode run — it warns and leaves it, so nobody's real `~/ops` gets orphaned by a mode flip.
- `ai/workspace-hub/CLAUDE.md.tmpl` no longer hardcodes the "these are symlinks" sentence; it renders `${HUB_LAYOUT_NOTE}`, which is written per mode.
- All four profiles + `answers.example.yaml` carry the new key.

**Not migrated:** this author's adminbox still has `~/ops` + `~/workspace/ops` symlink and does *not* enable the `workspace-hub` component, so it is unaffected. Converting it is a separate, manual job (git remotes, absolute paths in CLAUDE.md/memory, running services) — do not let a future `apply.sh` run do it implicitly.

---

## Public-flow VM provisioning (Use Case 1 of two)

**Acknowledged not-yet-built:** the wizard assumes Ubuntu Server is already installed and reachable. Provisioning the VM (Proxmox, ESXi, cloud), running the Ubuntu installer, and bootstrapping SSH access is currently the operator's job — clearly documented in the README.

**What's missing:**
- No Proxmox API integration (pvesh, cloud-init template, etc.)
- No autoinstall ISO recipe
- No Tailscale auth-key flow (interactive URL today)
- No `gh ssh-key add` step for cloning private follow-on repos (uap-config)

**Status:** explicitly out of scope for v1. Roadmap item.

---

## Org-internal "clone-existing-workspace" mode (Use Case 2 of two)

**Goal:** a new team dev runs `bootstrap.sh --clone-config=<org>/uap-config` on a fresh Ubuntu Server box and ends up with a machine that mirrors an existing team workstation.

**What's missing:**
- bootstrap.sh `--clone-config` flag
- Per-machine identity adjustment prompt (hostname especially)
- SSH key prereq doc (operator must `gh auth login` first; not yet automated)

**Status:** next implementation cycle after wizard-test feedback lands.

---

## Wizard test feedback log (2026-05-14)

Concrete items captured from the first real wizard run, already merged into `QUESTIONNAIRE.md`:

- [x] Section 2 collapsed; provisioning is operator's job (no more hypervisor questions in the wizard)
- [x] Section 6 collapsed to one i3-preset chooser (Standard / macOS-flavor / Minimalist)
- [x] Q7.7 default flipped to "create fresh subdirs" (symlink mode is the alternative for migrating operators)
- [x] **ICM removed from the wizard.** Q7.5 (use-ICM question) deleted. Section 10 trimmed from five questions to two (terminal comfort + keyboard workflow comfort); the ICM-shaped pipeline seeding (old Q10.4, Q10.5) is gone. `setup/CLAUDE.md` facilitator instructions no longer auto-seed `ops/pipelines/<type>/`. `setup/references.md` keeps ICM as one optional methodology among potentially many, not a default. **Rationale (user, 2026-05-14):** "everyone is different — let's leave folder contents alone."
- [x] Plymouth `os/plymouth/logo.png` replaced with the UAP logo (UFO + UAP text on transparent background, 800x600).
- [x] README hero image added at top (`branding/uap-hero.png`).
- [x] **Wizard split into Simple + Advanced modes.** Step 0 in `setup/CLAUDE.md` now asks which path. Simple = pick one of the four profiles, auto-detect username/hostname, ask email, apply. ~30 sec. Advanced = walk full `QUESTIONNAIRE.md`. Rationale: most users want defaults, not a 20-question survey.

Items not yet acted on:
- ops/ vs workspace/ confusion — see top section above. Worth noting: with ICM removed and Section 10 simplified, the wizard no longer creates a separate `~/ops/` — everything lives under `~/workspace/`. So the "two locations" problem largely dissolves on a fresh install; the only place it persists is on operator machines (like this author's adminbox) that pre-dated UAP. Reconsider whether this design followup is still active.
- [x] bootstrap.sh installed `build-essential` (228 MB) — nothing in UAP currently needs it. **Done:** dropped from the apt prereqs list. Prereqs are now just `git curl ca-certificates`.
- [x] bootstrap.sh didn't append `~/.local/bin` to the operator's `~/.bashrc`. **Done:** marker-idempotent block appended after Claude Code install. Uses a case-statement PATH guard so the export only fires when needed.
- qemu-guest-agent isn't enabled in fresh installs — graceful `qm reboot` from a Proxmox host fails. Worth a `apt install qemu-guest-agent && systemctl enable --now qemu-guest-agent` somewhere if the wizard ever detects it's running on a hypervisor VM (today the wizard doesn't try to detect that anymore — operators handle hypervisor concerns themselves).

---

## Wizard test feedback log (2026-05-15, second run)

Second wizard test against a freshly-rebuilt VM (107) running Ubuntu Server 24.04. Run-time gaps in `apply.sh` that the first test (2026-05-14) couldn't catch because that run only got as far as the facilitator wizard:

- [x] **`apply.sh` didn't apt-install the underlying packages** for any of the rendered components (i3, xrdp, alacritty, rofi, gtk-theme, plymouth). Operators were ending up with config files written into `~/.config/` for packages that didn't exist. **Done (commit e83a778):** added an idempotent `apt_install` helper with a once-per-run `apt-get update`, and every `install_*` hook now apt-installs its own dependency list before laying down configs.
- [x] **JetBrainsMono Nerd Font missing.** apt's `fonts-jetbrains-mono` is the non-patched variant; i3bar / rofi / alacritty all want the patched glyphs and silently degraded. **Done:** new `install_jetbrains_nerd_font` helper that pulls the patched font from `ryanoasis/nerd-fonts` GitHub releases into `~/.local/share/fonts/` and refreshes `fc-cache`. Called from `install_i3`.
- [x] **xrdp Phase 6 missing.** `install_xrdp` rendered `sesman.ini` + `reconnectwm.sh` but never did the actual apt install, systemctl enable, ufw rule, or keymap mirror. RDP from an iPad couldn't connect. **Done:** `install_xrdp` now does apt (xrdp + xorgxrdp), sesman.ini patch, reconnectwm.sh install, km-`<LCID>`.ini keymap mirror, `systemctl enable --now xrdp`, `systemctl restart xrdp-sesman`, `ufw allow 3389/tcp`, and `chmod 644 /etc/xrdp/key.pem`.
- [x] **`remoteControlAtStartup` missing from rendered `~/.claude/settings.json`.** Q7.4 of the wizard recorded a yes/no answer in identity.yaml but the value never made it into the JSON. **Done (commit 2da0087):** added the key directly to each `ai/claude-settings/*.settings.json.tmpl` template, hardcoded per tier — personal-lab + engineer = true, staff + production-admin = false. Personal-lab also gets `skipDangerousModePermissionPrompt: true`.
- [x] **`yq` not installed by bootstrap.** `apply.sh` requires Mike Farah's Go yq (the apt `yq` is a different Python tool with different syntax) and was failing immediately on a fresh box. **Done (commit 4d8f3c8):** bootstrap.sh now downloads yq v4.45.4 to `~/.local/bin/` before launching Claude.
- [x] **Operator apps (Edge, Chrome, Typora, btop, bat, glow, thunar, flameshot) not installed.** `apply.sh` had no hook for the contents of `identity.apps.*`. **Done (commit e83a778):** new `apps` component + `install_apps()` hook that reads `identity.apps.{browsers,markdown_editor,terminal_tools,file_manager,screenshot}` and installs via apt or third-party repos (Microsoft Edge, Google Chrome, Typora) as appropriate. All four profile yamls now list `apps` in `components_enabled`.

Next: third wizard test on a freshly-rebuilt VM to confirm a green-field box reaches a usable state from `bootstrap.sh` alone.

---

## Wizard test feedback log (2026-08-15, third run)

Green-field Ubuntu Server 24.04 on a Proxmox VM, deployed for a second operator on the same host. Full record kept outside this repo at `~/uap.local/wizard-test-YYYY-MM-DD.md`. **Verdict: ship it** — `bootstrap.sh` + `apply.sh` reached a usable box, exit 0, one non-blocking warning. Every gap from the 2026-05-15 run is confirmed fixed (apt installs per component, patched Nerd Font, full xrdp phase, `yq` in bootstrap, the `apps` hook, `remoteControlAtStartup`).

Also the first real-box exercise of `subworkspace_mode: create` — hub came out with `ops/` and `dev/` as real directories and `uap` as the lone symlink, and the template rendered the create-mode layout note.

New items:

- **`network.rdp_scope` is decorative — security.** All four profiles set `rdp_scope: tailscale-only`, but the key is read *nowhere* in `apply.sh` or any template. `install_xrdp` does an unconditional `run_sudo ufw allow 3389/tcp`, so a profile advertising a Tailscale-only RDP surface actually opens 3389 to the entire subnet. Either implement the scoping (`ufw allow in on tailscale0 to any port 3389` when set) or delete the key so it stops making a promise the code doesn't keep. **Highest-priority item here.**
- **herdr plugins need a Rust toolchain.** `install-plugins.sh` fails on a clean box: `no prebuilt binary was usable, and cargo could not be found`. herdr itself and `herdr-sysmeter` install fine, so this is only the plugin step — but it emits a WARN on every green-field install. Ship a usable prebuilt, add `cargo` to the herdr apt list, or make plugins opt-in.
- **qemu-guest-agent still manual.** Carried over unresolved from 2026-05-14; had to be hand-installed again. Now that "UAP runs on a hypervisor VM" is the normal case rather than the exception, this is worth an opt-in component — without it the host can't do a graceful `qm reboot` or report the guest IP.
- **`boot.wallpaper` is decorative — same class as `rdp_scope`.** The xinitrc template hardcodes `feh --bg-fill ~/.config/i3/background 2>/dev/null &`, but nothing in `apply.sh` ever creates that file and the repo ships no wallpaper asset. `install_xinitrc` apt-installs `feh` and stops there. So every profile sets `wallpaper: tokyo-night-default` and every fresh box boots to a blank desktop — and because stderr is redirected to `/dev/null`, `feh` fails silently with no clue why. Either ship a default image, generate one from `theme.bg_hex`/`bg_alt_hex` at apply time, or drop the key. Worth dropping the `2>/dev/null` regardless: silent failure is what made this invisible on two prior test runs.
- **No headless self-check.** Phase 4 of `WIZARD-TEST-CHECKLIST.md` (keybindings, bar, autostart, dark menus) all require a human in an RDP session, so an automated deployment can't self-report success. An `apply.sh --self-check` asserting config files, systemd units and PATH entries exist would cover most of it.
