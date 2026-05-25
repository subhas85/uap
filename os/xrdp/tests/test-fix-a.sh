# Test Fix A — kill stale xrdp child (dry-run only; we can't actually kill processes)

export XRDP_WATCHDOG_TEST_LIST_XRDP_CHILDREN=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
XRDP_WATCHDOG_STATE_DIR=$(mktemp -d)
export XRDP_WATCHDOG_STATE_DIR

XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="9001 9002" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_PID_AGES="9001=300 9002=5" \
XRDP_WATCHDOG_FAKE_PID_DISPLAYS="9001=10 9002=10" \
XRDP_WATCHDOG_FAKE_PID_TCP_DEAD="9001=true 9002=false" \
    out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_a: would kill" "dry-run fix A names action"
assert_contains "$out" "9001" "dry-run names stale pid"

rm -rf "$XRDP_WATCHDOG_STATE_DIR"
unset XRDP_WATCHDOG_STATE_DIR
