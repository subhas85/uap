export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
export XRDP_WATCHDOG_TEST_CHANSRV_SOCKET=1
XRDP_WATCHDOG_STATE_DIR=$(mktemp -d)
export XRDP_WATCHDOG_STATE_DIR

XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
    out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_b: would respawn chansrv" "dry-run names action"
assert_contains "$out" "display=10" "dry-run names display"

rm -rf "$XRDP_WATCHDOG_STATE_DIR"
unset XRDP_WATCHDOG_STATE_DIR
