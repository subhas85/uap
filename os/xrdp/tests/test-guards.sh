# Backoff: same fix shouldn't run twice within backoff window
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
export XRDP_WATCHDOG_TEST_CHANSRV_SOCKET=1
XRDP_WATCHDOG_STATE_DIR=$(mktemp -d)
export XRDP_WATCHDOG_STATE_DIR

# First dry-run tick: should "would respawn"
out=$(XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
      XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
      "$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_b: would respawn" "first tick fires fix"

# Second dry-run tick (immediately after): should skip due to backoff
out=$(XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
      XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
      "$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "backoff" "second tick within backoff window skips"

rm -rf "$XRDP_WATCHDOG_STATE_DIR"

# Circuit breaker: 10 fixes in an hour, 11th skipped
XRDP_WATCHDOG_STATE_DIR=$(mktemp -d)
export XRDP_WATCHDOG_STATE_DIR
# Pre-seed the circuit-breaker counter
mkdir -p "$XRDP_WATCHDOG_STATE_DIR"
for i in $(seq 1 10); do date +%s >> "$XRDP_WATCHDOG_STATE_DIR/fixes.hour"; done

out=$(XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
      XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
      "$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "circuit breaker" "11th fix triggers circuit breaker"

rm -rf "$XRDP_WATCHDOG_STATE_DIR"
