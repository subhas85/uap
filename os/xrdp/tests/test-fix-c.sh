export XRDP_WATCHDOG_TEST_JOURNAL=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
XRDP_WATCHDOG_STATE_DIR=$(mktemp -d)
export XRDP_WATCHDOG_STATE_DIR
XRDP_WATCHDOG_FAKE_DISPLAYS="10"
XRDP_WATCHDOG_FAKE_JOURNAL="xrdp-chansrv[123]: [ERROR] clipboard_event_selection_request: unknown target"

out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_c: would respawn chansrv" "dry-run names action"
assert_contains "$out" "display=10" "dry-run names display"
assert_contains "$out" "notify" "dry-run mentions notification step"

rm -rf "$XRDP_WATCHDOG_STATE_DIR"
unset XRDP_WATCHDOG_STATE_DIR
