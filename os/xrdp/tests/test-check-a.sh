# Test Check A — stale xrdp child detection

# Setup: source the script's functions without running main
export XRDP_WATCHDOG_TEST_LIST_XRDP_CHILDREN=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1

# Test 1: no xrdp children → OK
XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check A: OK" "no children → OK"

# Test 2: exactly one child for a display (solo-session guard) → OK even if stale
XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="9001" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_PID_AGES="9001=300" \
XRDP_WATCHDOG_FAKE_PID_DISPLAYS="9001=10" \
XRDP_WATCHDOG_FAKE_PID_TCP_DEAD="9001=true" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check A: OK" "solo session never marked stale"

# Test 3: two children for same display, one stale → BAD
XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="9001 9002" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_PID_AGES="9001=300 9002=5" \
XRDP_WATCHDOG_FAKE_PID_DISPLAYS="9001=10 9002=10" \
XRDP_WATCHDOG_FAKE_PID_TCP_DEAD="9001=true 9002=false" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check A: BAD" "stale child + new child → BAD"
assert_contains "$out" "9001" "BAD reason names the stale pid"

# Test 4: two children, both healthy → OK
XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="9001 9002" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_PID_AGES="9001=300 9002=300" \
XRDP_WATCHDOG_FAKE_PID_DISPLAYS="9001=10 9002=10" \
XRDP_WATCHDOG_FAKE_PID_TCP_DEAD="9001=false 9002=false" \
    out=$("$WATCHDOG_BIN" --check 2>&1)
assert_contains "$out" "Check A: OK" "two healthy children → OK"
