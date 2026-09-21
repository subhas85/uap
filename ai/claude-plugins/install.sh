#!/usr/bin/env bash
# Reproducibly (re)install the Claude Code plugin profile UAP runs on this box.
# Idempotent: every step checks before it acts. Requires: claude (logged in), node on PATH,
# passwordless sudo for /usr/local/bin and apt. See README.md for what is in, what is out, and why.
#
#   install.sh              # everything
#   install.sh --no-lsp     # skip dotnet-sdk / csharp-ls / typescript-language-server
#   install.sh --no-repos   # skip per-repo local-scope installs
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
LEAN_CTX_VERSION="3.10.2"
REPO_LIST="${HOME}/uap.local/claude-repo-plugins.list"
DO_LSP=1; DO_REPOS=1
for a in "$@"; do case "$a" in --no-lsp) DO_LSP=0;; --no-repos) DO_REPOS=0;; esac; done

say()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

have claude || { echo "claude not on PATH" >&2; exit 1; }
have node   || { echo "node not on PATH (ponytail hooks are node scripts)" >&2; exit 1; }

# --- 0. Snapshot -------------------------------------------------------------
BK="$HOME/.claude/backups/$(date +%F)-claude-plugins"
mkdir -p "$BK"
cp -n "$HOME/.claude/settings.json" "$BK/" 2>/dev/null || true
cp -n "$HOME/.claude.json" "$BK/claude.json" 2>/dev/null && chmod 600 "$BK/claude.json" || true
cp -n "$HOME/.claude/CLAUDE.md" "$BK/" 2>/dev/null || true
claude plugin list > "$BK/plugin-list.txt" 2>&1 || true
say "snapshot in $BK"

# --- 1. User-scope plugins ---------------------------------------------------
# Deliberately NOT here: azure (28 always-on skills + telemetry hook), caveman (terse prose
# works against decision-grade answers), ui-ux-pro-max (competes with a design system).
USER_PLUGINS=(
  superpowers@claude-plugins-official              # brainstorming, systematic-debugging, TDD, verification
  microsoft-docs@claude-plugins-official           # learn.microsoft.com MCP — Azure/.NET/Graph/Intune accuracy
  cloudflare@claude-plugins-official               # Workers, Wrangler, Pages, Access
  claude-md-management@claude-plugins-official     # keeps the CLAUDE.md hub from rotting
  explanatory-output-style@claude-plugins-official # "why this choice" at decision points
  ponytail@ponytail                                # minimal-code bias; lite by default (see ponytail.config.json)
)
installed="$(claude plugin list 2>/dev/null || true)"
claude plugin marketplace list 2>/dev/null | grep -q "ponytail" || claude plugin marketplace add DietrichGebert/ponytail
for p in "${USER_PLUGINS[@]}"; do
  if grep -q "❯ $p" <<<"$installed"; then say "plugin present: $p"; else claude plugin install "$p" --scope user -y; fi
done

# ponytail: default lite; only inject into code-writing subagents, never Explore.
mkdir -p "$HOME/.config/ponytail"
cp "$HERE/ponytail.config.json" "$HOME/.config/ponytail/config.json"
python3 - "$HOME/.claude/settings.json" <<'EOF'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d.setdefault('env',{})['PONYTAIL_SUBAGENT_MATCHER']='general|Plan|claude'
json.dump(d,open(p,'w'),indent=2); open(p,'a').write('\n')
EOF
say "ponytail: lite default, subagent matcher set"

# --- 2. lean-ctx (Hybrid mode: compression + dedup, nothing denied) -------------
if ! have lean-ctx || [ "$(lean-ctx --version 2>/dev/null | awk '{print $2}')" != "$LEAN_CTX_VERSION" ]; then
  tmp="$(mktemp -d)"; base="https://github.com/yvgude/lean-ctx/releases/download/v${LEAN_CTX_VERSION}"
  asset="lean-ctx-x86_64-unknown-linux-gnu.tar.gz"
  curl -sSL -o "$tmp/$asset" "$base/$asset"; curl -sSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"
  (cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c - >/dev/null)
  tar -xzf "$tmp/$asset" -C "$tmp"
  sudo install -m 755 "$(find "$tmp" -type f -name lean-ctx | head -1)" /usr/local/bin/lean-ctx
  rm -rf "$tmp"
fi
say "lean-ctx $(lean-ctx --version | awk '{print $2}')"
# Config BEFORE init so init respects rules_injection=off, compression_level=off, solution.enabled=false.
mkdir -p "$HOME/.config/lean-ctx"
cp "$HERE/lean-ctx.config.toml" "$HOME/.config/lean-ctx/config.toml"
lean-ctx config validate >/dev/null
# NOTE: `lean-ctx init` with no --agent edits ~/.bashrc (shell aliases) AND applies Replace mode. Agent form only.
lean-ctx init --agent claude --mode hybrid >/dev/null
# Guard: Hybrid must never leave native tools denied (plain init / uninstall have both put Grep/Glob in deny).
python3 - "$HOME/.claude/settings.json" <<'EOF2'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); deny=d.get('permissions',{}).get('deny',[])
if any(x in ('Grep','Glob','Read') for x in deny):
    d['permissions']['deny']=[x for x in deny if x not in ('Grep','Glob','Read')]
    json.dump(d,open(p,'w'),indent=2); open(p,'a').write('\n'); print('removed Grep/Glob from permissions.deny')
EOF2
[ -f "$HOME/.bashrc.lean-ctx.bak" ] && ! grep -q "lean-ctx shell hook" "$HOME/.bashrc" && rm -f "$HOME/.bashrc.lean-ctx.bak"
loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q yes || sudo loginctl enable-linger "$USER"
# Pin the mode. The MCP server re-derives it on every session start and 3.10.1 auto-picks Replace
# (Grep/Glob back into permissions.deny) unless LEAN_CTX_HOOK_MODE says otherwise. `hook_mode` in
# config.toml is not recognised by 3.10.1, so the env var goes into settings.json (inherited by hooks
# and the MCP server) and into the daemon unit.
python3 - "$HOME/.claude/settings.json" <<'EOF3'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d.setdefault('env',{})['LEAN_CTX_HOOK_MODE']='hybrid'
json.dump(d,open(p,'w'),indent=2); open(p,'a').write('\n')
EOF3
mkdir -p "$HOME/.config/systemd/user/lean-ctx-daemon.service.d"
printf '[Service]\nEnvironment=LEAN_CTX_HOOK_MODE=hybrid\n' > "$HOME/.config/systemd/user/lean-ctx-daemon.service.d/hybrid.conf"
systemctl --user daemon-reload
lean-ctx daemon enable >/dev/null
say "lean-ctx hybrid: hooks + MCP registered, mode pinned via LEAN_CTX_HOOK_MODE, daemon enabled"

# --- 3. User CLAUDE.md response contract ------------------------------------
if [ -f "$HOME/.claude/CLAUDE.md" ] && ! grep -q "^# Response contract" "$HOME/.claude/CLAUDE.md"; then
  warn "~/.claude/CLAUDE.md exists without the response contract — merge CLAUDE.md.user by hand"
else
  cp "$HERE/CLAUDE.md.user" "$HOME/.claude/CLAUDE.md"; say "~/.claude/CLAUDE.md response contract"
fi

# --- 4. Language servers -----------------------------------------------------
if [ "$DO_LSP" = 1 ]; then
  have dotnet || sudo apt-get install -y -qq dotnet-sdk-8.0
  # csharp-ls >= 0.17 ships in the .NET 10 tool-package format the Ubuntu .NET 8 SDK cannot read.
  have csharp-ls || { dotnet tool install -g csharp-ls --version 0.16.0 >/dev/null; ln -sf "$HOME/.dotnet/tools/csharp-ls" "$HOME/.local/bin/csharp-ls"; }
  if ! have typescript-language-server; then
    npm install -g typescript typescript-language-server >/dev/null
    nbin="$(dirname "$(readlink -f "$(command -v node)")")"
    ln -sf "$nbin/typescript-language-server" "$HOME/.local/bin/typescript-language-server"
    ln -sf "$nbin/tsc" "$HOME/.local/bin/tsc"
  fi
  say "LSP: csharp-ls $(csharp-ls --version 2>/dev/null | head -1 | awk '{print $2}'), typescript-language-server $(typescript-language-server --version)"
fi

# --- 5. Per-repo local-scope plugins ----------------------------------------
if [ "$DO_REPOS" = 1 ]; then
  if [ -f "$REPO_LIST" ]; then
    while read -r repo plugins; do
      [[ -z "$repo" || "$repo" == \#* ]] && continue
      [ -d "$repo" ] || { warn "skip $repo (missing)"; continue; }
      for p in $plugins; do (cd "$repo" && claude plugin install "$p" --scope local -y >/dev/null) && say "$(basename "$repo"): $p"; done
    done < "$REPO_LIST"
  else
    warn "no $REPO_LIST — copy repo-plugins.example.list there to enable per-repo LSPs"
  fi
fi

echo; lean-ctx doctor 2>/dev/null | grep -E "Daemon|Shell allowlist|MCP config|instructions" || true
echo "Verify in a new session: PONYTAIL MODE ACTIVE (lite) notice, ~/.claude/CLAUDE.md unchanged."
