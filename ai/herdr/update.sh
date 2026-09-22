#!/usr/bin/env bash
# herdr full-stop update: stop server → herdr update → headless server → plugins → integrations.
# For jumps that cross an endpoint-generation / protocol boundary (0.7.x → 0.9.x) where
# `herdr update --handoff` cannot carry panes. Layout comes back from session.json, pane
# text from session-history.json (experimental.pane_history), Claude panes via native
# `claude --resume`. Run DETACHED, outside any Herdr pane — see README "Updating".
#
#   NEW_CONFIG=/path/config.toml   copy this over ~/.config/herdr/config.toml while stopped
#   UNPINNED=1                     take latest plugin commits and rewrite plugins.lock
set -u
if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_CHILD_SESSION:-}" ]; then
  echo "refusing: running inside a Claude Code shell. Run from a plain terminal (or Hermes), see README." >&2
  exit 2
fi
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CFG_DIR="$HOME/.config/herdr"
LOG="$CFG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
exec >>"$LOG" 2>&1
log() { printf '%s %s\n' "$(date +%T)" "$*"; }

log "== herdr update start: $(herdr --version)"
herdr workspace list > "$CFG_DIR/layout-pre-update.json" 2>/dev/null || true

log "-- server stop"
herdr server stop || log "server stop returned $?"
for _ in $(seq 1 30); do pgrep -x herdr >/dev/null || break; sleep 1; done
pgrep -x herdr >/dev/null && { log "old server still alive, killing"; pkill -x herdr; sleep 2; }

if [ -n "${NEW_CONFIG:-}" ]; then
  log "-- config: installing $NEW_CONFIG"
  cp -f "$CFG_DIR/config.toml" "$CFG_DIR/config.toml.pre-update"
  install -m 644 "$NEW_CONFIG" "$CFG_DIR/config.toml"
fi

log "-- herdr update"
herdr update </dev/null || { log "UPDATE FAILED ($?) — restarting old server"; }
log "now: $(herdr --version)"

log "-- plugins (UNPINNED=${UNPINNED:-0})"
UNPINNED="${UNPINNED:-0}" bash "$HERE/install-plugins.sh" || log "install-plugins.sh returned $?"
if [ "${UNPINNED:-0}" = 1 ]; then
  {
    echo "# herdr-lazy lock — resolved plugin set at last sync ($(date +%F), herdr $(herdr --version | awk '{print $2}'))."
    echo "# Each \`owner/repo@commit\` reproduces exactly via \`plugin install --ref\`."
    echo
    herdr plugin list | grep -o 'github:[^@]*@[0-9a-f]*' | sed 's/^github://'
  } > "$HERE/plugins.lock"
  log "plugins.lock rewritten"; cat "$HERE/plugins.lock"
fi

log "-- integrations"
herdr integration install claude </dev/null || true
herdr integration install hermes </dev/null || true
herdr integration status
sudo -n systemctl restart hermes-gateway.service || log "hermes restart returned $? (system unit needs root)"

log "-- final state"
herdr --version
herdr plugin list
herdr integration status
# Deliberately NOT starting the server here. Panes inherit the server's environment,
# so it must be spawned by the user's own client (Alt+d → Herdr) with the desktop
# session env — not by whatever shell ran this script. 2026-09-21: a server started
# from a Claude Code shell gave every pane CLAUDE_CODE_CHILD_SESSION=1 and Claude Code
# silently stopped saving transcripts.
log "== done. Start the server yourself: Alt+d → Herdr (terminal workspace). Layout, pane text and Claude sessions restore on attach."
