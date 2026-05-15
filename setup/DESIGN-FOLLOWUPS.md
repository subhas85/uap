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

**Status:** flagged, not decided. Brainstorm needed before the next wizard iteration.

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

**Goal:** new the org dev runs `bootstrap.sh --clone-config=<org>/uap-config` on a fresh Ubuntu Server box and ends up with a machine that mirrors an existing the org workstation.

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
