# Test Check B — chansrv socket health per display
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
export XRDP_WATCHDOG_TEST_CHANSRV_SOCKET=1

# Test 1: socket LISTEN for active display → OK
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_CHANSRV_10="LISTEN" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check B: OK" "LISTEN socket → OK"

# Test 2: socket MISSING for active display → BAD
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check B: BAD" "missing socket → BAD"
assert_contains "$out" "display=10" "BAD names affected display"

# Test 3: multi-display, one bad
XRDP_WATCHDOG_FAKE_DISPLAYS="10 11" \
XRDP_WATCHDOG_FAKE_CHANSRV_10="LISTEN" \
XRDP_WATCHDOG_FAKE_CHANSRV_11="MISSING" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check B: BAD" "any missing → BAD"
assert_contains "$out" "display=11" "BAD names the right display"
