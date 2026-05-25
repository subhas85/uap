#!/usr/bin/env bash
# Integration test for xrdp-watchdog — REPRODUCES BUGS, runs only on test VMs.
#
# Refuses to run unless /etc/uap.local/test-mode exists.
set -euo pipefail

if [ ! -f /etc/uap.local/test-mode ]; then
    echo "REFUSING TO RUN: this test breaks xrdp on purpose."
    echo "Create /etc/uap.local/test-mode if this is a disposable VM."
    exit 1
fi

WATCHDOG="${WATCHDOG_BIN:-/usr/local/bin/xrdp-watchdog}"
[ -x "$WATCHDOG" ] || { echo "$WATCHDOG not executable"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

echo "=== Integration test 1: Check B — kill a chansrv, verify respawn ==="
chansrv_pid=$(pgrep -f xrdp-chansrv | head -1)
[ -n "$chansrv_pid" ] || fail "no chansrv to kill — is an RDP session active?"
display=$(sudo lsof -p "$chansrv_pid" 2>/dev/null | grep -oE 'xrdp_chansrv_socket_[0-9]+' | head -1 | sed 's|.*_||')
[ -n "$display" ] || fail "could not determine display for chansrv pid=$chansrv_pid"

echo "  killing chansrv pid=$chansrv_pid for display=$display"
sudo kill -KILL "$chansrv_pid"
sleep 2

echo "  running watchdog --once"
sudo "$WATCHDOG" --once

sleep 3
new_chansrv=$(pgrep -f xrdp-chansrv | head -1)
[ -n "$new_chansrv" ] && [ "$new_chansrv" != "$chansrv_pid" ] && \
    pass "chansrv respawned: old=$chansrv_pid new=$new_chansrv" || \
    fail "chansrv not respawned"

echo ""
echo "=== Integration test 2: Check C — synthesize cliprdr error log, verify Fix C ==="
echo "  emitting fake cliprdr error to journal"
logger -t xrdp-chansrv -p user.err "[ERROR] clipboard_event_selection_request: unknown target text/plain (integration test)"
sleep 1
sudo "$WATCHDOG" --once
echo "  (visual check: a notify-send notification should have appeared)"
pass "Check C integration ran without crash"

echo ""
echo "=== Integration test 3: --check exit codes ==="
sudo "$WATCHDOG" --check >/dev/null
rc=$?
[ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] && pass "--check exit code valid ($rc)" || fail "unexpected rc=$rc"

echo ""
echo "All integration tests passed."
