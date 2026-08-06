#!/usr/bin/env bash
# herdr sysmeter — publish host CPU% and RAM% as a herdr sidebar token.
# Renders on the claude-usage "Claude" mini-space (needs a ["$sys"] row in
# [ui.sidebar.spaces]). Pushed, not polled: herdr tokens must be re-reported,
# so this loops. TTL clears the row if the reporter dies.
set -u
INTERVAL="${SYSMETER_INTERVAL:-5}"
TTL_MS="${SYSMETER_TTL_MS:-15000}"
HERDR="${HERDR_BIN:-herdr}"

read_cpu() { # -> "idle total"
  read -r _ a b c d e f g h _ < /proc/stat
  echo "$(( d + e )) $(( a + b + c + d + e + f + g + h ))"
}

read -r pidle ptot <<<"$(read_cpu)"
while :; do
  sleep "$INTERVAL"
  read -r idle tot <<<"$(read_cpu)"
  dt=$(( tot - ptot )); di=$(( idle - pidle )); pidle=$idle; ptot=$tot
  cpu=0; [ "$dt" -gt 0 ] && cpu=$(( (100 * (dt - di)) / dt ))
  mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  ram=0; [ "${mt:-0}" -gt 0 ] && ram=$(( (100 * (mt - ma)) / mt ))
  wid=$("$HERDR" workspace list 2>/dev/null | python3 -c "import sys,json
w=[x['workspace_id'] for x in json.load(sys.stdin)['result']['workspaces'] if x['label']=='Claude']
print(w[0] if w else '')" 2>/dev/null)
  [ -n "$wid" ] && "$HERDR" workspace report-metadata "$wid" \
    --source sysmeter --token "sys=CPU ${cpu}% · RAM ${ram}%" --ttl-ms "$TTL_MS" >/dev/null 2>&1
done
