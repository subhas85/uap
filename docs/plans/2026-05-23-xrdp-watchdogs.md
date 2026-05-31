# xrdp Watchdogs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an idempotent `xrdp-watchdog` to the UAP `xrdp` module that auto-detects and remediates the three known reattach bugs (stale xrdp child, missing/defunct chansrv, cliprdr desync) so operators can safely run xrdp with `Policy=U`/`Policy=UB`.

**Architecture:** Single bash script driven by a systemd timer every 30s. Each tick is independent and idempotent. State-based detection (not log-pattern coupled) for version durability. Conservative remediation with flock, backoff, and a circuit breaker. Installs via existing UAP `apply.sh` extended with new identity flags.

**Tech Stack:** bash, systemd (service + timer), `flock`, `ss`, `lsof`, `ps`, `journalctl`, `notify-send` (optional), `yq` (existing UAP dep), `envsubst` (existing UAP pattern).

**Spec:** `~/uap/docs/specs/2026-05-23-xrdp-watchdogs-design.md`

---

## File Structure

**New files in repo:**

| Path | Purpose |
|---|---|
| `os/xrdp/xrdp-watchdog` | Main bash script (~250 lines) |
| `os/xrdp/xrdp-watchdog.service.tmpl` | systemd oneshot unit (template) |
| `os/xrdp/xrdp-watchdog.timer.tmpl` | systemd timer (template, renders `OnUnitActiveSec`) |
| `os/xrdp/xrdp-watchdog.sudoers` | sudoers fragment installed to `/etc/sudoers.d/` |
| `os/xrdp/tests/run-tests.sh` | Bash test harness for the watchdog script |
| `os/xrdp/tests/test-checks.sh` | Tests for Check A/B/C logic |
| `os/xrdp/tests/test-fixes.sh` | Tests for Fix A/B/C logic (mocked) |
| `os/xrdp/tests/test-guards.sh` | Tests for flock, backoff, circuit breaker |
| `os/xrdp/tests/integration.sh` | End-to-end integration test (disposable VM only) |

**Modified files in repo:**

| Path | Change |
|---|---|
| `setup/apply.sh` | Add identity reads + `install_xrdp()` extensions |
| `profiles/personal-lab.yaml`, `engineer.yaml`, `staff.yaml`, `production-admin.yaml` | Add new `xrdp.*` defaults |
| `README.md` | Add "Known issues — RDP reconnect bugs" section |

**Per-machine identity (NOT in repo):**

| Path | Change |
|---|---|
| `~/uap.local/identity.yaml` | Add `xrdp.install_watchdog`, `watchdog_interval_seconds`, `watchdog_clipboard_active_probe`, `tcp_keepalive` |

**Installed-on-disk (rendered by apply.sh):**

| Path | Owner | Mode | Source |
|---|---|---|---|
| `/usr/local/bin/xrdp-watchdog` | root:root | 755 | rendered from `os/xrdp/xrdp-watchdog` |
| `/etc/systemd/system/xrdp-watchdog.service` | root:root | 644 | rendered from `.service.tmpl` |
| `/etc/systemd/system/xrdp-watchdog.timer` | root:root | 644 | rendered from `.timer.tmpl` (`${WATCHDOG_INTERVAL_SECONDS}` substituted) |
| `/etc/sudoers.d/xrdp-watchdog` | root:root | 440 | rendered + `visudo -c` validated |

---

### Task 1: Add identity schema fields

**Files:**
- Modify: `~/uap.local/identity.yaml` (per-machine, not in repo)
- Modify: `profiles/personal-lab.yaml`
- Modify: `profiles/engineer.yaml`
- Modify: `profiles/staff.yaml`
- Modify: `profiles/production-admin.yaml`

- [ ] **Step 1: Add fields to `~/uap.local/identity.yaml` under the existing `xrdp:` block**

After the existing `sesman_policy` and `install_reconnectwm` lines, add:

```yaml
  install_watchdog: auto                  # true | false | auto (auto = on if policy is U|UB)
  watchdog_interval_seconds: 30
  watchdog_clipboard_active_probe: false  # opt-in, touches clipboard every tick
  tcp_keepalive: true                     # patches /etc/xrdp/xrdp.ini [Globals]
```

- [ ] **Step 2: Add the same defaults to all four profile templates in `profiles/`**

For each of `personal-lab.yaml`, `engineer.yaml`, `staff.yaml`, `production-admin.yaml`, add the same four lines under the `xrdp:` block. Use the same values — the framework defaults are conservative (`install_watchdog: auto` defers to policy; `tcp_keepalive: true` is the safe upgrade).

- [ ] **Step 3: Verify each profile still parses with yq**

Run:
```bash
for f in ~/uap/profiles/*.yaml ~/uap.local/identity.yaml; do
    echo "=== $f ==="
    yq '.xrdp' "$f"
done
```

Expected: each prints the full `xrdp:` block with the four new fields. No parse errors.

- [ ] **Step 4: Commit**

```bash
cd ~/uap
git add profiles/*.yaml
git commit -m "xrdp: add watchdog + tcp_keepalive identity fields to profiles"
```

Note: `~/uap.local/identity.yaml` is intentionally NOT committed — it's per-machine.

---

### Task 2: Read new identity fields in apply.sh

**Files:**
- Modify: `setup/apply.sh` (top of file where other identity reads live, around lines 160-170)

- [ ] **Step 1: Find the existing xrdp identity reads in apply.sh**

Run: `grep -n "SESMAN_POLICY\|INSTALL_RECONNECTWM\|RDP_LCID" ~/uap/setup/apply.sh`

Expected: shows existing `yq '.xrdp.sesman_policy'` and `yq '.xrdp.install_reconnectwm'` reads.

- [ ] **Step 2: Add four new identity reads next to the existing xrdp reads**

After the existing `INSTALL_RECONNECTWM=$(yq …)` line, add:

```bash
INSTALL_WATCHDOG=$(yq          '.xrdp.install_watchdog // "auto"'         "$IDENTITY")
WATCHDOG_INTERVAL_SECONDS=$(yq '.xrdp.watchdog_interval_seconds // 30'    "$IDENTITY")
WATCHDOG_CLIP_ACTIVE=$(yq      '.xrdp.watchdog_clipboard_active_probe // false' "$IDENTITY")
TCP_KEEPALIVE=$(yq             '.xrdp.tcp_keepalive // true'              "$IDENTITY")
```

The `// <default>` clauses make these safe if the field is absent from older identity files.

- [ ] **Step 3: Verify**

Run:
```bash
cd ~/uap && bash -n setup/apply.sh && echo "syntax OK"
~/uap/setup/apply.sh --dry-run 2>&1 | grep -i "xrdp\|watchdog" | head -20
```

Expected: syntax OK; dry-run mentions the existing xrdp install steps. The new vars aren't used yet, so won't appear in output.

- [ ] **Step 4: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "apply.sh: read watchdog + tcp_keepalive identity fields"
```

---

### Task 3: tcp_keepalive patch logic in install_xrdp()

**Files:**
- Modify: `setup/apply.sh` (inside `install_xrdp()`, after the sesman.ini Policy patch, before reconnectwm.sh install)

- [ ] **Step 1: Find the insertion point**

Run: `grep -n "Install reconnectwm" ~/uap/setup/apply.sh`

Expected: shows the comment line `# 3. Install reconnectwm.sh …`. Insert before it.

- [ ] **Step 2: Add the patch block**

Insert this block immediately before the `# 3. Install reconnectwm.sh` comment:

```bash
    # 2b. Patch /etc/xrdp/xrdp.ini [Globals] tcp_keepalive (idempotent)
    if [ "$TCP_KEEPALIVE" = "true" ] && [ -f /etc/xrdp/xrdp.ini ]; then
        if ! grep -qE '^tcp_keepalive=true' /etc/xrdp/xrdp.ini; then
            if grep -qE '^tcp_keepalive=' /etc/xrdp/xrdp.ini; then
                run_sudo sed -i 's/^tcp_keepalive=.*/tcp_keepalive=true/' /etc/xrdp/xrdp.ini
            else
                # Insert after [Globals] header (first line matching exactly that)
                run_sudo sed -i '/^\[Globals\]$/a tcp_keepalive=true' /etc/xrdp/xrdp.ini
            fi
            log "xrdp: xrdp.ini tcp_keepalive=true patched"
        else
            log "xrdp: xrdp.ini tcp_keepalive already true"
        fi
    fi
```

Also add a corresponding DRY-RUN line in the existing dry-run block above:

```bash
        [ "$TCP_KEEPALIVE" = "true" ] && log "xrdp: DRY-RUN — would ensure tcp_keepalive=true in xrdp.ini [Globals]"
```

- [ ] **Step 3: Verify idempotency on the live box**

Run:
```bash
bash -n ~/uap/setup/apply.sh && echo "syntax OK"
grep "^tcp_keepalive" /etc/xrdp/xrdp.ini
```

Expected: syntax OK; live file already shows `tcp_keepalive=true` (per `project_rdp_fixes.md` notes: confirmed live 2026-05-23).

Run apply.sh and verify it logs "already true":
```bash
~/uap/setup/apply.sh 2>&1 | grep tcp_keepalive
```

Expected: log line `xrdp: xrdp.ini tcp_keepalive already true`. No file change.

- [ ] **Step 4: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "xrdp: idempotently patch xrdp.ini tcp_keepalive in apply.sh"
```

---

### Task 4: Create watchdog script skeleton with CLI parsing and helper shims

**Files:**
- Create: `os/xrdp/xrdp-watchdog`
- Create: `os/xrdp/tests/run-tests.sh`

This task establishes the script's outer shell: argument parsing, logging helpers, the four detection-helper shims that are env-overrideable for testing, and stubs for the three checks/fixes. Subsequent tasks fill in the bodies.

- [ ] **Step 1: Create the test harness first (TDD)**

Create `os/xrdp/tests/run-tests.sh` with the following content:

```bash
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
    if echo "$haystack" | grep -qF "$needle"; then
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
```

```bash
chmod +x ~/uap/os/xrdp/tests/run-tests.sh
mkdir -p ~/uap/os/xrdp/tests
```

- [ ] **Step 2: Create the first failing test (asserts script runs with --help)**

Create `os/xrdp/tests/test-cli.sh`:

```bash
# tests for CLI argument parsing
out=$("$WATCHDOG_BIN" --help 2>&1)
assert_contains "$out" "xrdp-watchdog" "help mentions tool name"
assert_contains "$out" "--check" "help lists --check"
assert_contains "$out" "--explain" "help lists --explain"
assert_contains "$out" "--dry-run" "help lists --dry-run"

out=$("$WATCHDOG_BIN" --unknown-flag 2>&1)
rc=$?
assert_eq "$rc" "2" "unknown flag exits 2"
```

- [ ] **Step 3: Run the test, verify it fails (script doesn't exist yet)**

```bash
cd ~/uap/os/xrdp/tests
./run-tests.sh test-cli.sh
```

Expected: tests FAIL because `WATCHDOG_BIN` (the script at `../xrdp-watchdog`) does not exist.

- [ ] **Step 4: Create the watchdog script skeleton**

Create `os/xrdp/xrdp-watchdog`:

```bash
#!/usr/bin/env bash
# xrdp-watchdog — detects and remediates known xrdp reconnect bugs.
# See: ~/uap/docs/specs/2026-05-23-xrdp-watchdogs-design.md
set -u

PROG="xrdp-watchdog"
VERSION="0.1.0"

# --- mode flags (set by parse_args) ---
MODE="tick"        # tick | check | explain | once | help
DRY_RUN=0
LOG_LEVEL="info"   # debug | info | warning | error

# --- helper shims (env-overrideable for tests) ---
# Each shim prints state to stdout. Tests can override the function entirely
# by exporting XRDP_WATCHDOG_TEST_<NAME>=1 and providing alternate output via
# the matching env var.

_list_xrdp_children() {
    if [ "${XRDP_WATCHDOG_TEST_LIST_XRDP_CHILDREN:-0}" = "1" ]; then
        echo "${XRDP_WATCHDOG_FAKE_XRDP_CHILDREN:-}"
        return 0
    fi
    # PIDs of xrdp processes that are children of the xrdp listener.
    pgrep -P "$(pgrep -x xrdp | head -1)" xrdp 2>/dev/null || true
}

_get_chansrv_socket_state() {
    local display="$1"
    if [ "${XRDP_WATCHDOG_TEST_CHANSRV_SOCKET:-0}" = "1" ]; then
        # Fake state via env: XRDP_WATCHDOG_FAKE_CHANSRV_<N>=LISTEN|CONNECTED|MISSING
        local var="XRDP_WATCHDOG_FAKE_CHANSRV_${display}"
        echo "${!var:-MISSING}"
        return 0
    fi
    local sock="/run/xrdp/sockdir/xrdp_chansrv_socket_${display}"
    if [ ! -S "$sock" ]; then
        echo "MISSING"
        return 0
    fi
    # If lsof shows the socket has a peer that's a live xrdp child = CONNECTED;
    # else (only chansrv itself listening) = LISTEN.
    if sudo lsof -U 2>/dev/null | grep -qE "xrdp_chansrv_socket_${display}.*type=STREAM.*CONNECTED"; then
        echo "CONNECTED"
    else
        echo "LISTEN"
    fi
}

_list_active_displays() {
    if [ "${XRDP_WATCHDOG_TEST_LIST_DISPLAYS:-0}" = "1" ]; then
        echo "${XRDP_WATCHDOG_FAKE_DISPLAYS:-}"
        return 0
    fi
    ls /tmp/.X11-unix/X* 2>/dev/null | sed 's|.*X||' | sort -n
}

_journalctl_recent_errors() {
    local since="${1:-1 minute ago}"
    if [ "${XRDP_WATCHDOG_TEST_JOURNAL:-0}" = "1" ]; then
        echo "${XRDP_WATCHDOG_FAKE_JOURNAL:-}"
        return 0
    fi
    journalctl -u xrdp -u xrdp-sesman --since "$since" --no-pager 2>/dev/null || true
}

# --- logging ---
log() {
    local level="$1"; shift
    case "$level" in
        debug)   [ "$LOG_LEVEL" = "debug" ] || return 0 ;;
    esac
    logger -t "$PROG" -p "user.$level" -- "$*"
    [ -t 1 ] && echo "[$level] $*"
}

# --- check/fix stubs (filled in by later tasks) ---
check_a_stale_xrdp_child() { echo "OK"; }
check_b_chansrv_health()   { echo "OK"; }
check_c_cliprdr_log_scan() { echo "OK"; }

fix_a_kill_stale() { log info "fix_a: stub"; }
fix_b_respawn_chansrv() { log info "fix_b: stub"; }
fix_c_restart_chansrv_notify() { log info "fix_c: stub"; }

# --- CLI ---
print_help() {
    cat <<EOF
$PROG $VERSION — detect/remediate known xrdp reconnect bugs

Usage: $PROG [MODE]

Modes:
  (no args)    Run one tick (timer-invoked). Detect + remediate.
  --once       Same as no args (explicit).
  --check      Dry-run: print findings, exit 0 if all OK, 1 if any BAD.
  --dry-run    Run a tick but log what each fix would do without executing.
  --explain    Dump current state (xrdp children, chansrv sockets, displays).
  --help       Show this help.

Environment:
  LOG_LEVEL=debug   verbose logging (default: info)

See ~/uap/docs/specs/2026-05-23-xrdp-watchdogs-design.md
EOF
}

print_explain() {
    echo "=== xrdp children ==="
    _list_xrdp_children
    echo "=== active X displays ==="
    _list_active_displays
    echo "=== chansrv socket states ==="
    for d in $(_list_active_displays); do
        printf "  display=%s state=%s\n" "$d" "$(_get_chansrv_socket_state "$d")"
    done
    echo "=== recent xrdp journal errors (1m) ==="
    _journalctl_recent_errors "1 minute ago" | grep -iE 'error|fail|warn' | head -20 || echo "(none)"
}

run_check_only() {
    local any_bad=0
    local r
    r=$(check_a_stale_xrdp_child); echo "Check A: $r"; [[ "$r" =~ ^BAD ]] && any_bad=1
    r=$(check_b_chansrv_health);   echo "Check B: $r"; [[ "$r" =~ ^BAD ]] && any_bad=1
    r=$(check_c_cliprdr_log_scan); echo "Check C: $r"; [[ "$r" =~ ^BAD ]] && any_bad=1
    return $any_bad
}

run_tick() {
    local r
    r=$(check_a_stale_xrdp_child); [[ "$r" =~ ^BAD ]] && fix_a_kill_stale "$r"
    r=$(check_b_chansrv_health);   [[ "$r" =~ ^BAD ]] && fix_b_respawn_chansrv "$r"
    r=$(check_c_cliprdr_log_scan); [[ "$r" =~ ^BAD ]] && fix_c_restart_chansrv_notify "$r"
    log debug "tick complete"
}

parse_args() {
    case "${1:-}" in
        ""|--once) MODE="tick" ;;
        --check)   MODE="check" ;;
        --dry-run) MODE="tick"; DRY_RUN=1 ;;
        --explain) MODE="explain" ;;
        -h|--help) MODE="help" ;;
        *) echo "$PROG: unknown flag: $1" >&2; print_help >&2; exit 2 ;;
    esac
}

main() {
    parse_args "$@"
    case "$MODE" in
        help)    print_help ;;
        explain) print_explain ;;
        check)   run_check_only ;;
        tick)    run_tick ;;
    esac
}

main "$@"
```

```bash
chmod +x ~/uap/os/xrdp/xrdp-watchdog
```

- [ ] **Step 5: Run test again, verify it passes**

```bash
cd ~/uap/os/xrdp/tests
./run-tests.sh test-cli.sh
```

Expected: 5/5 PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog os/xrdp/tests/run-tests.sh os/xrdp/tests/test-cli.sh
git commit -m "xrdp-watchdog: skeleton, CLI, helper shims, test harness"
```

---

### Task 5: Check A + Fix A — stale xrdp child detection and removal

**Files:**
- Modify: `os/xrdp/xrdp-watchdog` (fill in `check_a_stale_xrdp_child` and `fix_a_kill_stale`)
- Create: `os/xrdp/tests/test-check-a.sh`
- Create: `os/xrdp/tests/test-fix-a.sh`

Logic per spec: enumerate xrdp children; for each, find its TCP socket on :3389; staleness = ESTABLISHED-but-dead-peer (kernel keepalive timer) + age > 60s + another xrdp child exists for the same display (solo-session guard).

- [ ] **Step 1: Write failing tests for Check A**

Create `os/xrdp/tests/test-check-a.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify failure**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-a.sh
```

Expected: tests fail because Check A is still the stub returning OK for all cases (so tests 3 fails — expected BAD but got OK).

- [ ] **Step 3: Add two new helper shims to the script**

In `os/xrdp/xrdp-watchdog`, add these helpers near the existing shims (before `_journalctl_recent_errors`):

```bash
_get_pid_age_seconds() {
    local pid="$1"
    if [ "${XRDP_WATCHDOG_TEST_PID_AGES:-0}" = "1" ] || [ -n "${XRDP_WATCHDOG_FAKE_PID_AGES:-}" ]; then
        # Parse "9001=300 9002=5"
        local kv
        for kv in ${XRDP_WATCHDOG_FAKE_PID_AGES:-}; do
            local k="${kv%=*}" v="${kv#*=}"
            [ "$k" = "$pid" ] && echo "$v" && return 0
        done
        echo "0"; return 0
    fi
    local started_ts
    started_ts=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    echo "${started_ts:-0}"
}

_get_pid_display() {
    local pid="$1"
    if [ "${XRDP_WATCHDOG_TEST_PID_DISPLAYS:-0}" = "1" ] || [ -n "${XRDP_WATCHDOG_FAKE_PID_DISPLAYS:-}" ]; then
        local kv
        for kv in ${XRDP_WATCHDOG_FAKE_PID_DISPLAYS:-}; do
            local k="${kv%=*}" v="${kv#*=}"
            [ "$k" = "$pid" ] && echo "$v" && return 0
        done
        echo ""; return 0
    fi
    # Inspect xrdp child's cmdline / open files to determine which display it serves.
    # xrdp children typically have an open fd on /run/xrdp/sockdir/xrdp_chansrv_socket_<N>
    sudo lsof -p "$pid" 2>/dev/null | grep -oE 'xrdp_chansrv_socket_[0-9]+' | head -1 | sed 's|.*_||'
}

_pid_tcp_dead() {
    local pid="$1"
    if [ "${XRDP_WATCHDOG_TEST_PID_TCP_DEAD:-0}" = "1" ] || [ -n "${XRDP_WATCHDOG_FAKE_PID_TCP_DEAD:-}" ]; then
        local kv
        for kv in ${XRDP_WATCHDOG_FAKE_PID_TCP_DEAD:-}; do
            local k="${kv%=*}" v="${kv#*=}"
            [ "$k" = "$pid" ] && [ "$v" = "true" ] && return 0
            [ "$k" = "$pid" ] && return 1
        done
        return 1
    fi
    # Real check: look at ss output for this pid's :3389 ESTABLISHED socket.
    # If the TCP keepalive timer field shows a recently-failed probe OR if the
    # remote peer is unresponsive to a probe, consider it dead.
    # Implementation: rely on kernel-level keepalive (tcp_keepalive=true must be set).
    # The kernel will close dead sockets; if ss shows the socket still ESTABLISHED
    # but `last data recv` > 600s ago AND age > 60s, treat as dead.
    local recv_age
    recv_age=$(sudo ss -tnoi 2>/dev/null | \
        awk -v pid="$pid" '$0 ~ ":3389" && $0 ~ "pid="pid {getline; print}' | \
        grep -oE 'lastrcv:[0-9]+' | head -1 | sed 's|lastrcv:||')
    [ -z "$recv_age" ] && return 1   # no recv-age info → don't kill
    [ "$recv_age" -gt 600000 ] && return 0   # ms; 10min no data = dead
    return 1
}
```

- [ ] **Step 4: Replace `check_a_stale_xrdp_child` stub with real logic**

Replace the stub `check_a_stale_xrdp_child()` line with:

```bash
check_a_stale_xrdp_child() {
    local children
    children=$(_list_xrdp_children)
    [ -z "$children" ] && echo "OK" && return 0

    # Bucket children by display
    declare -A by_display
    local pid display
    for pid in $children; do
        display=$(_get_pid_display "$pid")
        [ -z "$display" ] && continue
        by_display[$display]="${by_display[$display]:-} $pid"
    done

    # For each display, find stale children. Solo-session guard: skip if only 1 child.
    local d pids count age
    for d in "${!by_display[@]}"; do
        pids="${by_display[$d]}"
        count=$(echo $pids | wc -w)
        [ "$count" -lt 2 ] && continue  # solo session — never mark stale
        for pid in $pids; do
            age=$(_get_pid_age_seconds "$pid")
            [ "$age" -lt 60 ] && continue
            if _pid_tcp_dead "$pid"; then
                echo "BAD: stale xrdp child pid=$pid display=$d age=${age}s"
                return 0
            fi
        done
    done
    echo "OK"
}
```

- [ ] **Step 5: Run tests, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-a.sh
```

Expected: 5/5 PASS.

- [ ] **Step 6: Write failing tests for Fix A**

Create `os/xrdp/tests/test-fix-a.sh`:

```bash
# Test Fix A — kill stale xrdp child (mocked)
# We can't actually kill processes in tests; assert dry-run output instead.

export XRDP_WATCHDOG_TEST_LIST_XRDP_CHILDREN=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1

XRDP_WATCHDOG_FAKE_XRDP_CHILDREN="9001 9002" \
XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_PID_AGES="9001=300 9002=5" \
XRDP_WATCHDOG_FAKE_PID_DISPLAYS="9001=10 9002=10" \
XRDP_WATCHDOG_FAKE_PID_TCP_DEAD="9001=true 9002=false" \
    out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_a: would kill" "dry-run fix A names action"
assert_contains "$out" "9001" "dry-run names stale pid"
```

- [ ] **Step 7: Run, verify failure**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-fix-a.sh
```

Expected: FAIL — current stub just logs "fix_a: stub".

- [ ] **Step 8: Replace `fix_a_kill_stale` stub with real logic**

Replace the stub with:

```bash
fix_a_kill_stale() {
    local bad_line="$1"
    local pid display
    pid=$(echo "$bad_line"   | grep -oE 'pid=[0-9]+'    | sed 's|pid=||')
    display=$(echo "$bad_line" | grep -oE 'display=[0-9]+' | sed 's|display=||')
    [ -z "$pid" ] && log warning "fix_a: no pid in BAD line: $bad_line" && return 1

    # Re-verify staleness (world may have changed since detection)
    if ! _pid_tcp_dead "$pid"; then
        log info "fix_a: pid=$pid no longer stale, aborting"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        log info "fix_a: would kill stale xrdp child pid=$pid display=$display"
        return 0
    fi

    log info "fix_a: killing stale xrdp child pid=$pid display=$display"
    sudo kill -TERM "$pid" 2>/dev/null || true
    local i=0
    while [ $i -lt 5 ] && sudo kill -0 "$pid" 2>/dev/null; do
        sleep 1; i=$((i+1))
    done
    if sudo kill -0 "$pid" 2>/dev/null; then
        log warning "fix_a: pid=$pid did not exit on TERM, sending KILL"
        sudo kill -KILL "$pid" 2>/dev/null || true
    fi

    # Verify chansrv socket is back to LISTEN
    local state
    state=$(_get_chansrv_socket_state "$display")
    if [ "$state" != "LISTEN" ]; then
        log warning "fix_a: chansrv socket for display=$display is $state, not LISTEN; no escalation"
        return 1
    fi
    log info "fix_a: fixed stale xrdp child pid=$pid for display=$display"
    return 0
}
```

- [ ] **Step 9: Run tests, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-fix-a.sh
```

Expected: tests PASS.

- [ ] **Step 10: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog os/xrdp/tests/test-check-a.sh os/xrdp/tests/test-fix-a.sh
git commit -m "xrdp-watchdog: implement Check A + Fix A (stale xrdp child)"
```

---

### Task 6: Check B + Fix B — chansrv missing/defunct

**Files:**
- Modify: `os/xrdp/xrdp-watchdog`
- Create: `os/xrdp/tests/test-check-b.sh`
- Create: `os/xrdp/tests/test-fix-b.sh`

- [ ] **Step 1: Write failing tests for Check B**

Create `os/xrdp/tests/test-check-b.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify failure**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-b.sh
```

Expected: FAIL (stub returns OK).

- [ ] **Step 3: Replace `check_b_chansrv_health` stub**

```bash
check_b_chansrv_health() {
    local displays d state
    displays=$(_list_active_displays)
    for d in $displays; do
        state=$(_get_chansrv_socket_state "$d")
        if [ "$state" = "MISSING" ]; then
            echo "BAD: chansrv socket missing display=$d"
            return 0
        fi
    done
    echo "OK"
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-b.sh
```

Expected: 4/4 PASS.

- [ ] **Step 5: Write failing tests for Fix B (dry-run)**

Create `os/xrdp/tests/test-fix-b.sh`:

```bash
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
export XRDP_WATCHDOG_TEST_CHANSRV_SOCKET=1

XRDP_WATCHDOG_FAKE_DISPLAYS="10" \
XRDP_WATCHDOG_FAKE_CHANSRV_10="MISSING" \
    out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_b: would respawn chansrv" "dry-run names action"
assert_contains "$out" "display=10" "dry-run names display"
```

- [ ] **Step 6: Run, verify failure, then implement**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-fix-b.sh
```

Expected: FAIL.

Replace `fix_b_respawn_chansrv` stub:

```bash
fix_b_respawn_chansrv() {
    local bad_line="$1"
    local display
    display=$(echo "$bad_line" | grep -oE 'display=[0-9]+' | sed 's|display=||')
    [ -z "$display" ] && log warning "fix_b: no display in BAD line" && return 1

    # Find session owner via the per-session sesman process (parent-PID guard)
    local sesman_pid user xauth
    sesman_pid=$(pgrep -f "xrdp-sesman" | while read -r p; do
        env_disp=$(sudo cat /proc/$p/environ 2>/dev/null | tr '\0' '\n' | grep "^DISPLAY=:$display\$")
        [ -n "$env_disp" ] && echo "$p" && break
    done | head -1)

    if [ -z "$sesman_pid" ]; then
        log warning "fix_b: cannot find sesman for display=$display"
        return 1
    fi

    user=$(sudo cat /proc/"$sesman_pid"/environ 2>/dev/null | tr '\0' '\n' | grep '^USER=' | sed 's|USER=||')
    xauth=$(sudo cat /proc/"$sesman_pid"/environ 2>/dev/null | tr '\0' '\n' | grep '^XAUTHORITY=' | sed 's|XAUTHORITY=||')
    [ -z "$user" ]   && log warning "fix_b: no USER in sesman env"   && return 1
    [ -z "$xauth" ]  && xauth="/home/$user/.Xauthority"

    if [ "$DRY_RUN" = "1" ]; then
        log info "fix_b: would respawn chansrv for display=$display user=$user xauth=$xauth"
        return 0
    fi

    # Kill any defunct chansrv whose parent is this sesman
    local existing_chansrv
    existing_chansrv=$(pgrep -P "$sesman_pid" -f xrdp-chansrv || true)
    if [ -n "$existing_chansrv" ]; then
        log info "fix_b: killing defunct chansrv pid=$existing_chansrv"
        sudo kill -TERM "$existing_chansrv" 2>/dev/null || true
        sleep 2
        sudo kill -KILL "$existing_chansrv" 2>/dev/null || true
    fi

    log info "fix_b: respawning chansrv for display=$display user=$user"
    sudo -u "$user" DISPLAY=":$display" XAUTHORITY="$xauth" XRDP_SESSION="$display" \
        nohup /usr/sbin/xrdp-chansrv >>"/var/log/xrdp/chansrv-${display}.log" 2>&1 &

    # Wait for socket
    local i=0 state
    while [ $i -lt 3 ]; do
        state=$(_get_chansrv_socket_state "$display")
        [ "$state" != "MISSING" ] && break
        sleep 1; i=$((i+1))
    done
    if [ "$state" = "MISSING" ]; then
        log warning "fix_b: socket still missing after respawn for display=$display"
        return 1
    fi
    log info "fix_b: respawned chansrv for display=$display user=$user"
    return 0
}
```

- [ ] **Step 7: Run tests, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-fix-b.sh
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog os/xrdp/tests/test-check-b.sh os/xrdp/tests/test-fix-b.sh
git commit -m "xrdp-watchdog: implement Check B + Fix B (chansrv health)"
```

---

### Task 7: Check C + Fix C — cliprdr desync (passive log scan + notify-send)

**Files:**
- Modify: `os/xrdp/xrdp-watchdog`
- Create: `os/xrdp/tests/test-check-c.sh`
- Create: `os/xrdp/tests/test-fix-c.sh`

- [ ] **Step 1: Write failing tests for Check C**

Create `os/xrdp/tests/test-check-c.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify failure, then implement**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-c.sh
```

Expected: FAIL.

Replace `check_c_cliprdr_log_scan` stub:

```bash
check_c_cliprdr_log_scan() {
    local since="${WATCHDOG_INTERVAL_SECONDS:-30}"
    local log_chunk
    log_chunk=$(_journalctl_recent_errors "${since} seconds ago")
    if echo "$log_chunk" | grep -qE 'clipboard_event_selection_request|\[ERROR\] cliprdr_|cliprdr.*unknown target'; then
        # Affected display: try to extract from the error, else default to first active display
        local display
        display=$(echo "$log_chunk" | grep -oE 'display[: =][0-9]+' | head -1 | grep -oE '[0-9]+')
        [ -z "$display" ] && display=$(_list_active_displays | head -1)
        echo "BAD: cliprdr desync display=$display"
        return 0
    fi
    echo "OK"
}
```

- [ ] **Step 3: Run, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-check-c.sh
```

Expected: 3/3 PASS.

- [ ] **Step 4: Write failing tests for Fix C**

Create `os/xrdp/tests/test-fix-c.sh`:

```bash
export XRDP_WATCHDOG_TEST_JOURNAL=1
export XRDP_WATCHDOG_TEST_LIST_DISPLAYS=1
XRDP_WATCHDOG_FAKE_DISPLAYS="10"
XRDP_WATCHDOG_FAKE_JOURNAL="xrdp-chansrv[123]: [ERROR] clipboard_event_selection_request: unknown target"

out=$("$WATCHDOG_BIN" --dry-run 2>&1)
assert_contains "$out" "fix_c: would respawn chansrv" "dry-run names action"
assert_contains "$out" "display=10" "dry-run names display"
assert_contains "$out" "notify" "dry-run mentions notification step"
```

- [ ] **Step 5: Implement Fix C**

Replace `fix_c_restart_chansrv_notify` stub:

```bash
fix_c_restart_chansrv_notify() {
    local bad_line="$1"
    local display
    display=$(echo "$bad_line" | grep -oE 'display=[0-9]+' | sed 's|display=||')
    [ -z "$display" ] && return 1

    # Resolve user (same path as Fix B)
    local sesman_pid user xauth
    sesman_pid=$(pgrep -f "xrdp-sesman" | while read -r p; do
        env_disp=$(sudo cat /proc/$p/environ 2>/dev/null | tr '\0' '\n' | grep "^DISPLAY=:$display\$")
        [ -n "$env_disp" ] && echo "$p" && break
    done | head -1)
    [ -z "$sesman_pid" ] && log warning "fix_c: no sesman for display=$display" && return 1
    user=$(sudo cat /proc/"$sesman_pid"/environ 2>/dev/null | tr '\0' '\n' | grep '^USER=' | sed 's|USER=||')
    xauth=$(sudo cat /proc/"$sesman_pid"/environ 2>/dev/null | tr '\0' '\n' | grep '^XAUTHORITY=' | sed 's|XAUTHORITY=||')
    [ -z "$xauth" ] && xauth="/home/$user/.Xauthority"

    if [ "$DRY_RUN" = "1" ]; then
        log info "fix_c: would respawn chansrv for display=$display user=$user and notify"
        return 0
    fi

    # Kill and respawn chansrv (same as Fix B body)
    local existing
    existing=$(pgrep -P "$sesman_pid" -f xrdp-chansrv || true)
    if [ -n "$existing" ]; then
        sudo kill -TERM "$existing" 2>/dev/null || true
        sleep 2
        sudo kill -KILL "$existing" 2>/dev/null || true
    fi
    sudo -u "$user" DISPLAY=":$display" XAUTHORITY="$xauth" XRDP_SESSION="$display" \
        nohup /usr/sbin/xrdp-chansrv >>"/var/log/xrdp/chansrv-${display}.log" 2>&1 &

    # Notify the user (soft dep)
    if sudo -u "$user" DISPLAY=":$display" command -v notify-send >/dev/null 2>&1; then
        sudo -u "$user" DISPLAY=":$display" notify-send -u normal -t 10000 \
            "xrdp clipboard restarted" \
            "Disconnect and reconnect your RDP client to restore copy/paste." \
            2>/dev/null || log warning "fix_c: notify-send failed"
    else
        log warning "fix_c: notify-send unavailable, skipping notification"
    fi

    log info "fix_c: respawned chansrv for cliprdr desync display=$display user=$user; user notified"
    return 0
}
```

- [ ] **Step 6: Run, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-fix-c.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog os/xrdp/tests/test-check-c.sh os/xrdp/tests/test-fix-c.sh
git commit -m "xrdp-watchdog: implement Check C + Fix C (cliprdr desync + notify)"
```

---

### Task 8: Cross-cutting guards — flock, per-fix backoff, hourly circuit breaker

**Files:**
- Modify: `os/xrdp/xrdp-watchdog`
- Create: `os/xrdp/tests/test-guards.sh`

- [ ] **Step 1: Write failing tests for guards**

Create `os/xrdp/tests/test-guards.sh`:

```bash
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
```

- [ ] **Step 2: Run, verify failure**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-guards.sh
```

Expected: tests FAIL — no backoff or circuit breaker yet.

- [ ] **Step 3: Add guards to the script**

Near the top of `os/xrdp/xrdp-watchdog`, after the `LOG_LEVEL` declaration, add:

```bash
STATE_DIR="${XRDP_WATCHDOG_STATE_DIR:-/run/xrdp-watchdog}"
LOCK_FILE="${STATE_DIR}/lock"
BACKOFF_SECONDS=90
CIRCUIT_BREAKER_MAX=10
CIRCUIT_BREAKER_WINDOW=3600
```

After the helper shims, before the check stubs, add:

```bash
_ensure_state_dir() {
    [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null || \
        { sudo mkdir -p "$STATE_DIR" && sudo chown "$(whoami)" "$STATE_DIR"; }
}

_fix_within_backoff() {
    local fix_name="$1"
    local marker="${STATE_DIR}/${fix_name}.last"
    [ ! -f "$marker" ] && return 1
    local last now diff
    last=$(cat "$marker")
    now=$(date +%s)
    diff=$((now - last))
    [ "$diff" -lt "$BACKOFF_SECONDS" ]
}

_mark_fix_ran() {
    _ensure_state_dir
    date +%s > "${STATE_DIR}/$1.last"
    date +%s >> "${STATE_DIR}/fixes.hour"
}

_circuit_breaker_tripped() {
    local hour_file="${STATE_DIR}/fixes.hour"
    [ ! -f "$hour_file" ] && return 1
    local now cutoff count
    now=$(date +%s)
    cutoff=$((now - CIRCUIT_BREAKER_WINDOW))
    # Prune old entries
    awk -v c="$cutoff" '$1 >= c' "$hour_file" > "${hour_file}.tmp" && mv "${hour_file}.tmp" "$hour_file"
    count=$(wc -l < "$hour_file")
    [ "$count" -ge "$CIRCUIT_BREAKER_MAX" ]
}

_run_fix_guarded() {
    local fix_name="$1"; shift
    if _circuit_breaker_tripped; then
        log warning "$fix_name: circuit breaker tripped (max $CIRCUIT_BREAKER_MAX fixes/hour); skipping"
        return 0
    fi
    if _fix_within_backoff "$fix_name"; then
        log info "$fix_name: skipped — backoff ($BACKOFF_SECONDS s) active"
        return 0
    fi
    _ensure_state_dir
    # flock the host-wide lock (non-blocking)
    (
        flock -n 9 || { log info "$fix_name: skipped — lock held by another tick"; exit 0; }
        "$fix_name" "$@"
        _mark_fix_ran "$fix_name"
    ) 9>"$LOCK_FILE"
}
```

In `run_tick`, replace the direct fix calls with guarded versions:

```bash
run_tick() {
    local r
    r=$(check_a_stale_xrdp_child); [[ "$r" =~ ^BAD ]] && _run_fix_guarded fix_a_kill_stale "$r"
    r=$(check_b_chansrv_health);   [[ "$r" =~ ^BAD ]] && _run_fix_guarded fix_b_respawn_chansrv "$r"
    r=$(check_c_cliprdr_log_scan); [[ "$r" =~ ^BAD ]] && _run_fix_guarded fix_c_restart_chansrv_notify "$r"
    log debug "tick complete"
}
```

- [ ] **Step 4: Run guards tests, verify pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh test-guards.sh
```

Expected: PASS.

- [ ] **Step 5: Run all tests to confirm no regressions**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh
```

Expected: all tests across all files PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog os/xrdp/tests/test-guards.sh
git commit -m "xrdp-watchdog: add flock, per-fix backoff, hourly circuit breaker"
```

---

### Task 9: systemd service + timer units

**Files:**
- Create: `os/xrdp/xrdp-watchdog.service.tmpl`
- Create: `os/xrdp/xrdp-watchdog.timer.tmpl`

- [ ] **Step 1: Create the service unit template**

Create `os/xrdp/xrdp-watchdog.service.tmpl`:

```ini
[Unit]
Description=xrdp watchdog (detect + remediate reconnect bugs)
Documentation=file:///home/${OS_USER}/uap/docs/specs/2026-05-23-xrdp-watchdogs-design.md
After=xrdp.service xrdp-sesman.service
Wants=xrdp.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xrdp-watchdog
# Fail-open: never block xrdp if the watchdog itself errors
SuccessExitStatus=0 1 2
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
# State dir auto-managed
RuntimeDirectory=xrdp-watchdog
RuntimeDirectoryMode=0755
```

The `${OS_USER}` placeholder will be substituted by envsubst during install.

- [ ] **Step 2: Create the timer unit template**

Create `os/xrdp/xrdp-watchdog.timer.tmpl`:

```ini
[Unit]
Description=Run xrdp-watchdog every ${WATCHDOG_INTERVAL_SECONDS}s
Documentation=file:///home/${OS_USER}/uap/docs/specs/2026-05-23-xrdp-watchdogs-design.md

[Timer]
OnBootSec=60s
OnUnitActiveSec=${WATCHDOG_INTERVAL_SECONDS}s
AccuracySec=5s
Persistent=false

[Install]
WantedBy=timers.target
```

- [ ] **Step 3: Verify the templates render cleanly with envsubst**

```bash
cd ~/uap/os/xrdp
OS_USER=subhas WATCHDOG_INTERVAL_SECONDS=30 envsubst < xrdp-watchdog.service.tmpl
OS_USER=subhas WATCHDOG_INTERVAL_SECONDS=30 envsubst < xrdp-watchdog.timer.tmpl
```

Expected: both render to valid INI with all variables substituted, no `${...}` remaining.

- [ ] **Step 4: Validate the rendered units with systemd-analyze**

```bash
OS_USER=subhas WATCHDOG_INTERVAL_SECONDS=30 envsubst < ~/uap/os/xrdp/xrdp-watchdog.service.tmpl > /tmp/test.service
OS_USER=subhas WATCHDOG_INTERVAL_SECONDS=30 envsubst < ~/uap/os/xrdp/xrdp-watchdog.timer.tmpl > /tmp/test.timer
systemd-analyze verify /tmp/test.service 2>&1 || echo "(verify may warn for unit-not-installed; non-fatal)"
systemd-analyze verify /tmp/test.timer 2>&1 || true
rm -f /tmp/test.service /tmp/test.timer
```

Expected: no errors. Warnings about Documentation= URL or unit-not-installed are non-fatal.

- [ ] **Step 5: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog.service.tmpl os/xrdp/xrdp-watchdog.timer.tmpl
git commit -m "xrdp-watchdog: systemd service + timer unit templates"
```

---

### Task 10: sudoers fragment

**Files:**
- Create: `os/xrdp/xrdp-watchdog.sudoers`

The watchdog runs as root (simpler than a dedicated user — see deferred question in spec). Sudoers fragment is still useful for documenting *what* operations the script may need privilege for; for v1 we ship it as a no-op marker file documenting the privilege surface.

Actually, the spec specifies a dedicated `xrdp-watchdog` user with scoped NOPASSWD. We'll start by running as root via the systemd unit (simplest, secure as long as we trust the script). The dedicated user is deferred.

- [ ] **Step 1: Decide deployment mode**

For v1 the systemd unit runs the script as root (default; no `User=` line in `[Service]`). The script's sudo calls become unnecessary when already root. We need to update the script to bypass sudo when it's already running as root.

Replace every `sudo ` invocation in `os/xrdp/xrdp-watchdog` with a `_priv` helper:

```bash
_priv() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}
```

Add this helper near the other helpers, then replace each `sudo X` call with `_priv X`. The `sudo -u <user>` calls (running things as the session owner) stay as `sudo -u`.

- [ ] **Step 2: Run all tests, verify still pass**

```bash
cd ~/uap/os/xrdp/tests && ./run-tests.sh
```

Expected: all tests still PASS (tests don't exercise `_priv` since helpers are mocked).

- [ ] **Step 3: Commit**

```bash
cd ~/uap
git add os/xrdp/xrdp-watchdog
git commit -m "xrdp-watchdog: _priv helper (passthrough when root, sudo otherwise)"
```

Note: The dedicated `xrdp-watchdog` system user + scoped sudoers is deferred per the spec's "Open questions" section. v1 runs as root inside the systemd unit. If/when we move to a dedicated user, we'll add the sudoers fragment + `User=xrdp-watchdog` to the service unit then.

---

### Task 11: Wire watchdog install/uninstall into apply.sh

**Files:**
- Modify: `setup/apply.sh` (extend `install_xrdp()` and add helper `_resolve_watchdog()`)

- [ ] **Step 1: Add the `_resolve_watchdog` helper near the other apply.sh helpers**

Find a section near the top of `apply.sh` where helper functions live (`apt_install`, `run_sudo`, etc.) and add:

```bash
_resolve_watchdog() {
    # Resolve install_watchdog="auto" to true/false based on sesman policy.
    case "$INSTALL_WATCHDOG" in
        true)  echo "true" ;;
        false) echo "false" ;;
        auto)
            case "$SESMAN_POLICY" in
                U|UB) echo "true" ;;
                *)    echo "false" ;;
            esac ;;
        *)     echo "false" ;;
    esac
}
```

- [ ] **Step 2: Render the watchdog templates in the template-rendering loop**

Find the existing template-render loop in `apply.sh` (looks for `.tmpl` files in `os/` and renders to `$RENDER_DIR/`). If there's a per-component render block, add to it:

```bash
# Inside the template render section (matching the existing pattern):
if [ -f "$REPO_DIR/os/xrdp/xrdp-watchdog.service.tmpl" ]; then
    OS_USER="$OPERATOR_USERNAME" WATCHDOG_INTERVAL_SECONDS="$WATCHDOG_INTERVAL_SECONDS" \
        envsubst < "$REPO_DIR/os/xrdp/xrdp-watchdog.service.tmpl" > "$RENDER_DIR/xrdp/xrdp-watchdog.service"
fi
if [ -f "$REPO_DIR/os/xrdp/xrdp-watchdog.timer.tmpl" ]; then
    OS_USER="$OPERATOR_USERNAME" WATCHDOG_INTERVAL_SECONDS="$WATCHDOG_INTERVAL_SECONDS" \
        envsubst < "$REPO_DIR/os/xrdp/xrdp-watchdog.timer.tmpl" > "$RENDER_DIR/xrdp/xrdp-watchdog.timer"
fi
```

If the existing render loop is generic (handles any `*.tmpl`), these may already be picked up — verify with `ls $RENDER_DIR/xrdp/` after a dry-run.

- [ ] **Step 3: Add the install block to `install_xrdp()`**

After the existing reconnectwm.sh install (`# 3. Install reconnectwm.sh`), add a new numbered section:

```bash
    # 8. xrdp-watchdog (idempotent install/uninstall based on identity)
    local watchdog_state
    watchdog_state=$(_resolve_watchdog)

    if [ "$DRY_RUN" = 1 ]; then
        if [ "$watchdog_state" = "true" ]; then
            log "xrdp: DRY-RUN — would install xrdp-watchdog (interval=${WATCHDOG_INTERVAL_SECONDS}s)"
        else
            log "xrdp: DRY-RUN — would ensure xrdp-watchdog NOT installed"
        fi
    elif [ "$watchdog_state" = "true" ]; then
        run_sudo install -m 755 -o root -g root "$REPO_DIR/os/xrdp/xrdp-watchdog" /usr/local/bin/xrdp-watchdog
        run_sudo install -m 644 -o root -g root "$render/xrdp-watchdog.service" /etc/systemd/system/xrdp-watchdog.service
        run_sudo install -m 644 -o root -g root "$render/xrdp-watchdog.timer"   /etc/systemd/system/xrdp-watchdog.timer
        run_sudo systemctl daemon-reload
        run_sudo systemctl enable --now xrdp-watchdog.timer >/dev/null 2>&1
        log "xrdp: xrdp-watchdog installed and enabled (every ${WATCHDOG_INTERVAL_SECONDS}s)"
    else
        # Uninstall if previously installed (idempotent)
        if [ -f /etc/systemd/system/xrdp-watchdog.timer ]; then
            run_sudo systemctl disable --now xrdp-watchdog.timer >/dev/null 2>&1 || true
            run_sudo rm -f /etc/systemd/system/xrdp-watchdog.timer \
                           /etc/systemd/system/xrdp-watchdog.service \
                           /usr/local/bin/xrdp-watchdog
            run_sudo systemctl daemon-reload
            log "xrdp: xrdp-watchdog uninstalled (per identity)"
        fi
    fi
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n ~/uap/setup/apply.sh && echo "syntax OK"
```

- [ ] **Step 5: Dry-run on the live box, verify the resolution + install block fires**

```bash
~/uap/setup/apply.sh --dry-run 2>&1 | grep -i "watchdog\|tcp_keepalive"
```

Expected: lines mentioning tcp_keepalive and watchdog. On this box, `SESMAN_POLICY=UBD` so `install_watchdog: auto` resolves to "false" → log line says "would ensure NOT installed". This is correct — operators choose to flip policy first.

- [ ] **Step 6: Test the "install_watchdog: true" path with an override**

```bash
INSTALL_WATCHDOG=true ~/uap/setup/apply.sh --dry-run 2>&1 | grep -i watchdog
```

Hmm — apply.sh reads `INSTALL_WATCHDOG` from yq, not env. To test the install path, temporarily edit `~/uap.local/identity.yaml`:

```bash
cp ~/uap.local/identity.yaml /tmp/identity.bak
yq -i '.xrdp.install_watchdog = "true"' ~/uap.local/identity.yaml
~/uap/setup/apply.sh --dry-run 2>&1 | grep -i watchdog
# Expected: "would install xrdp-watchdog"
cp /tmp/identity.bak ~/uap.local/identity.yaml   # revert
```

- [ ] **Step 7: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "apply.sh: install/uninstall xrdp-watchdog based on identity"
```

---

### Task 12: Smoke test in apply.sh

**Files:**
- Modify: `setup/apply.sh` (after the watchdog install block)

- [ ] **Step 1: Add self-test after install**

In `install_xrdp()`, immediately after the install block from Task 11, add:

```bash
    # 9. Watchdog smoke test (skip in dry-run; only when just-installed)
    if [ "$DRY_RUN" = 0 ] && [ "$watchdog_state" = "true" ]; then
        if ! /usr/local/bin/xrdp-watchdog --check >/dev/null 2>&1; then
            local rc=$?
            # rc=1 means findings; rc=2 means CLI error / script bug; rc>2 means crash
            if [ "$rc" -gt 1 ]; then
                warn "xrdp: xrdp-watchdog --check failed (rc=$rc); rolling back install"
                run_sudo systemctl disable --now xrdp-watchdog.timer >/dev/null 2>&1 || true
                run_sudo rm -f /etc/systemd/system/xrdp-watchdog.timer \
                               /etc/systemd/system/xrdp-watchdog.service \
                               /usr/local/bin/xrdp-watchdog
                return 1
            fi
            log "xrdp: xrdp-watchdog --check reports findings (rc=1); install kept, see journalctl -u xrdp-watchdog"
        else
            log "xrdp: xrdp-watchdog --check passed cleanly"
        fi
    fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n ~/uap/setup/apply.sh && echo "syntax OK"
```

- [ ] **Step 3: Commit**

```bash
cd ~/uap
git add setup/apply.sh
git commit -m "apply.sh: smoke-test xrdp-watchdog after install, roll back on crash"
```

---

### Task 13: Integration test script

**Files:**
- Create: `os/xrdp/tests/integration.sh`

This test is for disposable VMs only. It actually breaks things to verify the watchdog fixes them.

- [ ] **Step 1: Create the integration test**

Create `os/xrdp/tests/integration.sh`:

```bash
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
```

```bash
chmod +x ~/uap/os/xrdp/tests/integration.sh
```

- [ ] **Step 2: Document the test-mode flag in the script's header**

(Already in the script's intro comment.) Also add to the test directory README:

```bash
cat > ~/uap/os/xrdp/tests/README.md <<'EOF'
# xrdp-watchdog tests

## Unit tests

```
./run-tests.sh
```

Runs all `test-*.sh` files. Uses env-overrideable shims; safe to run anywhere.

## Integration tests

```
./integration.sh
```

**WARNING:** breaks xrdp on purpose. Refuses to run without `/etc/uap.local/test-mode`.

Run only on disposable VMs.

```bash
sudo mkdir -p /etc/uap.local && sudo touch /etc/uap.local/test-mode
./integration.sh
```
EOF
```

- [ ] **Step 3: Commit**

```bash
cd ~/uap
git add os/xrdp/tests/integration.sh os/xrdp/tests/README.md
git commit -m "xrdp-watchdog: integration test script + tests README"
```

---

### Task 14: README — "Known issues — RDP reconnect bugs" section

**Files:**
- Modify: `README.md` (UAP repo root)

- [ ] **Step 1: Find the existing "Known issues" section (if any)**

```bash
grep -n "Known issues\|known issue" ~/uap/README.md
```

If a section exists, append. Otherwise, add a new section near the bottom.

- [ ] **Step 2: Add the watchdog documentation**

Insert this section in the appropriate spot:

```markdown
## Known issues — RDP reconnect bugs (auto-fixed by watchdog)

xrdp 0.9.x has three reconnect bugs that affect users running stricter session-reattach policies (`Policy=U` or `Policy=UB`). UAP ships an optional `xrdp-watchdog` that auto-detects and remediates them. Defaults to **auto** — enabled when the policy is `U`/`UB`, disabled on the conservative `UBD` default.

### The bugs

1. **Black screen on reconnect** — a stale xrdp child from an unclean disconnect holds the chansrv socket; new connections see black until the stale child is killed.
2. **chansrv missing/defunct** — `xrdp-chansrv` dies mid-session without a parent respawn; clipboard/audio/drive redirection silently stop working.
3. **Clipboard desync (cliprdr)** — chansrv's cliprdr channel state corrupts on disconnect; new mstsc connect inherits broken state. Fixing requires chansrv restart **plus** the operator must disconnect + reconnect mstsc for the cliprdr handshake to redo.

### Identity toggles

```yaml
# ~/uap.local/identity.yaml
xrdp:
  install_watchdog: auto                  # true | false | auto
  watchdog_interval_seconds: 30
  watchdog_clipboard_active_probe: false  # opt-in active clipboard probe
  tcp_keepalive: true                     # patches xrdp.ini [Globals]
```

### Inspect / control

```bash
systemctl status xrdp-watchdog.timer
journalctl -u xrdp-watchdog -f
xrdp-watchdog --check       # dry-run diagnostics
xrdp-watchdog --explain     # dump current xrdp/chansrv/display state
```

### Disable

Set `install_watchdog: false` in `~/uap.local/identity.yaml` and rerun `~/uap/setup/apply.sh`. The watchdog and its timer will be cleanly removed.

### Design rationale

See `docs/specs/2026-05-23-xrdp-watchdogs-design.md`.
```

- [ ] **Step 3: Commit**

```bash
cd ~/uap
git add README.md
git commit -m "README: document xrdp-watchdog and reconnect-bug auto-fix"
```

---

### Task 15: Deploy on adminbox + verify

This is the live-deployment task. It runs the apply.sh changes against the actual machine.

- [ ] **Step 1: Run apply.sh with current identity (Policy=UBD → watchdog NOT installed)**

```bash
~/uap/setup/apply.sh 2>&1 | tee /tmp/apply.log
```

Expected log lines:
- `xrdp: sesman.ini Policy already UBD`
- `xrdp: xrdp.ini tcp_keepalive already true`
- `xrdp: xrdp-watchdog NOT installed` (since policy is UBD, auto resolves to false)

- [ ] **Step 2: Flip to Policy=UB (intent: test the watchdog actually installs)**

This requires `sesman` restart, which kills active RDP sessions. Schedule for a moment when you have no important RDP work open. **Save and close everything first.**

```bash
yq -i '.xrdp.sesman_policy = "UB"' ~/uap.local/identity.yaml
~/uap/setup/apply.sh 2>&1 | tee /tmp/apply.log
```

Expected:
- `xrdp: sesman.ini Policy set to UB`
- `xrdp: xrdp-watchdog installed and enabled (every 30s)`
- `xrdp: xrdp-watchdog --check passed cleanly`
- sesman restart kicks your RDP session — reconnect.

After reconnecting:

```bash
systemctl status xrdp-watchdog.timer
journalctl -u xrdp-watchdog --since "5 minutes ago"
```

Expected: timer is enabled+active; journal shows periodic debug entries (or info if remediations happened).

- [ ] **Step 3: Run the watchdog --explain to confirm it sees current state**

```bash
sudo /usr/local/bin/xrdp-watchdog --explain
```

Expected: lists current xrdp child PIDs, X10 display, chansrv socket LISTEN state, no recent errors.

- [ ] **Step 4: (Optional) Roll back to UBD if you don't want to keep Policy=UB yet**

```bash
yq -i '.xrdp.sesman_policy = "UBD"' ~/uap.local/identity.yaml
~/uap/setup/apply.sh 2>&1 | tail -10
# Watchdog will be cleanly uninstalled per auto-resolution
```

- [ ] **Step 5: Final commit (deployment marker)**

If anything in the deployment surfaced bugs or final tweaks, commit them now. Otherwise nothing to commit — the deployment doesn't change repo state.

```bash
cd ~/uap && git status
```

Expected: clean working tree.

- [ ] **Step 6: Update relevant memory**

Update `~/.claude/projects/-home-subhas/memory/project_rdp_fixes.md` to note: bugs #1, #2, #3 are now auto-fixed by `xrdp-watchdog` (deployed YYYY-MM-DD). Update `project_xrdp_sesman_policy.md` if policy was flipped to UB.

---

## Self-Review

**Spec coverage check:**
- §"Detection invariants" Check A → Task 5 ✓
- §"Detection invariants" Check B → Task 6 ✓
- §"Detection invariants" Check C (passive) → Task 7 ✓
- §"Detection invariants" Check C (active probe) → deferred per spec ✓
- §"Remediation actions" Fix A/B/C → Tasks 5/6/7 ✓
- §"Cross-cutting guards" flock/backoff/circuit breaker → Task 8 ✓
- §"CLI surface" --check/--once/--dry-run/--explain/--help → Task 4 ✓
- §"Logging" via logger → Task 4 (log function in skeleton) ✓
- §"UAP integration" identity.yaml additions → Task 1 ✓
- §"UAP integration" apply.sh tcp_keepalive patch → Task 3 ✓
- §"UAP integration" apply.sh watchdog install/uninstall → Task 11 ✓
- §"UAP integration" smoke test → Task 12 ✓
- §"UAP integration" README docs → Task 14 ✓
- §"Testing approach" helper shims → Task 4 ✓
- §"Testing approach" integration tests → Task 13 ✓
- §"Testing approach" smoke test in apply.sh → Task 12 ✓
- §"Notes for implementer" chansrv parent-PID guard → Task 6/7 Fix B/C use `pgrep -P "$sesman_pid"` ✓
- §"Notes for implementer" lsof-on-UNIX-socket → Task 4 `_get_chansrv_socket_state` uses lsof ✓
- §"Notes for implementer" tcp_keepalive already live → Task 3 step 3 verifies and treats as no-op ✓
- §"Notes for implementer" no Co-Authored-By → all commit messages omit it ✓

**Placeholder scan:** No "TODO", "TBD", "implement later", or "similar to" references. Every code-bearing step contains the actual code. Commands have expected outputs.

**Type/name consistency:**
- `_list_xrdp_children`, `_get_chansrv_socket_state`, `_list_active_displays`, `_journalctl_recent_errors`, `_get_pid_age_seconds`, `_get_pid_display`, `_pid_tcp_dead`, `_priv`, `_ensure_state_dir`, `_fix_within_backoff`, `_mark_fix_ran`, `_circuit_breaker_tripped`, `_run_fix_guarded` — names used consistently across all tasks.
- `check_a_stale_xrdp_child`, `check_b_chansrv_health`, `check_c_cliprdr_log_scan` — consistent.
- `fix_a_kill_stale`, `fix_b_respawn_chansrv`, `fix_c_restart_chansrv_notify` — consistent.
- Env vars: `XRDP_WATCHDOG_TEST_*`, `XRDP_WATCHDOG_FAKE_*`, `XRDP_WATCHDOG_STATE_DIR` — consistent prefix.
- Identity vars: `INSTALL_WATCHDOG`, `WATCHDOG_INTERVAL_SECONDS`, `WATCHDOG_CLIP_ACTIVE`, `TCP_KEEPALIVE` — consistent between yq reads (Task 2), apply.sh template renders (Task 11), and unit templates (Task 9).
