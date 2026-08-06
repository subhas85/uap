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

for p in "${PLUGINS[@]}"; do
  echo ">> installing $p"
  herdr plugin install "$p" --yes
done

echo ">> installed:"
herdr plugin list

echo
echo ">> Sidebar rows, toast delivery, and keybindings live in config.toml."
echo "   Tracked reference: uap/ai/herdr/config.toml — merge into ~/.config/herdr/config.toml, then:"
echo "     herdr server reload-config"
