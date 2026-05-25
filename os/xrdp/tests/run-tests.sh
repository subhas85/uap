#!/usr/bin/env bash
# Bash test harness for xrdp-watchdog.
# Usage: ./run-tests.sh [test-file-glob]
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHDOG_BIN="${WATCHDOG_BIN:-$SCRIPT_DIR/../xrdp-watchdog}"
export WATCHDOG_BIN

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local actual="$1" expected="$2" name="${3:-(unnamed)}"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS+1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$name")
        echo "  FAIL: $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" name="${3:-(unnamed)}"
    if echo "$haystack" | grep -qF -- "$needle"; then
        PASS=$((PASS+1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$name")
        echo "  FAIL: $name (expected output to contain '$needle')"
        echo "    actual: $haystack"
    fi
}

run_test_file() {
    local f="$1"
    echo "=== $f ==="
    # shellcheck disable=SC1090
    source "$f"
}

GLOB="${1:-test-*.sh}"
for f in "$SCRIPT_DIR"/$GLOB; do
    [ -f "$f" ] || continue
    run_test_file "$f"
done

echo ""
echo "=== summary ==="
echo "passed: $PASS, failed: $FAIL"
if [ $FAIL -gt 0 ]; then
    printf "failed tests:\n"
    printf "  - %s\n" "${FAILED_TESTS[@]}"
    exit 1
fi
exit 0
