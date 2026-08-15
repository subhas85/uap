#!/usr/bin/env bash
# Reproducibly (re)install the Herdr plugins UAP runs on this box.
# Idempotent: safe to re-run after a `herdr update --handoff`, which drops the
# server's plugin registry (files stay under ~/.config/herdr/plugins/github/).
# Requires Herdr >= 0.7.4 (Claude Usage uses the 0.7.4 "popup" pane type).
set -euo pipefail

# Kept minimal 2026-07-21: only the two passive sidebar meters + the manager.
# The pane-only plugins (file-viewer, pr-tracker, phin-board) were trialled and removed.
PLUGINS=(
  "alejodelosrios/herdr-claude-usage"   # Spaces-sidebar Claude quota (Session%/Week%, account/seat-wide)
  "senna-lang/herdr-agent-usage"        # Agents-sidebar per-agent context + provider rate-limit rows
  "natori-hrj/herdr-lazy"               # declarative plugin manager + lockfile           (ctrl+b shift+l)
)

# To re-add a dropped pane plugin: herdr-lazy add <owner/repo> && herdr-lazy sync,
# then add its keybinding to config.toml. Options considered but not installed:
#   smarzban/herdr-file-viewer  Matovidlo/herdr-pr-tracker  phin-tech/herdr-phin-board
#   aorumbayev/herdr-ctx  (needs Bun; edits ~/.claude/settings.json; dup of usagebar $context)

need="0.7.4"
have="$(herdr --version 2>/dev/null | awk '{print $2}')"
if [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -1)" != "$need" ]; then
  echo "Herdr $have < $need — run the detached update (see README) first." >&2
  exit 1
fi

# herdr-lazy builds from source when no prebuilt binary matches the platform, and
# a fresh Ubuntu Server has no Rust toolchain. Say so up front rather than failing
# three plugins in with a build error.
if ! command -v cargo >/dev/null 2>&1; then
  echo "WARN: cargo not found — herdr-lazy falls back to 'cargo build' when no prebuilt" >&2
  echo "      binary is usable, and will fail without it. Fix: sudo apt install cargo" >&2
fi

# Resolve each plugin to the commit recorded in plugins.lock so a rebuild reproduces
# the set that was actually tested, instead of silently pulling whatever is latest.
# Set UNPINNED=1 to deliberately take latest (then refresh the lock afterwards).
LOCK="$(dirname "$(readlink -f "$0")")/plugins.lock"

lock_ref() {
  [ -f "$LOCK" ] || return 1
  # lines look like: owner/repo@commit   (comments and blanks ignored)
  awk -v repo="$1" -F'@' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { gsub(/[[:space:]]/, "", $1); gsub(/[[:space:]]/, "", $2) }
    $1 == repo { print $2; found=1; exit }
    END { exit !found }
  ' "$LOCK"
}

for p in "${PLUGINS[@]}"; do
  if [ "${UNPINNED:-0}" = 1 ]; then
    echo ">> installing $p (unpinned — latest)"
    herdr plugin install "$p" --yes
  elif ref="$(lock_ref "$p")" && [ -n "$ref" ]; then
    echo ">> installing $p @ ${ref:0:12} (from plugins.lock)"
    herdr plugin install "$p" --ref "$ref" --yes
  else
    echo ">> installing $p (WARN: no plugins.lock entry — taking latest)" >&2
    herdr plugin install "$p" --yes
  fi
done

echo ">> installed:"
herdr plugin list

echo
echo ">> Sidebar rows, toast delivery, and keybindings live in config.toml."
echo "   Tracked reference: uap/ai/herdr/config.toml — merge into ~/.config/herdr/config.toml, then:"
echo "     herdr server reload-config"
