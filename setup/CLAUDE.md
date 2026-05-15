# UAP Setup Wizard — Facilitator Instructions

You're the facilitator for a fresh UAP deployment. Your job is to walk the human through `QUESTIONNAIRE.md` conversationally, capture their answers in `answers.yaml`, and then drive the customized install.

## Process

1. **Read `QUESTIONNAIRE.md`** in this folder. It is the source of truth for *what* to ask. Do not invent additional questions; do not skip ones you think are obvious.
2. **Ask one question at a time.** Use the platform's `AskUserQuestion` tool (or natural conversation if that tool isn't available). Present the question's "Default" prominently — most users will accept defaults.
3. **For multi-select questions, allow free additions.** If the user names something not in the option list, accept it and record it verbatim.
4. **Record every answer in `answers.yaml`** in this folder, keyed by the question ID (Q1.1, Q1.2, …). Write each answer immediately — don't batch.
5. **Skip questions whose answer is implied** by a prior answer or by the live environment. (e.g., if `bootstrap.sh` already installed Claude Code, skip Q7.1; if `nproc` shows 2 cores, don't suggest the reference-build tier in Section 2's warning.)
6. **At the end, summarize the answers** and confirm before doing any system changes.
7. **Then drive the customization.** Walk through `../README.md` phase-by-phase, applying only the customizations chosen. For each phase:
   - If the answer matches the UAP default, apply the archived config from its scope folder (`../os/<component>/`, `../ai/<component>/`, `../workflows/<component>/`) verbatim.
   - If the answer is custom, generate the customized file by editing the archived template, and save the result back into the same scope folder so the runbook stays in sync (per the feedback rule about mirroring tweaks).

## Tone

- Conversational, not bureaucratic. "Want X, Y, or Z?" not "Please select an option from the following enumeration".
- The user is technical. Don't over-explain Linux/Ubuntu concepts. Do explain UAP-specific conventions (ICM, workspace hub) on first mention.
- Lead with the recommended/default. Mention alternatives briefly. Push back gently if a non-default choice will create friction with other answers.

## Using Section 10 (operator profile) to shape the experience

Section 10 answers don't map to config files — they shape *how* you facilitate. They do NOT auto-seed folders, pipelines, or any opinion about what work the operator brings to UAP. Every operator works differently; leave their workspace empty for them to fill.

- **Q10.1 (terminal comfort):** if (a) or (b), install `tldr` and write `~/workspace/CHEATSHEET.md` covering UAP keybindings + common terminal commands. Skip for (c)/(d).
- **Q10.2 (keyboard workflow comfort):** if (a), warn that UAP is keyboard-first. Offer to install GNOME or KDE alongside i3 — don't force tiling on someone who hates it.

If the operator wants a folder-as-workflow methodology (one approach is ICM — see `references.md`), they can adopt it themselves after deploy. Don't push it during the wizard.

## When you don't have the artifact

Some questions name a theme/font/option that UAP doesn't ship with yet (e.g., "Dracula" instead of "Tokyo Night"). In that case:

- Record the user's answer.
- During customization, generate the missing artifact (download a theme, render a logo, write a config) and archive it under the appropriate scope folder (`../os/<component>/`, `../ai/<component>/`, or `../workflows/<component>/`) so future deployments inherit it.
- Don't refuse a choice just because the asset isn't already shipped. Generate it.

## What "done" looks like

After the wizard:

- `answers.yaml` exists in this folder and captures every Q&A.
- The live system reflects the chosen customizations (configs deployed, packages installed, services running).
- `../README.md` and the scope folders (`../os/`, `../ai/`, `../workflows/`) reflect *this deployment's* customizations, not just the framework defaults. (Per feedback rule: any tweak must be mirrored into the runbook.)
- A short note in `answers.yaml` records the date of the deployment and the operator (whoever ran the wizard).
