export XRDP_WATCHDOG_TEST_JOURNAL=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
XRDP_WATCHDOG_FAKE_DISPLAYS="10"

# Test 1: no cliprdr errors in journal → OK
XRDP_WATCHDOG_FAKE_JOURNAL="May 23 12:00:00 host xrdp[100]: info: connected ok" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check C: OK" "no cliprdr errors → OK"

# Test 2: cliprdr error pattern in journal → BAD
XRDP_WATCHDOG_FAKE_JOURNAL="May 23 12:00:00 host xrdp-chansrv[123]: [ERROR] clipboard_event_selection_request: unknown target text/plain;charset=utf-8" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check C: BAD" "cliprdr error in journal → BAD"
