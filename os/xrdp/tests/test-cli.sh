# tests for CLI argument parsing
out=$("$WATCHDOG_BIN" --help 2>&1)
assert_contains "$out" "xrdp-watchdog" "help mentions tool name"
assert_contains "$out" "--check" "help lists --check"
assert_contains "$out" "--explain" "help lists --explain"
assert_contains "$out" "--dry-run" "help lists --dry-run"

out=$("$WATCHDOG_BIN" --unknown-flag 2>&1)
rc=$?
assert_eq "$rc" "2" "unknown flag exits 2"
