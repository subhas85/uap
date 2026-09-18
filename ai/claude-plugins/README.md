# Claude Code plugin profile

The set of Claude Code plugins, hooks and language servers UAP installs, and the reasoning for
what is deliberately left out. `install.sh` is idempotent and standalone (not driven by
`apply.sh`); run it on a fresh box after Claude Code is logged in, or re-run to converge.

## Goals, in priority order

1. Model accuracy and sound solutions.
2. Easy navigation of a multi-repo workspace.
3. Answers the operator can understand and make decisions on.
4. Token cost — only when it does not cost 1–3.

Every always-on skill description is injected into every session's system prompt. Competing
instructions dilute accuracy, so the bar for user-scope plugins is high; repo-specific tooling goes
in at `--scope local` inside the repo that needs it.

## What is installed

| Scope | Plugin | Why |
|---|---|---|
| user | superpowers | brainstorming, systematic-debugging, TDD, verification-before-completion |
| user | microsoft-docs | learn.microsoft.com MCP; grounds Azure / .NET / Graph / Intune answers |
| user | cloudflare | Workers, Wrangler, Pages, Access skills |
| user | claude-md-management | audits and maintains the CLAUDE.md hub |
| user | explanatory-output-style | explains the *why* at decision points |
| user | ponytail (`lite` default) | minimal-code bias; `/ponytail full` for pure coding, `/ponytail off` for ops |
| user | lean-ctx 3.10.x, Hybrid mode | shell-output compression + read dedup + MCP `ctx_*` tools; nothing denied |
| hub | typescript-lsp, csharp-lsp, context7 | enabled at the workspace hub so hub-started sessions get them; LSP binaries must be on PATH |
| hub | `mssql` MCP (`.mcp.json`) | QA database; the launcher reads the connection string from a vault at start, never from the file |
| repo | frontend-design, context7, LSPs | also at local scope inside each repo, as a fallback for sessions started there |

`~/uap.local/claude-repo-plugins.list` maps repos to their local-scope plugins (see
`repo-plugins.example.list`); the first line should be the workspace hub itself. Local scope writes
`.claude/settings.local.json`, which Claude Code git-ignores.

## What is deliberately out

| Plugin | Reason |
|---|---|
| caveman | Drops articles, fragments, "no tables". Works directly against goal 3 and degrades anything pasted onward (tickets, memos). The response contract in `CLAUDE.md.user` gives the useful half (answer-first, no filler) without the damage. |
| azure (official) | 28 always-on skills (~2.3k words, mostly AKS/Foundry), a PostToolUse hook that publishes telemetry to Microsoft via `npx @azure/mcp`, MCP re-resolves `@latest` on every start. `az` CLI already covers the useful part. |
| ui-ux-pro-max | 26 skills / ~1.5k words always-on; its palette/font database competes with a workspace design system. |
| lean-ctx Replace mode | Denies native Grep/Glob globally; every skill and subagent that assumes them degrades. Hybrid keeps the savings that matter (shell output, re-reads). |
| netlify-skills | 45 skills / ~3.8k words always-on — heavier than ui-ux-pro-max. |

## lean-ctx settings that matter (`lean-ctx.config.toml`)

| Key | Value | Effect |
|---|---|---|
| `shell_security` | `off` | The allowlist gates the *whole* compound Bash command, not just what is compressed; `warn` prints a WARN line into every affected tool result. Claude Code `permissions.deny` stays the safety net. |
| `shell_allow_inline_scripts` | `true` | `python3 -c` / `node -e` are normal here; default blocks them. |
| `read_redirect` | `off` | Native Read returns the real file, not a compressed view. |
| `rules_injection` | `off` | Nothing written into `~/.claude/CLAUDE.md`; no `lean-ctx` skill installed. |
| `prompt_reinject` | `off` | 3.10.1 otherwise injects a "ctx_* policy overrules native Bash" line on every prompt. |
| `compression_level` | `off` | Shapes model prose only (would inject "concise, skip hedging"); tool-output compression is unaffected. |
| `[solution] enabled` | `false` | Drops the YAGNI ladder from MCP instructions; ponytail already provides it. |
| `tool_profile` | `standard` | 16 MCP tools instead of 68. |
| `shadow_mode` | `false` | Redirect hooks stop logging/nudging "shadow intercepts" on native Read/Grep. |
| env `LEAN_CTX_HOOK_MODE=hybrid` | settings.json `env` + daemon drop-in | **The one that matters.** The MCP server re-derives the mode on every session start and auto-picks Replace for Claude; without this pin Grep/Glob reappear in `permissions.deny` after every session. `hook_mode` in config.toml is not recognised by 3.10.1. |

Write the config **before** `lean-ctx init` and keep top-level keys above the first `[section]` (TOML).
`lean-ctx init` with no `--agent` edits `~/.bashrc` **and** applies Replace mode (Grep/Glob into
`permissions.deny`); `lean-ctx uninstall` restored that deny too, and so does **every MCP server start** unless
`LEAN_CTX_HOOK_MODE=hybrid` is in the environment. `install.sh` pins the env and strips the deny after init.
Known 3.10.1 limitation: the SessionStart hook injects an unconditional "ALWAYS use ctx_* … denied by hook"
banner (no config or env switch short of `LEAN_CTX_DISABLED=1`; upstream `main` gates it on
`rules_injection=off`, so a later release should fix it). `CLAUDE.md.user` tells the model to ignore it. Never run `lean-ctx doctor --fix`. Restart the daemon after config edits. Alternative considered:
**rtk** (one PreToolUse hook, no daemon/MCP) — same retained benefit with less machinery; kept lean-ctx
for parity with the operator's other box.

## Capabilities vs instructions (why LSPs live at the workspace hub)

Claude Code loads a subfolder's `CLAUDE.md` lazily when it reads files there, but **plugins, hooks, MCP
servers, skills, agents, commands and the LSP root are fixed at launch** from the start directory plus user
scope. An operator who starts sessions at the workspace hub never gets a repo's `.claude/` tooling. So:
cheap, broadly useful capabilities (LSPs, context7, a QA-database MCP) are enabled at the hub; heavy
repo-specific process tooling stays in the repo and those sessions are started there.

## Verify

```
claude -p "Reply SESSION-OK and say whether a PONYTAIL MODE ACTIVE notice is present"
lean-ctx doctor        # Daemon running, Shell allowlist off, rules injection off
claude mcp list        # lean-ctx and microsoft-learn Connected
```
